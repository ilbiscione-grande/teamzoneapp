-- Player attributes in a team's squad (decided by the product owner
-- 2026-11-21): the leaders tick, per player, which attributes are the
-- player's strengths and which are areas to develop. No grades.
--
--   catalogue   a fixed list per sport, plus up to 15 of the team's own;
--   who sees    the team's leaders only (team.roster.manage), never the
--               player or guardians;
--   leaving     when the player role in the team ends, the player's
--               attributes in that team are deleted;
--   used for    suggesting players for positions in a formation (later
--               steps, docs/implementation/player-attributes.md).

create table core.sport_attributes(
 sport text not null check(sport in('football','handball','other')),
 key text not null check(key ~ '^[a-z][a-z0-9_]{1,39}$'),
 area text not null check(area in('physical','technical','tactical','mental')),
 sort smallint not null,
 primary key(sport,key)
);
alter table core.sport_attributes enable row level security;
revoke all on core.sport_attributes from public,anon,authenticated;

insert into core.sport_attributes(sport,key,area,sort) values
 ('football','acceleration','physical',10),('football','speed','physical',20),
 ('football','strength','physical',30),('football','endurance','physical',40),
 ('football','agility','physical',50),('football','jumping','physical',60),
 ('football','heading','technical',110),('football','shooting','technical',120),
 ('football','crossing','technical',130),('football','passing','technical',140),
 ('football','long_passing','technical',150),('football','first_touch','technical',160),
 ('football','dribbling','technical',170),('football','weak_foot','technical',180),
 ('football','finishing','technical',190),('football','set_pieces','technical',200),
 ('football','goalkeeping_hands','technical',210),('football','goalkeeping_feet','technical',220),
 ('football','defending_1v1','tactical',310),('football','attacking_1v1','tactical',320),
 ('football','positioning','tactical',330),('football','game_reading','tactical',340),
 ('football','pressing','tactical',350),('football','duels','tactical',360),
 ('football','runs_in_behind','tactical',370),
 ('football','leadership','mental',410),('football','communication','mental',420),
 ('football','work_rate','mental',430),('football','composure','mental',440),
 ('handball','acceleration','physical',10),('handball','speed','physical',20),
 ('handball','strength','physical',30),('handball','endurance','physical',40),
 ('handball','agility','physical',50),('handball','jumping','physical',60),
 ('handball','shooting','technical',120),('handball','long_shots','technical',125),
 ('handball','passing','technical',140),('handball','feints','technical',170),
 ('handball','finishing','technical',190),('handball','goalkeeping','technical',210),
 ('handball','defending_1v1','tactical',310),('handball','attacking_1v1','tactical',320),
 ('handball','positioning','tactical',330),('handball','game_reading','tactical',340),
 ('handball','duels','tactical',360),('handball','fast_breaks','tactical',380),
 ('handball','leadership','mental',410),('handball','communication','mental',420),
 ('handball','work_rate','mental',430),('handball','composure','mental',440),
 ('other','acceleration','physical',10),('other','speed','physical',20),
 ('other','strength','physical',30),('other','endurance','physical',40),
 ('other','agility','physical',50),
 ('other','game_reading','tactical',340),
 ('other','leadership','mental',410),('other','communication','mental',420),
 ('other','work_rate','mental',430),('other','composure','mental',440);

-- The team's own attributes, beside the sport's list.
create table core.team_attributes(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 team_id uuid not null references core.teams(id) on delete cascade,
 label text not null check(length(label) between 1 and 40 and label=btrim(label)),
 created_at timestamptz not null default now(),
 created_by uuid
);
create unique index team_attributes_label on core.team_attributes(team_id,lower(label));
alter table core.team_attributes enable row level security;
revoke all on core.team_attributes from public,anon,authenticated;
create policy team_attributes_no_direct_access on core.team_attributes
 for all to authenticated using(false) with check(false);

