-- A team's own formations with what each place asks for (step 3 of
-- docs/implementation/player-attributes.md): the lines ("4-3-3"), the
-- match format, and per place an optional position and the attributes that
-- matter there, each important (1) or very important (2). Tacticsboard and
-- the app's line-up share them; the suggestion (step 4) reads them.
--
-- Places use the app's codes: GK (none in 3v3), then each line from the own
-- goal, left to right: 1A, 1B, … 2A, … Tacticsboard places a formation's
-- players in the same order. A place's general position follows its line:
-- the first of several lines defends, the last attacks, the rest midfield.
--
-- Only those who see the attributes (the team's leaders) see the formations.

create table core.team_formations(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 team_id uuid not null references core.teams(id) on delete cascade,
 name text not null check(length(name) between 1 and 60 and name=btrim(name)),
 lines text not null check(lines ~ '^[1-6](-[1-6]){0,4}$'),
 match_format text not null check(match_format in('3v3','5v5','7v7','9v9','11v11')),
 slots jsonb not null default '[]' check(jsonb_typeof(slots)='array'),
 revision bigint not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid
);
create unique index team_formations_name on core.team_formations(team_id,lower(name));
alter table core.team_formations enable row level security;
revoke all on core.team_formations from public,anon,authenticated;
create policy team_formations_no_direct_access on core.team_formations
 for all to authenticated using(false) with check(false);

-- The places of [lines] in [match_format], in order, with the general
-- position each asks for.
create or replace function internal.formation_slots(lines text,match_format text)
returns table(code text,position_group text,sort integer)
language sql immutable set search_path='' as $$
 with parts as (
  select part.line::integer line,part.players::integer players,cardinality(string_to_array(lines,'-')) total
  from unnest(string_to_array(lines,'-')) with ordinality as part(players,line))
 select 'GK','goalkeeper',0 where match_format<>'3v3'
 union all
 select parts.line||chr(64+place),
  case when parts.line=1 and parts.total>1 then 'defender' when parts.line=parts.total then 'forward' else 'midfielder' end,
  parts.line*10+place
 from parts cross join generate_series(1,parts.players) place
 order by 3
$$;

-- The players on the pitch in [match_format], the goalkeeper included.
create or replace function internal.format_players(match_format text)
returns integer language sql immutable set search_path='' as $$
 select case match_format when '3v3' then 3 when '5v5' then 5 when '7v7' then 7 when '9v9' then 9 else 11 end
$$;

create or replace function internal.require_team_formations_access(target_club_id uuid,target_team_id uuid)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.require_player_attributes_access(target_club_id,target_team_id);
end$$;

-- One formation as the clients read it: every place, with what is set for
-- it; requirements on attributes the team no longer has are left out.
create or replace function internal.team_formation_json(formation core.team_formations)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',formation.id,'name',formation.name,'lines',formation.lines,
  'match_format',formation.match_format,'revision',formation.revision,'updated_at',formation.updated_at,
  'slots',coalesce((select jsonb_agg(jsonb_build_object('code',slot.code,'group',slot.position_group,
    'position',saved.value->>'position',
    'requirements',coalesce((select jsonb_agg(requirement.value order by requirement.ordinality)
     from jsonb_array_elements(saved.value->'requirements') with ordinality requirement
     where requirement.value->>'attribute' in(select internal.team_attribute_keys(formation.team_id))),'[]'::jsonb))
    order by slot.sort)
   from internal.formation_slots(formation.lines,formation.match_format) slot
   left join lateral (select value from jsonb_array_elements(formation.slots) value
    where value->>'code'=slot.code limit 1) saved on true),'[]'::jsonb))
$$;

create or replace function internal.list_team_formations_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.require_team_formations_access(target_club_id,target_team_id);
 return jsonb_build_object('formations',coalesce((select jsonb_agg(internal.team_formation_json(formation)
   order by lower(formation.name),formation.id)
  from core.team_formations formation where formation.team_id=target_team_id),'[]'::jsonb));
end$$;

