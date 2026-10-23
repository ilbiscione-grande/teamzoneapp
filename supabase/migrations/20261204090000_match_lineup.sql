-- Match module, step 2 (decision package 11): the line-up on the pitch. The
-- event's line-up (core.event_lineups) stays the one source, shared with the
-- line-up under Förberedelser: a starter may now carry its formation slot and
-- its place on the pitch (x from the own goal line to the opponent's, y
-- from the left touchline to the right, both 0..1), and the line-up a plan of
-- substitutions (who goes off, who comes on, at what minute, a note). The
-- line-up under Förberedelser saves starters without places; a starter it
-- keeps keeps the place the module gave it, and it leaves the plan as it is.
-- The module reads and saves the line-up with the Match module and the
-- event's squad right (event.squad.manage), as the line-up under
-- Förberedelser does.

alter table core.event_lineups
  add column substitution_plan jsonb not null default '[]'::jsonb check (jsonb_typeof(substitution_plan) = 'array');

-- As in 20261113090000, with slot, place and shirt number per player, and
-- for those who edit it the substitution plan with names.
create or replace function internal.lineup_json(target_event_id uuid, can_edit boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  with event_row as (select event.id, event.owning_team_id from core.events event where event.id = target_event_id),
  numbers as (
    select details.club_person_id, details.jersey_number
    from core.team_person_details details join event_row on details.team_id = event_row.owning_team_id
  )
  select jsonb_build_object('event_id', target_event_id, 'can_edit', can_edit,
    'formation', lineup.formation, 'published', coalesce(lineup.published, false),
    'revision', coalesce(lineup.revision, 0),
    'starters', coalesce((select jsonb_agg(jsonb_build_object('person_id', item.value->>'person_id',
        'position', item.value->>'position', 'slot', item.value->>'slot', 'x', item.value->'x', 'y', item.value->'y',
        'name', person.display_name, 'number', numbers.jersey_number) order by item.ordinality)
      from jsonb_array_elements(lineup.starters) with ordinality as item(value, ordinality)
      left join core.club_people person on person.id::text = item.value->>'person_id'
      left join numbers on numbers.club_person_id::text = item.value->>'person_id'), '[]'::jsonb),
    'substitutes', coalesce((select jsonb_agg(jsonb_build_object('person_id', item.value->>'person_id',
        'name', person.display_name, 'number', numbers.jersey_number) order by item.ordinality)
      from jsonb_array_elements(lineup.substitutes) with ordinality as item(value, ordinality)
      left join core.club_people person on person.id::text = item.value->>'person_id'
      left join numbers on numbers.club_person_id::text = item.value->>'person_id'), '[]'::jsonb),
    'substitution_plan', case when not can_edit then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id', item.value->>'id',
        'minute', item.value->'minute', 'out_id', item.value->>'out_id', 'in_id', item.value->>'in_id',
        'note', coalesce(item.value->>'note', ''), 'out_name', player_out.display_name, 'in_name', player_in.display_name)
        order by item.ordinality)
      from jsonb_array_elements(lineup.substitution_plan) with ordinality as item(value, ordinality)
      left join core.club_people player_out on player_out.id::text = item.value->>'out_id'
      left join core.club_people player_in on player_in.id::text = item.value->>'in_id'), '[]'::jsonb) end)
  from (select 1) one left join core.event_lineups lineup on lineup.event_id = target_event_id
$$;

