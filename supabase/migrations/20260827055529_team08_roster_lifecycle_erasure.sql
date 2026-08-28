-- TEAM-08: explicit roster archive and dual-controlled PII erasure.

-- Keep an anonymized profile tombstone for audit/history after Auth Admin deletes the account.
alter table core.profiles drop constraint if exists profiles_id_fkey;

create table core.club_person_erasure_requests(
 id uuid primary key default gen_random_uuid(),club_id uuid not null,team_id uuid not null,
 club_person_id uuid not null,state text not null default 'requested'
  check(state in('requested','approved','rejected','completed')),
 reason text not null check(length(btrim(reason)) between 2 and 240),
 initiated_by uuid not null references core.profiles(id),approved_by uuid references core.profiles(id),
 created_at timestamptz not null default now(),decided_at timestamptz,completed_at timestamptz,
 revision bigint not null default 1 check(revision>0),
 foreign key(team_id,club_id) references core.teams(id,club_id),
 foreign key(club_person_id,club_id) references core.club_people(id,club_id),
 check(approved_by is null or approved_by<>initiated_by)
);
create unique index club_person_erasure_one_open_idx
on core.club_person_erasure_requests(club_person_id) where state='requested';
create index club_person_erasure_team_state_idx
on core.club_person_erasure_requests(club_id,team_id,state,created_at desc);

create table internal.global_person_erasure_requests(
 id uuid primary key default gen_random_uuid(),person_id uuid not null references core.persons(id),
 requested_by uuid not null references core.profiles(id),reviewed_by uuid references core.profiles(id),
 state text not null default 'requested' check(state in('requested','approved','rejected','completed')),
 reason text not null check(length(btrim(reason)) between 2 and 500),created_at timestamptz not null default now(),
 reviewed_at timestamptz,completed_at timestamptz,revision bigint not null default 1 check(revision>0),
 check(reviewed_by is null or reviewed_by<>requested_by)
);
create unique index global_person_erasure_one_open_idx
on internal.global_person_erasure_requests(person_id) where state in('requested','approved');

alter table core.club_person_erasure_requests enable row level security;
alter table internal.global_person_erasure_requests enable row level security;
revoke all on table core.club_person_erasure_requests,internal.global_person_erasure_requests
from public,anon,authenticated;

