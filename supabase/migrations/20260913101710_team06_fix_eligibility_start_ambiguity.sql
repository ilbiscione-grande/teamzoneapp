create or replace function internal.create_play_eligibility_for_actor(
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
 select dedupe.result into existing from internal.command_deduplication dedupe
 where dedupe.actor_profile_id=actor_id
  and dedupe.command_type='roster.play_eligibility.create.v1'
  and dedupe.idempotency_key=create_play_eligibility_for_actor.idempotency_key;
 if existing is not null then return (existing->>'eligibility_id')::uuid; end if;
 select assignment.team_id into home_team_id from core.team_assignments assignment
 where assignment.club_id=target_club_id and assignment.club_person_id=target_club_person_id
   and assignment.state='active'
   and assignment.starts_at<=create_play_eligibility_for_actor.starts_at
   and (assignment.ends_at is null
     or assignment.ends_at>create_play_eligibility_for_actor.starts_at)
 order by assignment.starts_at desc limit 1;
 if home_team_id is null or home_team_id=target_team_id
   or not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active')
   or create_play_eligibility_for_actor.eligibility_kind not in ('development','dispensation','loan','guest')
   or create_play_eligibility_for_actor.validity_kind not in ('season','fixed','indefinite')
   or create_play_eligibility_for_actor.starts_at>now()+interval '366 days'
   or length(btrim(source_note)) not between 2 and 80
   or (create_play_eligibility_for_actor.validity_kind='season' and (create_play_eligibility_for_actor.ends_at is null or create_play_eligibility_for_actor.season_ends_on is null or create_play_eligibility_for_actor.ends_at::date<>create_play_eligibility_for_actor.season_ends_on or create_play_eligibility_for_actor.review_due_at is not null))
   or (create_play_eligibility_for_actor.validity_kind='fixed' and (create_play_eligibility_for_actor.ends_at is null or create_play_eligibility_for_actor.season_ends_on is not null or create_play_eligibility_for_actor.review_due_at is not null))
   or (create_play_eligibility_for_actor.validity_kind='indefinite' and (create_play_eligibility_for_actor.ends_at is not null or create_play_eligibility_for_actor.season_ends_on is not null or create_play_eligibility_for_actor.review_due_at is null))
   or effective_end<=create_play_eligibility_for_actor.starts_at
   or effective_end>create_play_eligibility_for_actor.starts_at+interval '2 years'
 then raise invalid_parameter_value using message='invalid_input'; end if;
 perform pg_advisory_xact_lock(hashtextextended(target_club_id::text||':'||target_team_id::text||':'||target_club_person_id::text,0));
 if exists(select 1 from core.play_eligibilities current_row
   where current_row.club_id=target_club_id and current_row.team_id=target_team_id
     and current_row.club_person_id=target_club_person_id and current_row.state in ('pending','active')
     and tstzrange(current_row.starts_at,coalesce(current_row.ends_at,current_row.review_due_at),'[)')
       && tstzrange(create_play_eligibility_for_actor.starts_at,effective_end,'[)'))
 then raise exclusion_violation using message='overlapping_play_eligibility'; end if;
 insert into core.play_eligibilities(club_id,team_id,club_person_id,kind,source_club_id,source,
   state,starts_at,ends_at,validity_kind,season_ends_on,review_due_at,created_by)
 values(target_club_id,target_team_id,target_club_person_id,create_play_eligibility_for_actor.eligibility_kind,
   case when create_play_eligibility_for_actor.eligibility_kind in ('loan','guest') then target_club_id else null end,btrim(source_note),
   'active',create_play_eligibility_for_actor.starts_at,create_play_eligibility_for_actor.ends_at,
   create_play_eligibility_for_actor.validity_kind,create_play_eligibility_for_actor.season_ends_on,
   create_play_eligibility_for_actor.review_due_at,actor_id)
 returning id into eligibility_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.play_eligibility.create.v1',jsonb_build_object('eligibility_id',eligibility_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'roster.play_eligibility.create.v1','play_eligibility',eligibility_id,1,
  jsonb_build_object('home_team_id',home_team_id,'target_team_id',target_team_id,
    'validity_kind',create_play_eligibility_for_actor.validity_kind));
 return eligibility_id;
end $$;

revoke all on function internal.create_play_eligibility_for_actor(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid) from public,anon,authenticated;
grant execute on function internal.create_play_eligibility_for_actor(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260913101710_team06_fix_eligibility_start_ambiguity','greenfield','TEAM-06 qualify event-time command parameters');
notify pgrst,'reload schema';
