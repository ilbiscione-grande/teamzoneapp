-- Per-leader permissions (TEAM-10). Authorization already works on capability
-- grants per assignment, never on the role label; this splits the broad
-- event.manage into the areas a team actually divides between leaders, and
-- lets whoever holds team.leaders.manage (club functionaries, and the head
-- coach by template) choose a leader's set in the panel.
--
-- Panel capabilities (team scope, on the person's leader assignment):
--   team.roster.manage            Trupp och medlemmar
--   team.leaders.manage           Ledare och behörigheter
--   event.manage                  Skapa och flytta event (unchanged meaning)
--   event.squad.manage            Kallelser
--   event.attendance.manage       Närvaro
--   event.attendance.correct_late Sen närvarorättelse
--   event.logistics               Material, uppgifter, filer, agenda
--   training.plan                 Träningsupplägg
--   match.plan                    Matchplan och taktik
--   match.live                    Matchläge och resultat
--   development.manage            Spelarutveckling
--   publication.manage            Publicera
--
-- Rollout keeps behaviour: everyone who holds event.manage today receives the
-- split capabilities at the same scope. Club-scoped holders (functionaries)
-- receive the whole panel set. New leaders get the standard set, which does
-- not include team.leaders.manage: only its holders can create leaders.

create function internal.leader_permission_catalog()
returns text[] language sql immutable set search_path='' as $$
 select array['team.roster.manage','team.leaders.manage','event.manage','event.squad.manage',
  'event.attendance.manage','event.attendance.correct_late','event.logistics','training.plan',
  'match.plan','match.live','development.manage','publication.manage']::text[]
$$;

create function internal.leader_standard_capabilities()
returns text[] language sql immutable set search_path='' as $$
 select array['team.roster.view','team.roster.manage','event.manage','event.squad.manage',
  'event.attendance.manage','event.attendance.correct_late','event.logistics','training.plan',
  'match.plan','match.live']::text[]
$$;

-- An event capability counts on the event's primary team, or on a shared
-- team whose share level allows that kind of work.
create function internal.actor_has_event_capability(target_event_id uuid,required_capability text)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from core.events event_row
  join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
  where event_row.id=target_event_id
   and internal.actor_has_capability(event_row.club_id,relation.team_id,required_capability)
   and (relation.relation='primary' or (relation.relation='shared' and relation.capabilities &&
    case when required_capability in('event.squad.manage','event.attendance.manage')
     then array['manage_roster','co_manage']::text[] else array['co_manage']::text[] end)))
$$;