-- Checks and stores a line-up for an event already allowed. A null plan
-- keeps the stored one; a starter without a slot keeps the slot and place
-- it had.
create or replace function internal.store_event_lineup(event_row core.events, formation text,
  starters jsonb, substitutes jsonb, substitution_plan jsonb, published boolean, expected_revision bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare existing core.event_lineups%rowtype; chosen text[]; new_revision bigint; kept_starters jsonb; plan jsonb;
begin
  if event_row.event_type <> 'match' or jsonb_typeof(coalesce(starters, '[]')) <> 'array'
    or jsonb_typeof(coalesce(substitutes, '[]')) <> 'array'
    or jsonb_typeof(coalesce(substitution_plan, '[]')) <> 'array'
    or jsonb_array_length(coalesce(starters, '[]')) > 30 or jsonb_array_length(coalesce(substitutes, '[]')) > 30
    or jsonb_array_length(coalesce(substitution_plan, '[]')) > 40
    or length(formation) > 20 or published is null then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(starters, '[]')) item
      where jsonb_typeof(item.value) <> 'object'
        or length(item.value->>'position') > 30 or length(item.value->>'slot') > 12
        or (item.value ? 'x' and (jsonb_typeof(item.value->'x') <> 'number' or (item.value->>'x')::numeric not between 0 and 1))
        or (item.value ? 'y' and (jsonb_typeof(item.value->'y') <> 'number' or (item.value->>'y')::numeric not between 0 and 1))) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select array_agg(chosen_row.person_id) into chosen from (
    select value->>'person_id' person_id from jsonb_array_elements(coalesce(starters, '[]'))
    union all select value->>'person_id' from jsonb_array_elements(coalesce(substitutes, '[]'))) chosen_row;
  if exists (select 1 from unnest(coalesce(chosen, '{}')) person_id
      where person_id is null or person_id !~ '^[0-9a-fA-F-]{36}$'
        or not exists (select 1 from core.club_people person where person.id = person_id::uuid
          and person.club_id = event_row.club_id))
    or cardinality(coalesce(chosen, '{}')) <> (select count(distinct person_id) from unnest(coalesce(chosen, '{}')) person_id) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  -- A planned substitution is between two players of the line-up.
  if exists (select 1 from jsonb_array_elements(coalesce(substitution_plan, '[]')) item
      where jsonb_typeof(item.value) <> 'object'
        or coalesce(length(item.value->>'id'), 0) not between 1 and 40
        or length(item.value->>'note') > 200
        or (item.value->'minute' is not null and jsonb_typeof(item.value->'minute') <> 'null'
          and (jsonb_typeof(item.value->'minute') <> 'number' or (item.value->>'minute')::numeric not between 0 and 300))
        or not (item.value->>'out_id' = any(coalesce(chosen, '{}')))
        or not (item.value->>'in_id' = any(coalesce(chosen, '{}')))
        or item.value->>'out_id' = item.value->>'in_id') then
    raise invalid_parameter_value using message = 'invalid_substitution';
  end if;
  select * into existing from core.event_lineups where event_id = event_row.id for update;
  if coalesce(existing.revision, 0) <> coalesce(expected_revision, 0) then
    raise serialization_failure using message = 'stale_revision';
  end if;
  select coalesce(jsonb_agg(case when item.value ? 'slot' then item.value
      else item.value || coalesce((select jsonb_strip_nulls(jsonb_build_object('slot', old.value->'slot', 'x', old.value->'x', 'y', old.value->'y'))
        from jsonb_array_elements(coalesce(existing.starters, '[]')) old
        where old.value->>'person_id' = item.value->>'person_id' limit 1), '{}'::jsonb) end order by item.ordinality), '[]'::jsonb)
    into kept_starters
    from jsonb_array_elements(coalesce(starters, '[]')) with ordinality as item(value, ordinality);
  -- A kept plan drops the substitutions whose players left the line-up.
  plan := coalesce(substitution_plan, (select coalesce(jsonb_agg(item.value order by item.ordinality), '[]'::jsonb)
    from jsonb_array_elements(coalesce(existing.substitution_plan, '[]')) with ordinality as item(value, ordinality)
    where item.value->>'out_id' = any(coalesce(chosen, '{}')) and item.value->>'in_id' = any(coalesce(chosen, '{}'))));
  insert into core.event_lineups(event_id, club_id, formation, starters, substitutes, substitution_plan, published, updated_by)
  values (event_row.id, event_row.club_id, nullif(btrim(coalesce(formation, '')), ''), kept_starters,
    coalesce(substitutes, '[]'), plan, published, auth.uid())
  on conflict (event_id) do update set formation = excluded.formation, starters = excluded.starters,
    substitutes = excluded.substitutes, substitution_plan = excluded.substitution_plan, published = excluded.published,
    revision = core.event_lineups.revision + 1, updated_by = excluded.updated_by, updated_at = now()
  returning revision into new_revision;
  return new_revision;
