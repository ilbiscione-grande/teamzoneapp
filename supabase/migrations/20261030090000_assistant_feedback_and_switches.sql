-- Min assistent, decided 2026-10-15 (min_assistent_concept.md section 9):
-- * TeamZone support can switch an assistant task type off for everyone. The
--   leader home and the personal conflicts leave switched-off types out, so
--   their cards disappear at once; users' snoozed/archived choices are kept
--   and the cards return when the type is switched on again. Every change
--   needs a reason and is kept in a history table.
-- * "Inte till hjälp" with four fixed reasons and no free text. It archives
--   the card for that person and is stored privately per task type. Support
--   sees counts per type and reason only, never who gave them.

create or replace function internal.assistant_task_kinds()
returns text[] language sql immutable set search_path = '' as $$
  select array['pending_callups', 'missing_callups', 'missing_attendance', 'missing_match_result',
    'missing_match_report', 'calendar_conflict', 'personal_calendar_conflict', 'unfinished_preparation']
$$;

create table if not exists internal.assistant_task_kind_switches (
  kind text primary key check (kind = any (internal.assistant_task_kinds())),
  disabled boolean not null,
  reason text not null check (length(btrim(reason)) between 3 and 300),
  changed_by uuid not null references core.profiles(id),
  changed_at timestamptz not null default now()
);
create table if not exists internal.assistant_task_kind_switch_history (
  id bigint generated always as identity primary key,
  kind text not null,
  disabled boolean not null,
  reason text not null,
  changed_by uuid not null references core.profiles(id),
  changed_at timestamptz not null default now()
);
create table if not exists internal.assistant_task_feedback (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references core.profiles(id) on delete cascade,
  kind text not null check (kind = any (internal.assistant_task_kinds())),
  route text not null,
  reason text not null check (reason in ('incorrect', 'already_handled', 'not_my_responsibility', 'too_often')),
  created_at timestamptz not null default now()
);
create index if not exists assistant_task_feedback_recent_idx
  on internal.assistant_task_feedback(created_at);
create index if not exists assistant_task_feedback_profile_idx
  on internal.assistant_task_feedback(profile_id, kind, created_at);
alter table internal.assistant_task_kind_switches enable row level security;
alter table internal.assistant_task_kind_switch_history enable row level security;
alter table internal.assistant_task_feedback enable row level security;
revoke all on internal.assistant_task_kind_switches, internal.assistant_task_kind_switch_history,
  internal.assistant_task_feedback from public, anon, authenticated;

create or replace function internal.assistant_task_kind_enabled(task_kind text)
returns boolean language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from internal.assistant_task_kind_switches s
    where s.kind = task_kind and s.disabled)
$$;

