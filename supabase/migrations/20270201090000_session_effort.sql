-- Self-rated effort after a training (PAR-PRIV-04, decided by the product
-- owner 2026-11-02), counted in the Team Development Plan's load (step 8).
--
-- After a training the player answers how hard it was, 1–10. The rules:
--   age          from 13: the birth date, else the year one turns 13 (the
--                birth year, as the age classes count); unknown, no question;
--   who sees     the player and the team's leaders (in the load), and the
--                player's guardians, who see what the player sees;
--   opting out   the player can stop the questions; their answers in the
--                club are then deleted;
--   retention    an answer is deleted 24 months after the training;
--   never used   for an automatic ranking or selection.
-- The question is asked for 7 days after the training, of the team's
-- active players, when the club has the Team Development Plan.

create table core.session_effort_ratings (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references core.events(id) on delete cascade,
  club_person_id uuid not null,
  rating smallint not null check (rating between 1 and 10),
  recorded_by uuid references core.profiles(id) on delete set null,
  recorded_at timestamptz not null default now(),
  unique (event_id, club_person_id)
);
create index session_effort_ratings_person on core.session_effort_ratings (club_person_id, recorded_at);
create index session_effort_ratings_recorded_by on core.session_effort_ratings (recorded_by);
alter table core.session_effort_ratings enable row level security;
revoke all on core.session_effort_ratings from public, anon, authenticated;
create policy session_effort_ratings_no_direct_access on core.session_effort_ratings
  for all to authenticated using (false) with check (false);

create table core.session_effort_opt_outs (
  club_person_id uuid primary key,
  club_id uuid not null,
  opted_out_by uuid references core.profiles(id) on delete set null,
  opted_out_at timestamptz not null default now()
);
create index session_effort_opt_outs_by on core.session_effort_opt_outs (opted_out_by);
alter table core.session_effort_opt_outs enable row level security;
revoke all on core.session_effort_opt_outs from public, anon, authenticated;
create policy session_effort_opt_outs_no_direct_access on core.session_effort_opt_outs
  for all to authenticated using (false) with check (false);

-- Whether the person is old enough to rate on [day]: 13 by the birth date,
-- else in the year they turn 13.
create or replace function internal.effort_age_reached(person core.club_people, day date)
returns boolean language sql immutable set search_path = '' as $$
  select case
    when person.birth_date is not null then person.birth_date + interval '13 years' <= day
    when person.birth_year is not null then extract(year from day)::integer - person.birth_year >= 13
    else false end
$$;

-- The people the actor answers for or sees at a training: themselves when
-- one of the team's players, and the players they are guardian of; each
-- old enough, with their answer and whether they opted out.
create or replace function internal.get_session_effort_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events; day date; open boolean;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or event_row.event_type <> 'training' or event_row.owning_team_id is null
    or event_row.archived_at is not null or event_row.state = 'cancelled' or event_row.ends_at > now()
    or not internal.module_allows_read(event_row.club_id, 'module.team_development') then
    return jsonb_build_object('people', '[]'::jsonb);
  end if;
  day := (event_row.starts_at at time zone event_row.timezone)::date;
  open := event_row.ends_at > now() - interval '7 days';
  return jsonb_build_object('open', open, 'people', coalesce((
    select jsonb_agg(jsonb_build_object(
        'person_id', person.id, 'name', person.display_name, 'self', mine.own,
        'rating', rating.rating, 'opted_out', opt_out.club_person_id is not null,
        'can_answer', mine.own and open and opt_out.club_person_id is null)
      order by not mine.own, person.display_name)
    from core.club_people person
    cross join lateral (select internal.actor_owns_club_person(event_row.club_id, person.id) own) mine
    left join core.session_effort_ratings rating on rating.event_id = event_row.id and rating.club_person_id = person.id
    left join core.session_effort_opt_outs opt_out on opt_out.club_person_id = person.id
    where person.club_id = event_row.club_id and person.status = 'active'
      and internal.effort_age_reached(person, day)
      and internal.actor_represents_club_person(event_row.club_id, person.id)
      and exists (select 1 from core.assignments assignment
        where assignment.team_id = event_row.owning_team_id and assignment.club_person_id = person.id
          and assignment.role_package = 'player' and assignment.state = 'active')), '[]'::jsonb));
end;
$$;