end;$$;

-- As in 20261113090000, through the shared store.
create or replace function internal.save_event_lineup_for_actor(target_event_id uuid, formation text,
  starters jsonb, substitutes jsonb, published boolean, expected_revision bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype;
begin
  select * into event_row from core.events where id = target_event_id for update;
  if event_row.id is null or not internal.actor_can_manage_squad(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return internal.store_event_lineup(event_row, formation, starters, substitutes, null, published, expected_revision);
end;$$;

-- The Match module's line-up: as the line-up json, with the team's match
-- format, and for those who edit it the team's shirt numbers and main
-- positions to place players by. Players see it once published.
create or replace function internal.get_match_lineup_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events; can_edit boolean; published boolean;
begin
  event_row := internal.match_plan_event(target_event_id);
  can_edit := internal.module_allows_write(event_row.club_id, 'module.match_workspace')
    and internal.actor_can_manage_squad(event_row.id) and event_row.archived_at is null;
  select lineup.published into published from core.event_lineups lineup where lineup.event_id = event_row.id;
  if not can_edit and not coalesce(published, false) then return null; end if;
  return internal.lineup_json(event_row.id, can_edit) || jsonb_build_object(
    'match_format', (select team.match_format from core.teams team where team.id = event_row.owning_team_id),
    'players', case when can_edit then coalesce((select jsonb_agg(player.value order by player.number nulls last, player.name)
      from (select distinct on (person.id) jsonb_build_object('person_id', person.id, 'name', person.display_name,
          'number', details.jersey_number, 'main_position', details.main_position,
          'positions', to_jsonb(coalesce(details.positions, '{}'))) value, details.jersey_number number, person.display_name name
        from core.assignments assignment
        join core.club_people person on person.id = assignment.club_person_id
        left join core.team_person_details details on details.team_id = assignment.team_id and details.club_person_id = person.id
        where assignment.team_id = event_row.owning_team_id and assignment.role_package = 'player'
          and assignment.state = 'active') player), '[]'::jsonb)
      else '[]'::jsonb end);
end;$$;

create or replace function internal.save_match_lineup_for_actor(target_event_id uuid, expected_revision bigint,
  formation text, starters jsonb, substitutes jsonb, substitution_plan jsonb, published boolean)
returns bigint language plpgsql security definer set search_path = '' as $$
declare event_row core.events;
begin
  event_row := internal.match_plan_event(target_event_id);
  if not internal.module_allows_write(event_row.club_id, 'module.match_workspace')
    or not internal.actor_can_manage_squad(event_row.id) or event_row.archived_at is not null then
    raise insufficient_privilege using message = 'not_allowed';
  end if;
  perform 1 from core.events where id = event_row.id for update;
  return internal.store_event_lineup(event_row, formation, starters, substitutes,
    coalesce(substitution_plan, '[]'::jsonb), published, expected_revision);
end;$$;

create or replace function api.get_match_lineup(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_match_lineup_for_actor(target_event_id) $$;
create or replace function api.save_match_lineup(target_event_id uuid, expected_revision bigint, formation text,
  starters jsonb, substitutes jsonb, substitution_plan jsonb, published boolean) returns bigint
language sql security invoker set search_path = '' as $$
  select internal.save_match_lineup_for_actor(target_event_id, expected_revision, formation, starters, substitutes,
    substitution_plan, published) $$;

revoke all on function
  internal.store_event_lineup(core.events, text, jsonb, jsonb, jsonb, boolean, bigint),
  internal.get_match_lineup_for_actor(uuid), internal.save_match_lineup_for_actor(uuid, bigint, text, jsonb, jsonb, jsonb, boolean),
  api.get_match_lineup(uuid), api.save_match_lineup(uuid, bigint, text, jsonb, jsonb, jsonb, boolean)
from public, anon, authenticated;
grant execute on function
  internal.get_match_lineup_for_actor(uuid), internal.save_match_lineup_for_actor(uuid, bigint, text, jsonb, jsonb, jsonb, boolean),
  api.get_match_lineup(uuid), api.save_match_lineup(uuid, bigint, text, jsonb, jsonb, jsonb, boolean)
to authenticated;
