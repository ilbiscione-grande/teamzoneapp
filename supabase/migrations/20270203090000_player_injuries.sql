-- Team Development Plan, new design step 9 (2026-11-02): injuries
-- (PAR-METHOD-02, decided by the product owner 2026-11-02).
--
--   age          registration is on from 15 (the birth date, else the year
--                one turns 15); under 15 it needs the club's, the player's
--                and a guardian's consent;
--   turning off  the team's leaders or the club can turn it off for a
--                player (and on again); turning off or withdrawing a
--                consent deletes the player's injuries;
--   who sees     the leaders see everything; the player sees their own
--                injuries but not the leaders' notes; guardians see what
--                the player sees;
--   back         no clearance: a leader notes the day the player is back in
--                training;
--   retention    an injury is deleted 24 months after the player was back
--                (or after it started, if never closed).
-- The leaders work through the plan (development.manage); the club through
-- club.memberships.manage. Sanctions are not part of this.

create table core.player_injury_settings (
  club_person_id uuid primary key,
  club_id uuid not null,
  turned_off boolean not null default false,
  turned_off_by uuid references core.profiles(id) on delete set null,
  club_consent_by uuid references core.profiles(id) on delete set null,
  club_consent_at timestamptz,
  player_consent_by uuid references core.profiles(id) on delete set null,
  player_consent_at timestamptz,
  guardian_consent_by uuid references core.profiles(id) on delete set null,
  guardian_consent_at timestamptz,
  updated_at timestamptz not null default now()
);
create index player_injury_settings_turned_off_by on core.player_injury_settings (turned_off_by);
create index player_injury_settings_club_by on core.player_injury_settings (club_consent_by);
create index player_injury_settings_player_by on core.player_injury_settings (player_consent_by);
create index player_injury_settings_guardian_by on core.player_injury_settings (guardian_consent_by);
alter table core.player_injury_settings enable row level security;
revoke all on core.player_injury_settings from public, anon, authenticated;
create policy player_injury_settings_no_direct_access on core.player_injury_settings
  for all to authenticated using (false) with check (false);

create table core.player_injuries (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  team_id uuid not null references core.teams(id) on delete cascade,
  club_person_id uuid not null,
  started_on date not null,
  what text not null check (length(btrim(what)) between 2 and 80),
  note text not null default '' check (length(note) <= 2000),
  back_on date,
  created_by uuid references core.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  check (back_on is null or back_on >= started_on)
);
create index player_injuries_person on core.player_injuries (club_person_id, started_on desc);
create index player_injuries_team on core.player_injuries (team_id);
create index player_injuries_created_by on core.player_injuries (created_by);
alter table core.player_injuries enable row level security;
revoke all on core.player_injuries from public, anon, authenticated;
create policy player_injuries_no_direct_access on core.player_injuries
  for all to authenticated using (false) with check (false);

-- Whether the person is 15 on [day]: by the birth date, else in the year
-- they turn 15.
create or replace function internal.injury_age_reached(person core.club_people, day date)
returns boolean language sql immutable set search_path = '' as $$
  select case
    when person.birth_date is not null then person.birth_date + interval '15 years' <= day
    when person.birth_year is not null then extract(year from day)::integer - person.birth_year >= 15
    else false end
$$;

-- The player's registration: on, or why not ('turned_off', 'consent').
create or replace function internal.injury_status(person core.club_people)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'adult', internal.injury_age_reached(person, (now() at time zone 'Europe/Stockholm')::date),
    'turned_off', coalesce(setting.turned_off, false),
    'consents', jsonb_build_object('club', setting.club_consent_at is not null,
      'player', setting.player_consent_at is not null, 'guardian', setting.guardian_consent_at is not null),
    'allowed', not coalesce(setting.turned_off, false)
      and (internal.injury_age_reached(person, (now() at time zone 'Europe/Stockholm')::date)
        or (setting.club_consent_at is not null and setting.player_consent_at is not null
          and setting.guardian_consent_at is not null)))
  from (select 1) one left join core.player_injury_settings setting on setting.club_person_id = person.id
$$;

