-- REF-01: domare och domartillsättare.
--
-- Referee (domare) and referee assigner (domartillsättare) are team roles,
-- held in a referee club's team (e.g. Njudungs FDK), given like leader
-- roles. A match has 0–3 referee places: Huvuddomare, Assisterande domare
-- 1 and 2.
--
-- Both sides confirm when the other side can (decided 2026-10-17):
--   * a team's event manager proposes a referee: the referee, or an
--     assigner in the referee's club, accepts or declines. A referee nobody
--     can answer for (no account, no assigner) is confirmed at once;
--   * a referee (or an assigner for one of the club's referees) offers to
--     referee a match: the team's event managers accept or decline;
--   * a leader can also write in a referee who is not in TeamZone.
-- Referees and assigners can search all scheduled matches (decided): date,
-- time, team, club, opponent and place, nothing about the players.

alter table core.assignments drop constraint if exists assignments_role_package_check;
alter table core.assignments add constraint assignments_role_package_check
  check (role_package in ('player', 'leader', 'guardian', 'club_functionary', 'guest', 'referee', 'referee_assigner'));

alter table core.events add column if not exists referee_slots smallint not null default 0;
alter table core.events drop constraint if exists events_referee_slots_check;
alter table core.events add constraint events_referee_slots_check check (referee_slots between 0 and 3);

create table if not exists core.event_referees (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  slot text not null check (slot in ('main', 'assistant_1', 'assistant_2')),
  referee_person_id uuid references core.club_people(id),
  referee_club_id uuid references core.clubs(id),
  external_name text check (external_name is null or length(btrim(external_name)) between 1 and 120),
  state text not null check (state in ('awaiting_referee', 'awaiting_team', 'confirmed', 'declined', 'withdrawn')),
  proposed_side text not null check (proposed_side in ('team', 'referee')),
  proposed_by uuid references core.profiles(id) on delete set null,
  decided_by uuid references core.profiles(id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check ((referee_person_id is null) <> (external_name is null)),
  check ((referee_person_id is null) = (referee_club_id is null))
);
create unique index if not exists event_referees_open_slot on core.event_referees(event_id, slot)
  where state in ('awaiting_referee', 'awaiting_team', 'confirmed');
create unique index if not exists event_referees_person_once on core.event_referees(event_id, referee_person_id)
  where state in ('awaiting_referee', 'awaiting_team', 'confirmed') and referee_person_id is not null;
create index if not exists event_referees_person_idx on core.event_referees(referee_person_id, state);
alter table core.event_referees enable row level security;
revoke all on core.event_referees from public, anon, authenticated;

create or replace function internal.referee_slot_index(slot text)
returns integer language sql immutable set search_path = '' as $$
  select case slot when 'main' then 1 when 'assistant_1' then 2 when 'assistant_2' then 3 end
$$;

-- A club person who currently holds the referee role, in an active club.
create or replace function internal.active_referee(target_person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from core.assignments assignment
    join core.club_people person on person.id = assignment.club_person_id and person.status = 'active'
    join core.clubs club on club.id = assignment.club_id and club.status = 'active'
    where assignment.club_person_id = target_person_id and assignment.role_package = 'referee'
      and assignment.state = 'active' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now()))
$$;

-- Who answers for a referee: the referee's own account, and the referee
-- club's assigners.
create or replace function internal.referee_confirmers(target_person_id uuid)
returns table(profile_id uuid, club_id uuid, club_person_id uuid)
language sql stable security definer set search_path = '' as $$
  select distinct link.profile_id, link.club_id, link.club_person_id
  from core.club_people referee
  join core.person_account_links link on link.club_id = referee.club_id and link.state = 'active'
  where referee.id = target_person_id
    and (link.club_person_id = referee.id
      or exists (select 1 from core.assignments assignment
        where assignment.club_id = referee.club_id and assignment.club_person_id = link.club_person_id
          and assignment.role_package = 'referee_assigner' and assignment.state = 'active'
          and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())))
$$;

create or replace function internal.actor_acts_for_referee(target_person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from internal.referee_confirmers(target_person_id) confirmer
    where confirmer.profile_id = auth.uid())
$$;

