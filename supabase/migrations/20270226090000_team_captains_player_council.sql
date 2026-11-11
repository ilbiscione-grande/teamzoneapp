-- Lagkapten, vice kapten och spelarråd (2026-11-11). A team's leaders mark a
-- player as captain or vice captain (one of each per team: giving the
-- armband to someone else takes it from the previous holder) and pick the
-- players in the player council. They are saved with the player's other
-- team details. The council gets its own team chat, "<lag> – Spelarråd",
-- for the team's leaders and the council's players; it is created when the
-- first player joins the council.

alter table core.team_person_details
  add column captain_role text check (captain_role is null or captain_role in ('captain','vice_captain')),
  add column player_council boolean not null default false;
create unique index team_person_details_captain_role on core.team_person_details (team_id, captain_role)
  where captain_role is not null;

alter table core.system_thread_bindings drop constraint system_thread_bindings_thread_kind_check;
alter table core.system_thread_bindings add constraint system_thread_bindings_thread_kind_check
  check (thread_kind in ('team','leader','council'));

-- As set_team_person_details_v5, with the captain role and the council.
-- Only players have them.
create or replace function internal.set_team_person_details_v6_for_actor(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_title text,new_main_position text,new_jersey_number integer,
 new_captain_role text,new_player_council boolean,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare saved_revision bigint; cached jsonb; is_player boolean; actor_id uuid:=auth.uid();
 armband text:=nullif(btrim(new_captain_role),''); council boolean:=coalesce(new_player_council,false);
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 if armband is not null and armband not in('captain','vice_captain') then
  raise invalid_parameter_value using message='invalid_captain_role'; end if;
 -- One lock per team: the armband moves between players.
 perform pg_advisory_xact_lock(hashtextextended('team-captains:'||target_team_id::text,0));
 select d.result into cached from internal.command_deduplication d
 where d.actor_profile_id=actor_id and d.command_type='team.person_details.updated.v2'
  and d.idempotency_key=set_team_person_details_v6_for_actor.idempotency_key;
 if cached is not null then return (cached->>'revision')::bigint; end if;
 saved_revision:=internal.set_team_person_details_v5_for_actor(target_club_id,target_team_id,target_person_id,
  new_titles,new_positions,new_custom_titles,new_custom_positions,new_main_title,new_main_position,
  new_jersey_number,expected_revision,idempotency_key);
 is_player:=internal.team_role_active(target_club_id,target_team_id,target_person_id,'player');
 if not is_player and (armband is not null or council) then
  raise check_violation using message='captain_needs_player_role'; end if;
 if armband is not null then
  update core.team_person_details set captain_role=null,revision=revision+1,updated_by=actor_id,updated_at=now()
  where team_id=target_team_id and captain_role=armband and club_person_id<>target_person_id;
 end if;
 update core.team_person_details set captain_role=armband,player_council=council
 where team_id=target_team_id and club_person_id=target_person_id
  and (captain_role is distinct from armband or player_council is distinct from council);
 if found then
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
  values(target_club_id,actor_id,'team.player_roles.updated.v1','team_person',target_person_id,saved_revision,
   jsonb_build_object('team_id',target_team_id,'captain_role',armband,'player_council',council));
 end if;
 return saved_revision;
end$$;

create or replace function api.set_team_person_details_v6(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_title text,new_main_position text,new_jersey_number integer,
 new_captain_role text,new_player_council boolean,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as
$$ select internal.set_team_person_details_v6_for_actor(target_club_id,target_team_id,target_person_id,
 new_titles,new_positions,new_custom_titles,new_custom_positions,new_main_title,new_main_position,new_jersey_number,
 new_captain_role,new_player_council,expected_revision,idempotency_key) $$;

revoke all on function
 internal.set_team_person_details_v6_for_actor(uuid,uuid,uuid,text[],text[],text[],text[],text,text,integer,text,boolean,bigint,uuid),
 api.set_team_person_details_v6(uuid,uuid,uuid,text[],text[],text[],text[],text,text,integer,text,boolean,bigint,uuid)
from public,anon,authenticated;
grant execute on function
 internal.set_team_person_details_v6_for_actor(uuid,uuid,uuid,text[],text[],text[],text[],text,text,integer,text,boolean,bigint,uuid),
 api.set_team_person_details_v6(uuid,uuid,uuid,text[],text[],text[],text[],text,text,integer,text,boolean,bigint,uuid)
to authenticated;

-- As in 20261123080000, with the captain role and the council.
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
    'main_position',details.main_position,'main_title',details.main_title,
    'jersey_number',details.jersey_number,
    'captain_role',details.captain_role,'player_council',coalesce(details.player_council,false),
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
    and assignment.role_package in('player','leader','club_functionary','referee','referee_assigner')
    and assignment.state='active' and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and person.status='active'),'[]'::jsonb));
end$$;

