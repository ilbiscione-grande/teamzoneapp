-- TEAM-06 time-bounded cross-team representation without changing home team.

alter table core.play_eligibilities
  alter column ends_at drop not null,
  add column validity_kind text not null default 'fixed'
    check(validity_kind in ('season','fixed','indefinite')),
  add column season_ends_on date,
  add column review_due_at timestamptz;

alter table core.play_eligibilities add constraint play_eligibilities_validity_shape check(
  (validity_kind='season' and ends_at is not null and season_ends_on is not null
    and ends_at::date=season_ends_on and review_due_at is null)
  or (validity_kind='fixed' and ends_at is not null and season_ends_on is null and review_due_at is null)
  or (validity_kind='indefinite' and ends_at is null and season_ends_on is null and review_due_at is not null)
);

create index play_eligibilities_active_team_period_idx
on core.play_eligibilities(club_id,team_id,starts_at,ends_at,review_due_at)
where state='active';
create index play_eligibilities_active_person_idx
on core.play_eligibilities(club_id,club_person_id,starts_at)
where state='active';

create function internal.create_play_eligibility_for_actor(
  target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
  eligibility_kind text,validity_kind text,starts_at timestamptz,ends_at timestamptz,
  season_ends_on date,review_due_at timestamptz,source_note text,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); eligibility_id uuid; existing jsonb; home_team_id uuid;
  effective_end timestamptz:=coalesce(ends_at,review_due_at);
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.play_eligibility.create.v1'
  and internal.command_deduplication.idempotency_key=create_play_eligibility_for_actor.idempotency_key;
 if existing is not null then return (existing->>'eligibility_id')::uuid; end if;
 select assignment.team_id into home_team_id from core.team_assignments assignment
 where assignment.club_id=target_club_id and assignment.club_person_id=target_club_person_id
   and assignment.state='active' and assignment.starts_at<=starts_at
   and (assignment.ends_at is null or assignment.ends_at>starts_at)
 order by assignment.starts_at desc limit 1;
 if home_team_id is null or home_team_id=target_team_id
   or not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active')
   or eligibility_kind not in ('development','dispensation','loan','guest')
   or validity_kind not in ('season','fixed','indefinite')
   or starts_at>now()+interval '366 days' or length(btrim(source_note)) not between 2 and 80
   or (validity_kind='season' and (ends_at is null or season_ends_on is null or ends_at::date<>season_ends_on or review_due_at is not null))
   or (validity_kind='fixed' and (ends_at is null or season_ends_on is not null or review_due_at is not null))
   or (validity_kind='indefinite' and (ends_at is not null or season_ends_on is not null or review_due_at is null))
   or effective_end<=starts_at or effective_end>starts_at+interval '2 years'
 then raise invalid_parameter_value using message='invalid_input'; end if;
 perform pg_advisory_xact_lock(hashtextextended(target_club_id::text||':'||target_team_id::text||':'||target_club_person_id::text,0));
 if exists(select 1 from core.play_eligibilities current_row
   where current_row.club_id=target_club_id and current_row.team_id=target_team_id
     and current_row.club_person_id=target_club_person_id and current_row.state in ('pending','active')
     and tstzrange(current_row.starts_at,coalesce(current_row.ends_at,current_row.review_due_at),'[)')
       && tstzrange(starts_at,effective_end,'[)'))
 then raise exclusion_violation using message='overlapping_play_eligibility'; end if;
 insert into core.play_eligibilities(club_id,team_id,club_person_id,kind,source_club_id,source,
   state,starts_at,ends_at,validity_kind,season_ends_on,review_due_at,created_by)
 values(target_club_id,target_team_id,target_club_person_id,eligibility_kind,
   case when eligibility_kind in ('loan','guest') then target_club_id else null end,btrim(source_note),
   'active',starts_at,ends_at,validity_kind,season_ends_on,review_due_at,actor_id)
 returning id into eligibility_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.play_eligibility.create.v1',jsonb_build_object('eligibility_id',eligibility_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'roster.play_eligibility.create.v1','play_eligibility',eligibility_id,1,
  jsonb_build_object('home_team_id',home_team_id,'target_team_id',target_team_id,'validity_kind',validity_kind));
 return eligibility_id;
end $$;

create function internal.list_play_eligibilities_for_actor(target_club_id uuid,target_team_id uuid)
returns table(eligibility_id uuid,club_person_id uuid,person_name text,eligibility_team_id uuid,target_team_name text,
  eligibility_kind text,validity_kind text,state text,starts_at timestamptz,ends_at timestamptz,
  season_ends_on date,review_due_at timestamptz,revision bigint)
language plpgsql stable security definer set search_path=''
as $$ begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
   and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 return query select eligibility.id,person.id,person.display_name,team.id,team.name,
   eligibility.kind,eligibility.validity_kind,
   case when eligibility.state='active' and coalesce(eligibility.ends_at,eligibility.review_due_at)<=now()
     then case when eligibility.validity_kind='indefinite' then 'review_due' else 'ended' end
     else eligibility.state end,
   eligibility.starts_at,eligibility.ends_at,eligibility.season_ends_on,eligibility.review_due_at,eligibility.revision
 from core.play_eligibilities eligibility
 join core.club_people person on person.id=eligibility.club_person_id and person.club_id=eligibility.club_id
 join core.teams team on team.id=eligibility.team_id and team.club_id=eligibility.club_id
 where eligibility.club_id=target_club_id and eligibility.team_id=target_team_id
 order by (eligibility.state='active') desc,coalesce(eligibility.ends_at,eligibility.review_due_at) desc,person.display_name;