-- Adds a formation (no [formation_id]) or replaces one. [new_slots] holds,
-- per place code, an optional position key of the team's sport and up to
-- six requirements {attribute, weight 1|2}; places left out ask for nothing
-- beyond their line. Returns the saved formation.
create or replace function internal.save_team_formation_for_actor(target_club_id uuid,target_team_id uuid,
 formation_id uuid,new_name text,new_lines text,new_match_format text,new_slots jsonb,expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare clean_name text:=regexp_replace(btrim(coalesce(new_name,'')),'\s+',' ','g');
 clean_lines text:=regexp_replace(coalesce(new_lines,''),'\s','','g');
 team_sport text; clean_slots jsonb; saved core.team_formations;
begin
 perform internal.require_team_formations_access(target_club_id,target_team_id);
 if length(clean_name) not between 1 and 60 then raise invalid_parameter_value using message='invalid_name'; end if;
 if new_match_format is null or new_match_format not in('3v3','5v5','7v7','9v9','11v11')
  or clean_lines !~ '^[1-6](-[1-6]){0,4}$'
  or (select count(*) from internal.formation_slots(clean_lines,new_match_format))<>internal.format_players(new_match_format) then
  raise invalid_parameter_value using message='invalid_formation';
 end if;
 if jsonb_typeof(coalesce(new_slots,'[]'))<>'array' then raise invalid_parameter_value using message='invalid_slots'; end if;
 select sport into team_sport from core.teams where id=target_team_id for update;
 -- Each place once, a known code, a position of the sport, valid requirements.
 if exists(select 1 from jsonb_array_elements(coalesce(new_slots,'[]')) value
  where jsonb_typeof(value)<>'object'
   or value->>'code' is null
   or value->>'code' not in(select code from internal.formation_slots(clean_lines,new_match_format))
   or (value->>'position' is not null and not exists(select 1 from core.sport_positions catalog
    where catalog.sport=team_sport and catalog.key=value->>'position'))
   or jsonb_typeof(coalesce(value->'requirements','[]'))<>'array'
   or jsonb_array_length(coalesce(value->'requirements','[]'))>6
   or exists(select 1 from jsonb_array_elements(coalesce(value->'requirements','[]')) requirement
    where jsonb_typeof(requirement)<>'object'
     or requirement->>'attribute' is null
     or requirement->>'attribute' not in(select internal.team_attribute_keys(target_team_id))
     or coalesce(requirement->>'weight','') not in('1','2'))
   or (select count(distinct requirement->>'attribute')<>count(*)
    from jsonb_array_elements(coalesce(value->'requirements','[]')) requirement))
  or (select count(distinct value->>'code')<>count(*) from jsonb_array_elements(coalesce(new_slots,'[]')) value) then
  raise invalid_parameter_value using message='invalid_slots';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('code',value->>'code','position',value->>'position',
   'requirements',coalesce((select jsonb_agg(jsonb_build_object('attribute',requirement.value->>'attribute',
     'weight',(requirement.value->>'weight')::integer) order by requirement.ordinality)
    from jsonb_array_elements(value->'requirements') with ordinality requirement),'[]'::jsonb))),'[]'::jsonb)
 into clean_slots
 from jsonb_array_elements(coalesce(new_slots,'[]')) value
 where value->>'position' is not null or jsonb_array_length(coalesce(value->'requirements','[]'))>0;
 if exists(select 1 from core.team_formations formation where formation.team_id=target_team_id
  and lower(formation.name)=lower(clean_name) and formation.id is distinct from formation_id) then
  raise unique_violation using message='formation_name_taken';
 end if;
 if formation_id is null then
  if (select count(*) from core.team_formations formation where formation.team_id=target_team_id)>=30 then
   raise check_violation using message='too_many_formations'; end if;
  insert into core.team_formations(club_id,team_id,name,lines,match_format,slots,updated_by)
  values(target_club_id,target_team_id,clean_name,clean_lines,new_match_format,clean_slots,auth.uid())
  returning * into saved;
 else
  update core.team_formations formation set name=clean_name,lines=clean_lines,match_format=new_match_format,
   slots=clean_slots,revision=formation.revision+1,updated_at=now(),updated_by=auth.uid()
  where formation.id=formation_id and formation.team_id=target_team_id
   and (expected_revision is null or formation.revision=expected_revision)
  returning * into saved;
  if saved.id is null then
   if exists(select 1 from core.team_formations formation where formation.id=formation_id and formation.team_id=target_team_id) then
    raise sqlstate 'PT409' using message='stale_revision'; end if;
   raise no_data_found using message='formation_not_found';
  end if;
 end if;
 return internal.team_formation_json(saved);
end$$;

create or replace function internal.delete_team_formation_for_actor(target_club_id uuid,target_team_id uuid,formation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform internal.require_team_formations_access(target_club_id,target_team_id);
 delete from core.team_formations formation where formation.id=formation_id and formation.team_id=target_team_id;
 return internal.list_team_formations_for_actor(target_club_id,target_team_id);
end$$;

create function api.list_team_formations(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$ select internal.list_team_formations_for_actor(target_club_id,target_team_id) $$;
create function api.save_team_formation(target_club_id uuid,target_team_id uuid,formation_id uuid,
 new_name text,new_lines text,new_match_format text,new_slots jsonb,expected_revision bigint)
returns jsonb language sql security invoker set search_path='' as
$$ select internal.save_team_formation_for_actor(target_club_id,target_team_id,formation_id,
 new_name,new_lines,new_match_format,new_slots,expected_revision) $$;
create function api.delete_team_formation(target_club_id uuid,target_team_id uuid,formation_id uuid)
returns jsonb language sql security invoker set search_path='' as
$$ select internal.delete_team_formation_for_actor(target_club_id,target_team_id,formation_id) $$;

revoke all on function
 internal.formation_slots(text,text),internal.format_players(text),
 internal.require_team_formations_access(uuid,uuid),internal.team_formation_json(core.team_formations),
 internal.list_team_formations_for_actor(uuid,uuid),
 internal.save_team_formation_for_actor(uuid,uuid,uuid,text,text,text,jsonb,bigint),
 internal.delete_team_formation_for_actor(uuid,uuid,uuid),
 api.list_team_formations(uuid,uuid),
 api.save_team_formation(uuid,uuid,uuid,text,text,text,jsonb,bigint),
 api.delete_team_formation(uuid,uuid,uuid)
from public,anon,authenticated;
grant execute on function
 internal.list_team_formations_for_actor(uuid,uuid),
 internal.save_team_formation_for_actor(uuid,uuid,uuid,text,text,text,jsonb,bigint),
 internal.delete_team_formation_for_actor(uuid,uuid,uuid),
 api.list_team_formations(uuid,uuid),
 api.save_team_formation(uuid,uuid,uuid,text,text,text,jsonb,bigint),
 api.delete_team_formation(uuid,uuid,uuid)
to authenticated;
notify pgrst,'reload schema';