-- As in 20261012120000, leaving switched-off task types out.
create or replace function internal.get_leader_home_for_actor(target_context_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 base jsonb := internal.get_leader_home_base_for_actor(target_context_id);
 context_row record;
 my_person_id uuid;
 observed_at timestamptz := statement_timestamp();
begin
 select * into context_row from internal.get_my_contexts_for_actor() where context_id=target_context_id;
 select link.club_person_id into my_person_id from core.person_account_links link
 where link.profile_id=auth.uid() and link.club_id=context_row.club_id and link.state='active' limit 1;
 return base || jsonb_build_object(
  'tasks',coalesce((
   select jsonb_agg(item.value order by item.ordinality)
   from jsonb_array_elements(case when jsonb_typeof(base->'tasks')='array' then base->'tasks' else '[]'::jsonb end)
    with ordinality item
   where internal.assistant_task_kind_enabled(item.value->>'kind')),'[]'::jsonb),
  'next_event',case when jsonb_typeof(base->'next_event')='object' then
   (base->'next_event')||jsonb_build_object('my_callup',
    internal.home_my_callup((base->'next_event'->>'event_id')::uuid,my_person_id,observed_at)) end,
  'today_events',coalesce((
   select jsonb_agg(item.value||jsonb_build_object('my_callup',
     internal.home_my_callup((item.value->>'event_id')::uuid,my_person_id,observed_at)) order by item.ordinality)
   from jsonb_array_elements(base->'today_events') with ordinality item),'[]'::jsonb),
  'upcoming_events',coalesce((
   select jsonb_agg(row_value order by starts_at,event_id) from(
    select event_row.id event_id,event_row.title,event_row.event_type,event_row.state,event_row.starts_at,event_row.ends_at,
     internal.event_place_label(location.name,location.pitch) location_name,location.address,
     internal.home_my_callup(event_row.id,my_person_id,observed_at) my_callup
    from core.events event_row
    join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
    left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
    where event_row.club_id=context_row.club_id and relation.team_id=context_row.team_id
     and event_row.state='scheduled' and event_row.archived_at is null
     and (event_row.starts_at at time zone event_row.timezone)::date>(observed_at at time zone event_row.timezone)::date
     and event_row.starts_at<observed_at+interval '14 days'
    order by event_row.starts_at,event_row.id limit 6) row_value),'[]'::jsonb));
end$$;

create or replace function api.get_personal_calendar_conflicts()
returns jsonb language sql stable security invoker set search_path='' as $$
 select case when internal.assistant_task_kind_enabled('personal_calendar_conflict')
   then internal.get_personal_calendar_conflicts_for_actor()
   else jsonb_build_object('generated_at', statement_timestamp(), 'tasks', '[]'::jsonb) end
$$;

-- "Inte till hjälp": archives the card (validated like Skjut upp/Arkivera)
-- and stores the reason. offer_hide: "Visas för ofta" for the same type at
-- least three times in 30 days, so the app offers to hide the type.
create or replace function internal.give_assistant_task_feedback_for_actor(context_id uuid, task_kind text,
  task_route text, feedback_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); too_often integer;
begin
  if actor is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if feedback_reason is null
    or feedback_reason not in ('incorrect', 'already_handled', 'not_my_responsibility', 'too_often')
    or task_kind is null or not (task_kind = any (internal.assistant_task_kinds())) then
    raise invalid_parameter_value using message = 'invalid_feedback';
  end if;
  perform internal.set_assistant_task_state_for_actor(context_id, task_kind, task_route, 'archived', null);
  delete from internal.assistant_task_feedback where created_at < now() - interval '180 days';
  insert into internal.assistant_task_feedback(profile_id, kind, route, reason)
  values (actor, task_kind, task_route, feedback_reason);
  select count(*) into too_often from internal.assistant_task_feedback f
  where f.profile_id = actor and f.kind = task_kind and f.reason = 'too_often'
    and f.created_at > now() - interval '30 days';
  return jsonb_build_object('archived', true,
    'offer_hide', feedback_reason = 'too_often' and too_often >= 3);
end;$$;

-- Support: every task type, whether it is on, and feedback counts for the
-- last 30 days (people and reasons, never who).
create or replace function internal.list_assistant_task_kinds_for_support()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_is_support_admin() then raise insufficient_privilege using message = 'not_found'; end if;
  return (select jsonb_agg(jsonb_build_object(
      'kind', k.kind,
      'disabled', coalesce(s.disabled, false),
      'reason', s.reason,
      'changed_at', s.changed_at,
      'feedback', coalesce((select jsonb_object_agg(f.reason, f.n) from (
          select reason, count(*) n from internal.assistant_task_feedback
          where kind = k.kind and created_at > now() - interval '30 days' group by reason) f), '{}'::jsonb),
      'feedback_people', (select count(distinct profile_id) from internal.assistant_task_feedback
          where kind = k.kind and created_at > now() - interval '30 days'))
    order by k.ordinality)
    from unnest(internal.assistant_task_kinds()) with ordinality k(kind, ordinality)
    left join internal.assistant_task_kind_switches s on s.kind = k.kind);
end;$$;

create or replace function internal.set_assistant_task_kind_switch_for_support(task_kind text, disable boolean,
  change_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if not internal.actor_is_support_admin() then raise insufficient_privilege using message = 'not_found'; end if;
  if task_kind is null or not (task_kind = any (internal.assistant_task_kinds())) or disable is null
    or change_reason is null or length(btrim(change_reason)) not between 3 and 300 then
    raise invalid_parameter_value using message = 'invalid_switch';
  end if;
  insert into internal.assistant_task_kind_switches(kind, disabled, reason, changed_by, changed_at)
  values (task_kind, disable, btrim(change_reason), actor, now())
  on conflict (kind) do update set disabled = excluded.disabled, reason = excluded.reason,
    changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  insert into internal.assistant_task_kind_switch_history(kind, disabled, reason, changed_by)
  values (task_kind, disable, btrim(change_reason), actor);
end;$$;

create or replace function api.give_assistant_task_feedback(context_id uuid, task_kind text, task_route text,
  feedback_reason text)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.give_assistant_task_feedback_for_actor(context_id, task_kind, task_route, feedback_reason)$$;
create or replace function api.list_assistant_task_kinds_for_support()
returns jsonb language sql stable security invoker set search_path = '' as
$$select internal.list_assistant_task_kinds_for_support()$$;
create or replace function api.set_assistant_task_kind_switch(task_kind text, disable boolean, change_reason text)
returns void language sql security invoker set search_path = '' as
$$select internal.set_assistant_task_kind_switch_for_support(task_kind, disable, change_reason)$$;

revoke all on function internal.assistant_task_kind_enabled(text),
  internal.give_assistant_task_feedback_for_actor(uuid, text, text, text),
  internal.list_assistant_task_kinds_for_support(),
  internal.set_assistant_task_kind_switch_for_support(text, boolean, text),
  api.give_assistant_task_feedback(uuid, text, text, text),
  api.list_assistant_task_kinds_for_support(),
  api.set_assistant_task_kind_switch(text, boolean, text)
  from public, anon, authenticated;
grant execute on function internal.assistant_task_kind_enabled(text),
  internal.give_assistant_task_feedback_for_actor(uuid, text, text, text),
  internal.list_assistant_task_kinds_for_support(),
  internal.set_assistant_task_kind_switch_for_support(text, boolean, text),
  api.give_assistant_task_feedback(uuid, text, text, text),
  api.list_assistant_task_kinds_for_support(),
  api.set_assistant_task_kind_switch(text, boolean, text)
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261030090000_assistant_feedback_and_switches', 'greenfield',
  'Min assistent: fixed-reason feedback, support switch per task type'
where not exists (select 1 from internal.migration_provenance
  where migration_name = '20261030090000_assistant_feedback_and_switches');
notify pgrst, 'reload schema';