-- As in 20260827142616, with the council chat: the team's leaders (as in
-- the leader chat) and the players in the council. Thread type 'leader',
-- so no group rules apply; the binding kind is 'council'.
create or replace function internal.sync_team_system_threads(target_team_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare team_row core.teams%rowtype;kind_value text;thread_id_value uuid;created_count integer:=0;participant_count integer:=0;
 suffix text;
begin
 select * into team_row from core.teams where id=target_team_id for update;
 if team_row.id is null then raise no_data_found using message='team_not_found';end if;
 if team_row.status<>'active' then
  update core.thread_participants participant set state='removed',left_at=coalesce(left_at,now()),revision=revision+1
  where participant.thread_id in(select binding.thread_id from core.system_thread_bindings binding where binding.team_id=team_row.id)
   and participant.state='active';
  update core.message_threads thread set state='closed',closed_at=coalesce(closed_at,now()),revision=revision+1
  where thread.id in(select binding.thread_id from core.system_thread_bindings binding where binding.team_id=team_row.id) and thread.state='active';
  return jsonb_build_object('team_id',team_row.id,'state','closed');
 end if;
 foreach kind_value in array array['team','leader','council'] loop
  suffix:=case kind_value when 'leader' then ' – Ledarchatt' when 'council' then ' – Spelarråd' else ' – Lagchatt' end;
  thread_id_value:=null;
  select binding.thread_id into thread_id_value from core.system_thread_bindings binding
   where binding.team_id=team_row.id and binding.thread_kind=kind_value;
  if thread_id_value is null then
   -- The council chat waits for the council's first player.
   if kind_value='council' and not exists(select 1 from core.team_person_details details
    join core.assignments assignment on assignment.club_id=details.club_id and assignment.team_id=details.team_id
     and assignment.club_person_id=details.club_person_id and assignment.role_package='player'
     and assignment.state='active' and assignment.starts_at<=now() and(assignment.ends_at is null or assignment.ends_at>now())
    where details.team_id=team_row.id and details.player_council) then
    continue;
   end if;
   insert into core.message_threads(club_id,thread_type,subject,created_by)
   values(team_row.club_id,case kind_value when 'council' then 'leader' else kind_value end,team_row.name||suffix,team_row.created_by)
   returning id into thread_id_value;
   insert into core.thread_scopes(thread_id,club_id,team_id,scope_role)
   values(thread_id_value,team_row.club_id,team_row.id,'owner');
   insert into core.system_thread_bindings(team_id,club_id,thread_kind,thread_id)
   values(team_row.id,team_row.club_id,kind_value,thread_id_value);
   created_count:=created_count+1;
  end if;
  update core.message_threads set subject=team_row.name||suffix
  where id=thread_id_value and subject is distinct from team_row.name||suffix;
  update core.message_threads set state='active',closed_at=null where id=thread_id_value and state='closed';
  with eligible as(
   select distinct on(link.profile_id) link.profile_id,link.club_id,link.club_person_id
   from core.assignments assignment
   join core.person_account_links link on link.club_id=assignment.club_id
    and link.club_person_id=assignment.club_person_id and link.state='active'
   where assignment.team_id=team_row.id and assignment.club_id=team_row.club_id
    and assignment.state='active' and assignment.starts_at<=now()
    and(assignment.ends_at is null or assignment.ends_at>now())
    and(kind_value='team'
     or(assignment.role_package='leader' and exists(
      select 1 from core.capability_grants grant_row where grant_row.assignment_id=assignment.id
       and grant_row.club_id=assignment.club_id and grant_row.capability='team.roster.view'
       and grant_row.scope_type='team' and grant_row.scope_id=team_row.id
       and grant_row.starts_at<=now() and(grant_row.ends_at is null or grant_row.ends_at>now())))
     or(kind_value='council' and assignment.role_package='player' and exists(
      select 1 from core.team_person_details details where details.team_id=team_row.id
       and details.club_person_id=assignment.club_person_id and details.player_council)))
   order by link.profile_id,assignment.starts_at desc,assignment.id
  )
  insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role,state,left_at)
  select thread_id_value,eligible.profile_id,eligible.club_id,eligible.club_person_id,'member','active',null from eligible
  on conflict(thread_id,profile_id) do update set club_id=excluded.club_id,club_person_id=excluded.club_person_id,
   state='active',left_at=null,revision=core.thread_participants.revision+1;
  with eligible as(
   select distinct link.profile_id from core.assignments assignment
   join core.person_account_links link on link.club_id=assignment.club_id
    and link.club_person_id=assignment.club_person_id and link.state='active'
   where assignment.team_id=team_row.id and assignment.club_id=team_row.club_id
    and assignment.state='active' and assignment.starts_at<=now()
    and(assignment.ends_at is null or assignment.ends_at>now())
    and(kind_value='team'
     or(assignment.role_package='leader' and exists(
      select 1 from core.capability_grants grant_row where grant_row.assignment_id=assignment.id
       and grant_row.capability='team.roster.view' and grant_row.scope_type='team' and grant_row.scope_id=team_row.id
       and grant_row.starts_at<=now() and(grant_row.ends_at is null or grant_row.ends_at>now())))
     or(kind_value='council' and assignment.role_package='player' and exists(
      select 1 from core.team_person_details details where details.team_id=team_row.id
       and details.club_person_id=assignment.club_person_id and details.player_council)))
  )
  update core.thread_participants participant set state='removed',left_at=now(),revision=revision+1
  where participant.thread_id=thread_id_value and participant.state='active'
   and not exists(select 1 from eligible where eligible.profile_id=participant.profile_id);
  select count(*) into participant_count from core.thread_participants where thread_id=thread_id_value and state='active';
 end loop;
 return jsonb_build_object('team_id',team_row.id,'threads_created',created_count,'last_participant_count',participant_count);
end;$$;

create or replace function internal.sync_system_threads_from_team_person_details()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (tg_op='INSERT' and new.player_council) or (tg_op='UPDATE' and old.player_council is distinct from new.player_council) then
  perform internal.sync_team_system_threads(new.team_id);
 end if;
 return new;
end;$$;
revoke all on function internal.sync_system_threads_from_team_person_details() from public,anon,authenticated;
create trigger team_person_details_sync_system_threads after insert or update of player_council on core.team_person_details
 for each row execute function internal.sync_system_threads_from_team_person_details();

notify pgrst,'reload schema';
