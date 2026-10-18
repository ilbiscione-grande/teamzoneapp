-- REF-02, phase 1: föreningsdomare and the club's domaransvarig.
--
-- A club referee (föreningsdomare) is a person in the club with an active
-- row in core.club_referees: a role on the club level on top of their usual
-- role, with start, end and training, and no context of its own. They see
-- only their own club's matches.
-- Domaransvarig is the capability club.referees.manage on one of the
-- person's assignments in the club; club administrators always have it.
-- A match gets a kind of referee: förbundsdomare (federation), förenings-
-- domare (club) or none; per-team defaults set it on new and coming matches.
-- Club referees are proposed by domaransvarig (the referee answers, under
-- 15 a guardian) or sign up themselves (domaransvarig approves).
-- Suggestions flag clashes with the referee's own activities, the age rule
-- (at least 3 years older than the team's players) and the season's count.

create table if not exists core.club_referees (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  club_person_id uuid not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  trained_on date,
  valid_until date,
  created_by uuid references core.profiles(id) on delete set null,
  ended_by uuid references core.profiles(id) on delete set null,
  foreign key (club_person_id, club_id) references core.club_people(id, club_id)
);
create unique index if not exists club_referees_one_active on core.club_referees(club_person_id) where ends_at is null;
alter table core.club_referees enable row level security;
revoke all on core.club_referees from public, anon, authenticated;

alter table core.events add column if not exists referee_kind text;
alter table core.events drop constraint if exists events_referee_kind_check;
alter table core.events add constraint events_referee_kind_check check (referee_kind in ('federation', 'club', 'none'));

create table if not exists core.team_referee_defaults (
  team_id uuid primary key references core.teams(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  referee_kind text not null check (referee_kind in ('federation', 'club', 'none')),
  slot_count smallint not null default 1 check (slot_count between 0 and 3),
  home_only boolean not null default true,
  updated_by uuid references core.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table core.team_referee_defaults enable row level security;
revoke all on core.team_referee_defaults from public, anon, authenticated;

alter table core.event_referees add column if not exists kind text not null default 'federation';
alter table core.event_referees drop constraint if exists event_referees_kind_check;
alter table core.event_referees add constraint event_referees_kind_check check (kind in ('federation', 'club'));
alter table core.event_referees drop constraint if exists event_referees_state_check;
alter table core.event_referees add constraint event_referees_state_check
  check (state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed', 'declined', 'withdrawn'));
drop index if exists core.event_referees_open_slot;
drop index if exists core.event_referees_person_once;
create unique index event_referees_open_slot on core.event_referees(event_id, slot)
  where state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed');
create unique index event_referees_person_once on core.event_referees(event_id, referee_person_id)
  where state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed') and referee_person_id is not null;

create or replace function internal.active_club_referee(target_person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from core.club_referees referee
    join core.club_people person on person.id = referee.club_person_id and person.status = 'active'
    join core.clubs club on club.id = referee.club_id and club.status = 'active'
    where referee.club_person_id = target_person_id and referee.starts_at <= now()
      and (referee.ends_at is null or referee.ends_at > now()))
$$;

create or replace function internal.actor_manages_club_referees(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.actor_has_capability(target_club_id, null, 'club.referees.manage')
    or internal.actor_manages_club(target_club_id)
$$;

-- Who hears about sign-ups: domaransvariga and the club's administrators.
create or replace function internal.club_referee_coordinators(target_club_id uuid)
returns table(profile_id uuid, club_person_id uuid) language sql stable security definer set search_path = '' as $$
  select distinct on (link.profile_id) link.profile_id, link.club_person_id
  from core.person_account_links link
  join core.assignments assignment on assignment.club_person_id = link.club_person_id
    and assignment.club_id = link.club_id and assignment.state = 'active'
    and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
  join core.capability_grants grant_row on grant_row.assignment_id = assignment.id
    and grant_row.club_id = assignment.club_id and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
    and grant_row.capability in ('club.referees.manage', 'club.memberships.manage')
    and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
  where link.club_id = target_club_id and link.state = 'active'
  order by link.profile_id, link.club_person_id
$$;

-- Whole years, from the birth date or else the birth year; null unknown.
create or replace function internal.person_age_years(target_person_id uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select case
    when person.birth_date is not null then extract(year from age(current_date, person.birth_date))::integer
    when person.birth_year is not null then extract(year from current_date)::integer - person.birth_year
  end
  from core.club_people person where person.id = target_person_id
$$;

-- As in 20261108090000, and for club referees: from 15 the referee
-- answers, under 15 the guardians do.
create or replace function internal.referee_confirmers(target_person_id uuid)
returns table(profile_id uuid, club_id uuid, club_person_id uuid)
language sql stable security definer set search_path = '' as $$
  with referee as (
    select person.id, person.club_id, coalesce(internal.person_age_years(person.id), 99) < 15 as young
    from core.club_people person where person.id = target_person_id
  )
  select distinct link.profile_id, link.club_id, link.club_person_id
  from referee
  join core.person_account_links link on link.club_id = referee.club_id and link.state = 'active'
  where (link.club_person_id = referee.id and not referee.young)
    or (referee.young and exists (select 1 from core.guardian_relations relation
      where relation.club_id = referee.club_id and relation.child_person_id = referee.id
        and relation.guardian_person_id = link.club_person_id and relation.state = 'active'
        and relation.starts_at <= now() and (relation.ends_at is null or relation.ends_at > now())))
    or exists (select 1 from core.assignments assignment
      where assignment.club_id = referee.club_id and assignment.club_person_id = link.club_person_id
        and assignment.role_package = 'referee_assigner' and assignment.state = 'active'
        and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now()))
$$;

-- The referee is at least three years older than every player of the team:
-- true, false, or null when a birth year is missing.
create or replace function internal.club_referee_age_ok(target_person_id uuid, target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  with referee as (
    select coalesce(extract(year from person.birth_date)::integer, person.birth_year) as born
    from core.club_people person where person.id = target_person_id
  ), players as (
    select min(coalesce(extract(year from person.birth_date)::integer, person.birth_year)) as oldest,
      bool_or(person.birth_date is null and person.birth_year is null) as unknown
    from core.events event_row
    join core.team_assignments home on home.team_id = event_row.owning_team_id and home.state = 'active'
    join core.club_people person on person.id = home.club_person_id and person.status = 'active'
    where event_row.id = target_event_id
  )
  select case when referee.born is null or players.oldest is null then null
    else referee.born <= players.oldest - 3 end
  from referee, players
$$;

-- The referee already has something at the time: their own team's event
-- (as player or leader) or another referee assignment.
create or replace function internal.referee_has_clash(target_person_id uuid, target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  with match as (select starts_at, ends_at from core.events where id = target_event_id)
  select exists (select 1 from core.events other, match
      where other.id <> target_event_id and other.state in ('draft', 'scheduled')
        and other.starts_at < match.ends_at and other.ends_at > match.starts_at
        and other.owning_team_id in (
          select home.team_id from core.team_assignments home
          where home.club_person_id = target_person_id and home.state = 'active'
          union
          select assignment.team_id from core.assignments assignment
          where assignment.club_person_id = target_person_id and assignment.state = 'active'
            and assignment.team_id is not null))
    or exists (select 1 from core.event_referees referee
      join core.events other on other.id = referee.event_id, match
      where referee.referee_person_id = target_person_id and referee.event_id <> target_event_id
        and referee.state in ('awaiting_referee', 'awaiting_coordinator', 'awaiting_team', 'confirmed')
        and other.starts_at < match.ends_at and other.ends_at > match.starts_at)
$$;

-- Confirmed club assignments this year.
create or replace function internal.club_referee_season_count(target_person_id uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer from core.event_referees referee
  join core.events event_row on event_row.id = referee.event_id
  where referee.referee_person_id = target_person_id and referee.state = 'confirmed'
    and event_row.starts_at >= date_trunc('year', now())
$$;

-- Applies the team's default kind of referee to a match without one.
create or replace function internal.apply_team_referee_default()
returns trigger language plpgsql security definer set search_path = '' as $$
declare rule core.team_referee_defaults%rowtype;
begin
  if new.event_type <> 'match' or new.referee_kind is not null then return new; end if;
  select * into rule from core.team_referee_defaults where team_id = new.owning_team_id;
  if rule.team_id is null or (rule.home_only and new.home_away is distinct from 'home') then return new; end if;
  new.referee_kind := rule.referee_kind;
  if rule.referee_kind <> 'none' and new.referee_slots < rule.slot_count then
    new.referee_slots := rule.slot_count;
  end if;
  return new;
end;$$;
drop trigger if exists events_apply_team_referee_default on core.events;
create trigger events_apply_team_referee_default before insert or update of event_type, home_away, owning_team_id
on core.events for each row execute function internal.apply_team_referee_default();

create or replace function internal.set_event_referee_kind_for_actor(target_event_id uuid, kind text)
returns void language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype;
begin
  select * into event_row from core.events where id = target_event_id for update;
  if event_row.id is null or not (internal.actor_can_manage_event(event_row.id)
      or internal.actor_manages_club_referees(event_row.club_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if kind is null or kind not in ('federation', 'club', 'none') or event_row.event_type <> 'match' then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if kind = 'none' and exists (select 1 from core.event_referees referee where referee.event_id = event_row.id
      and referee.state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed')) then
    raise invalid_parameter_value using message = 'slots_in_use';
  end if;
  update core.events set referee_kind = kind,
    referee_slots = case when kind = 'none' then 0 when referee_slots = 0 then 1 else referee_slots end
  where id = event_row.id;
end;$$;

create or replace function internal.save_team_referee_default_for_actor(target_team_id uuid, kind text,
  slot_count integer, home_only boolean)
returns integer language plpgsql security definer set search_path = '' as $$
declare target_club uuid; changed integer;
begin
  select club_id into target_club from core.teams where id = target_team_id and status = 'active';
  if target_club is null or not internal.actor_manages_club_referees(target_club) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if kind is null or kind not in ('federation', 'club', 'none') or slot_count is null or slot_count not between 0 and 3 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  insert into core.team_referee_defaults(team_id, club_id, referee_kind, slot_count, home_only, updated_by)
  values (target_team_id, target_club, kind, slot_count, coalesce(home_only, true), auth.uid())
  on conflict (team_id) do update set referee_kind = excluded.referee_kind, slot_count = excluded.slot_count,
    home_only = excluded.home_only, updated_by = excluded.updated_by, updated_at = now();
  -- Coming matches without a kind follow the rule at once.
  update core.events event_row set referee_kind = kind,
    referee_slots = case when kind = 'none' then event_row.referee_slots
      else greatest(event_row.referee_slots, slot_count) end
  where event_row.owning_team_id = target_team_id and event_row.event_type = 'match'
    and event_row.referee_kind is null and event_row.starts_at > now()
    and event_row.state in ('draft', 'scheduled')
    and (not coalesce(home_only, true) or event_row.home_away = 'home');
  get diagnostics changed = row_count;
  return changed;
end;$$;

create or replace function internal.set_club_referee_for_actor(target_club_id uuid, target_person_id uuid,
  enabled boolean, trained_on date, valid_until date)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not internal.actor_manages_club_referees(target_club_id)
    or not exists (select 1 from core.club_people person where person.id = target_person_id
      and person.club_id = target_club_id and person.status = 'active') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if valid_until is not null and trained_on is not null and valid_until < trained_on then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if coalesce(enabled, false) then
    update core.club_referees set trained_on = set_club_referee_for_actor.trained_on,
      valid_until = set_club_referee_for_actor.valid_until
    where club_person_id = target_person_id and ends_at is null;
    if not found then
      insert into core.club_referees(club_id, club_person_id, trained_on, valid_until, created_by)
      values (target_club_id, target_person_id, set_club_referee_for_actor.trained_on,
        set_club_referee_for_actor.valid_until, auth.uid());
    end if;
  else
    update core.club_referees set ends_at = now(), ended_by = auth.uid()
    where club_person_id = target_person_id and ends_at is null;
  end if;
end;$$;

-- Domaransvarig: the capability on one of the person's active assignments
-- in the club, given and taken back by the club's administrators.
create or replace function internal.set_club_referee_coordinator_for_actor(target_club_id uuid,
  target_person_id uuid, enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare assignment_id uuid;
begin
  if not internal.actor_manages_club(target_club_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if coalesce(enabled, false) then
    select assignment.id into assignment_id from core.assignments assignment
    where assignment.club_id = target_club_id and assignment.club_person_id = target_person_id
      and assignment.state = 'active' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
    order by assignment.starts_at limit 1;
    if assignment_id is null then raise invalid_parameter_value using message = 'no_assignment'; end if;
    if not exists (select 1 from core.capability_grants grant_row
        join core.assignments assignment on assignment.id = grant_row.assignment_id
        where assignment.club_person_id = target_person_id and grant_row.capability = 'club.referees.manage'
          and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
          and (grant_row.ends_at is null or grant_row.ends_at > now())) then
      insert into core.capability_grants(club_id, assignment_id, capability, scope_type, scope_id, starts_at, created_by)
      values (target_club_id, assignment_id, 'club.referees.manage', 'club', target_club_id, now(), auth.uid());
    end if;
  else
    -- An end must come after the start, also the same moment it was given.
    update core.capability_grants grant_row
    set ends_at = greatest(now(), grant_row.starts_at + interval '1 microsecond')
    from core.assignments assignment
    where assignment.id = grant_row.assignment_id and assignment.club_person_id = target_person_id
      and grant_row.capability = 'club.referees.manage' and grant_row.scope_type = 'club'
      and grant_row.scope_id = target_club_id and (grant_row.ends_at is null or grant_row.ends_at > now());
  end if;
end;$$;

create or replace function internal.club_referee_json(target_person_id uuid, target_event_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('person_id', person.id, 'name', person.display_name,
    'age', internal.person_age_years(person.id),
    'trained_on', referee.trained_on, 'valid_until', referee.valid_until,
    'season_count', internal.club_referee_season_count(person.id),
    'age_ok', case when target_event_id is null then null else internal.club_referee_age_ok(person.id, target_event_id) end,
    'clash', case when target_event_id is null then false else internal.referee_has_clash(person.id, target_event_id) end)
  from core.club_people person
  left join core.club_referees referee on referee.club_person_id = person.id and referee.ends_at is null
  where person.id = target_person_id
$$;

-- The domaransvarig's board: the club's matches in a period with their
-- kind of referee, places and referees, and the club's referees.
create or replace function internal.get_club_referee_board_for_actor(target_club_id uuid, from_date date, to_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare first_day date := coalesce(from_date, (now() at time zone 'Europe/Stockholm')::date);
  last_day date := coalesce(to_date, first_day + 14);
begin
  if not internal.actor_manages_club_referees(target_club_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if last_day < first_day or last_day - first_day > 92 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  return jsonb_build_object(
    'matches', coalesce((select jsonb_agg(internal.referee_event_json(event_row.id)
        || jsonb_build_object('referee_kind', event_row.referee_kind, 'team_id', event_row.owning_team_id,
          'referees', coalesce((select jsonb_agg(internal.event_referee_json(referee.id)
              order by internal.referee_slot_index(referee.slot))
            from core.event_referees referee where referee.event_id = event_row.id
              and referee.state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed')), '[]'::jsonb))
        order by event_row.starts_at)
      from core.events event_row
      join core.teams team on team.id = event_row.owning_team_id and team.status = 'active'
      where event_row.club_id = target_club_id and event_row.event_type = 'match'
        and event_row.state in ('draft', 'scheduled')
        and (event_row.starts_at at time zone 'Europe/Stockholm')::date between first_day and last_day), '[]'::jsonb),
    'referees', coalesce((select jsonb_agg(internal.club_referee_json(referee.club_person_id, null)
        order by person.display_name)
      from core.club_referees referee join core.club_people person on person.id = referee.club_person_id
      where referee.club_id = target_club_id and referee.ends_at is null and person.status = 'active'), '[]'::jsonb),
    'defaults', coalesce((select jsonb_agg(jsonb_build_object('team_id', team.id, 'team_name', team.name,
        'referee_kind', rule.referee_kind, 'slot_count', rule.slot_count, 'home_only', rule.home_only)
        order by team.name)
      from core.teams team left join core.team_referee_defaults rule on rule.team_id = team.id
      where team.club_id = target_club_id and team.status = 'active'), '[]'::jsonb),
    'coordinators', coalesce((select jsonb_agg(distinct jsonb_build_object('person_id', person.id, 'name', person.display_name))
      from core.capability_grants grant_row
      join core.assignments assignment on assignment.id = grant_row.assignment_id and assignment.state = 'active'
      join core.club_people person on person.id = assignment.club_person_id and person.status = 'active'
      where grant_row.capability = 'club.referees.manage' and grant_row.scope_type = 'club'
        and grant_row.scope_id = target_club_id and grant_row.starts_at <= now()
        and (grant_row.ends_at is null or grant_row.ends_at > now())), '[]'::jsonb),
    'can_appoint_coordinators', internal.actor_manages_club(target_club_id));
end;$$;

-- People in the club the domaransvarig can make club referees (or an
-- administrator domaransvarig): name, team and age.
create or replace function internal.search_club_people_for_referees_for_actor(target_club_id uuid, search_text text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare query text := btrim(coalesce(search_text, ''));
begin
  if not internal.actor_manages_club_referees(target_club_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if length(query) < 2 or length(query) > 80 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('person_id', person.id, 'name', person.display_name,
      'age', internal.person_age_years(person.id), 'club_referee', internal.active_club_referee(person.id),
      'team_names', (select string_agg(distinct team.name, ', ') from core.teams team
        where team.id in (select home.team_id from core.team_assignments home where home.club_person_id = person.id and home.state = 'active'
          union select assignment.team_id from core.assignments assignment where assignment.club_person_id = person.id
            and assignment.state = 'active' and assignment.team_id is not null)))
    order by person.display_name)
    from (select * from core.club_people person where person.club_id = target_club_id and person.status = 'active'
      and person.display_name ilike '%' || query || '%' order by person.display_name limit 30) person), '[]'::jsonb);
end;$$;

-- Suggestions for one match: the club's referees with the age rule, clashes
-- and the season's count; the least used first.
create or replace function internal.list_club_referee_candidates_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events%rowtype;
begin
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or not internal.actor_manages_club_referees(event_row.club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((select jsonb_agg(item order by (item->>'clash')::boolean, coalesce((item->>'age_ok')::boolean, true) desc,
      (item->>'season_count')::integer, item->>'name')
    from (select internal.club_referee_json(referee.club_person_id, event_row.id) item
      from core.club_referees referee join core.club_people person on person.id = referee.club_person_id
      where referee.club_id = event_row.club_id and referee.ends_at is null and person.status = 'active'
        and not exists (select 1 from core.event_referees taken where taken.event_id = event_row.id
          and taken.referee_person_id = referee.club_person_id
          and taken.state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed'))) rows), '[]'::jsonb);
end;$$;

-- For club referees (and their guardians): the own club's coming matches
-- that want club referees and have an open place.
create or replace function internal.list_open_club_matches_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(internal.referee_event_json(event_row.id) || jsonb_build_object(
      'person_id', mine.club_person_id, 'person_name', person.display_name,
      'age_ok', internal.club_referee_age_ok(mine.club_person_id, event_row.id),
      'clash', internal.referee_has_clash(mine.club_person_id, event_row.id),
      'taken', coalesce((select jsonb_agg(jsonb_build_object('slot', referee.slot, 'state', referee.state))
        from core.event_referees referee where referee.event_id = event_row.id
          and referee.state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed')), '[]'::jsonb))
    order by event_row.starts_at), '[]'::jsonb)
  from core.club_referees mine
  join core.club_people person on person.id = mine.club_person_id and person.status = 'active'
  join core.events event_row on event_row.club_id = mine.club_id and event_row.event_type = 'match'
    and event_row.state = 'scheduled' and event_row.referee_kind = 'club'
    and event_row.starts_at > now() and event_row.starts_at < now() + interval '60 days'
  where mine.ends_at is null and internal.actor_acts_for_referee(mine.club_person_id)
    and (select count(*) from core.event_referees referee where referee.event_id = event_row.id
      and referee.state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed'))
      < greatest(event_row.referee_slots, 1)
    and not exists (select 1 from core.event_referees referee where referee.event_id = event_row.id
      and referee.referee_person_id = mine.club_person_id
      and referee.state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed'))
    and internal.club_referee_age_ok(mine.club_person_id, event_row.id) is not false
$$;

-- As in 20261108090000, with the coordinators as a side.
create or replace function internal.notify_event_referee(target_referee_id uuid, target_side text, new_event_type text)
returns integer language plpgsql security definer set search_path = '' as $$
declare referee core.event_referees%rowtype; event_row core.events%rowtype; added integer;
begin
  select * into referee from core.event_referees where id = target_referee_id;
  select * into event_row from core.events where id = referee.event_id;
  if referee.id is null or event_row.id is null then return 0; end if;
  if target_side = 'team' then
    insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
      recipient_profile_id, recipient_person_id, payload_ref)
    select event_row.club_id, gen_random_uuid(), new_event_type, 'referee_assignment', referee.id,
      recipient.profile_id, recipient.club_person_id,
      jsonb_build_object('event_id', event_row.id, 'referee_id', referee.id, 'side', 'team')
    from internal.match_pool_recipients(event_row.club_id, event_row.owning_team_id) recipient
    where recipient.profile_id is distinct from auth.uid()
    on conflict do nothing;
  elsif target_side = 'coordinator' then
    insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
      recipient_profile_id, recipient_person_id, payload_ref)
    select event_row.club_id, gen_random_uuid(), new_event_type, 'referee_assignment', referee.id,
      recipient.profile_id, recipient.club_person_id,
      jsonb_build_object('event_id', event_row.id, 'referee_id', referee.id, 'side', 'coordinator')
    from internal.club_referee_coordinators(event_row.club_id) recipient
    where recipient.profile_id is distinct from auth.uid()
    on conflict do nothing;
  elsif referee.referee_person_id is not null then
    insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
      recipient_profile_id, recipient_person_id, payload_ref)
    select confirmer.club_id, gen_random_uuid(), new_event_type, 'referee_assignment', referee.id,
      confirmer.profile_id, confirmer.club_person_id,
      jsonb_build_object('event_id', event_row.id, 'referee_id', referee.id, 'side', 'referee')
    from internal.referee_confirmers(referee.referee_person_id) confirmer
    where confirmer.profile_id is distinct from auth.uid()
    on conflict do nothing;
  end if;
  get diagnostics added = row_count;
  return added;
end;$$;

-- As in 20261108090000, with the kind and the coordinator's rights.
create or replace function internal.event_referee_json(target_referee_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', referee.id, 'event_id', referee.event_id, 'slot', referee.slot,
    'state', referee.state, 'proposed_side', referee.proposed_side, 'kind', referee.kind,
    'person_id', referee.referee_person_id,
    'name', coalesce(person.display_name, referee.external_name),
    'club_name', club.name, 'external', referee.external_name is not null,
    'created_at', referee.created_at)
  from core.event_referees referee
  left join core.club_people person on person.id = referee.referee_person_id
  left join core.clubs club on club.id = referee.referee_club_id
  where referee.id = target_referee_id
$$;

create or replace function internal.get_event_referees_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or not (internal.actor_can_read_event(event_row.id)
      or internal.actor_manages_club_referees(event_row.club_id)
      or exists (select 1 from core.event_referees referee where referee.event_id = event_row.id
        and referee.referee_person_id is not null and internal.actor_acts_for_referee(referee.referee_person_id))) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'event_id', event_row.id,
    'slots', event_row.referee_slots,
    'referee_kind', event_row.referee_kind,
    'can_manage', internal.actor_can_manage_event(event_row.id),
    'can_manage_club_referees', internal.actor_manages_club_referees(event_row.club_id),
    'referees', coalesce((select jsonb_agg(internal.event_referee_json(referee.id)
        order by internal.referee_slot_index(referee.slot), referee.created_at)
      from core.event_referees referee
      where referee.event_id = event_row.id
        and referee.state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed')),
      '[]'::jsonb));
end;$$;

-- As in 20261108090000: a team's event manager proposes any referee; the
-- domaransvarig proposes the club's referees for a club-referee match.
create or replace function internal.propose_event_referee_for_actor(target_event_id uuid, target_slot text,
  target_person_id uuid, written_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype; new_id uuid; new_state text; referee_club uuid; new_kind text := 'federation';
  name text := nullif(btrim(coalesce(written_name, '')), ''); by_team boolean; by_coordinator boolean;
begin
  select * into event_row from core.events where id = target_event_id for update;
  if event_row.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  by_team := internal.actor_can_manage_event(event_row.id);
  by_coordinator := internal.actor_manages_club_referees(event_row.club_id);
  if not (by_team or by_coordinator) then raise insufficient_privilege using message = 'not_found'; end if;
  if event_row.event_type <> 'match' or event_row.state not in ('draft', 'scheduled') then
    raise invalid_parameter_value using message = 'not_a_match';
  end if;
  if internal.referee_slot_index(target_slot) is null or ((target_person_id is null) = (name is null))
    or length(name) > 120 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if target_person_id is not null then
    select club_id into referee_club from core.club_people where id = target_person_id;
    if referee_club = event_row.club_id and internal.active_club_referee(target_person_id) then
      new_kind := 'club';
    elsif not internal.active_referee(target_person_id) then
      raise invalid_parameter_value using message = 'not_a_referee';
    end if;
    -- Only the team proposes federation referees; the coordinator the club's.
    if not by_team and new_kind <> 'club' then raise insufficient_privilege using message = 'not_found'; end if;
    new_state := case when exists (select 1 from internal.referee_confirmers(target_person_id)
      where profile_id is distinct from auth.uid()) then 'awaiting_referee' else 'confirmed' end;
  else
    if not by_team then raise insufficient_privilege using message = 'not_found'; end if;
    new_state := 'confirmed';
  end if;
  if event_row.referee_slots < internal.referee_slot_index(target_slot) then
    update core.events set referee_slots = internal.referee_slot_index(target_slot) where id = event_row.id;
  end if;
  begin
    insert into core.event_referees(event_id, club_id, slot, referee_person_id, referee_club_id, external_name, state,
      proposed_side, proposed_by, decided_by, decided_at, kind)
    values (event_row.id, event_row.club_id, target_slot, target_person_id, referee_club, name, new_state,
      'team', auth.uid(), case when new_state = 'confirmed' then auth.uid() end,
      case when new_state = 'confirmed' then now() end, new_kind)
    returning id into new_id;
  exception when unique_violation then
    raise invalid_parameter_value using message = 'slot_taken';
  end;
  if new_state = 'awaiting_referee' then
    perform internal.notify_event_referee(new_id, 'referee', 'referee.proposed.v1');
  end if;
  return new_id;
end;$$;

-- A club referee (or a guardian for one under 15) signs up for an open
-- place on the own club's club-referee match; domaransvarig approves.
create or replace function internal.request_club_referee_for_actor(target_event_id uuid, target_slot text,
  target_person_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype; new_id uuid; person_club uuid;
begin
  if target_person_id is null or not internal.actor_acts_for_referee(target_person_id)
    or not internal.active_club_referee(target_person_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select club_id into person_club from core.club_people where id = target_person_id;
  select * into event_row from core.events where id = target_event_id for update;
  if event_row.id is null or event_row.club_id <> person_club or event_row.event_type <> 'match'
    or event_row.state <> 'scheduled' or event_row.starts_at <= now() or event_row.referee_kind <> 'club' then
    raise invalid_parameter_value using message = 'not_a_match';
  end if;
  if internal.referee_slot_index(target_slot) is null
    or internal.referee_slot_index(target_slot) > greatest(event_row.referee_slots, 1) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if internal.club_referee_age_ok(target_person_id, event_row.id) is false then
    raise invalid_parameter_value using message = 'too_young';
  end if;
  begin
    insert into core.event_referees(event_id, club_id, slot, referee_person_id, referee_club_id, state,
      proposed_side, proposed_by, kind)
    values (event_row.id, event_row.club_id, target_slot, target_person_id, person_club, 'awaiting_coordinator',
      'referee', auth.uid(), 'club')
    returning id into new_id;
  exception when unique_violation then
    raise invalid_parameter_value using message = 'slot_taken';
  end;
  perform internal.notify_event_referee(new_id, 'coordinator', 'referee.club_requested.v1');
  return new_id;
end;$$;

-- As in 20261108090000, and the domaransvarig answers club sign-ups.
create or replace function internal.respond_event_referee_for_actor(target_referee_id uuid, accept boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare referee core.event_referees%rowtype; new_state text;
begin
  select * into referee from core.event_referees where id = target_referee_id for update;
  if referee.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  if referee.state = 'awaiting_referee' then
    if not internal.actor_acts_for_referee(referee.referee_person_id) then
      raise insufficient_privilege using message = 'not_found';
    end if;
  elsif referee.state = 'awaiting_team' then
    if not internal.actor_can_manage_event(referee.event_id) then raise insufficient_privilege using message = 'not_found'; end if;
  elsif referee.state = 'awaiting_coordinator' then
    if not internal.actor_manages_club_referees(referee.club_id) then raise insufficient_privilege using message = 'not_found'; end if;
  else
    raise invalid_parameter_value using message = 'not_pending';
  end if;
  new_state := case when coalesce(accept, false) then 'confirmed' else 'declined' end;
  update core.event_referees set state = new_state, decided_by = auth.uid(), decided_at = now(),
    updated_at = clock_timestamp()
  where id = referee.id;
  perform internal.notify_event_referee(referee.id, referee.proposed_side,
    case when new_state = 'confirmed' then 'referee.confirmed.v1' else 'referee.declined.v1' end);
  return new_state;
end;$$;

-- As in 20261108090000; the domaransvarig may also take back club places.
create or replace function internal.withdraw_event_referee_for_actor(target_referee_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare referee core.event_referees%rowtype; by_organiser boolean;
begin
  select * into referee from core.event_referees where id = target_referee_id for update;
  if referee.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  by_organiser := internal.actor_can_manage_event(referee.event_id)
    or (referee.kind = 'club' and internal.actor_manages_club_referees(referee.club_id));
  if not by_organiser and not (referee.referee_person_id is not null and internal.actor_acts_for_referee(referee.referee_person_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if referee.state not in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed') then return; end if;
  update core.event_referees set state = 'withdrawn', decided_by = auth.uid(), decided_at = now(),
    updated_at = clock_timestamp()
  where id = referee.id;
  perform internal.notify_event_referee(referee.id,
    case when by_organiser then 'referee' when referee.kind = 'club' then 'coordinator' else 'team' end,
    'referee.withdrawn.v1');
end;$$;

-- As in 20261108090000, and the club referees one acts for.
create or replace function internal.list_my_referee_people_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('person_id', person.id, 'name', person.display_name,
      'club_name', club.name, 'club_referee', internal.active_club_referee(person.id),
      'self', exists (select 1 from core.person_account_links link where link.club_person_id = person.id
        and link.profile_id = auth.uid() and link.state = 'active'))
    order by person.display_name), '[]'::jsonb)
  from core.club_people person
  join core.clubs club on club.id = person.club_id
  where (internal.active_referee(person.id) or internal.active_club_referee(person.id))
    and internal.actor_acts_for_referee(person.id)
$$;

-- What the app needs to know: is the signed-in person (or a child) a club
-- referee, and which clubs do they coordinate referees for.
create or replace function internal.get_my_referee_summary_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'club_referee', exists (select 1 from core.club_referees referee where referee.ends_at is null
      and internal.actor_acts_for_referee(referee.club_person_id)),
    'coordinator_clubs', coalesce((select jsonb_agg(jsonb_build_object('club_id', club.id, 'club_name', club.name)
        order by club.name)
      from core.clubs club where club.status = 'active'
        and club.id in (select link.club_id from core.person_account_links link
          where link.profile_id = auth.uid() and link.state = 'active')
        and internal.actor_manages_club_referees(club.id)), '[]'::jsonb),
    'open_count', (select jsonb_array_length(internal.list_open_club_matches_for_actor())))
$$;

-- As in 20261108090000, with club referee sign-ups.
create or replace function internal.push_message_for_outbox(target_outbox_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare outbox internal.notification_outbox%rowtype; profile core.profiles%rowtype;
  swedish boolean; event_row core.events%rowtype; team_name text; kind text;
  title text; body text; callup_row core.callups%rowtype; raw_token text;
  response jsonb; thread_row core.message_threads%rowtype; reply jsonb; targets jsonb;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  select * into outbox from internal.notification_outbox where id = target_outbox_id;
  if outbox.id is null or outbox.recipient_profile_id is null then return null; end if;
  select * into profile from core.profiles where id = outbox.recipient_profile_id;
  swedish := coalesce(profile.locale, 'sv') not like 'en%';
  targets := coalesce((
    select jsonb_agg(jsonb_build_object('endpoint_id', endpoint.id, 'platform', stored.platform,
      'token', extensions.pgp_sym_decrypt(stored.token_ciphertext, internal.push_token_key())))
    from core.notification_endpoints endpoint
    join internal.push_endpoint_tokens stored on stored.endpoint_id = endpoint.id
    where endpoint.profile_id = outbox.recipient_profile_id and endpoint.channel = 'push'
      and endpoint.state = 'active'), '[]'::jsonb);
  if outbox.event_type like 'callup.%' and outbox.payload_ref->>'event_id' ~ '^[0-9a-fA-F-]{36}$' then
    select * into event_row from core.events where id = (outbox.payload_ref->>'event_id')::uuid;
    if event_row.id is null then return null; end if;
    select name into team_name from core.teams where id = event_row.owning_team_id;
    kind := case event_row.event_type
      when 'training' then case when swedish then 'Träning' else 'Training' end
      when 'match' then 'Match'
      when 'meeting' then case when swedish then 'Möte' else 'Meeting' end
      else case when swedish then 'Aktivitet' else 'Activity' end end;
    title := case
      when outbox.event_type like 'callup.callup.cancelled.%' then case when swedish then 'Kallelsen är inställd' else 'Callup cancelled' end
      when outbox.event_type like 'callup.callup.reminded.%' then case when swedish then 'Påminnelse: svara på kallelsen' else 'Reminder: answer the callup' end
      else case when swedish then 'Ny kallelse' else 'New callup' end end;
    body := concat_ws(' · ', kind, team_name,
      internal.push_local_time(event_row.starts_at, coalesce(profile.timezone, event_row.timezone), swedish));
    -- Tokens only for someone with a device to answer from.
    if jsonb_array_length(targets) > 0
      and outbox.event_type ~ '^callup\.callup\.(sent|late_sent|reminded)\.'
      and outbox.payload_ref->>'callup_id' ~ '^[0-9a-fA-F-]{36}$' then
      select * into callup_row from core.callups where id = (outbox.payload_ref->>'callup_id')::uuid;
      if callup_row.id is not null and callup_row.event_id = event_row.id and callup_row.state = 'pending'
        and (callup_row.expires_at is null or callup_row.expires_at > now()) then
        delete from internal.push_response_tokens
        where expires_at <= now() or consumed_at < now() - interval '1 day';
        raw_token := encode(extensions.gen_random_bytes(32), 'hex');
        insert into internal.push_response_tokens(callup_id, recipient_profile_id, acting_as_person_id,
          token_hash, expires_at)
        values (callup_row.id, outbox.recipient_profile_id,
          -- Someone other than the called person (a guardian) answers for
          -- them; decided by the recipient's own link, not recipient_person_id
          -- (which can be null).
          case when exists (select 1 from core.person_account_links link
              where link.profile_id = outbox.recipient_profile_id and link.club_id = callup_row.club_id
                and link.club_person_id = callup_row.club_person_id and link.state = 'active')
            then null else callup_row.club_person_id end,
          extensions.digest(raw_token, 'sha256'),
          least(callup_row.expires_at, now() + interval '2 days'));
        response := jsonb_build_object('callup_id', callup_row.id, 'token', raw_token);
      end if;
    end if;
  elsif outbox.event_type = 'message.message.sent.v1' then
    select team.name into team_name from core.thread_scopes scope join core.teams team on team.id = scope.team_id
    where outbox.payload_ref->>'thread_id' ~ '^[0-9a-fA-F-]{36}$'
      and scope.thread_id = (outbox.payload_ref->>'thread_id')::uuid
    order by team.name limit 1;
    title := case when swedish then 'Nytt meddelande' else 'New message' end;
    body := coalesce(team_name, case when swedish then 'Öppna TeamZone för att läsa.' else 'Open TeamZone to read it.' end);
    if jsonb_array_length(targets) > 0 and outbox.payload_ref->>'thread_id' ~ '^[0-9a-fA-F-]{36}$' then
      select * into thread_row from core.message_threads where id = (outbox.payload_ref->>'thread_id')::uuid;
      -- Announcements are written by their creator only: no reply button.
      if thread_row.id is not null and thread_row.state = 'active' and thread_row.thread_type <> 'announcement' then
        delete from internal.push_reply_tokens
        where expires_at <= now() or consumed_at < now() - interval '1 day';
        raw_token := encode(extensions.gen_random_bytes(32), 'hex');
        insert into internal.push_reply_tokens(thread_id, recipient_profile_id, token_hash, expires_at)
        values (thread_row.id, outbox.recipient_profile_id, extensions.digest(raw_token, 'sha256'),
          now() + interval '2 days');
        reply := jsonb_build_object('thread_id', thread_row.id, 'token', raw_token);
      end if;
    end if;
  elsif outbox.event_type = 'contact.message.received.v1' then
    -- A message via the club site: type and club or team, never the text.
    select coalesce(team.name, club.name) into team_name
    from internal.public_contact_submissions submission
    join core.clubs club on club.id = submission.club_id
    left join core.teams team on team.id = submission.team_id
    where outbox.payload_ref->>'submission_id' ~ '^[0-9a-fA-F-]{36}$'
      and submission.id = (outbox.payload_ref->>'submission_id')::uuid;
    title := case when swedish then 'Nytt meddelande via klubbsajten' else 'New message via the club site' end;
    body := coalesce(team_name, case when swedish then 'Öppna TeamZone för att läsa.' else 'Open TeamZone to read it.' end);
  elsif outbox.event_type like 'referee.%' then
    -- A referee assignment: what happened and the match's time, no names.
    select concat_ws(' · ', team.name, internal.push_local_time(event_row.starts_at,
        coalesce(profile.timezone, event_row.timezone), swedish))
      into body
    from core.events event_row join core.teams team on team.id = event_row.owning_team_id
    where outbox.payload_ref->>'event_id' ~ '^[0-9a-fA-F-]{36}$'
      and event_row.id = (outbox.payload_ref->>'event_id')::uuid;
    title := case outbox.event_type
      when 'referee.proposed.v1' then case when swedish then 'Förfrågan om att döma' else 'Asked to referee' end
      when 'referee.requested.v1' then case when swedish then 'En domare vill döma er match' else 'A referee offers to referee your match' end
      when 'referee.confirmed.v1' then case when swedish then 'Domaren är bekräftad' else 'Referee confirmed' end
      when 'referee.declined.v1' then case when swedish then 'Domarförfrågan nekad' else 'Referee request declined' end
      when 'referee.club_requested.v1' then case when swedish then 'En föreningsdomare vill döma' else 'A club referee offers to referee' end
      else case when swedish then 'Domaruppdraget är ändrat' else 'Referee assignment changed' end end;
    body := coalesce(body, case when swedish then 'Öppna TeamZone.' else 'Open TeamZone.' end);
  elsif outbox.event_type = 'matchpool.watch.matched.v1' then
    -- A new listing that fits a watch: age class, format and place, never names.
    select listing.age_class || ' · ' || replace(listing.match_format, 'v', case when swedish then ' mot ' else ' v ' end)
        || ' · ' || listing.place_label
      into body
    from internal.match_pool_listings listing
    where outbox.payload_ref->>'listing_id' ~ '^[0-9a-fA-F-]{36}$'
      and listing.id = (outbox.payload_ref->>'listing_id')::uuid;
    title := case when swedish then 'Ny annons som matchar er bevakning' else 'A new listing matches your watch' end;
    body := coalesce(body, case when swedish then 'Öppna matchpoolen.' else 'Open the match pool.' end);
  elsif outbox.event_type like 'matchpool.%' then
    -- The pool: what happened and the leader's own team, never the text.
    select team.name into team_name from core.teams team
    where outbox.payload_ref->>'team_id' ~ '^[0-9a-fA-F-]{36}$'
      and team.id = (outbox.payload_ref->>'team_id')::uuid;
    title := case outbox.event_type
      when 'matchpool.interest.received.v1' then case when swedish then 'Intresse för er annons i matchpoolen' else 'Interest in your match pool listing' end
      when 'matchpool.interest.accepted.v1' then case when swedish then 'Träningsmatchen är bokad' else 'The friendly is booked' end
      when 'matchpool.message.sent.v1' then case when swedish then 'Nytt meddelande i matchpoolen' else 'New message in the match pool' end
      when 'matchpool.cancellation.requested.v1' then case when swedish then 'Begäran om avbokning' else 'Cancellation requested' end
      when 'matchpool.cancellation.accepted.v1' then case when swedish then 'Träningsmatchen är avbokad' else 'The friendly is cancelled' end
      when 'matchpool.cancellation.declined.v1' then case when swedish then 'Träningsmatchen gäller' else 'The friendly is still on' end
      when 'matchpool.cancellation.withdrawn.v1' then case when swedish then 'Träningsmatchen gäller' else 'The friendly is still on' end
      else case when swedish then 'Besked från matchpoolen' else 'News from the match pool' end end;
    body := coalesce(team_name, case when swedish then 'Öppna matchpoolen på teamzoneapp.se.' else 'Open the match pool on teamzoneapp.se.' end);
  else
    return null;
  end if;
  return jsonb_build_object(
    'title', title,
    'body', body,
    'route', internal.notification_deep_link(outbox),
    'response', response,
    'reply', reply,
    'language', case when swedish then 'sv' else 'en' end,
    'targets', targets);
end;$$;

-- As in 20261108090000, with club referee sign-ups.
create or replace function internal.notification_title(event_type text)
returns text language sql immutable set search_path = '' as $$
 select case
  when event_type = 'message.message.sent.v1' then 'Nytt meddelande'
  when event_type = 'contact.message.received.v1' then 'Nytt meddelande via klubbsajten'
  when event_type = 'matchpool.interest.received.v1' then 'Intresse för er annons i matchpoolen'
  when event_type = 'matchpool.interest.accepted.v1' then 'Träningsmatchen är bokad'
  when event_type in ('matchpool.interest.declined.v1', 'matchpool.interest.closed.v1') then 'Besked från matchpoolen'
  when event_type = 'matchpool.message.sent.v1' then 'Nytt meddelande i matchpoolen'
  when event_type = 'matchpool.cancellation.requested.v1' then 'Begäran om avbokning'
  when event_type = 'matchpool.cancellation.accepted.v1' then 'Träningsmatchen är avbokad'
  when event_type in ('matchpool.cancellation.declined.v1', 'matchpool.cancellation.withdrawn.v1') then 'Träningsmatchen gäller'
  when event_type = 'matchpool.watch.matched.v1' then 'Ny annons som matchar er bevakning'
  when event_type = 'referee.proposed.v1' then 'Förfrågan om att döma'
  when event_type = 'referee.requested.v1' then 'En domare vill döma er match'
  when event_type = 'referee.confirmed.v1' then 'Domaren är bekräftad'
  when event_type = 'referee.declined.v1' then 'Domarförfrågan nekad'
  when event_type = 'referee.club_requested.v1' then 'En föreningsdomare vill döma'
  when event_type like 'referee.%' then 'Domaruppdraget är ändrat'
  when event_type like 'callup.%.cancelled.%' then 'Kallelse återkallad'
  when event_type like 'callup.%.reminded.%' then 'Påminnelse om kallelse'
  when event_type like 'callup.%' then 'Ny kallelse'
  when event_type like 'event.%' then 'Kalendern har uppdaterats'
  else 'Ny aktivitet i TeamZone' end
$$;

create or replace function api.set_event_referee_kind(target_event_id uuid, kind text)
returns void language sql security invoker set search_path = '' as
$$select internal.set_event_referee_kind_for_actor(target_event_id, kind)$$;
create or replace function api.save_team_referee_default(target_team_id uuid, kind text, slot_count integer, home_only boolean)
returns integer language sql security invoker set search_path = '' as
$$select internal.save_team_referee_default_for_actor(target_team_id, kind, slot_count, home_only)$$;
create or replace function api.set_club_referee(target_club_id uuid, target_person_id uuid, enabled boolean,
  trained_on date default null, valid_until date default null)
returns void language sql security invoker set search_path = '' as
$$select internal.set_club_referee_for_actor(target_club_id, target_person_id, enabled, trained_on, valid_until)$$;
create or replace function api.set_club_referee_coordinator(target_club_id uuid, target_person_id uuid, enabled boolean)
returns void language sql security invoker set search_path = '' as
$$select internal.set_club_referee_coordinator_for_actor(target_club_id, target_person_id, enabled)$$;
create or replace function api.get_club_referee_board(target_club_id uuid, from_date date, to_date date)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_club_referee_board_for_actor(target_club_id, from_date, to_date)$$;
create or replace function api.list_club_referee_candidates(target_event_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_club_referee_candidates_for_actor(target_event_id)$$;
create or replace function api.search_club_people_for_referees(target_club_id uuid, search_text text)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.search_club_people_for_referees_for_actor(target_club_id, search_text)$$;
create or replace function api.list_open_club_matches()
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_open_club_matches_for_actor()$$;
create or replace function api.request_club_referee(target_event_id uuid, target_slot text, target_person_id uuid)
returns uuid language sql security invoker set search_path = '' as
$$select internal.request_club_referee_for_actor(target_event_id, target_slot, target_person_id)$$;
create or replace function api.get_my_referee_summary()
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_my_referee_summary_for_actor()$$;

revoke all on function internal.active_club_referee(uuid), internal.actor_manages_club_referees(uuid),
  internal.club_referee_coordinators(uuid), internal.person_age_years(uuid), internal.club_referee_age_ok(uuid, uuid),
  internal.referee_has_clash(uuid, uuid), internal.club_referee_season_count(uuid), internal.apply_team_referee_default(),
  internal.club_referee_json(uuid, uuid),
  internal.set_event_referee_kind_for_actor(uuid, text), internal.save_team_referee_default_for_actor(uuid, text, integer, boolean),
  internal.set_club_referee_for_actor(uuid, uuid, boolean, date, date),
  internal.set_club_referee_coordinator_for_actor(uuid, uuid, boolean),
  internal.get_club_referee_board_for_actor(uuid, date, date), internal.list_club_referee_candidates_for_actor(uuid),
  internal.list_open_club_matches_for_actor(), internal.request_club_referee_for_actor(uuid, text, uuid),
  internal.search_club_people_for_referees_for_actor(uuid, text), api.search_club_people_for_referees(uuid, text),
  internal.get_my_referee_summary_for_actor(),
  api.set_event_referee_kind(uuid, text), api.save_team_referee_default(uuid, text, integer, boolean),
  api.set_club_referee(uuid, uuid, boolean, date, date), api.set_club_referee_coordinator(uuid, uuid, boolean),
  api.get_club_referee_board(uuid, date, date), api.list_club_referee_candidates(uuid), api.list_open_club_matches(),
  api.request_club_referee(uuid, text, uuid), api.get_my_referee_summary()
  from public, anon, authenticated;
grant execute on function
  internal.set_event_referee_kind_for_actor(uuid, text), internal.save_team_referee_default_for_actor(uuid, text, integer, boolean),
  internal.set_club_referee_for_actor(uuid, uuid, boolean, date, date),
  internal.set_club_referee_coordinator_for_actor(uuid, uuid, boolean),
  internal.get_club_referee_board_for_actor(uuid, date, date), internal.list_club_referee_candidates_for_actor(uuid),
  internal.list_open_club_matches_for_actor(), internal.request_club_referee_for_actor(uuid, text, uuid),
  internal.search_club_people_for_referees_for_actor(uuid, text), api.search_club_people_for_referees(uuid, text),
  internal.get_my_referee_summary_for_actor(),
  api.set_event_referee_kind(uuid, text), api.save_team_referee_default(uuid, text, integer, boolean),
  api.set_club_referee(uuid, uuid, boolean, date, date), api.set_club_referee_coordinator(uuid, uuid, boolean),
  api.get_club_referee_board(uuid, date, date), api.list_club_referee_candidates(uuid), api.list_open_club_matches(),
  api.request_club_referee(uuid, text, uuid), api.get_my_referee_summary()
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261109090000_club_referees', 'greenfield', 'REF-02: club referees and the club referee coordinator'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261109090000_club_referees');
notify pgrst, 'reload schema';
