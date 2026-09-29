-- TEAM-09: add and change a person's role in a team, including adding an
-- existing club leader to another team. Roles stay history-preserving:
-- a change ends the old role period and starts a new one, and capability
-- grants follow the active assignment through the existing triggers
-- (leader bundle; player context synced from the home-team period).
--
-- Scope: player and leader only. Club functionary is a club-wide mandate and
-- guardian needs a child relation; neither is granted here. A manager can
-- give themselves an additional role, but cannot change or remove their own
-- leader role (which would remove the rights used to do it).

create function internal.assert_team_role_manager(target_club_id uuid,target_team_id uuid)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if target_team_id is null
  or not exists(select 1 from core.teams team where team.id=target_team_id and team.club_id=target_club_id and team.status='active')
  or not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
end$$;

create function internal.team_role_active(target_club_id uuid,target_team_id uuid,target_person_id uuid,target_role text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from core.assignments assignment
  where assignment.club_id=target_club_id and assignment.team_id=target_team_id
   and assignment.club_person_id=target_person_id and assignment.role_package=target_role
   and assignment.state='active' and assignment.starts_at<=now()
   and (assignment.ends_at is null or assignment.ends_at>now()))
$$;

create function internal.list_team_roles_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
  and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
 return jsonb_build_object(
  'can_manage',internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage'),
  'roles',coalesce((select jsonb_agg(jsonb_build_object(
    'person_id',person.id,'name',person.display_name,'role',assignment.role_package,
    'starts_at',assignment.starts_at,'is_self',internal.actor_owns_club_person(target_club_id,person.id))
   order by case assignment.role_package when 'leader' then 0 when 'club_functionary' then 1 else 2 end,person.display_name,person.id)
   from core.assignments assignment
   join core.club_people person on person.id=assignment.club_person_id and person.club_id=assignment.club_id
   where assignment.club_id=target_club_id and assignment.team_id=target_team_id
    and assignment.role_package in('player','leader','club_functionary')
    and assignment.state='active' and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and person.status='active'),'[]'::jsonb));
end$$;

-- Leaders and functionaries elsewhere in the club who are not yet leaders of
-- this team: "lägg till från klubbens befintliga ledare".
create function internal.list_club_leader_candidates_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 return coalesce((select jsonb_agg(jsonb_build_object('person_id',candidate.id,'name',candidate.display_name,
   'context',candidate.context,'is_self',internal.actor_owns_club_person(target_club_id,candidate.id))
   order by candidate.display_name,candidate.id)
  from(
   select person.id,person.display_name,
    string_agg(distinct coalesce(team.name,'Klubben'),', ') context
   from core.club_people person
   join core.assignments assignment on assignment.club_person_id=person.id and assignment.club_id=person.club_id
   left join core.teams team on team.id=assignment.team_id and team.club_id=assignment.club_id
   where person.club_id=target_club_id and person.status='active'
    and assignment.role_package in('leader','club_functionary')
    and assignment.state='active' and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and not internal.team_role_active(target_club_id,target_team_id,person.id,'leader')
   group by person.id,person.display_name) candidate),'[]'::jsonb);
end$$;