-- The signed-in person is a referee or an assigner somewhere.
create or replace function internal.actor_is_referee_side()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from core.person_account_links link
    join core.assignments assignment on assignment.club_person_id = link.club_person_id
      and assignment.club_id = link.club_id
    where link.profile_id = auth.uid() and link.state = 'active'
      and assignment.role_package in ('referee', 'referee_assigner') and assignment.state = 'active'
      and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now()))
$$;

-- The signed-in person manages events in some team (may look for referees).
create or replace function internal.actor_manages_events()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from core.person_account_links link
    join core.assignments assignment on assignment.club_person_id = link.club_person_id
      and assignment.club_id = link.club_id and assignment.state = 'active'
    join core.capability_grants grant_row on grant_row.assignment_id = assignment.id
      and grant_row.capability = 'event.manage'
      and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
    where link.profile_id = auth.uid() and link.state = 'active')
$$;

-- The match as referees see it: no players, no notes.
create or replace function internal.referee_event_json(target_event_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('event_id', event_row.id, 'title', event_row.title, 'state', event_row.state,
    'starts_at', event_row.starts_at, 'ends_at', event_row.ends_at,
    'team_name', team.name, 'club_name', club.name, 'opponent_name', event_row.opponent_name,
    'home_away', event_row.home_away, 'referee_slots', event_row.referee_slots,
    'location', internal.event_place_label(place.name, place.pitch))
  from core.events event_row
  join core.teams team on team.id = event_row.owning_team_id
  join core.clubs club on club.id = event_row.club_id
  left join core.event_locations place on place.id = event_row.location_id
  where event_row.id = target_event_id
$$;

create or replace function internal.event_referee_json(target_referee_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', referee.id, 'event_id', referee.event_id, 'slot', referee.slot,
    'state', referee.state, 'proposed_side', referee.proposed_side,
    'person_id', referee.referee_person_id,
    'name', coalesce(person.display_name, referee.external_name),
    'club_name', club.name, 'external', referee.external_name is not null,
    'created_at', referee.created_at)
  from core.event_referees referee
  left join core.club_people person on person.id = referee.referee_person_id
  left join core.clubs club on club.id = referee.referee_club_id
  where referee.id = target_referee_id
$$;

-- Tells one side about a change. The team side: the team's event managers
-- (the match pool's recipients); the referee side: the referee's account
-- and the club's assigners. Never the one who acted.
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

create or replace function internal.get_event_referees_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or not (internal.actor_can_read_event(event_row.id)
      or exists (select 1 from core.event_referees referee where referee.event_id = event_row.id
        and referee.referee_person_id is not null and internal.actor_acts_for_referee(referee.referee_person_id))) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'event_id', event_row.id,
    'slots', event_row.referee_slots,
    'can_manage', internal.actor_can_manage_event(event_row.id),
    'referees', coalesce((select jsonb_agg(internal.event_referee_json(referee.id)
        order by internal.referee_slot_index(referee.slot), referee.created_at)
      from core.event_referees referee
      where referee.event_id = event_row.id and referee.state in ('awaiting_referee', 'awaiting_team', 'confirmed')),
      '[]'::jsonb));
end;$$;

create or replace function internal.set_event_referee_slots_for_actor(target_event_id uuid, slot_count integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not internal.actor_can_manage_event(target_event_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if slot_count is null or slot_count not between 0 and 3 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  if exists (select 1 from core.event_referees referee where referee.event_id = target_event_id
      and referee.state in ('awaiting_referee', 'awaiting_team', 'confirmed')
      and internal.referee_slot_index(referee.slot) > slot_count) then
    raise invalid_parameter_value using message = 'slots_in_use';
  end if;
  update core.events set referee_slots = slot_count where id = target_event_id;
end;$$;

create or replace function internal.search_referees_for_actor(search_text text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare query text := btrim(coalesce(search_text, ''));
begin
  if not (internal.actor_manages_events() or internal.actor_is_referee_side()) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if length(query) < 2 or length(query) > 80 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(item order by name) from (
    select distinct on (person.id) jsonb_build_object('person_id', person.id, 'name', person.display_name,
        'club_name', club.name, 'team_name', team.name,
        'confirmable', exists (select 1 from internal.referee_confirmers(person.id))) item,
      person.display_name name
    from core.assignments assignment
    join core.club_people person on person.id = assignment.club_person_id and person.status = 'active'
    join core.clubs club on club.id = assignment.club_id and club.status = 'active'
    left join core.teams team on team.id = assignment.team_id
    where assignment.role_package = 'referee' and assignment.state = 'active'
      and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
      and (person.display_name ilike '%' || query || '%' or club.name ilike '%' || query || '%')
    order by person.id limit 30) rows), '[]'::jsonb);
end;$$;

create or replace function internal.propose_event_referee_for_actor(target_event_id uuid, target_slot text,
  target_person_id uuid, written_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype; new_id uuid; new_state text; referee_club uuid;
  name text := nullif(btrim(coalesce(written_name, '')), '');
begin
  if not internal.actor_can_manage_event(target_event_id) then raise insufficient_privilege using message = 'not_found'; end if;
  select * into event_row from core.events where id = target_event_id for update;
  if event_row.event_type <> 'match' or event_row.state not in ('draft', 'scheduled') then
    raise invalid_parameter_value using message = 'not_a_match';
  end if;
  if internal.referee_slot_index(target_slot) is null or ((target_person_id is null) = (name is null))
    or length(name) > 120 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if target_person_id is not null then
    if not internal.active_referee(target_person_id) then raise invalid_parameter_value using message = 'not_a_referee'; end if;
    select club_id into referee_club from core.club_people where id = target_person_id;
    new_state := case when exists (select 1 from internal.referee_confirmers(target_person_id)
      where profile_id is distinct from auth.uid()) then 'awaiting_referee' else 'confirmed' end;
  else
    new_state := 'confirmed';
  end if;
  -- Choosing a later place also opens it.
  if event_row.referee_slots < internal.referee_slot_index(target_slot) then
    update core.events set referee_slots = internal.referee_slot_index(target_slot) where id = event_row.id;
  end if;
  begin
    insert into core.event_referees(event_id, club_id, slot, referee_person_id, referee_club_id, external_name, state,
      proposed_side, proposed_by, decided_by, decided_at)
    values (event_row.id, event_row.club_id, target_slot, target_person_id, referee_club, name, new_state,
      'team', auth.uid(), case when new_state = 'confirmed' then auth.uid() end,
      case when new_state = 'confirmed' then now() end)
    returning id into new_id;
  exception when unique_violation then
    raise invalid_parameter_value using message = 'slot_taken';
  end;
  if new_state = 'awaiting_referee' then
    perform internal.notify_event_referee(new_id, 'referee', 'referee.proposed.v1');
  end if;
  return new_id;
end;$$;

create or replace function internal.request_event_referee_for_actor(target_event_id uuid, target_slot text,
  target_person_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype; new_id uuid; referee_club uuid;
begin
  if target_person_id is null or not internal.actor_acts_for_referee(target_person_id)
    or not internal.active_referee(target_person_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into event_row from core.events where id = target_event_id for update;
  if event_row.id is null or event_row.event_type <> 'match' or event_row.state <> 'scheduled'
    or event_row.starts_at <= now()
    or not exists (select 1 from core.clubs club where club.id = event_row.club_id and club.status = 'active') then
    raise invalid_parameter_value using message = 'not_a_match';
  end if;
  if internal.referee_slot_index(target_slot) is null
    or internal.referee_slot_index(target_slot) > greatest(event_row.referee_slots, 1) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select club_id into referee_club from core.club_people where id = target_person_id;
  begin
    insert into core.event_referees(event_id, club_id, slot, referee_person_id, referee_club_id, state,
      proposed_side, proposed_by)
    values (event_row.id, event_row.club_id, target_slot, target_person_id, referee_club, 'awaiting_team',
      'referee', auth.uid())
    returning id into new_id;
  exception when unique_violation then
    raise invalid_parameter_value using message = 'slot_taken';
  end;
  perform internal.notify_event_referee(new_id, 'team', 'referee.requested.v1');
  return new_id;
end;$$;

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

create or replace function internal.withdraw_event_referee_for_actor(target_referee_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare referee core.event_referees%rowtype; by_team boolean;
begin
  select * into referee from core.event_referees where id = target_referee_id for update;
  if referee.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  by_team := internal.actor_can_manage_event(referee.event_id);
  if not by_team and not (referee.referee_person_id is not null and internal.actor_acts_for_referee(referee.referee_person_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if referee.state not in ('awaiting_referee', 'awaiting_team', 'confirmed') then return; end if;
  update core.event_referees set state = 'withdrawn', decided_by = auth.uid(), decided_at = now(),
    updated_at = clock_timestamp()
  where id = referee.id;
  perform internal.notify_event_referee(referee.id, case when by_team then 'referee' else 'team' end,
    'referee.withdrawn.v1');
end;$$;

-- Referees and assigners: scheduled matches in a date range (at most two
-- months), with which places are open.
create or replace function internal.search_referee_matches_for_actor(search_text text, from_date date, to_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare query text := btrim(coalesce(search_text, ''));
  first_day date := greatest(coalesce(from_date, (now() at time zone 'Europe/Stockholm')::date),
    (now() at time zone 'Europe/Stockholm')::date);
  last_day date := coalesce(to_date, first_day + 30);
begin
  if not internal.actor_is_referee_side() then raise insufficient_privilege using message = 'not_found'; end if;
  if last_day < first_day or last_day - first_day > 62 or length(query) > 80 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  return coalesce((select jsonb_agg(item order by starts) from (
    select internal.referee_event_json(event_row.id) || jsonb_build_object(
        'taken', coalesce((select jsonb_agg(jsonb_build_object('slot', referee.slot, 'state', referee.state))
          from core.event_referees referee where referee.event_id = event_row.id
            and referee.state in ('awaiting_referee', 'awaiting_team', 'confirmed')), '[]'::jsonb)) item,
      event_row.starts_at starts
    from core.events event_row
    join core.teams team on team.id = event_row.owning_team_id and team.status = 'active'
    join core.clubs club on club.id = event_row.club_id and club.status = 'active'
    left join core.event_locations place on place.id = event_row.location_id
    where event_row.event_type = 'match' and event_row.state = 'scheduled'
      and event_row.starts_at > now()
      and (event_row.starts_at at time zone 'Europe/Stockholm')::date between first_day and last_day
      and (query = '' or team.name ilike '%' || query || '%' or club.name ilike '%' || query || '%'
        or event_row.opponent_name ilike '%' || query || '%' or place.name ilike '%' || query || '%')
    order by event_row.starts_at limit 100) rows), '[]'::jsonb);
end;$$;

-- The referees the signed-in person may act for: themselves, and for an
-- assigner every referee in the club.
create or replace function internal.list_my_referee_people_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('person_id', person.id, 'name', person.display_name,
      'club_name', club.name,
      'self', exists (select 1 from core.person_account_links link where link.club_person_id = person.id
        and link.profile_id = auth.uid() and link.state = 'active'))
    order by person.display_name), '[]'::jsonb)
  from core.club_people person
  join core.clubs club on club.id = person.club_id
  where internal.active_referee(person.id) and internal.actor_acts_for_referee(person.id)
$$;

-- Every assignment the signed-in person answers for, from a month back.
create or replace function internal.list_my_referee_assignments_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(internal.event_referee_json(referee.id)
      || jsonb_build_object('match', internal.referee_event_json(referee.event_id),
        'awaiting_me', referee.state = 'awaiting_referee')
    order by event_row.starts_at), '[]'::jsonb)
  from core.event_referees referee
  join core.events event_row on event_row.id = referee.event_id
  where referee.referee_person_id is not null
    and referee.state in ('awaiting_referee', 'awaiting_team', 'confirmed')
    and event_row.starts_at > now() - interval '30 days'
    and internal.actor_acts_for_referee(referee.referee_person_id)
$$;

-- As in 20261003090342, with the referee roles.
create or replace function internal.team_role_command(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 from_role text,to_role text,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); command text; existing jsonb; result jsonb;
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 command:=case when from_role is null then 'roster.role.add.v1' when to_role is null then 'roster.role.remove.v1' else 'roster.role.change.v1' end;
 -- REF-01: referees and referee assigners are team roles like leaders.
 if idempotency_key is null
  or (from_role is not null and from_role not in('player','leader','referee','referee_assigner'))
  or (to_role is not null and to_role not in('player','leader','referee','referee_assigner'))
  or from_role is not distinct from to_role then
  raise invalid_parameter_value using message='invalid_role';
 end if;
 select dedup.result into existing from internal.command_deduplication dedup
 where dedup.actor_profile_id=actor_id and dedup.command_type=command
  and dedup.idempotency_key=team_role_command.idempotency_key;
 if existing is not null then return existing; end if;
 perform pg_advisory_xact_lock(hashtextextended('team_role:'||target_club_id::text||':'||target_person_id::text,0));
 if not exists(select 1 from core.club_people person where person.id=target_person_id
  and person.club_id=target_club_id and person.status='active') then
  raise invalid_parameter_value using message='invalid_person';
 end if;
 if from_role is not null then
  if not internal.team_role_active(target_club_id,target_team_id,target_person_id,from_role) then
   raise serialization_failure using message='stale_role';
  end if;
  if from_role='leader' and internal.actor_owns_club_person(target_club_id,target_person_id)
   and not internal.actor_has_capability(target_club_id,null,'club.memberships.manage') then
   raise check_violation using message='own_leader_role';
  end if;
  if to_role='player' and exists(select 1 from core.team_assignments home where home.club_id=target_club_id
   and home.club_person_id=target_person_id and home.state='active' and home.team_id<>target_team_id) then
   raise check_violation using message='home_in_other_team';
  end if;
  perform internal.stop_team_role(target_club_id,target_team_id,target_person_id,from_role);
 end if;
 if to_role is not null then
  perform internal.start_team_role(target_club_id,target_team_id,target_person_id,to_role);
 end if;
 result:=jsonb_build_object('person_id',target_person_id,'from_role',from_role,'to_role',to_role);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,command,result);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,command,'club_person',target_person_id,1,
  jsonb_build_object('team_id',target_team_id,'from_role',from_role,'to_role',to_role));
 return result;
end$$;

-- As in 20260929090000; the role itself, not always leader.
create or replace function internal.start_team_role(target_club_id uuid,target_team_id uuid,target_person_id uuid,target_role text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if internal.team_role_active(target_club_id,target_team_id,target_person_id,target_role) then return; end if;
 if target_role='player' then
  if exists(select 1 from core.team_assignments home where home.club_id=target_club_id
   and home.club_person_id=target_person_id and home.state='active' and home.team_id<>target_team_id) then
   raise check_violation using message='home_in_other_team';
  end if;
  if not exists(select 1 from core.team_assignments home where home.club_id=target_club_id
   and home.club_person_id=target_person_id and home.team_id=target_team_id and home.state='active') then
   insert into core.team_assignments(club_id,team_id,club_person_id,starts_at,created_by)
   values(target_club_id,target_team_id,target_person_id,now(),auth.uid());
  end if;
 else
  -- The role itself: leader, referee or referee_assigner.
  insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
  values(target_club_id,target_team_id,target_person_id,target_role,'active',now(),auth.uid());
 end if;
end$$;

-- As in 20260929160000, listing the referee roles.
create or replace function internal.list_team_roles_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_sport text; manages_leaders boolean;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
  and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  and not internal.actor_has_capability(target_club_id,target_team_id,'team.leaders.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
 manages_leaders:=internal.actor_has_capability(target_club_id,target_team_id,'team.leaders.manage');
 select sport into team_sport from core.teams where id=target_team_id and club_id=target_club_id;
 return jsonb_build_object(
  'can_manage',manages_leaders,
  'can_edit_details',internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') or manages_leaders,
  'grantable',case when manages_leaders then to_jsonb(coalesce(array(select v from unnest(internal.leader_permission_catalog()) v
    where internal.actor_has_capability(target_club_id,target_team_id,v)),'{}')) else '[]'::jsonb end,
  'sport',coalesce(team_sport,'football'),
  'position_catalog',coalesce((select jsonb_agg(jsonb_build_object('key',catalog.key,'level',catalog.level,
    'parent',catalog.parent_key) order by catalog.sort) from core.sport_positions catalog
   where catalog.sport=team_sport),'[]'::jsonb),
  'roles',coalesce((select jsonb_agg(jsonb_build_object(
    'person_id',person.id,'name',person.display_name,'role',assignment.role_package,
    'starts_at',assignment.starts_at,'is_self',internal.actor_owns_club_person(target_club_id,person.id),
    'functions',coalesce(details.functions,'{}'::text[]),
    'positions',coalesce(details.positions,'{}'::text[]),
    'custom_titles',coalesce(details.custom_titles,'{}'::text[]),
    'custom_positions',coalesce(details.custom_positions,'{}'::text[]),
    'details_revision',coalesce(details.revision,0),
    'permissions',case when manages_leaders and assignment.role_package='leader'
     then to_jsonb(internal.leader_panel_capabilities(target_club_id,target_team_id,person.id)) else null end,
    'permission_template',case when manages_leaders then details.permission_template else null end)
   order by case assignment.role_package when 'leader' then 0 when 'club_functionary' then 1 else 2 end,person.display_name,person.id)
   from core.assignments assignment
   join core.club_people person on person.id=assignment.club_person_id and person.club_id=assignment.club_id
   left join core.team_person_details details on details.club_id=assignment.club_id
    and details.team_id=assignment.team_id and details.club_person_id=assignment.club_person_id
   where assignment.club_id=target_club_id and assignment.team_id=target_team_id
    and assignment.role_package in('player','leader','club_functionary','referee','referee_assigner')
    and assignment.state='active' and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and person.status='active'),'[]'::jsonb));
end$$;

-- As in 20261104090000, with referee assignments.
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

-- As in 20261104090000, with referee assignments.
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
  when event_type like 'referee.%' then 'Domaruppdraget är ändrat'
  when event_type like 'callup.%.cancelled.%' then 'Kallelse återkallad'
  when event_type like 'callup.%.reminded.%' then 'Påminnelse om kallelse'
  when event_type like 'callup.%' then 'Ny kallelse'
  when event_type like 'event.%' then 'Kalendern har uppdaterats'
  else 'Ny aktivitet i TeamZone' end
$$;

-- As in 20261102090000, with referee assignments.
create or replace function internal.notification_preview(event_type text)
returns text language sql immutable set search_path = '' as $$
 select case
  when event_type = 'message.message.sent.v1' then 'Öppna inkorgen för att läsa meddelandet.'
  when event_type = 'contact.message.received.v1' then 'Öppna inkorgen för att läsa och svara.'
  when event_type like 'matchpool.%' then 'Öppna matchpoolen på teamzoneapp.se.'
  when event_type like 'referee.%' then 'Öppna matchen för att se domarna.'
  when event_type like 'callup.%.cancelled.%' then 'En kallelse har återkallats.'
  when event_type like 'callup.%.reminded.%' then 'Du har en kallelse som behöver besvaras.'
  when event_type like 'callup.%' then 'Du har fått en kallelse.'
  when event_type like 'event.%' then 'Öppna kalendern för aktuell information.'
  else 'Öppna TeamZone för mer information.' end
$$;

-- As in 20261104090000, with referee assignments.
create or replace function internal.notification_deep_link(
  outbox internal.notification_outbox)
returns text
language sql
stable
set search_path=''
as $$
  select case
    when outbox.event_type='message.message.sent.v1'
      and outbox.payload_ref->>'thread_id'~'^[0-9a-fA-F-]{36}$'
      then '/inbox?thread='||(outbox.payload_ref->>'thread_id')
    when outbox.event_type='matchpool.watch.matched.v1'
      and outbox.payload_ref->>'listing_id'~'^[0-9a-fA-F-]{36}$'
      then '/inbox?poolad='||(outbox.payload_ref->>'listing_id')
    when outbox.event_type like 'matchpool.%'
      and outbox.payload_ref->>'interest_id'~'^[0-9a-fA-F-]{36}$'
      then '/inbox?pool='||(outbox.payload_ref->>'interest_id')
    -- REF-01: the team side opens the match; the referee side the home page
    -- with the referee assignments.
    when outbox.event_type like 'referee.%' and outbox.payload_ref->>'side' = 'referee'
      then '/home'
    when outbox.event_type like 'referee.%'
      and outbox.payload_ref->>'event_id'~'^[0-9a-fA-F-]{36}$'
      then '/calendar/event/'||(outbox.payload_ref->>'event_id')
    when outbox.event_type like 'callup.%'
      and outbox.payload_ref->>'event_id'~'^[0-9a-fA-F-]{36}$'
      then '/calendar/event/'||(outbox.payload_ref->>'event_id')
    when outbox.aggregate_type='event'
      then '/calendar/event/'||outbox.aggregate_id::text
    else '/inbox'
  end;
$$;

create or replace function api.get_event_referees(target_event_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_event_referees_for_actor(target_event_id)$$;
create or replace function api.set_event_referee_slots(target_event_id uuid, slot_count integer)
returns void language sql security invoker set search_path = '' as
$$select internal.set_event_referee_slots_for_actor(target_event_id, slot_count)$$;
create or replace function api.search_referees(search_text text)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.search_referees_for_actor(search_text)$$;
create or replace function api.propose_event_referee(target_event_id uuid, target_slot text, target_person_id uuid,
  written_name text default null)
returns uuid language sql security invoker set search_path = '' as
$$select internal.propose_event_referee_for_actor(target_event_id, target_slot, target_person_id, written_name)$$;
create or replace function api.request_event_referee(target_event_id uuid, target_slot text, target_person_id uuid)
returns uuid language sql security invoker set search_path = '' as
$$select internal.request_event_referee_for_actor(target_event_id, target_slot, target_person_id)$$;
create or replace function api.respond_event_referee(target_referee_id uuid, accept boolean)
returns text language sql security invoker set search_path = '' as
$$select internal.respond_event_referee_for_actor(target_referee_id, accept)$$;
create or replace function api.withdraw_event_referee(target_referee_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.withdraw_event_referee_for_actor(target_referee_id)$$;
create or replace function api.search_referee_matches(search_text text, from_date date, to_date date)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.search_referee_matches_for_actor(search_text, from_date, to_date)$$;
create or replace function api.list_my_referee_people()
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_my_referee_people_for_actor()$$;
create or replace function api.list_my_referee_assignments()
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_my_referee_assignments_for_actor()$$;

revoke all on function internal.referee_slot_index(text), internal.active_referee(uuid),
  internal.referee_confirmers(uuid), internal.actor_acts_for_referee(uuid), internal.actor_is_referee_side(),
  internal.actor_manages_events(), internal.referee_event_json(uuid), internal.event_referee_json(uuid),
  internal.notify_event_referee(uuid, text, text),
  internal.get_event_referees_for_actor(uuid), internal.set_event_referee_slots_for_actor(uuid, integer),
  internal.search_referees_for_actor(text), internal.propose_event_referee_for_actor(uuid, text, uuid, text),
  internal.request_event_referee_for_actor(uuid, text, uuid), internal.respond_event_referee_for_actor(uuid, boolean),
  internal.withdraw_event_referee_for_actor(uuid), internal.search_referee_matches_for_actor(text, date, date),
  internal.list_my_referee_people_for_actor(), internal.list_my_referee_assignments_for_actor(),
  api.get_event_referees(uuid), api.set_event_referee_slots(uuid, integer), api.search_referees(text),
  api.propose_event_referee(uuid, text, uuid, text), api.request_event_referee(uuid, text, uuid),
  api.respond_event_referee(uuid, boolean), api.withdraw_event_referee(uuid),
  api.search_referee_matches(text, date, date), api.list_my_referee_people(), api.list_my_referee_assignments()
  from public, anon, authenticated;
grant execute on function
  internal.get_event_referees_for_actor(uuid), internal.set_event_referee_slots_for_actor(uuid, integer),
  internal.search_referees_for_actor(text), internal.propose_event_referee_for_actor(uuid, text, uuid, text),
  internal.request_event_referee_for_actor(uuid, text, uuid), internal.respond_event_referee_for_actor(uuid, boolean),
  internal.withdraw_event_referee_for_actor(uuid), internal.search_referee_matches_for_actor(text, date, date),
  internal.list_my_referee_people_for_actor(), internal.list_my_referee_assignments_for_actor(),
  api.get_event_referees(uuid), api.set_event_referee_slots(uuid, integer), api.search_referees(text),
  api.propose_event_referee(uuid, text, uuid, text), api.request_event_referee(uuid, text, uuid),
  api.respond_event_referee(uuid, boolean), api.withdraw_event_referee(uuid),
  api.search_referee_matches(text, date, date), api.list_my_referee_people(), api.list_my_referee_assignments()
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261108090000_referees', 'greenfield', 'REF-01: referee and referee assigner roles, referees on matches'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261108090000_referees');
notify pgrst, 'reload schema';