-- A player's injuries, the latest first; the notes only for the leaders.
create or replace function internal.injury_rows(target_person_id uuid, with_notes boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', injury.id, 'started_on', injury.started_on,
      'what', injury.what, 'back_on', injury.back_on)
      || case when with_notes then jsonb_build_object('note', injury.note) else '{}'::jsonb end
    order by injury.started_on desc, injury.id), '[]'::jsonb)
  from core.player_injuries injury where injury.club_person_id = target_person_id
$$;

-- For the leaders: the team's active players, each with the registration's
-- status and their injuries.
create or replace function internal.tdp_injuries(plan core.development_plans)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('players', coalesce(jsonb_agg(jsonb_build_object(
      'person_id', person.id, 'name', person.display_name)
      || internal.injury_status(person)
      || jsonb_build_object('injuries', internal.injury_rows(person.id, true))
    order by person.display_name, person.id), '[]'::jsonb))
  from core.club_people person
  where person.club_id = plan.club_id and person.status = 'active'
    and exists (select 1 from core.assignments assignment
      where assignment.team_id = plan.team_id and assignment.club_person_id = person.id
        and assignment.role_package = 'player' and assignment.state = 'active')
$$;

create or replace function internal.get_team_development_injuries_for_actor(target_plan_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  return internal.tdp_injuries(internal.tdp_plan(target_plan_id));
end;
$$;

-- One of the plan's team's active players, for a leader who may change.
create or replace function internal.tdp_injury_player(plan core.development_plans, target_person_id uuid)
returns core.club_people language plpgsql stable security definer set search_path = '' as $$
declare person core.club_people;
begin
  select * into person from core.club_people
  where id = target_person_id and club_id = plan.club_id and status = 'active'
    and exists (select 1 from core.assignments assignment
      where assignment.team_id = plan.team_id and assignment.club_person_id = target_person_id
        and assignment.role_package = 'player' and assignment.state = 'active');
  if person.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  return person;
end;
$$;

-- Registers an injury or changes one; the registration must be on.
create or replace function internal.save_team_development_injury_for_actor(target_plan_id uuid,
  target_injury_id uuid, target_person_id uuid, new_started_on date, new_what text, new_note text, new_back_on date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; person core.club_people; changed uuid;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  person := internal.tdp_injury_player(plan, target_person_id);
  if not (internal.injury_status(person)->>'allowed')::boolean then
    raise insufficient_privilege using message = 'not_allowed';
  end if;
  if new_started_on is null or new_started_on > (now() at time zone 'Europe/Stockholm')::date
    or length(btrim(coalesce(new_what, ''))) not between 2 and 80 or length(coalesce(new_note, '')) > 2000
    or (new_back_on is not null and new_back_on < new_started_on) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if target_injury_id is null then
    insert into core.player_injuries (club_id, team_id, club_person_id, started_on, what, note, back_on, created_by)
    values (plan.club_id, plan.team_id, person.id, new_started_on, btrim(new_what), coalesce(new_note, ''),
      new_back_on, auth.uid());
  else
    update core.player_injuries set started_on = new_started_on, what = btrim(new_what),
      note = coalesce(new_note, ''), back_on = new_back_on, updated_at = now()
    where id = target_injury_id and club_person_id = person.id
    returning id into changed;
    if changed is null then raise insufficient_privilege using message = 'not_found'; end if;
  end if;
  return internal.tdp_injuries(plan);
end;
$$;

create or replace function internal.delete_team_development_injury_for_actor(target_plan_id uuid, target_injury_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; removed uuid;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  delete from core.player_injuries where id = target_injury_id and team_id = plan.team_id returning id into removed;
  if removed is null then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tdp_injuries(plan);
end;
$$;

-- The leaders turn a player's registration off (deleting the injuries) or
-- on, and give the club's consent under 15.
create or replace function internal.set_team_development_injury_registration_for_actor(target_plan_id uuid,
  target_person_id uuid, turn_off boolean, club_consent boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; person core.club_people;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  person := internal.tdp_injury_player(plan, target_person_id);
  perform internal.set_injury_registration(person, turn_off, club_consent);
  return internal.tdp_injuries(plan);
end;
$$;

-- Turns off or on and sets the club's consent (null leaves either as it is).
create or replace function internal.set_injury_registration(person core.club_people, turn_off boolean,
  club_consent boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into core.player_injury_settings (club_person_id, club_id) values (person.id, person.club_id)
  on conflict (club_person_id) do nothing;
  update core.player_injury_settings set
    turned_off = coalesce(turn_off, turned_off),
    turned_off_by = case when turn_off is null then turned_off_by else auth.uid() end,
    club_consent_by = case when club_consent is null then club_consent_by when club_consent then auth.uid() end,
    club_consent_at = case when club_consent is null then club_consent_at when club_consent then now() end,
    updated_at = now()
  where club_person_id = person.id;
  if turn_off or club_consent = false then
    delete from core.player_injuries where club_person_id = person.id
      and (turn_off or not internal.injury_age_reached(person, (now() at time zone 'Europe/Stockholm')::date));
  end if;
end;
$$;

-- For the club (club.memberships.manage): the same, for any of its people.
create or replace function internal.set_club_injury_registration_for_actor(target_person_id uuid,
  turn_off boolean, club_consent boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare person core.club_people;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into person from core.club_people where id = target_person_id;
  if person.id is null or not internal.actor_has_capability(person.club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  perform internal.set_injury_registration(person, turn_off, club_consent);
  return internal.injury_status(person);
end;
$$;

-- For a player and their guardians: the player's own and the children's
-- registration and injuries in a team, without the leaders' notes; who
-- may consent under 15.
create or replace function internal.get_my_injuries_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare team core.teams;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into team from core.teams where id = target_team_id;
  if team.id is null or not (internal.module_allows_read(team.club_id, 'module.team_development')
      or internal.module_allows_read(team.club_id, 'module.player_development')) then
    return jsonb_build_object('people', '[]'::jsonb);
  end if;
  return jsonb_build_object('people', coalesce((
    select jsonb_agg(jsonb_build_object('person_id', person.id, 'name', person.display_name, 'self', mine.own)
        || internal.injury_status(person)
        || jsonb_build_object('injuries', internal.injury_rows(person.id, false))
      order by not mine.own, person.display_name)
    from core.club_people person
    cross join lateral (select internal.actor_owns_club_person(team.club_id, person.id) own) mine
    where person.club_id = team.club_id and person.status = 'active'
      and internal.actor_represents_club_person(team.club_id, person.id)
      and exists (select 1 from core.assignments assignment
        where assignment.team_id = team.id and assignment.club_person_id = person.id
          and assignment.role_package = 'player' and assignment.state = 'active')), '[]'::jsonb));
end;
$$;

-- The player's own consent, or a guardian's, under 15; withdrawing one
-- deletes the injuries registered under it.
create or replace function internal.set_injury_consent_for_actor(target_team_id uuid, target_person_id uuid,
  give boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare person core.club_people; own boolean;
begin
  if give is null then raise invalid_parameter_value using message = 'invalid_input'; end if;
  select * into person from core.club_people where id = target_person_id;
  if person.id is null or not exists (select 1 from jsonb_array_elements(
      internal.get_my_injuries_for_actor(target_team_id)->'people') shown
      where shown.value->>'person_id' = target_person_id::text) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  own := internal.actor_owns_club_person(person.club_id, person.id);
  insert into core.player_injury_settings (club_person_id, club_id) values (person.id, person.club_id)
  on conflict (club_person_id) do nothing;
  if own then
    update core.player_injury_settings set player_consent_by = case when give then auth.uid() end,
      player_consent_at = case when give then now() end, updated_at = now() where club_person_id = person.id;
  else
    update core.player_injury_settings set guardian_consent_by = case when give then auth.uid() end,
      guardian_consent_at = case when give then now() end, updated_at = now() where club_person_id = person.id;
  end if;
  if not give and not internal.injury_age_reached(person, (now() at time zone 'Europe/Stockholm')::date) then
    delete from core.player_injuries where club_person_id = person.id;
  end if;
  return internal.get_my_injuries_for_actor(target_team_id);
end;
$$;

-- Injuries 24 months after the player was back (or after they started)
-- are deleted.
create or replace function internal.apply_player_injury_retention()
returns integer language plpgsql security definer set search_path = '' as $$
declare removed integer;
begin
  delete from core.player_injuries where coalesce(back_on, started_on) < current_date - interval '24 months';
  get diagnostics removed = row_count;
  return removed;
end;
$$;

do $$
declare existing_job_id bigint;
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    for existing_job_id in select jobid from cron.job where jobname = 'player-injury-retention' loop
      perform cron.unschedule(existing_job_id);
    end loop;
    perform cron.schedule('player-injury-retention', '47 3 * * *', 'select internal.apply_player_injury_retention();');
  end if;
end $$;

create or replace function api.get_team_development_injuries(target_plan_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.get_team_development_injuries_for_actor(target_plan_id) $$;
create or replace function api.save_team_development_injury(target_plan_id uuid, target_injury_id uuid,
  target_person_id uuid, new_started_on date, new_what text, new_note text, new_back_on date) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_team_development_injury_for_actor(target_plan_id, target_injury_id, target_person_id,
    new_started_on, new_what, new_note, new_back_on) $$;
create or replace function api.delete_team_development_injury(target_plan_id uuid, target_injury_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.delete_team_development_injury_for_actor(target_plan_id, target_injury_id) $$;
create or replace function api.set_team_development_injury_registration(target_plan_id uuid, target_person_id uuid,
  turn_off boolean, club_consent boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_team_development_injury_registration_for_actor(target_plan_id, target_person_id, turn_off,
    club_consent) $$;
create or replace function api.set_club_injury_registration(target_person_id uuid, turn_off boolean,
  club_consent boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_club_injury_registration_for_actor(target_person_id, turn_off, club_consent) $$;
create or replace function api.get_my_injuries(target_team_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.get_my_injuries_for_actor(target_team_id) $$;
create or replace function api.set_injury_consent(target_team_id uuid, target_person_id uuid, give boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_injury_consent_for_actor(target_team_id, target_person_id, give) $$;

revoke all on function
  internal.injury_age_reached(core.club_people, date),
  internal.injury_status(core.club_people),
  internal.injury_rows(uuid, boolean),
  internal.tdp_injuries(core.development_plans),
  internal.tdp_injury_player(core.development_plans, uuid),
  internal.set_injury_registration(core.club_people, boolean, boolean),
  internal.apply_player_injury_retention(),
  internal.get_team_development_injuries_for_actor(uuid),
  internal.save_team_development_injury_for_actor(uuid, uuid, uuid, date, text, text, date),
  internal.delete_team_development_injury_for_actor(uuid, uuid),
  internal.set_team_development_injury_registration_for_actor(uuid, uuid, boolean, boolean),
  internal.set_club_injury_registration_for_actor(uuid, boolean, boolean),
  internal.get_my_injuries_for_actor(uuid),
  internal.set_injury_consent_for_actor(uuid, uuid, boolean),
  api.get_team_development_injuries(uuid),
  api.save_team_development_injury(uuid, uuid, uuid, date, text, text, date),
  api.delete_team_development_injury(uuid, uuid),
  api.set_team_development_injury_registration(uuid, uuid, boolean, boolean),
  api.set_club_injury_registration(uuid, boolean, boolean),
  api.get_my_injuries(uuid),
  api.set_injury_consent(uuid, uuid, boolean)
from public, anon, authenticated;
grant execute on function
  internal.get_team_development_injuries_for_actor(uuid),
  internal.save_team_development_injury_for_actor(uuid, uuid, uuid, date, text, text, date),
  internal.delete_team_development_injury_for_actor(uuid, uuid),
  internal.set_team_development_injury_registration_for_actor(uuid, uuid, boolean, boolean),
  internal.set_club_injury_registration_for_actor(uuid, boolean, boolean),
  internal.get_my_injuries_for_actor(uuid),
  internal.set_injury_consent_for_actor(uuid, uuid, boolean),
  api.get_team_development_injuries(uuid),
  api.save_team_development_injury(uuid, uuid, uuid, date, text, text, date),
  api.delete_team_development_injury(uuid, uuid),
  api.set_team_development_injury_registration(uuid, uuid, boolean, boolean),
  api.set_club_injury_registration(uuid, boolean, boolean),
  api.get_my_injuries(uuid),
  api.set_injury_consent(uuid, uuid, boolean)
to authenticated;
notify pgrst, 'reload schema';
