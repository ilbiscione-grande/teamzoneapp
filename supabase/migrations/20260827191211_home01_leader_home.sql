-- HOME-01: deterministic, capability-scoped leader home projection.

insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by)
select grant_row.club_id,grant_row.assignment_id,capability.value,grant_row.scope_type,grant_row.scope_id,
 grant_row.starts_at,grant_row.ends_at,grant_row.created_by from core.capability_grants grant_row
cross join(values('event.squad.manage'),('event.attendance.manage'))capability(value)
where grant_row.capability='event.manage'and grant_row.scope_type='team'
on conflict(assignment_id,capability,scope_type,scope_id)do nothing;

create or replace function internal.sync_event_management_capabilities()
returns trigger language plpgsql security definer set search_path=''as $$
begin
 if new.capability='event.manage'and new.scope_type='team'then
  insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by)
  select new.club_id,new.assignment_id,value,new.scope_type,new.scope_id,new.starts_at,new.ends_at,new.created_by
  from(values('event.squad.manage'),('event.attendance.manage'))capability(value)
  on conflict(assignment_id,capability,scope_type,scope_id)do update set starts_at=excluded.starts_at,
   ends_at=excluded.ends_at,revision=core.capability_grants.revision+1;
 end if;
 return null;
end$$;
drop trigger if exists event_management_capabilities_sync on core.capability_grants;
create trigger event_management_capabilities_sync after insert or update of starts_at,ends_at on core.capability_grants
for each row execute function internal.sync_event_management_capabilities();

create or replace function internal.get_leader_home_for_actor(target_context_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''as $$
declare actor_id uuid:=auth.uid();context_row record;observed_at timestamptz:=statement_timestamp();
 can_manage_squad boolean;can_record_attendance boolean;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into context_row from internal.get_my_contexts_for_actor()where context_id=target_context_id;
 if context_row.context_id is null or context_row.role_package<>'leader'or context_row.team_id is null
 then raise insufficient_privilege using message='not_found';end if;
 can_manage_squad:=internal.actor_has_capability(context_row.club_id,context_row.team_id,'event.squad.manage');
 can_record_attendance:=internal.actor_has_capability(context_row.club_id,context_row.team_id,'event.attendance.manage');
 return jsonb_build_object(
  'schema_version',1,'generated_at',observed_at,'role_package','leader','context_id',target_context_id,
  'today_events',coalesce((select jsonb_agg(row_value order by starts_at,event_id)from(
   select event_row.id event_id,event_row.title,event_row.event_type,event_row.state,event_row.starts_at,event_row.ends_at,
    location.name location_name,location.address
   from core.events event_row join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
   where event_row.club_id=context_row.club_id and relation.team_id=context_row.team_id and event_row.state<>'cancelled'
    and(event_row.starts_at at time zone event_row.timezone)::date=(observed_at at time zone event_row.timezone)::date
   order by event_row.starts_at,event_row.id limit 8)row_value),'[]'::jsonb),
  'next_event',(select jsonb_build_object('event_id',event_row.id,'title',event_row.title,'event_type',event_row.event_type,
   'state',event_row.state,'starts_at',event_row.starts_at,'ends_at',event_row.ends_at,'location_name',location.name,'address',location.address)
   from core.events event_row join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
   where event_row.club_id=context_row.club_id and relation.team_id=context_row.team_id and event_row.state='scheduled'
    and event_row.starts_at>=observed_at order by event_row.starts_at,event_row.id limit 1),
  'tasks',coalesce((select jsonb_agg(task order by priority,kind)from(
   select 'pending_callups'kind,1 priority,'Obesvarade kallelser'title,count(*)::integer count,
    '/calendar?event='||callup.event_id::text route
   from core.callups callup join core.events event_row on event_row.id=callup.event_id and event_row.club_id=callup.club_id
   where can_manage_squad and event_row.owning_team_id=context_row.team_id and event_row.starts_at>=observed_at
    and event_row.state='scheduled'and callup.state='pending'
   group by callup.event_id having count(*)>0
   union all
   select 'missing_attendance',2,'Närvaro saknas',count(*)::integer,'/calendar?event='||callup.event_id::text
   from core.callups callup join core.events event_row on event_row.id=callup.event_id and event_row.club_id=callup.club_id
   left join core.attendance_facts fact on fact.event_id=callup.event_id and fact.club_person_id=callup.club_person_id
   where can_record_attendance and event_row.owning_team_id=context_row.team_id
    and event_row.ends_at<observed_at and event_row.ends_at>=observed_at-interval'7 days'
    and event_row.state in('scheduled','completed')and callup.state='accepted'and fact.id is null
   group by callup.event_id having count(*)>0)task),'[]'::jsonb),
  'planning_actions',jsonb_build_array(
   jsonb_build_object('kind','create_event','title','Planera aktivitet','route','/calendar','enabled',
    internal.actor_has_capability(context_row.club_id,context_row.team_id,'event.manage')),
   jsonb_build_object('kind','manage_team','title','Hantera laget','route','/team','enabled',
    internal.actor_has_capability(context_row.club_id,context_row.team_id,'club.memberships.manage')),
   jsonb_build_object('kind','open_inbox','title','Öppna inkorgen','route','/inbox','enabled',true)
  )
 );
end$$;

create or replace function api.get_leader_home(context_id uuid)returns jsonb language sql stable security invoker set search_path=''as
$$select internal.get_leader_home_for_actor(context_id)$$;
revoke all on function internal.sync_event_management_capabilities(),internal.get_leader_home_for_actor(uuid),api.get_leader_home(uuid)from public,anon,authenticated;
grant execute on function internal.get_leader_home_for_actor(uuid),api.get_leader_home(uuid)to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20260827191211_home01_leader_home','greenfield','HOME-01 leader today, next event and deterministic tasks'
where not exists(select 1 from internal.migration_provenance where migration_name='20260827191211_home01_leader_home');
notify pgrst,'reload schema';