-- One row per ticked attribute: a catalogue key, or a team attribute's id.
create table core.player_attributes(
 club_id uuid not null,
 team_id uuid not null references core.teams(id) on delete cascade,
 club_person_id uuid not null references core.club_people(id) on delete cascade,
 attribute_key text not null check(length(attribute_key) between 2 and 40),
 assessment text not null check(assessment in('strength','development')),
 updated_at timestamptz not null default now(),
 updated_by uuid,
 primary key(team_id,club_person_id,attribute_key)
);
create index player_attributes_person on core.player_attributes(club_person_id);
alter table core.player_attributes enable row level security;
revoke all on core.player_attributes from public,anon,authenticated;
create policy player_attributes_no_direct_access on core.player_attributes
 for all to authenticated using(false) with check(false);

create or replace function internal.require_player_attributes_access(target_club_id uuid,target_team_id uuid)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not exists(select 1 from core.teams team where team.id=target_team_id and team.club_id=target_club_id)
  or not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
end$$;

-- The keys a team may tick: its sport's list and its own attributes.
create or replace function internal.team_attribute_keys(target_team_id uuid)
returns setof text language sql stable security definer set search_path='' as $$
 select catalog.key from core.teams team
 join core.sport_attributes catalog on catalog.sport=team.sport where team.id=target_team_id
 union all
 select own.id::text from core.team_attributes own where own.team_id=target_team_id
$$;

-- The squad's attributes for the team's leaders: the lists, and each
-- active player with what is ticked (keys no longer in the lists are left
-- out, e.g. after the team changed sport).
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