-- Starts a role now. Player = a home-team period here (the existing trigger
-- adds the player context); leader = a leader assignment (the existing
-- trigger materializes the leader capabilities).
create function internal.start_team_role(target_club_id uuid,target_team_id uuid,target_person_id uuid,target_role text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if internal.team_role_active(target_club_id,target_team_id,target_person_id,target_role) then return; end if;
 if target_role='player' then
  if exists(select 1 from core.team_assignments home where home.club_id=target_club_id
   and home.club_person_id=target_person_id and home.state='active' and home.team_id<>target_team_id) then
   raise check_violation using message='home_in_other_team';
  end if;
  if not exists(select 1 from core.team_assignments home where home.club_id=target_club_id
   and home.club_person_id=target_person_id and home.team_id=target_team_id and home.state='active') then
   insert into core.team_assignments(club_id,team_id,club_person_id,starts_at,created_by)
   values(target_club_id,target_team_id,target_person_id,now(),auth.uid());
  end if;
 else
  insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
  values(target_club_id,target_team_id,target_person_id,'leader','active',now(),auth.uid());
 end if;
end$$;

create function internal.stop_team_role(target_club_id uuid,target_team_id uuid,target_person_id uuid,target_role text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if target_role='player' then
  update core.team_assignments set state='ended',ends_at=greatest(now(),starts_at+interval '1 microsecond'),
   ended_by=auth.uid(),revision=revision+1
  where club_id=target_club_id and team_id=target_team_id and club_person_id=target_person_id and state='active';
 else
  update core.assignments set state='ended',ends_at=greatest(now(),starts_at+interval '1 microsecond'),revision=revision+1
  where club_id=target_club_id and team_id=target_team_id and club_person_id=target_person_id
   and role_package=target_role and state='active';
 end if;
end$$;

create function internal.team_role_command(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 from_role text,to_role text,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); command text; existing jsonb; result jsonb;
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 command:=case when from_role is null then 'roster.role.add.v1' when to_role is null then 'roster.role.remove.v1' else 'roster.role.change.v1' end;
 if idempotency_key is null or (from_role is not null and from_role not in('player','leader'))
  or (to_role is not null and to_role not in('player','leader')) or from_role is not distinct from to_role then
  raise invalid_parameter_value using message='invalid_role';
 end if;
 select dedup.result into existing from internal.command_deduplication dedup
 where dedup.actor_profile_id=actor_id and dedup.command_type=command
  and dedup.idempotency_key=team_role_command.idempotency_key;
 if existing is not null then return existing; end if;
 perform pg_advisory_xact_lock(hashtextextended('team_role:'||target_club_id::text||':'||target_person_id::text,0));
 if not exists(select 1 from core.club_people person where person.id=target_person_id
  and person.club_id=target_club_id and person.status='active') then
  raise invalid_parameter_value using message='invalid_person';
 end if;
 if from_role is not null then
  if not internal.team_role_active(target_club_id,target_team_id,target_person_id,from_role) then
   raise serialization_failure using message='stale_role';
  end if;
  if from_role='leader' and internal.actor_owns_club_person(target_club_id,target_person_id) then
   raise check_violation using message='own_leader_role';
  end if;
  -- Validate the new role before ending the old one.
  if to_role='player' and exists(select 1 from core.team_assignments home where home.club_id=target_club_id
   and home.club_person_id=target_person_id and home.state='active' and home.team_id<>target_team_id) then
   raise check_violation using message='home_in_other_team';
  end if;
  perform internal.stop_team_role(target_club_id,target_team_id,target_person_id,from_role);
 end if;
 if to_role is not null then
  perform internal.start_team_role(target_club_id,target_team_id,target_person_id,to_role);
 end if;
 result:=jsonb_build_object('person_id',target_person_id,'from_role',from_role,'to_role',to_role);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,command,result);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,command,'club_person',target_person_id,1,
  jsonb_build_object('team_id',target_team_id,'from_role',from_role,'to_role',to_role));
 return result;
end$$;

create function api.list_team_roles(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.list_team_roles_for_actor(target_club_id,target_team_id)$$;
create function api.list_club_leader_candidates(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.list_club_leader_candidates_for_actor(target_club_id,target_team_id)$$;
create function api.add_team_role(target_club_id uuid,target_team_id uuid,target_person_id uuid,role text,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.team_role_command(target_club_id,target_team_id,target_person_id,null,role,idempotency_key)$$;
create function api.change_team_role(target_club_id uuid,target_team_id uuid,target_person_id uuid,from_role text,to_role text,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.team_role_command(target_club_id,target_team_id,target_person_id,from_role,to_role,idempotency_key)$$;
create function api.remove_team_role(target_club_id uuid,target_team_id uuid,target_person_id uuid,role text,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.team_role_command(target_club_id,target_team_id,target_person_id,role,null,idempotency_key)$$;

revoke all on function internal.assert_team_role_manager(uuid,uuid),internal.team_role_active(uuid,uuid,uuid,text),
 internal.list_team_roles_for_actor(uuid,uuid),internal.list_club_leader_candidates_for_actor(uuid,uuid),
 internal.start_team_role(uuid,uuid,uuid,text),internal.stop_team_role(uuid,uuid,uuid,text),
 internal.team_role_command(uuid,uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function internal.list_team_roles_for_actor(uuid,uuid),internal.list_club_leader_candidates_for_actor(uuid,uuid),
 internal.team_role_command(uuid,uuid,uuid,text,text,uuid) to authenticated;
revoke all on function api.list_team_roles(uuid,uuid),api.list_club_leader_candidates(uuid,uuid),
 api.add_team_role(uuid,uuid,uuid,text,uuid),api.change_team_role(uuid,uuid,uuid,text,text,uuid),
 api.remove_team_role(uuid,uuid,uuid,text,uuid) from public,anon;
grant execute on function api.list_team_roles(uuid,uuid),api.list_club_leader_candidates(uuid,uuid),
 api.add_team_role(uuid,uuid,uuid,text,uuid),api.change_team_role(uuid,uuid,uuid,text,text,uuid),
 api.remove_team_role(uuid,uuid,uuid,text,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260929090000_team09_team_roles','greenfield','TEAM-09 add/change team roles and add existing club leaders');
notify pgrst,'reload schema';
