-- Match module, step 2, fixed: saving a line-up always failed with
-- invalid_input. In the check that each chosen player is one of the club's
-- people, the chosen id was named person_id, which core.club_people also has
-- as a column, so inside its subquery the name meant the column. The chosen
-- ids are now chosen_id; otherwise as in 20261204090000.

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
  select array_agg(chosen_row.chosen_id) into chosen from (
    select value->>'person_id' chosen_id from jsonb_array_elements(coalesce(starters, '[]'))
    union all select value->>'person_id' from jsonb_array_elements(coalesce(substitutes, '[]'))) chosen_row;
  if exists (select 1 from unnest(coalesce(chosen, '{}')) picked(chosen_id)
      where picked.chosen_id is null or picked.chosen_id !~ '^[0-9a-fA-F-]{36}$'
        or not exists (select 1 from core.club_people person where person.id = picked.chosen_id::uuid
          and person.club_id = event_row.club_id))
    or cardinality(coalesce(chosen, '{}')) <> (select count(distinct picked.chosen_id) from unnest(coalesce(chosen, '{}')) picked(chosen_id)) then
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