-- Replaces what is ticked for one player; an attribute is a strength or an
-- area to develop, not both. Returns the whole list again.
create or replace function internal.set_player_attributes_for_actor(target_club_id uuid,target_team_id uuid,
 target_person_id uuid,new_strengths text[],new_development text[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare strengths text[]; development text[];
begin
 perform internal.require_player_attributes_access(target_club_id,target_team_id);
 if not exists(select 1 from core.assignments assignment join core.club_people person
   on person.id=assignment.club_person_id and person.club_id=assignment.club_id and person.status='active'
  where assignment.club_id=target_club_id and assignment.team_id=target_team_id
   and assignment.club_person_id=target_person_id and assignment.role_package='player' and assignment.state='active') then
  raise check_violation using message='attributes_need_player_role';
 end if;
 strengths:=coalesce(array(select distinct v from unnest(coalesce(new_strengths,'{}')) v),'{}');
 development:=coalesce(array(select distinct v from unnest(coalesce(new_development,'{}')) v),'{}');
 if strengths && development then raise invalid_parameter_value using message='attribute_both_ways'; end if;
 if exists(select 1 from unnest(strengths||development) v
  where v is null or v not in(select internal.team_attribute_keys(target_team_id))) then
  raise invalid_parameter_value using message='invalid_attribute';
 end if;
 delete from core.player_attributes value where value.team_id=target_team_id and value.club_person_id=target_person_id
  and not exists(select 1 from unnest(strengths) s where s=value.attribute_key and value.assessment='strength')
  and not exists(select 1 from unnest(development) d where d=value.attribute_key and value.assessment='development');
 insert into core.player_attributes(club_id,team_id,club_person_id,attribute_key,assessment,updated_by)
 select target_club_id,target_team_id,target_person_id,item.key,item.assessment,auth.uid()
 from (select s key,'strength' assessment from unnest(strengths) s
  union all select d,'development' from unnest(development) d) item
 on conflict(team_id,club_person_id,attribute_key) do nothing;
 return internal.get_team_player_attributes_for_actor(target_club_id,target_team_id);
end$$;

-- Adds a team attribute (no [attribute_id]) or renames one.
create or replace function internal.save_team_attribute_for_actor(target_club_id uuid,target_team_id uuid,
 attribute_id uuid,new_label text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare clean_label text:=regexp_replace(btrim(coalesce(new_label,'')),'\s+',' ','g');
begin
 perform internal.require_player_attributes_access(target_club_id,target_team_id);
 if length(clean_label) not between 1 and 40 then raise invalid_parameter_value using message='invalid_label'; end if;
 perform 1 from core.teams where id=target_team_id for update;
 if exists(select 1 from core.team_attributes own where own.team_id=target_team_id and lower(own.label)=lower(clean_label)
  and own.id is distinct from attribute_id) then
  raise unique_violation using message='attribute_label_taken';
 end if;
 if attribute_id is null then
  if (select count(*) from core.team_attributes own where own.team_id=target_team_id)>=15 then
   raise check_violation using message='too_many_attributes'; end if;
  insert into core.team_attributes(club_id,team_id,label,created_by) values(target_club_id,target_team_id,clean_label,auth.uid());
 else
  update core.team_attributes own set label=clean_label
  where own.id=attribute_id and own.team_id=target_team_id;
  if not found then raise no_data_found using message='attribute_not_found'; end if;
 end if;
 return internal.get_team_player_attributes_for_actor(target_club_id,target_team_id);
end$$;

-- Removes a team attribute and every tick on it.
create or replace function internal.delete_team_attribute_for_actor(target_club_id uuid,target_team_id uuid,attribute_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform internal.require_player_attributes_access(target_club_id,target_team_id);
 delete from core.player_attributes where team_id=target_team_id and attribute_key=attribute_id::text;
 delete from core.team_attributes own where own.id=attribute_id and own.team_id=target_team_id;
 return internal.get_team_player_attributes_for_actor(target_club_id,target_team_id);
end$$;

-- When the player role in the team ends, the player's attributes there go.
create or replace function internal.clear_player_attributes_on_role_end()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.state='active' and new.state<>'active' and old.team_id is not null and old.role_package='player'
  and not exists(select 1 from core.assignments a where a.id<>old.id and a.club_id=old.club_id
   and a.team_id=old.team_id and a.club_person_id=old.club_person_id and a.role_package='player' and a.state='active') then
  delete from core.player_attributes where team_id=old.team_id and club_person_id=old.club_person_id;
 end if;
 return new;
end$$;
create trigger assignments_clear_player_attributes after update of state on core.assignments
for each row execute function internal.clear_player_attributes_on_role_end();

create function api.get_team_player_attributes(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$ select internal.get_team_player_attributes_for_actor(target_club_id,target_team_id) $$;
create function api.set_player_attributes(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_strengths text[],new_development text[])
returns jsonb language sql security invoker set search_path='' as
$$ select internal.set_player_attributes_for_actor(target_club_id,target_team_id,target_person_id,new_strengths,new_development) $$;
create function api.save_team_attribute(target_club_id uuid,target_team_id uuid,attribute_id uuid,new_label text)
returns jsonb language sql security invoker set search_path='' as
$$ select internal.save_team_attribute_for_actor(target_club_id,target_team_id,attribute_id,new_label) $$;
create function api.delete_team_attribute(target_club_id uuid,target_team_id uuid,attribute_id uuid)
returns jsonb language sql security invoker set search_path='' as
$$ select internal.delete_team_attribute_for_actor(target_club_id,target_team_id,attribute_id) $$;

revoke all on function
 internal.require_player_attributes_access(uuid,uuid),internal.team_attribute_keys(uuid),
 internal.get_team_player_attributes_for_actor(uuid,uuid),
 internal.set_player_attributes_for_actor(uuid,uuid,uuid,text[],text[]),
 internal.save_team_attribute_for_actor(uuid,uuid,uuid,text),
 internal.delete_team_attribute_for_actor(uuid,uuid,uuid),
 internal.clear_player_attributes_on_role_end(),
 api.get_team_player_attributes(uuid,uuid),api.set_player_attributes(uuid,uuid,uuid,text[],text[]),
 api.save_team_attribute(uuid,uuid,uuid,text),api.delete_team_attribute(uuid,uuid,uuid)
from public,anon,authenticated;
grant execute on function
 internal.get_team_player_attributes_for_actor(uuid,uuid),
 internal.set_player_attributes_for_actor(uuid,uuid,uuid,text[],text[]),
 internal.save_team_attribute_for_actor(uuid,uuid,uuid,text),
 internal.delete_team_attribute_for_actor(uuid,uuid,uuid),
 api.get_team_player_attributes(uuid,uuid),api.set_player_attributes(uuid,uuid,uuid,text[],text[]),
 api.save_team_attribute(uuid,uuid,uuid,text),api.delete_team_attribute(uuid,uuid,uuid)
to authenticated;
notify pgrst,'reload schema';