-- Callups and attendance follow their own capabilities.
create or replace function internal.actor_can_manage_squad(target_event_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$select internal.actor_has_event_capability(target_event_id,'event.squad.manage')$$;
create or replace function internal.actor_can_manage_attendance(target_event_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$select internal.actor_has_event_capability(target_event_id,'event.attendance.manage')$$;
create or replace function internal.actor_can_manage_event_roster(target_event_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$select internal.actor_can_manage_squad(target_event_id) or internal.actor_can_manage_attendance(target_event_id)$$;

-- Match day (clock, goals, result, report) follows match.live.
create or replace function internal.assert_match_manager(target_event_id uuid)
returns core.events language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or event_row.event_type<>'match' or event_row.state='cancelled'
 or not internal.actor_has_event_capability(target_event_id,'match.live') then
   raise insufficient_privilege using message='not_found';
 end if;
 return event_row;
end$$;

do $$ declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.get_match_report_for_actor(uuid)'::regprocedure);
 patched:=replace(definition,'internal.actor_can_manage_event(p_event_id)',
  'internal.actor_has_event_capability(p_event_id,''match.live'')');
 if patched=definition then raise exception 'match report contract changed'; end if;
 execute patched;
 definition:=pg_get_functiondef('api.get_match_v2_snapshot(uuid)'::regprocedure);
 patched:=replace(definition,'''can_manage'',internal.actor_can_manage_event(p_event_id)',
  '''can_manage'',internal.actor_has_event_capability(p_event_id,''match.live'')');
 if patched=definition then raise exception 'match snapshot contract changed'; end if;
 execute patched;
 -- Tell the client which areas the actor may work in.
 definition:=pg_get_functiondef('internal.get_event_details_for_actor(uuid)'::regprocedure);
 patched:=replace(definition,
  'if internal.actor_can_manage_event_roster(event_row.id) then actions:=actions||array[''manage_roster''];end if;',
  'if internal.actor_can_manage_event_roster(event_row.id) then actions:=actions||array[''manage_roster''];end if;
  if internal.actor_has_event_capability(event_row.id,''match.live'') then actions:=actions||array[''match_live''];end if;
  if internal.actor_has_event_capability(event_row.id,''match.plan'') then actions:=actions||array[''match_plan''];end if;
  if internal.actor_has_event_capability(event_row.id,''training.plan'') then actions:=actions||array[''training_plan''];end if;
  if internal.actor_has_event_capability(event_row.id,''event.logistics'') then actions:=actions||array[''event_logistics''];end if;');
 if patched=definition then raise exception 'event details contract changed'; end if;
 execute patched;
end$$;

-- Förberedelser: each area needs its own capability. Enforced on the rows,
-- so every command (create, tick, reorder, delete, note, file) is covered.
create function internal.preparation_area(target_event_id uuid,item_kind text)
returns text language sql stable security definer set search_path='' as $$
 select case
  when item_kind='focus' then 'training.plan'
  when item_kind='note' then case (select event_type from core.events where id=target_event_id)
   when 'training' then 'training.plan' when 'match' then 'match.plan' else 'event.logistics' end
  else 'event.logistics' end
$$;

create or replace function internal.actor_can_edit_event_preparation(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from core.events event_row where event_row.id=target_event_id and event_row.archived_at is null)
  and (internal.actor_has_event_capability(target_event_id,'event.logistics')
   or internal.actor_has_event_capability(target_event_id,'training.plan')
   or internal.actor_has_event_capability(target_event_id,'match.plan'))
$$;

create or replace function internal.actor_can_delete_event_file_object(target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select target_bucket='event-files' and exists(
  select 1 from core.event_files file where file.bucket_id=target_bucket and file.object_key=target_key
   and file.state in('staged','deleted') and internal.actor_has_event_capability(file.event_id,'event.logistics'))
$$;

create function internal.enforce_preparation_area()
returns trigger language plpgsql security definer set search_path='' as $$
declare row_value jsonb:=coalesce(to_jsonb(new),to_jsonb(old)); target_event uuid; area text;
begin
 if auth.uid() is null then return coalesce(new,old); end if;
 -- One trigger for three tables: read columns via jsonb, since only the
 -- items table has a kind.
 target_event:=(row_value->>'event_id')::uuid;
 area:=case tg_table_name
  when 'event_preparation_items' then internal.preparation_area(target_event,row_value->>'kind')
  when 'event_preparation_notes' then internal.preparation_area(target_event,'note')
  else 'event.logistics' end;
 if not internal.actor_has_event_capability(target_event,area) then
  raise insufficient_privilege using message='not_found';
 end if;
 return coalesce(new,old);
end$$;
create trigger event_preparation_items_area before insert or update or delete on core.event_preparation_items
for each row execute function internal.enforce_preparation_area();
create trigger event_preparation_notes_area before insert or update or delete on core.event_preparation_notes
for each row execute function internal.enforce_preparation_area();
create trigger event_files_area before insert or update or delete on core.event_files
for each row execute function internal.enforce_preparation_area();

create or replace function internal.get_event_preparation_for_actor(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare can_edit boolean; leader boolean; note_row core.event_preparation_notes%rowtype; archived boolean;
begin
 if auth.uid() is null or not internal.actor_can_read_event(p_event_id) then
  raise insufficient_privilege using message='not_found'; end if;
 can_edit:=internal.actor_can_edit_event_preparation(p_event_id);
 archived:=exists(select 1 from core.events where id=p_event_id and archived_at is not null);
 leader:=internal.actor_is_event_leader(p_event_id);
 select * into note_row from core.event_preparation_notes where event_id=p_event_id;
 return jsonb_build_object('event_id',p_event_id,'can_edit',can_edit,
  'permissions',jsonb_build_object(
   'logistics',not archived and internal.actor_has_event_capability(p_event_id,'event.logistics'),
   'training',not archived and internal.actor_has_event_capability(p_event_id,'training.plan'),
   'match',not archived and internal.actor_has_event_capability(p_event_id,'match.plan')),
  'items',coalesce((select jsonb_agg(internal.event_preparation_item_json(item) order by item.kind,item.position,item.created_at,item.id)
   from core.event_preparation_items item where item.event_id=p_event_id),'[]'::jsonb),
  'note',jsonb_build_object('body',coalesce(note_row.body,''),'revision',coalesce(note_row.revision,0),'updated_at',note_row.updated_at),
  'files',coalesce((select jsonb_agg(internal.event_file_json(file,leader) order by file.created_at,file.id)
   from core.event_files file where file.event_id=p_event_id and file.state='active'
    and internal.actor_can_view_event_file(file.id)),'[]'::jsonb));
end$$;

-- Leader bundle: new leaders get the standard set (not leaders.manage).
create or replace function internal.materialize_leader_capabilities_from_assignment()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.role_package='leader' and new.team_id is not null and new.state='active'
  and new.starts_at<=now() and (new.ends_at is null or new.ends_at>now()) then
  insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by)
  select new.club_id,new.id,capability.value,'team',new.team_id,greatest(new.starts_at,now()),new.ends_at,new.created_by
  from unnest(internal.leader_standard_capabilities()) capability(value)
  on conflict(assignment_id,capability,scope_type,scope_id) do nothing;
 end if;
 return new;
end$$;

-- Club-scoped event.manage (founders, functionaries, their copies on new
-- teams) always comes with the whole panel set.
create function internal.expand_club_scope_event_manage()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.capability='event.manage' and new.scope_type='club' then
  insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by)
  select new.club_id,new.assignment_id,capability.value,'club',new.scope_id,new.starts_at,new.ends_at,new.created_by
  from unnest(internal.leader_permission_catalog()) capability(value)
  on conflict(assignment_id,capability,scope_type,scope_id) do nothing;
 end if;
 return new;
end$$;
create trigger capability_grants_expand_club_event_manage after insert on core.capability_grants
for each row execute function internal.expand_club_scope_event_manage();

-- Backfill (behaviour-preserving).
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by)
select g.club_id,g.assignment_id,capability.value,g.scope_type,g.scope_id,g.starts_at,g.ends_at,g.created_by
from core.capability_grants g
cross join unnest(array['event.squad.manage','event.attendance.manage','event.logistics','training.plan',
 'match.plan','match.live']::text[]) capability(value)
where g.capability='event.manage'
on conflict(assignment_id,capability,scope_type,scope_id) do nothing;
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,ends_at,created_by)
select g.club_id,g.assignment_id,capability.value,'club',g.scope_id,g.starts_at,g.ends_at,g.created_by
from core.capability_grants g cross join unnest(internal.leader_permission_catalog()) capability(value)
where g.capability='event.manage' and g.scope_type='club'
on conflict(assignment_id,capability,scope_type,scope_id) do nothing;

-- Only holders of team.leaders.manage can make someone a leader, whichever
-- flow does it (role command, application approval, role override).
create function internal.enforce_leader_creation()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.role_package='leader' and new.state='active' and new.team_id is not null and auth.uid() is not null
  and (tg_op='INSERT' or old.role_package<>'leader' or old.state<>'active')
  and not internal.actor_has_capability(new.club_id,new.team_id,'team.leaders.manage') then
  raise insufficient_privilege using message='leaders_manage_required';
 end if;
 return new;
end$$;
create trigger assignments_enforce_leader_creation before insert or update of role_package,state on core.assignments
for each row execute function internal.enforce_leader_creation();

-- Role commands: leader roles need team.leaders.manage; titles/positions and
-- player roles need roster management.
create or replace function internal.assert_team_role_manager(target_club_id uuid,target_team_id uuid)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if target_team_id is null
  or not exists(select 1 from core.teams team where team.id=target_team_id and team.club_id=target_club_id and team.status='active')
  or not (internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
   or internal.actor_has_capability(target_club_id,target_team_id,'team.leaders.manage')) then
  raise insufficient_privilege using message='not_found';
 end if;
end$$;

create function internal.assert_team_leaders_manager(target_club_id uuid,target_team_id uuid)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.leaders.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
end$$;

do $$ declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.team_role_command(uuid,uuid,uuid,text,text,uuid)'::regprocedure);
 patched:=replace(definition,
  ' perform internal.assert_team_role_manager(target_club_id,target_team_id);',
  ' perform internal.assert_team_role_manager(target_club_id,target_team_id);
 if ''leader'' in(coalesce(from_role,''''),coalesce(to_role,'''')) then
  perform internal.assert_team_leaders_manager(target_club_id,target_team_id);
 end if;');
 if patched=definition then raise exception 'team role command contract changed'; end if;
 execute patched;
 definition:=pg_get_functiondef('internal.list_club_leader_candidates_for_actor(uuid,uuid)'::regprocedure);
 patched:=replace(definition,' perform internal.assert_team_role_manager(target_club_id,target_team_id);',
  ' perform internal.assert_team_leaders_manager(target_club_id,target_team_id);');
 if patched=definition then raise exception 'leader candidates contract changed'; end if;
 execute patched;
end$$;

alter table core.team_person_details add column permission_template text
 check(permission_template is null or permission_template in
  ('head_coach','assistant_coach','team_manager','specialist_coach','standard','custom'));

-- The template label goes with the leader role, like titles do.
create or replace function internal.clear_team_person_details_on_role_end()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.state='active' and new.state<>'active' and old.team_id is not null then
  if old.role_package='player' and not exists(select 1 from core.assignments a where a.id<>old.id
   and a.club_id=old.club_id and a.team_id=old.team_id and a.club_person_id=old.club_person_id
   and a.role_package='player' and a.state='active') then
   update core.team_person_details set positions='{}',custom_positions='{}',revision=revision+1,updated_at=now()
   where team_id=old.team_id and club_person_id=old.club_person_id
    and (cardinality(positions)>0 or cardinality(custom_positions)>0);
  elsif old.role_package in('leader','club_functionary') and not exists(select 1 from core.assignments a where a.id<>old.id
   and a.club_id=old.club_id and a.team_id=old.team_id and a.club_person_id=old.club_person_id
   and a.role_package in('leader','club_functionary') and a.state='active') then
   update core.team_person_details set functions='{}',custom_titles='{}',permission_template=null,
    revision=revision+1,updated_at=now()
   where team_id=old.team_id and club_person_id=old.club_person_id
    and (cardinality(functions)>0 or cardinality(custom_titles)>0 or permission_template is not null);
  end if;
 end if;
 return new;
end$$;

-- A leader's active panel capabilities (team scope) on their leader role.
create function internal.leader_panel_capabilities(target_club_id uuid,target_team_id uuid,target_person_id uuid)
returns text[] language sql stable security definer set search_path='' as $$
 select coalesce(array(select distinct g.capability from core.assignments a
  join core.capability_grants g on g.assignment_id=a.id and g.club_id=a.club_id
  where a.club_id=target_club_id and a.team_id=target_team_id and a.club_person_id=target_person_id
   and a.role_package='leader' and a.state='active'
   and g.scope_type='team' and g.scope_id=target_team_id
   and g.capability=any(internal.leader_permission_catalog())
   and g.starts_at<=now() and (g.ends_at is null or g.ends_at>now())
  order by 1),'{}')
$$;

create function internal.team_has_leaders_manager(target_club_id uuid,target_team_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from core.assignments a
  join core.capability_grants g on g.assignment_id=a.id and g.club_id=a.club_id
  join core.club_people p on p.id=a.club_person_id and p.club_id=a.club_id and p.status='active'
  where a.club_id=target_club_id and a.state='active' and a.starts_at<=now()
   and (a.ends_at is null or a.ends_at>now())
   and g.capability='team.leaders.manage' and g.starts_at<=now() and (g.ends_at is null or g.ends_at>now())
   and ((g.scope_type='team' and g.scope_id=target_team_id) or (g.scope_type='club' and g.scope_id=target_club_id)))
$$;

create function internal.set_leader_permissions_for_actor(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_capabilities text[],expected_capabilities text[],template text,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); cached jsonb; leader_assignment uuid; current_caps text[]; wanted text[];
 change text; result jsonb;
begin
 perform internal.assert_team_leaders_manager(target_club_id,target_team_id);
 if idempotency_key is null or new_capabilities is null or expected_capabilities is null
  or array_position(new_capabilities,null) is not null
  or not new_capabilities<@internal.leader_permission_catalog()
  or (template is not null and template not in('head_coach','assistant_coach','team_manager','specialist_coach','standard','custom')) then
  raise invalid_parameter_value using message='invalid_permissions'; end if;
 select d.result into cached from internal.command_deduplication d where d.actor_profile_id=actor_id
  and d.command_type='team.leader_permissions.updated.v1' and d.idempotency_key=set_leader_permissions_for_actor.idempotency_key;
 if cached is not null then return cached; end if;
 perform pg_advisory_xact_lock(hashtextextended('leader-permissions:'||target_team_id::text,0));
 select a.id into leader_assignment from core.assignments a
 join core.club_people p on p.id=a.club_person_id and p.club_id=a.club_id and p.status='active'
 where a.club_id=target_club_id and a.team_id=target_team_id and a.club_person_id=target_person_id
  and a.role_package='leader' and a.state='active' and a.starts_at<=now() and (a.ends_at is null or a.ends_at>now())
 order by a.starts_at limit 1;
 if leader_assignment is null then raise insufficient_privilege using message='not_found'; end if;
 current_caps:=internal.leader_panel_capabilities(target_club_id,target_team_id,target_person_id);
 wanted:=coalesce(array(select distinct v from unnest(new_capabilities) v order by 1),'{}');
 if current_caps<>coalesce(array(select distinct v from unnest(expected_capabilities) v order by 1),'{}') then
  raise serialization_failure using message='stale_permissions'; end if;
 -- You can only give or take away what you hold yourself.
 foreach change in array coalesce(array(
  select v from unnest(wanted) v where not v=any(current_caps)
  union select v from unnest(current_caps) v where not v=any(wanted)),'{}') loop
  if not internal.actor_has_capability(target_club_id,target_team_id,change) then
   raise check_violation using message='not_grantable'; end if;
 end loop;
 if internal.actor_owns_club_person(target_club_id,target_person_id)
  and 'team.leaders.manage'=any(current_caps) and not 'team.leaders.manage'=any(wanted) then
  raise check_violation using message='own_leaders_permission'; end if;
 -- End removed grants; one that has not started yet (granted in this same
 -- instant) is simply deleted, since it never took effect.
 delete from core.capability_grants
 where assignment_id=leader_assignment and scope_type='team' and scope_id=target_team_id
  and capability=any(current_caps) and not capability=any(wanted) and starts_at>=now();
 update core.capability_grants set ends_at=now()
 where assignment_id=leader_assignment and scope_type='team' and scope_id=target_team_id
  and capability=any(current_caps) and not capability=any(wanted) and starts_at<now()
  and (ends_at is null or ends_at>now());
 insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by)
 select target_club_id,leader_assignment,v,'team',target_team_id,now(),actor_id
 from unnest(wanted) v where not v=any(current_caps)
 on conflict(assignment_id,capability,scope_type,scope_id) do update
 set starts_at=now(),ends_at=null,revision=core.capability_grants.revision+1,created_by=excluded.created_by;
 if not internal.team_has_leaders_manager(target_club_id,target_team_id) then
  raise check_violation using message='last_leaders_manager'; end if;
 insert into core.team_person_details(club_id,team_id,club_person_id,permission_template,updated_by)
 values(target_club_id,target_team_id,target_person_id,template,actor_id)
 on conflict(team_id,club_person_id) do update set permission_template=excluded.permission_template;
 result:=jsonb_build_object('capabilities',to_jsonb(wanted),'template',template);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'team.leader_permissions.updated.v1',result);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'team.leader_permissions.updated.v1','team_person',target_person_id,1,
  jsonb_build_object('team_id',target_team_id,'from',to_jsonb(current_caps),'to',to_jsonb(wanted),'template',template));
 return result;
end$$;

create function api.set_leader_permissions(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_capabilities text[],expected_capabilities text[],template text,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.set_leader_permissions_for_actor(target_club_id,target_team_id,target_person_id,
 new_capabilities,expected_capabilities,template,idempotency_key)$$;

-- The roles list tells the client what the viewer may do and, for those who
-- manage leaders, each leader's current permissions.
create or replace function internal.list_team_roles_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_sport text; manages_leaders boolean;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
  and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  and not internal.actor_has_capability(target_club_id,target_team_id,'team.leaders.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
 manages_leaders:=internal.actor_has_capability(target_club_id,target_team_id,'team.leaders.manage');
 select sport into team_sport from core.teams where id=target_team_id and club_id=target_club_id;
 return jsonb_build_object(
  'can_manage',manages_leaders,
  'can_edit_details',internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') or manages_leaders,
  'grantable',case when manages_leaders then to_jsonb(coalesce(array(select v from unnest(internal.leader_permission_catalog()) v
    where internal.actor_has_capability(target_club_id,target_team_id,v)),'{}')) else '[]'::jsonb end,
  'sport',coalesce(team_sport,'football'),
  'position_catalog',coalesce((select jsonb_agg(jsonb_build_object('key',catalog.key,'level',catalog.level,
    'parent',catalog.parent_key) order by catalog.sort) from core.sport_positions catalog
   where catalog.sport=team_sport),'[]'::jsonb),
  'roles',coalesce((select jsonb_agg(jsonb_build_object(
    'person_id',person.id,'name',person.display_name,'role',assignment.role_package,
    'starts_at',assignment.starts_at,'is_self',internal.actor_owns_club_person(target_club_id,person.id),
    'functions',coalesce(details.functions,'{}'::text[]),
    'positions',coalesce(details.positions,'{}'::text[]),
    'custom_titles',coalesce(details.custom_titles,'{}'::text[]),
    'custom_positions',coalesce(details.custom_positions,'{}'::text[]),
    'details_revision',coalesce(details.revision,0),
    'permissions',case when manages_leaders and assignment.role_package='leader'
     then to_jsonb(internal.leader_panel_capabilities(target_club_id,target_team_id,person.id)) else null end,
    'permission_template',case when manages_leaders then details.permission_template else null end)
   order by case assignment.role_package when 'leader' then 0 when 'club_functionary' then 1 else 2 end,person.display_name,person.id)
   from core.assignments assignment
   join core.club_people person on person.id=assignment.club_person_id and person.club_id=assignment.club_id
   left join core.team_person_details details on details.club_id=assignment.club_id
    and details.team_id=assignment.team_id and details.club_person_id=assignment.club_person_id
   where assignment.club_id=target_club_id and assignment.team_id=target_team_id
    and assignment.role_package in('player','leader','club_functionary')
    and assignment.state='active' and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and person.status='active'),'[]'::jsonb));
end$$;

revoke all on function internal.leader_permission_catalog(),internal.leader_standard_capabilities(),
 internal.actor_has_event_capability(uuid,text),internal.preparation_area(uuid,text),
 internal.enforce_preparation_area(),internal.expand_club_scope_event_manage(),internal.enforce_leader_creation(),
 internal.assert_team_leaders_manager(uuid,uuid),internal.leader_panel_capabilities(uuid,uuid,uuid),
 internal.team_has_leaders_manager(uuid,uuid),
 internal.set_leader_permissions_for_actor(uuid,uuid,uuid,text[],text[],text,uuid),
 api.set_leader_permissions(uuid,uuid,uuid,text[],text[],text,uuid) from public,anon,authenticated;
grant execute on function internal.set_leader_permissions_for_actor(uuid,uuid,uuid,text[],text[],text,uuid),
 api.set_leader_permissions(uuid,uuid,uuid,text[],text[],text,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260929160000_team_leader_permissions','greenfield','TEAM-10 per-leader permissions, split event.manage, templates');
notify pgrst,'reload schema';
