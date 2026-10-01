-- TEAM-13: a player's main position plus alternative positions, and profile
-- pictures in the squad list.
--
-- The main position is one of the person's positions (catalog key or own
-- label); the others are the alternatives. Older clients keep working: a main
-- position that is no longer among the positions is cleared automatically.

alter table core.team_person_details
 add column if not exists main_position text
  check (main_position is null or length(btrim(main_position)) between 1 and 40);

create or replace function internal.validate_team_person_details()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if cardinality(new.positions)>20 or array_position(new.positions,null) is not null
  or exists(select 1 from unnest(new.positions) position where not exists(
   select 1 from core.teams team join core.sport_positions catalog on catalog.sport=team.sport
   where team.id=new.team_id and catalog.key=position)) then
  raise check_violation using message='invalid_position';
 end if;
 if new.main_position is not null and not (new.main_position=any(new.positions)
  or new.main_position=any(new.custom_positions)) then
  new.main_position:=null;
 end if;
 return new;
end$$;

create or replace function internal.set_team_person_details_v3_for_actor(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_position text,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare main text:=nullif(btrim(new_main_position),''); saved_revision bigint;
begin
 if main is not null and not (main=any(internal.normalize_labels(new_positions))
  or main=any(internal.normalize_labels(new_custom_positions))) then
  raise invalid_parameter_value using message='invalid_main_position'; end if;
 saved_revision:=internal.save_team_person_details(target_club_id,target_team_id,target_person_id,
  new_titles,new_positions,new_custom_titles,new_custom_positions,expected_revision,idempotency_key,
  'team.person_details.updated.v2');
 update core.team_person_details set main_position=main
 where team_id=target_team_id and club_person_id=target_person_id and main_position is distinct from main;
 return saved_revision;
end$$;

create or replace function api.set_team_person_details_v3(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_position text,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$
 select internal.set_team_person_details_v3_for_actor(target_club_id,target_team_id,target_person_id,
  new_titles,new_positions,new_custom_titles,new_custom_positions,new_main_position,expected_revision,idempotency_key)
$$;

revoke all on function internal.set_team_person_details_v3_for_actor(uuid,uuid,uuid,text[],text[],text[],text[],text,bigint,uuid),
 api.set_team_person_details_v3(uuid,uuid,uuid,text[],text[],text[],text[],text,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.set_team_person_details_v3_for_actor(uuid,uuid,uuid,text[],text[],text[],text[],text,bigint,uuid),
 api.set_team_person_details_v3(uuid,uuid,uuid,text[],text[],text[],text[],text,bigint,uuid) to authenticated;

-- The roles list carries the main position.
do $patch$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.list_team_roles_for_actor(uuid,uuid)'::regprocedure);
 patched:=replace(definition,
  '''positions'',coalesce(details.positions,''{}''::text[]),',
  '''positions'',coalesce(details.positions,''{}''::text[]),''main_position'',details.main_position,');
 if patched=definition then raise exception 'list_team_roles_for_actor: patch point not found'; end if;
 execute patched;
end$patch$;

-- Profile pictures of the team's current members, for members of the club.
-- Reading the pictures still goes through the avatar storage policy.
create or replace function internal.list_team_avatars_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_club_access(target_club_id)
  or not exists(select 1 from core.teams team where team.id=target_team_id and team.club_id=target_club_id) then
  raise insufficient_privilege using message='not_found'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('person_id',member.club_person_id,'object_key',avatar.object_key)
   order by member.club_person_id)
  from (select distinct assignment.club_person_id from core.assignments assignment
   where assignment.club_id=target_club_id and assignment.team_id=target_team_id
    and assignment.role_package in('player','leader','club_functionary') and assignment.state='active') member
  join core.person_account_links link on link.club_person_id=member.club_person_id
   and link.club_id=target_club_id and link.state='active'
  join core.profiles profile on profile.id=link.profile_id
  join core.profile_avatars avatar on avatar.id=profile.avatar_asset_id and avatar.state='active'),'[]'::jsonb);
end$$;

create or replace function api.list_team_avatars(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.list_team_avatars_for_actor(target_club_id,target_team_id)$$;

revoke all on function internal.list_team_avatars_for_actor(uuid,uuid),api.list_team_avatars(uuid,uuid)
 from public,anon,authenticated;
grant execute on function internal.list_team_avatars_for_actor(uuid,uuid),api.list_team_avatars(uuid,uuid)
 to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261001190000_main_position_and_roster_avatars','greenfield',
 'TEAM-13 main and alternative positions, profile pictures in the squad list'
where not exists(select 1 from internal.migration_provenance
 where migration_name='20261001190000_main_position_and_roster_avatars');
notify pgrst,'reload schema';