-- The player's own answer; no [new_rating] takes it back.
create or replace function internal.set_session_effort_for_actor(target_event_id uuid, new_rating integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare event_row core.events; person_id uuid;
begin
  select * into event_row from core.events where id = target_event_id;
  select (person.value->>'person_id')::uuid into person_id
  from jsonb_array_elements(internal.get_session_effort_for_actor(target_event_id)->'people') person
  where (person.value->>'can_answer')::boolean limit 1;
  if person_id is null then raise insufficient_privilege using message = 'not_allowed'; end if;
  if new_rating is null then
    delete from core.session_effort_ratings where event_id = event_row.id and club_person_id = person_id;
  elsif new_rating not between 1 and 10 then
    raise invalid_parameter_value using message = 'invalid_input';
  else
    insert into core.session_effort_ratings (club_id, event_id, club_person_id, rating, recorded_by)
    values (event_row.club_id, event_row.id, person_id, new_rating, auth.uid())
    on conflict (event_id, club_person_id) do update
      set rating = excluded.rating, recorded_by = excluded.recorded_by, recorded_at = now();
  end if;
  return internal.get_session_effort_for_actor(target_event_id);
end;
$$;

-- The player stops the questions (their answers in the club are deleted)
-- or starts them again.
create or replace function internal.set_session_effort_opt_out_for_actor(target_event_id uuid, opt_out boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare event_row core.events; person_id uuid;
begin
  select * into event_row from core.events where id = target_event_id;
  select (person.value->>'person_id')::uuid into person_id
  from jsonb_array_elements(internal.get_session_effort_for_actor(target_event_id)->'people') person
  where (person.value->>'self')::boolean limit 1;
  if person_id is null then raise insufficient_privilege using message = 'not_allowed'; end if;
  if opt_out then
    insert into core.session_effort_opt_outs (club_person_id, club_id, opted_out_by)
    values (person_id, event_row.club_id, auth.uid()) on conflict (club_person_id) do nothing;
    delete from core.session_effort_ratings where club_person_id = person_id and club_id = event_row.club_id;
  else
    delete from core.session_effort_opt_outs where club_person_id = person_id;
  end if;
  return internal.get_session_effort_for_actor(target_event_id);
end;
$$;

-- Answers older than 24 months after their training are deleted.
create or replace function internal.apply_session_effort_retention()
returns integer language plpgsql security definer set search_path = '' as $$
declare removed integer;
begin
  delete from core.session_effort_ratings rating using core.events event_row
  where event_row.id = rating.event_id and event_row.ends_at < now() - interval '24 months';
  get diagnostics removed = row_count;
  return removed;
end;
$$;

do $$
declare existing_job_id bigint;
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    for existing_job_id in select jobid from cron.job where jobname = 'session-effort-retention' loop
      perform cron.unschedule(existing_job_id);
    end loop;
    perform cron.schedule('session-effort-retention', '37 3 * * *', 'select internal.apply_session_effort_retention();');
  end if;
end $$;

-- The load (step 8) with the players' rated effort over the last 7 days:
-- the average and how many answers.
create or replace function internal.tdp_load(plan core.development_plans, day date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare settings jsonb := internal.tdp_load_settings(plan.team_id); players jsonb;
begin
  with held as (
    select event_row.id, event_row.event_type, (event_row.starts_at at time zone event_row.timezone)::date on_day,
      greatest(0, least(600, extract(epoch from event_row.ends_at - event_row.starts_at)::integer / 60)) length
    from core.events event_row
    where event_row.owning_team_id = plan.team_id and event_row.club_id = plan.club_id
      and event_row.event_type in ('training', 'match') and event_row.archived_at is null and event_row.state <> 'cancelled'
      and event_row.starts_at <= now()
      and (event_row.starts_at at time zone event_row.timezone)::date between day - 27 and day
  ), taken as (
    -- Trainings with attendance taken: what the attendance share counts.
    select held.* from held where held.event_type = 'training'
      and exists (select 1 from core.attendance_facts fact where fact.event_id = held.id and fact.status <> 'unknown')
  ), trained as (
    select fact.club_person_id, taken.on_day,
      case fact.status when 'present' then taken.length
        when 'late' then greatest(0, taken.length - coalesce(fact.minutes, 0))
        else least(taken.length, coalesce(fact.minutes, 0)) end minutes
    from taken join core.attendance_facts fact on fact.event_id = taken.id
    where fact.status in ('present', 'late', 'partial')
  ), played as (
    select played.club_person_id, held.on_day, played.minutes
    from held cross join lateral internal.tdp_match_minutes(held.id) played
    where held.event_type = 'match' and played.minutes > 0
  ), rated as (
    select rating.club_person_id, rating.rating from held
    join core.session_effort_ratings rating on rating.event_id = held.id
    where held.on_day > day - 7
  ), squad as (
    select distinct person.id, person.display_name from core.assignments assignment
    join core.club_people person on person.id = assignment.club_person_id
    where assignment.team_id = plan.team_id and assignment.club_id = plan.club_id
      and assignment.role_package = 'player' and assignment.state = 'active' and person.status = 'active'
  ), counted as (
    select squad.id, squad.display_name,
      (select count(*) from trained where trained.club_person_id = squad.id and trained.on_day > day - 7)::integer sessions_7,
      (select count(*) from trained where trained.club_person_id = squad.id)::integer sessions_28,
      (select coalesce(sum(minutes), 0) from trained where trained.club_person_id = squad.id and trained.on_day > day - 7)::integer training_7,
      (select coalesce(sum(minutes), 0) from trained where trained.club_person_id = squad.id)::integer training_28,
      (select coalesce(sum(minutes), 0) from played where played.club_person_id = squad.id and played.on_day > day - 7)::integer match_7,
      (select coalesce(sum(minutes), 0) from played where played.club_person_id = squad.id)::integer match_28,
      (select count(*) from taken)::integer trainings_28,
      (select round(avg(rated.rating), 1) from rated where rated.club_person_id = squad.id) effort_7,
      (select count(*) from rated where rated.club_person_id = squad.id)::integer efforts_7
    from squad
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'person_id', counted.id, 'name', counted.display_name,
      'sessions_7', counted.sessions_7, 'sessions_28', counted.sessions_28,
      'training_minutes_7', counted.training_7, 'training_minutes_28', counted.training_28,
      'match_minutes_7', counted.match_7, 'match_minutes_28', counted.match_28,
      'trainings_28', counted.trainings_28,
      'effort_7', counted.effort_7, 'efforts_7', counted.efforts_7,
      'attendance_percent', case when counted.trainings_28 > 0
        then round(100.0 * counted.sessions_28 / counted.trainings_28)::integer end,
      'load_percent', case when counted.training_28 + counted.match_28 > 0
        then round(400.0 * (counted.training_7 + counted.match_7) / (counted.training_28 + counted.match_28))::integer end,
      'signals', to_jsonb(array_remove(array[
        case when (settings->>'load_increase_percent') is not null
          and counted.training_28 + counted.match_28 > counted.training_7 + counted.match_7
          and 400.0 * (counted.training_7 + counted.match_7) / (counted.training_28 + counted.match_28)
            >= (settings->>'load_increase_percent')::integer then 'load_increase' end,
        case when (settings->>'attendance_min_percent') is not null and counted.trainings_28 >= 3
          and 100.0 * counted.sessions_28 / counted.trainings_28 < (settings->>'attendance_min_percent')::integer
          then 'low_attendance' end,
        case when (settings->>'match_minutes_max') is not null
          and counted.match_7 > (settings->>'match_minutes_max')::integer then 'match_minutes' end
      ], null))
    ) order by counted.display_name, counted.id), '[]'::jsonb)
  into players from counted;
  return jsonb_build_object('day', day, 'settings', settings, 'players', players);
end;
$$;

create or replace function api.get_session_effort(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.get_session_effort_for_actor(target_event_id) $$;
create or replace function api.set_session_effort(target_event_id uuid, new_rating integer) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_session_effort_for_actor(target_event_id, new_rating) $$;
create or replace function api.set_session_effort_opt_out(target_event_id uuid, opt_out boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_session_effort_opt_out_for_actor(target_event_id, opt_out) $$;

revoke all on function
  internal.effort_age_reached(core.club_people, date),
  internal.get_session_effort_for_actor(uuid),
  internal.set_session_effort_for_actor(uuid, integer),
  internal.set_session_effort_opt_out_for_actor(uuid, boolean),
  internal.apply_session_effort_retention(),
  internal.tdp_load(core.development_plans, date),
  api.get_session_effort(uuid),
  api.set_session_effort(uuid, integer),
  api.set_session_effort_opt_out(uuid, boolean)
from public, anon, authenticated;
grant execute on function
  internal.get_session_effort_for_actor(uuid),
  internal.set_session_effort_for_actor(uuid, integer),
  internal.set_session_effort_opt_out_for_actor(uuid, boolean),
  api.get_session_effort(uuid),
  api.set_session_effort(uuid, integer),
  api.set_session_effort_opt_out(uuid, boolean)
to authenticated;
notify pgrst, 'reload schema';
