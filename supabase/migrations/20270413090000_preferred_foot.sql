-- A player's preferred foot (asked for by the product owner 2026-11-21),
-- set by the team's leaders on the Egenskaper tab and kept like the
-- attributes: per team, seen only by the team's leaders, deleted when the
-- player role in the team ends.
--   left, right    one foot;
--   both_equal     both, equally good;
--   both_left      both, better with the left (the right is decent);
--   both_right     both, better with the right (the left is decent).

create table core.player_feet(
 club_id uuid not null,
 team_id uuid not null references core.teams(id) on delete cascade,
 club_person_id uuid not null references core.club_people(id) on delete cascade,
 foot text not null check(foot in('left','right','both_equal','both_left','both_right')),
 updated_at timestamptz not null default now(),
 updated_by uuid,
 primary key(team_id,club_person_id)
);
create index player_feet_person on core.player_feet(club_person_id);
alter table core.player_feet enable row level security;
revoke all on core.player_feet from public,anon,authenticated;
create policy player_feet_no_direct_access on core.player_feet
 for all to authenticated using(false) with check(false);

-- As in 20270407090000, each player with their foot.
create or replace function internal.get_team_player_attributes_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_sport text;
begin
 perform internal.require_player_attributes_access(target_club_id,target_team_id);
 select sport into team_sport from core.teams where id=target_team_id;
 return jsonb_build_object(
  'sport',team_sport,
  'catalog',coalesce((select jsonb_agg(jsonb_build_object('key',catalog.key,'area',catalog.area) order by catalog.sort)
   from core.sport_attributes catalog where catalog.sport=team_sport),'[]'::jsonb),
  'custom',coalesce((select jsonb_agg(jsonb_build_object('id',own.id,'label',own.label) order by lower(own.label),own.id)
   from core.team_attributes own where own.team_id=target_team_id),'[]'::jsonb),
  'players',coalesce((select jsonb_agg(jsonb_build_object(
    'person_id',person.id,'name',person.display_name,
    'foot',(select feet.foot from core.player_feet feet where feet.team_id=target_team_id and feet.club_person_id=person.id),
    'strengths',coalesce((select jsonb_agg(value.attribute_key order by value.attribute_key) from core.player_attributes value
     where value.team_id=target_team_id and value.club_person_id=person.id and value.assessment='strength'
      and value.attribute_key in(select internal.team_attribute_keys(target_team_id))),'[]'::jsonb),
    'development',coalesce((select jsonb_agg(value.attribute_key order by value.attribute_key) from core.player_attributes value
     where value.team_id=target_team_id and value.club_person_id=person.id and value.assessment='development'
      and value.attribute_key in(select internal.team_attribute_keys(target_team_id))),'[]'::jsonb))
   order by person.display_name,person.id)
   from core.club_people person
   where person.club_id=target_club_id and person.status='active'
    and exists(select 1 from core.assignments assignment where assignment.club_id=target_club_id
     and assignment.team_id=target_team_id and assignment.club_person_id=person.id
     and assignment.role_package='player' and assignment.state='active'
     and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now()))),'[]'::jsonb));
end$$;

-- Sets the player's foot; no [new_foot] takes it away. Returns the list.
create or replace function internal.set_player_foot_for_actor(target_club_id uuid,target_team_id uuid,
 target_person_id uuid,new_foot text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform internal.require_player_attributes_access(target_club_id,target_team_id);
 if not exists(select 1 from core.assignments assignment join core.club_people person
   on person.id=assignment.club_person_id and person.club_id=assignment.club_id and person.status='active'
  where assignment.club_id=target_club_id and assignment.team_id=target_team_id
   and assignment.club_person_id=target_person_id and assignment.role_package='player' and assignment.state='active') then
  raise check_violation using message='attributes_need_player_role';
 end if;
 if new_foot is null then
  delete from core.player_feet where team_id=target_team_id and club_person_id=target_person_id;
 elsif new_foot not in('left','right','both_equal','both_left','both_right') then
  raise invalid_parameter_value using message='invalid_foot';
 else
  insert into core.player_feet(club_id,team_id,club_person_id,foot,updated_by)
  values(target_club_id,target_team_id,target_person_id,new_foot,auth.uid())
  on conflict(team_id,club_person_id) do update set foot=excluded.foot,updated_at=now(),updated_by=excluded.updated_by;
 end if;
 return internal.get_team_player_attributes_for_actor(target_club_id,target_team_id);
end$$;

-- As in 20270407090000, the foot goes too when the player role ends.
create or replace function internal.clear_player_attributes_on_role_end()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.state='active' and new.state<>'active' and old.team_id is not null and old.role_package='player'
  and not exists(select 1 from core.assignments a where a.id<>old.id and a.club_id=old.club_id
   and a.team_id=old.team_id and a.club_person_id=old.club_person_id and a.role_package='player' and a.state='active') then
  delete from core.player_attributes where team_id=old.team_id and club_person_id=old.club_person_id;
  delete from core.player_feet where team_id=old.team_id and club_person_id=old.club_person_id;
 end if;
 return new;
end$$;

create function api.set_player_foot(target_club_id uuid,target_team_id uuid,target_person_id uuid,new_foot text)
returns jsonb language sql security invoker set search_path='' as
$$ select internal.set_player_foot_for_actor(internal.club_of_team(target_club_id,target_team_id),target_team_id,
 target_person_id,new_foot) $$;

revoke all on function internal.set_player_foot_for_actor(uuid,uuid,uuid,text),api.set_player_foot(uuid,uuid,uuid,text)
from public,anon,authenticated;
grant execute on function internal.set_player_foot_for_actor(uuid,uuid,uuid,text),api.set_player_foot(uuid,uuid,uuid,text)
to authenticated;
notify pgrst,'reload schema';
