-- Match module, step 3c: own buttons and Min vy in Live. A team keeps its
-- own counters for Live (ball wins, crosses, offsides …), set once and used
-- in every match; a tap is a 'kpi' match fact as the KPI goals' ticks are
-- (detail.button_id and the label), and minus voids the latest one. Each
-- leader chooses which buttons Live shows them (Min vy), kept per leader
-- and team so it follows them between devices and matches; no choice shows
-- them all. Reading needs the Match module and the event; changing the
-- buttons is for those who prepare the match (match.plan), counting for
-- those who run it (match.live).

create table core.team_match_buttons (
  team_id uuid primary key references core.teams(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  buttons jsonb not null default '[]'::jsonb check (jsonb_typeof(buttons) = 'array'),
  revision bigint not null default 1,
  updated_by uuid references core.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table core.match_button_views (
  team_id uuid not null references core.teams(id) on delete cascade,
  profile_id uuid not null references core.profiles(id) on delete cascade,
  shown jsonb not null check (jsonb_typeof(shown) = 'array'),
  updated_at timestamptz not null default now(),
  primary key (team_id, profile_id)
);

alter table core.team_match_buttons enable row level security;
alter table core.match_button_views enable row level security;
revoke all on core.team_match_buttons, core.match_button_views from public, anon, authenticated;

-- The team's buttons, whether the reader may change them, and their own view
-- (null: everything shown).
create or replace function internal.get_match_buttons_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events;
begin
  event_row := internal.match_plan_event(target_event_id);
  return jsonb_build_object(
    'buttons', coalesce((select buttons from core.team_match_buttons where team_id = event_row.owning_team_id), '[]'::jsonb),
    'revision', coalesce((select revision from core.team_match_buttons where team_id = event_row.owning_team_id), 0),
    'can_edit', internal.match_plan_can_edit(event_row),
    'my_view', (select shown from core.match_button_views
      where team_id = event_row.owning_team_id and profile_id = auth.uid()));
end;
$$;

create or replace function internal.save_match_buttons_for_actor(target_event_id uuid, new_buttons jsonb, expected_revision bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare event_row core.events; current_revision bigint; saved bigint;
begin
  event_row := internal.match_plan_event(target_event_id);
  if not internal.match_plan_can_edit(event_row) then raise insufficient_privilege using message = 'not_allowed'; end if;
  if jsonb_typeof(coalesce(new_buttons, 'null')) <> 'array' or jsonb_array_length(new_buttons) > 12
    or exists (select 1 from jsonb_array_elements(new_buttons) item
      where jsonb_typeof(item.value) <> 'object'
        or coalesce(length(item.value->>'id'), 0) not between 1 and 40
        or coalesce(length(btrim(item.value->>'label')), 0) not between 1 and 30)
    or (select count(distinct item.value->>'id') from jsonb_array_elements(new_buttons) item) <> jsonb_array_length(new_buttons) then
    raise invalid_parameter_value using message = 'invalid_buttons';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(event_row.owning_team_id::text, 1));
  select revision into current_revision from core.team_match_buttons where team_id = event_row.owning_team_id;
  if coalesce(current_revision, 0) <> coalesce(expected_revision, 0) then
    raise serialization_failure using message = 'stale_revision';
  end if;
  insert into core.team_match_buttons (team_id, club_id, buttons, updated_by)
  values (event_row.owning_team_id, event_row.club_id,
    (select coalesce(jsonb_agg(jsonb_build_object('id', item.value->>'id', 'label', btrim(item.value->>'label'))
      order by item.ordinality), '[]'::jsonb) from jsonb_array_elements(new_buttons) with ordinality as item(value, ordinality)),
    auth.uid())
  on conflict (team_id) do update set buttons = excluded.buttons, revision = core.team_match_buttons.revision + 1,
    updated_by = excluded.updated_by, updated_at = now()
  returning revision into saved;
  return saved;
end;
$$;

-- Min vy: the keys of the buttons to show (standard kinds, KPI goals, own
-- buttons); null shows everything again.
create or replace function internal.save_my_match_view_for_actor(target_event_id uuid, shown_keys jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare event_row core.events;
begin
  event_row := internal.match_plan_event(target_event_id);
  if shown_keys is null then
    delete from core.match_button_views where team_id = event_row.owning_team_id and profile_id = auth.uid();
    return;
  end if;
  if jsonb_typeof(shown_keys) <> 'array' or jsonb_array_length(shown_keys) > 60
    or exists (select 1 from jsonb_array_elements(shown_keys) item
      where jsonb_typeof(item.value) <> 'string' or length(item.value #>> '{}') > 60) then
    raise invalid_parameter_value using message = 'invalid_view';
  end if;
  insert into core.match_button_views (team_id, profile_id, shown)
  values (event_row.owning_team_id, auth.uid(), shown_keys)
  on conflict (team_id, profile_id) do update set shown = excluded.shown, updated_at = now();
end;
$$;

-- A tap on an own button: plus adds a 'kpi' fact, minus voids the latest.
create or replace function internal.record_match_button_for_actor(
  p_command_id uuid, p_event_id uuid, p_button_id text, p_delta integer, p_minute integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare event_row core.events; workspace core.match_workspaces%rowtype; result_value jsonb;
  button jsonb; new_fact_id uuid; fact core.match_facts%rowtype; tick_count integer;
begin
  event_row := internal.match_plan_event(p_event_id);
  perform pg_advisory_xact_lock(hashtextextended(p_event_id::text, 0));
  perform internal.ensure_match_workspace(p_event_id);
  if not internal.register_match_command(p_command_id, p_event_id, null, 'record_button',
    jsonb_build_object('button_id', p_button_id, 'delta', p_delta, 'minute', p_minute)) then
    select command.result into result_value from audit.match_commands command where command.command_id = p_command_id;
    return result_value;
  end if;
  perform internal.assert_match_manager(p_event_id);
  select * into workspace from core.match_workspaces where event_id = p_event_id for update;
  if workspace.state <> 'live' then raise check_violation using message = 'match_not_live'; end if;
  select item.value into button from core.team_match_buttons buttons, jsonb_array_elements(buttons.buttons) item
  where buttons.team_id = event_row.owning_team_id and item.value->>'id' = p_button_id;
  if button is null or p_delta not in (-1, 1) or p_minute is null or p_minute not between 0 and 300 then
    raise invalid_parameter_value using message = 'invalid_button';
  end if;
  if p_delta = 1 then
    new_fact_id := gen_random_uuid();
    insert into core.match_facts (id, event_id, minute, fact_type, side, club_id, detail, source_command_id, created_by, updated_by)
    values (new_fact_id, p_event_id, p_minute, 'kpi', 'us', workspace.club_id,
      jsonb_build_object('button_id', p_button_id, 'label', button->>'label'), p_command_id, auth.uid(), auth.uid());
    insert into audit.match_fact_versions (fact_id, event_id, fact_revision, snapshot, action, actor_profile_id)
    values (new_fact_id, p_event_id, 1, (select to_jsonb(f) from core.match_facts f where f.id = new_fact_id), 'created', auth.uid());
  else
    select * into fact from core.match_facts f where f.event_id = p_event_id and f.fact_type = 'kpi' and f.state = 'active'
      and f.detail->>'button_id' = p_button_id order by f.created_at desc, f.id desc limit 1 for update;
    if fact.id is null then raise invalid_parameter_value using message = 'invalid_fact'; end if;
    update core.match_facts set state = 'voided', voided_at = now(), voided_by = auth.uid(), void_reason = 'button_minus',
      fact_revision = fact_revision + 1, updated_at = now(), updated_by = auth.uid() where id = fact.id returning * into fact;
    insert into audit.match_fact_versions (fact_id, event_id, fact_revision, snapshot, action, actor_profile_id, reason)
    values (fact.id, p_event_id, fact.fact_revision, to_jsonb(fact), 'voided', auth.uid(), 'button_minus');
  end if;
  select count(*) into tick_count from core.match_facts f where f.event_id = p_event_id and f.fact_type = 'kpi'
    and f.state = 'active' and f.detail->>'button_id' = p_button_id;
  return internal.finish_match_command(p_command_id, p_event_id,
    jsonb_build_object('button_id', p_button_id, 'value', tick_count, 'match_event_id', new_fact_id));
end;
$$;

create or replace function api.get_match_buttons(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_match_buttons_for_actor(target_event_id) $$;
create or replace function api.save_match_buttons(target_event_id uuid, new_buttons jsonb, expected_revision bigint) returns bigint
language sql security invoker set search_path = '' as $$ select internal.save_match_buttons_for_actor(target_event_id, new_buttons, expected_revision) $$;
create or replace function api.save_my_match_view(target_event_id uuid, shown_keys jsonb) returns void
language sql security invoker set search_path = '' as $$ select internal.save_my_match_view_for_actor(target_event_id, shown_keys) $$;
create or replace function api.record_match_button(p_command_id uuid, p_event_id uuid, p_button_id text, p_delta integer, p_minute integer)
returns jsonb language sql security invoker set search_path = '' as
$$ select internal.record_match_button_for_actor(p_command_id, p_event_id, p_button_id, p_delta, p_minute) $$;

revoke all on function
  internal.get_match_buttons_for_actor(uuid), internal.save_match_buttons_for_actor(uuid, jsonb, bigint),
  internal.save_my_match_view_for_actor(uuid, jsonb), internal.record_match_button_for_actor(uuid, uuid, text, integer, integer),
  api.get_match_buttons(uuid), api.save_match_buttons(uuid, jsonb, bigint), api.save_my_match_view(uuid, jsonb),
  api.record_match_button(uuid, uuid, text, integer, integer)
from public, anon, authenticated;
grant execute on function
  internal.get_match_buttons_for_actor(uuid), internal.save_match_buttons_for_actor(uuid, jsonb, bigint),
  internal.save_my_match_view_for_actor(uuid, jsonb), internal.record_match_button_for_actor(uuid, uuid, text, integer, integer),
  api.get_match_buttons(uuid), api.save_match_buttons(uuid, jsonb, bigint), api.save_my_match_view(uuid, jsonb),
  api.record_match_button(uuid, uuid, text, integer, integer)
to authenticated;