create or replace function internal.list_club_people_for_actor(target_club_id uuid,target_team_id uuid default null)
returns table(club_person_id uuid,display_name text,age_class text,safeguarding_required boolean,
 team_id uuid,team_name text,assignment_state text,assignment_starts_at timestamptz,assignment_ends_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
  and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 return query select person.id,person.display_name,person.age_class,person.safeguarding_required,
  home.team_id,team.name,home.state,home.starts_at,home.ends_at
 from core.club_people person
 join lateral(select assignment.* from core.team_assignments assignment
  where assignment.club_person_id=person.id and assignment.club_id=person.club_id
   and (target_team_id is null or assignment.team_id=target_team_id)
  order by assignment.state='active' desc,assignment.starts_at desc,assignment.id desc limit 1) home on true
 join core.teams team on team.id=home.team_id and team.club_id=home.club_id
 where person.club_id=target_club_id and person.status in('active','ended')
 order by home.state='active' desc,person.display_name,person.id;
end
$$;

create function internal.archive_team_assignment_for_actor(target_club_id uuid,target_team_id uuid,
 target_club_person_id uuid,target_assignment_id uuid,expected_revision bigint,reason text,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();row_value core.team_assignments%rowtype;existing jsonb;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.assignment.archive.v1'
  and internal.command_deduplication.idempotency_key=archive_team_assignment_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  or length(btrim(coalesce(reason,''))) not between 2 and 240
 then raise insufficient_privilege using message='not_found';end if;
 perform pg_advisory_xact_lock(hashtextextended(target_club_id::text||':'||target_club_person_id::text,0));
 select * into row_value from core.team_assignments where id=target_assignment_id and club_id=target_club_id
  and team_id=target_team_id and club_person_id=target_club_person_id for update;
 if row_value.id is null then raise insufficient_privilege using message='not_found';end if;
 if row_value.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if row_value.state<>'active' then raise check_violation using message='invalid_transition';end if;
 update core.team_assignments set state='ended',ends_at=greatest(now(),starts_at+interval '1 microsecond'),
  ended_by=actor_id,revision=revision+1 where id=row_value.id returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.assignment.archive.v1',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,reason) values(target_club_id,actor_id,'roster.assignment.archive.v1',
  'team_assignment',row_value.id,new_revision,btrim(reason));
 return new_revision;
end
$$;

create function internal.request_club_person_erasure_for_actor(target_club_id uuid,target_team_id uuid,
 target_club_person_id uuid,reason text,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();request_id uuid;existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.club_erasure.request.v1'
  and internal.command_deduplication.idempotency_key=request_club_person_erasure_for_actor.idempotency_key;
 if existing is not null then return(existing->>'request_id')::uuid;end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  or length(btrim(coalesce(reason,''))) not between 2 and 240
  or not exists(select 1 from core.team_assignments where club_id=target_club_id and team_id=target_team_id
   and club_person_id=target_club_person_id)
 then raise insufficient_privilege using message='not_found';end if;
 insert into core.club_person_erasure_requests(club_id,team_id,club_person_id,reason,initiated_by)
 values(target_club_id,target_team_id,target_club_person_id,btrim(reason),actor_id) returning id into request_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.club_erasure.request.v1',jsonb_build_object('request_id',request_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason)
 values(target_club_id,actor_id,'roster.club_erasure.request.v1','club_person_erasure',request_id,1,btrim(reason));
 return request_id;
end
$$;

create function internal.anonymize_club_person(target_club_person_id uuid,actor_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
 update core.team_assignments set state='ended',ends_at=greatest(now(),starts_at+interval '1 microsecond'),
  ended_by=actor_id,revision=revision+1 where club_person_id=target_club_person_id and state='active';
 update core.assignments set state='ended',ends_at=greatest(now(),starts_at+interval '1 microsecond'),
  revision=revision+1 where club_person_id=target_club_person_id and state in('active','pending','suspended');
 update core.person_account_links set state='ended',ended_at=now(),revision=revision+1
  where club_person_id=target_club_person_id and state in('active','pending');
 update core.guardian_relations set state='ended',ends_at=coalesce(ends_at,greatest(now(),starts_at+interval '1 microsecond')),revision=revision+1
  where (guardian_person_id=target_club_person_id or child_person_id=target_club_person_id) and state in('active','pending');
 update core.play_eligibilities set state='ended',
  ends_at=least(coalesce(ends_at,now()),greatest(now(),starts_at+interval '1 microsecond')),
  validity_kind='fixed',season_ends_on=null,review_due_at=null,revision=revision+1
  where club_person_id=target_club_person_id and state in('active','pending');
 update core.roster_invites set state='revoked',revision=revision+1
  where club_person_id=target_club_person_id and state='issued';
 update core.guardian_invites set state='revoked',revision=revision+1
  where (guardian_person_id=target_club_person_id or child_person_id=target_club_person_id) and state='issued';
 update core.club_people set display_name='Tidigare spelare',age_class=null,safeguarding_required=false,
  provenance='anonymized',status='ended',revision=revision+1 where id=target_club_person_id;
end
$$;

create function internal.approve_club_person_erasure_for_actor(target_request_id uuid,
 expected_revision bigint,reason text,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();request_row core.club_person_erasure_requests%rowtype;existing jsonb;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.club_erasure.approve.v1'
  and internal.command_deduplication.idempotency_key=approve_club_person_erasure_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into request_row from core.club_person_erasure_requests where id=target_request_id for update;
 if request_row.id is null or not internal.actor_has_capability(request_row.club_id,null,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if request_row.initiated_by=actor_id then raise insufficient_privilege using message='separate_approver_required';end if;
 if request_row.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if request_row.state<>'requested' then raise check_violation using message='invalid_transition';end if;
 perform pg_advisory_xact_lock(hashtextextended(request_row.club_id::text||':'||request_row.club_person_id::text,0));
 perform internal.anonymize_club_person(request_row.club_person_id,actor_id);
 update core.club_person_erasure_requests set state='completed',approved_by=actor_id,decided_at=now(),
  completed_at=now(),revision=revision+1 where id=request_row.id returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.club_erasure.approve.v1',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,reason,metadata) values(request_row.club_id,actor_id,'roster.club_erasure.approve.v1',
  'club_person_erasure',request_row.id,new_revision,nullif(btrim(reason),''),
  jsonb_build_object('initiated_by',request_row.initiated_by,'club_person_id',request_row.club_person_id));
 return new_revision;
end
$$;

create function internal.list_roster_lifecycle_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare result jsonb;
begin
 if auth.uid() is null or not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found';end if;
 select jsonb_build_object(
  'people',coalesce((select jsonb_agg(jsonb_build_object('club_person_id',person.id,
    'person_name',person.display_name,'assignment_id',assignment.id,'assignment_state',assignment.state,
    'assignment_revision',assignment.revision) order by assignment.state='active' desc,person.display_name,person.id)
   from core.team_assignments assignment join core.club_people person on person.id=assignment.club_person_id
    and person.club_id=assignment.club_id where assignment.club_id=target_club_id and assignment.team_id=target_team_id
    and assignment.id=(select latest.id from core.team_assignments latest where latest.club_id=assignment.club_id
      and latest.team_id=assignment.team_id and latest.club_person_id=assignment.club_person_id
      order by latest.state='active' desc,latest.starts_at desc,latest.id desc limit 1)),'[]'::jsonb),
  'requests',coalesce((select jsonb_agg(jsonb_build_object('request_id',request.id,
    'club_person_id',request.club_person_id,'person_name',person.display_name,'state',request.state,
    'initiated_by',request.initiated_by,'revision',request.revision) order by request.created_at desc)
   from core.club_person_erasure_requests request join core.club_people person on person.id=request.club_person_id
   where request.club_id=target_club_id and request.team_id=target_team_id),'[]'::jsonb)
 ) into result;
 return result;
end
$$;

create function internal.request_global_person_erasure_for_actor(reason text,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();target_person_id uuid;request_id uuid;existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='person.global_erasure.request.v1'
  and internal.command_deduplication.idempotency_key=request_global_person_erasure_for_actor.idempotency_key;
 if existing is not null then return(existing->>'request_id')::uuid;end if;
 select person.person_id into target_person_id from core.person_account_links link
  join core.club_people person on person.id=link.club_person_id and person.club_id=link.club_id
  where link.profile_id=actor_id and link.state='active' limit 1;
 if target_person_id is null or length(btrim(coalesce(reason,''))) not between 2 and 500
 then raise insufficient_privilege using message='not_found';end if;
 insert into internal.global_person_erasure_requests(person_id,requested_by,reason)
 values(target_person_id,actor_id,btrim(reason)) returning id into request_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'person.global_erasure.request.v1',jsonb_build_object('request_id',request_id));
 return request_id;
end
$$;

create function api.review_global_person_erasure(target_request_id uuid,reviewer_profile_id uuid,decision text,reason text)
returns void language plpgsql security definer set search_path=''
as $$
declare request_row internal.global_person_erasure_requests%rowtype;person_row record;
begin
 if current_user not in('service_role','postgres') then raise insufficient_privilege using message='service_role_required';end if;
 select * into request_row from internal.global_person_erasure_requests where id=target_request_id for update;
 if request_row.id is null or request_row.state<>'requested' or reviewer_profile_id=request_row.requested_by
  or decision not in('approved','rejected') or length(btrim(coalesce(reason,''))) not between 2 and 500
 then raise check_violation using message='invalid_review';end if;
 if decision='rejected' then
  update internal.global_person_erasure_requests set state='rejected',reviewed_by=reviewer_profile_id,
   reviewed_at=now(),revision=revision+1 where id=request_row.id;return;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('global:'||request_row.person_id::text,0));
 for person_row in select id from core.club_people where person_id=request_row.person_id loop
  perform internal.anonymize_club_person(person_row.id,reviewer_profile_id);
 end loop;
 update core.persons set status='ended',revision=revision+1 where id=request_row.person_id;
 update core.profiles set display_name='Raderad användare',revision=revision+1
  where id=request_row.requested_by;
 update internal.global_person_erasure_requests set state='approved',reviewed_by=reviewer_profile_id,
  reviewed_at=now(),revision=revision+1 where id=request_row.id;
end
$$;

create function api.finalize_global_person_erasure(target_request_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare request_row internal.global_person_erasure_requests%rowtype;
begin
 if current_user not in('service_role','postgres') then raise insufficient_privilege using message='service_role_required';end if;
 select * into request_row from internal.global_person_erasure_requests where id=target_request_id for update;
 if request_row.id is null or request_row.state<>'approved' then raise check_violation using message='invalid_transition';end if;
 if exists(select 1 from auth.users where id=request_row.requested_by)
 then raise check_violation using message='auth_user_still_exists';end if;
 update internal.global_person_erasure_requests set state='completed',completed_at=now(),revision=revision+1
 where id=request_row.id;
end
$$;

create function api.archive_team_assignment(target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
 target_assignment_id uuid,expected_revision bigint,reason text,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''
as $$select internal.archive_team_assignment_for_actor(target_club_id,target_team_id,target_club_person_id,
 target_assignment_id,expected_revision,reason,idempotency_key)$$;
create function api.request_club_person_erasure(target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
 reason text,idempotency_key uuid) returns uuid language sql security invoker set search_path=''
as $$select internal.request_club_person_erasure_for_actor(target_club_id,target_team_id,target_club_person_id,reason,idempotency_key)$$;
create function api.approve_club_person_erasure(target_request_id uuid,expected_revision bigint,reason text,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''
as $$select internal.approve_club_person_erasure_for_actor(target_request_id,expected_revision,reason,idempotency_key)$$;
create function api.list_roster_lifecycle(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.list_roster_lifecycle_for_actor(target_club_id,target_team_id)$$;
create function api.request_global_person_erasure(reason text,idempotency_key uuid)
returns uuid language sql security invoker set search_path=''
as $$select internal.request_global_person_erasure_for_actor(reason,idempotency_key)$$;

revoke all on function internal.anonymize_club_person(uuid,uuid),
 internal.archive_team_assignment_for_actor(uuid,uuid,uuid,uuid,bigint,text,uuid),
 internal.request_club_person_erasure_for_actor(uuid,uuid,uuid,text,uuid),
 internal.approve_club_person_erasure_for_actor(uuid,bigint,text,uuid),
 internal.list_roster_lifecycle_for_actor(uuid,uuid),internal.request_global_person_erasure_for_actor(text,uuid)
from public,anon,authenticated;
revoke all on function api.archive_team_assignment(uuid,uuid,uuid,uuid,bigint,text,uuid),
 api.request_club_person_erasure(uuid,uuid,uuid,text,uuid),api.approve_club_person_erasure(uuid,bigint,text,uuid),
 api.list_roster_lifecycle(uuid,uuid),api.request_global_person_erasure(text,uuid),
 api.review_global_person_erasure(uuid,uuid,text,text),api.finalize_global_person_erasure(uuid)
 from public,anon,authenticated;
grant execute on function internal.archive_team_assignment_for_actor(uuid,uuid,uuid,uuid,bigint,text,uuid),
 internal.request_club_person_erasure_for_actor(uuid,uuid,uuid,text,uuid),
 internal.approve_club_person_erasure_for_actor(uuid,bigint,text,uuid),
 internal.list_roster_lifecycle_for_actor(uuid,uuid),internal.request_global_person_erasure_for_actor(text,uuid)
to authenticated;
grant execute on function api.archive_team_assignment(uuid,uuid,uuid,uuid,bigint,text,uuid),
 api.request_club_person_erasure(uuid,uuid,uuid,text,uuid),api.approve_club_person_erasure(uuid,bigint,text,uuid),
 api.list_roster_lifecycle(uuid,uuid),api.request_global_person_erasure(text,uuid) to authenticated;
grant execute on function api.review_global_person_erasure(uuid,uuid,text,text),
 api.finalize_global_person_erasure(uuid) to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827055529_team08_roster_lifecycle_erasure','greenfield','TEAM-08 archive, dual-control erasure and neutral history');
notify pgrst,'reload schema';