end $$;

create function internal.end_play_eligibility_for_actor(target_eligibility_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); eligibility core.play_eligibilities%rowtype; existing jsonb; new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.play_eligibility.end.v1'
  and internal.command_deduplication.idempotency_key=end_play_eligibility_for_actor.idempotency_key;
 if existing is not null then return (existing->>'revision')::bigint; end if;
 select * into eligibility from core.play_eligibilities where id=target_eligibility_id for update;
 if eligibility.id is null or not internal.actor_has_capability(eligibility.club_id,eligibility.team_id,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 if eligibility.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
 if eligibility.state<>'active' then raise check_violation using message='invalid_transition'; end if;
 update core.play_eligibilities set state='ended',ends_at=least(coalesce(ends_at,now()),greatest(now(),starts_at+interval '1 microsecond')),
   validity_kind='fixed',season_ends_on=null,review_due_at=null,revision=revision+1
 where id=eligibility.id returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.play_eligibility.end.v1',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(eligibility.club_id,actor_id,'roster.play_eligibility.end.v1','play_eligibility',eligibility.id,new_revision,
  jsonb_build_object('target_team_id',eligibility.team_id,'club_person_id',eligibility.club_person_id));
 return new_revision;
end $$;

create or replace function internal.person_eligibility_at_event(target_event_id uuid,target_person_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(
  (select jsonb_build_object('kind','team_assignment','id',assignment.id,'team_id',assignment.team_id,'starts_at',assignment.starts_at,'ends_at',assignment.ends_at)
   from core.events event_row join core.team_assignments assignment on assignment.club_id=event_row.club_id and assignment.team_id=event_row.owning_team_id
   where event_row.id=target_event_id and assignment.club_person_id=target_person_id and assignment.state='active'
    and assignment.starts_at<=event_row.starts_at and (assignment.ends_at is null or assignment.ends_at>event_row.starts_at) limit 1),
  (select jsonb_build_object('kind',eligibility.kind,'id',eligibility.id,'team_id',eligibility.team_id,
    'starts_at',eligibility.starts_at,'ends_at',eligibility.ends_at,'validity_kind',eligibility.validity_kind)
   from core.events event_row join core.play_eligibilities eligibility on eligibility.club_id=event_row.club_id and eligibility.team_id=event_row.owning_team_id
   where event_row.id=target_event_id and eligibility.club_person_id=target_person_id and eligibility.state='active'
    and eligibility.starts_at<=event_row.starts_at
    and (eligibility.ends_at is null or eligibility.ends_at>event_row.starts_at)
    and (eligibility.review_due_at is null or eligibility.review_due_at>event_row.starts_at)
   order by eligibility.starts_at desc,eligibility.id limit 1)
 );
$$;

create function api.create_play_eligibility(target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
 eligibility_kind text,validity_kind text,starts_at timestamptz,ends_at timestamptz,season_ends_on date,
 review_due_at timestamptz,source_note text,idempotency_key uuid)
returns uuid language sql security invoker set search_path='' as $$select internal.create_play_eligibility_for_actor(target_club_id,target_team_id,target_club_person_id,eligibility_kind,validity_kind,starts_at,ends_at,season_ends_on,review_due_at,source_note,idempotency_key)$$;
create function api.list_play_eligibilities(target_club_id uuid,target_team_id uuid)
returns table(eligibility_id uuid,club_person_id uuid,person_name text,eligibility_team_id uuid,target_team_name text,
 eligibility_kind text,validity_kind text,state text,starts_at timestamptz,ends_at timestamptz,season_ends_on date,review_due_at timestamptz,revision bigint)
language sql stable security invoker set search_path='' as $$select * from internal.list_play_eligibilities_for_actor(target_club_id,target_team_id)$$;
create function api.end_play_eligibility(eligibility_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$select internal.end_play_eligibility_for_actor(eligibility_id,expected_revision,idempotency_key)$$;

revoke all on function internal.create_play_eligibility_for_actor(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid),internal.list_play_eligibilities_for_actor(uuid,uuid),internal.end_play_eligibility_for_actor(uuid,bigint,uuid) from public,anon,authenticated;
revoke all on function api.create_play_eligibility(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid),api.list_play_eligibilities(uuid,uuid),api.end_play_eligibility(uuid,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.create_play_eligibility_for_actor(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid),internal.list_play_eligibilities_for_actor(uuid,uuid),internal.end_play_eligibility_for_actor(uuid,bigint,uuid) to authenticated;
grant execute on function api.create_play_eligibility(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid),api.list_play_eligibilities(uuid,uuid),api.end_play_eligibility(uuid,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827044300_team06_cross_team_representation','greenfield','TEAM-06 event-time cross-team representation');
notify pgrst,'reload schema';
