-- POOL-02: watches and cancellation in the match pool.
--
-- Watches: a leader saves what the team looks for (kind, distance from the
-- team's starting point, format, gender, age class, verified clubs only);
-- a new listing that fits notifies the leader who saved the watch, at most
-- ten times per watch and day.
--
-- Cancellation (decided 2026-10-17): a booked match is cancelled only when
-- both teams agree. Either side asks, the other side accepts or declines,
-- and the asking side may take the request back. On acceptance the
-- matches the pool put in the calendars are cancelled (players are told as
-- for any cancelled match), and the listing's team may put the same
-- listing out again. Which team asked and when is kept in a log without
-- message text, for two years.

alter table internal.match_pool_listings drop constraint if exists match_pool_listings_state_check;
alter table internal.match_pool_listings add constraint match_pool_listings_state_check
  check (state in ('open', 'matched', 'withdrawn', 'expired', 'hidden', 'cancelled'));
alter table internal.match_pool_listings add column if not exists republished_listing_id uuid;

alter table internal.match_pool_interests drop constraint if exists match_pool_interests_state_check;
alter table internal.match_pool_interests add constraint match_pool_interests_state_check
  check (state in ('pending', 'accepted', 'declined', 'withdrawn', 'closed', 'cancelled'));
alter table internal.match_pool_interests
  add column if not exists cancel_requested_side text check (cancel_requested_side in ('listing', 'interest')),
  add column if not exists cancel_requested_team_id uuid references core.teams(id),
  add column if not exists cancel_requested_by uuid references core.profiles(id) on delete set null,
  add column if not exists cancel_requested_at timestamptz,
  add column if not exists cancel_reason text check (cancel_reason is null or length(cancel_reason) <= 500),
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancel_accepted_by uuid references core.profiles(id) on delete set null;

create table if not exists internal.match_pool_cancellations (
  id uuid primary key default gen_random_uuid(),
  listing_club_id uuid not null references core.clubs(id),
  listing_team_id uuid not null references core.teams(id),
  interest_club_id uuid not null references core.clubs(id),
  interest_team_id uuid not null references core.teams(id),
  requested_by_team_id uuid not null references core.teams(id),
  match_starts_at timestamptz,
  requested_at timestamptz not null,
  cancelled_at timestamptz not null default now()
);

create table if not exists internal.match_pool_watches (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  team_id uuid not null,
  created_by uuid not null references core.profiles(id) on delete cascade,
  kind text not null default 'all' check (kind in ('all', 'home_slot', 'away_wanted')),
  max_distance_km integer not null check (max_distance_km between 5 and 500),
  match_format text check (match_format in ('3v3', '5v5', '7v7', '8v8', '9v9', '11v11')),
  gender text check (gender in ('boys', 'girls', 'mixed', 'men', 'women')),
  age_class text check (age_class is null or length(btrim(age_class)) between 1 and 40),
  verified_only boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  foreign key (team_id, club_id) references core.teams(id, club_id)
);
create index if not exists match_pool_watches_team_idx on internal.match_pool_watches(team_id);

alter table internal.match_pool_cancellations enable row level security;
alter table internal.match_pool_watches enable row level security;
revoke all on internal.match_pool_cancellations, internal.match_pool_watches from public, anon, authenticated;

-- The listing's dates still lie ahead (whatever its state).
create or replace function internal.match_pool_dates_ahead(listing internal.match_pool_listings)
returns boolean language sql stable set search_path = '' as $$
  select case listing.kind
    when 'home_slot' then listing.starts_at > now()
    else listing.date_to >= (now() at time zone 'Europe/Stockholm')::date end
$$;

create or replace function internal.match_pool_can_republish(listing internal.match_pool_listings)
returns boolean language sql stable set search_path = '' as $$
  select listing.state = 'cancelled' and listing.republished_listing_id is null
    and internal.match_pool_dates_ahead(listing)
$$;

-- As in 20261102090000, with the cancellation.
create or replace function internal.match_pool_interest_json(interest internal.match_pool_interests, my_side text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', interest.id, 'listing_id', interest.listing_id, 'state', interest.state,
    'team_id', interest.team_id, 'team_name', team.name, 'club_name', club.name,
    'verified', club.verification_status = 'official',
    'starts_at', interest.starts_at, 'ends_at', interest.ends_at,
    'venue_name', interest.venue_name, 'venue_surface', interest.venue_surface,
    'add_to_calendar', interest.add_to_calendar,
    'unread', internal.match_pool_unread(interest.id, my_side),
    'last_message', (select left(message.body, 160) from internal.match_pool_messages message
      where message.interest_id = interest.id order by message.created_at desc limit 1),
    'last_activity_at', (select max(message.created_at) from internal.match_pool_messages message
      where message.interest_id = interest.id),
    'cancel_requested_side', interest.cancel_requested_side,
    'cancel_requested_team_name', (select requester.name from core.teams requester
      where requester.id = interest.cancel_requested_team_id),
    'cancel_requested_at', interest.cancel_requested_at,
    'cancel_reason', interest.cancel_reason,
    'cancelled_at', interest.cancelled_at,
    'created_at', interest.created_at)
  from core.teams team join core.clubs club on club.id = team.club_id
  where team.id = interest.team_id
$$;

-- Cancels a match the pool put in a calendar, as a leader who may manage
-- it: the one acting now, otherwise the leader who created it (the same
-- switch of claim as when it was added). A match already cancelled,
-- completed or gone is left alone; a failure does not stop the
-- cancellation of the booking.
create or replace function internal.match_pool_cancel_event(target_event_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype; previous text := current_setting('request.jwt.claim.sub', true); done boolean := false;
begin
  if target_event_id is null then return false; end if;
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or event_row.state not in ('draft', 'scheduled') then return false; end if;
  if not internal.actor_can_manage_event(event_row.id) then
    perform set_config('request.jwt.claim.sub', event_row.created_by::text, true);
  end if;
  begin
    perform internal.transition_event_for_actor(event_row.id, 'cancelled', event_row.revision,
      'Avbokad i matchpoolen', md5('matchpool-cancel:' || event_row.id)::uuid);
    done := true;
  exception when others then
    done := false;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(previous, ''), true);
  return done;
end;$$;

create or replace function internal.request_match_pool_cancellation_for_actor(target_interest_id uuid, reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare my_side text := internal.match_pool_actor_side(target_interest_id); interest internal.match_pool_interests%rowtype;
  listing internal.match_pool_listings%rowtype; my_team uuid; note text := nullif(btrim(coalesce(reason, '')), '');
begin
  if my_side is null then raise insufficient_privilege using message = 'not_found'; end if;
  if length(note) > 500 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  select * into interest from internal.match_pool_interests where id = target_interest_id for update;
  select * into listing from internal.match_pool_listings where id = interest.listing_id;
  if interest.state <> 'accepted' then raise invalid_parameter_value using message = 'not_booked'; end if;
  if interest.cancel_requested_side is not null then raise invalid_parameter_value using message = 'cancellation_pending'; end if;
  my_team := case when my_side = 'listing' then listing.team_id else interest.team_id end;
  update internal.match_pool_interests set cancel_requested_side = my_side, cancel_requested_team_id = my_team,
    cancel_requested_by = auth.uid(), cancel_requested_at = clock_timestamp(), cancel_reason = note,
    updated_at = clock_timestamp()
  where id = interest.id;
  insert into internal.match_pool_messages(interest_id, side, body)
  values (interest.id, 'system', (select name from core.teams where id = my_team) || ' vill avboka matchen'
    || coalesce(': ' || note, '.') || ' Det andra laget behöver godkänna avbokningen.');
  perform internal.notify_match_pool(interest.id, case when my_side = 'listing' then 'interest' else 'listing' end,
    'matchpool.cancellation.requested.v1');
end;$$;

create or replace function internal.withdraw_match_pool_cancellation_for_actor(target_interest_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare my_side text := internal.match_pool_actor_side(target_interest_id); interest internal.match_pool_interests%rowtype;
begin
  if my_side is null then raise insufficient_privilege using message = 'not_found'; end if;
  select * into interest from internal.match_pool_interests where id = target_interest_id for update;
  if interest.state <> 'accepted' or interest.cancel_requested_side is distinct from my_side then return; end if;
  update internal.match_pool_interests set cancel_requested_side = null, cancel_requested_team_id = null,
    cancel_requested_by = null, cancel_requested_at = null, cancel_reason = null, updated_at = clock_timestamp()
  where id = interest.id;
  insert into internal.match_pool_messages(interest_id, side, body)
  values (interest.id, 'system', 'Begäran om avbokning är återtagen. Matchen gäller.');
  perform internal.notify_match_pool(interest.id, case when my_side = 'listing' then 'interest' else 'listing' end,
    'matchpool.cancellation.withdrawn.v1');
end;$$;

create or replace function internal.respond_match_pool_cancellation_for_actor(target_interest_id uuid, accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare my_side text := internal.match_pool_actor_side(target_interest_id); interest internal.match_pool_interests%rowtype;
  listing internal.match_pool_listings%rowtype; requester_side text; listing_cancelled boolean; interest_cancelled boolean;
begin
  if my_side is null then raise insufficient_privilege using message = 'not_found'; end if;
  select * into interest from internal.match_pool_interests where id = target_interest_id for update;
  select * into listing from internal.match_pool_listings where id = interest.listing_id for update;
  if interest.state = 'cancelled' and accept then return jsonb_build_object('cancelled', true); end if;
  if interest.state <> 'accepted' or interest.cancel_requested_side is null then
    raise invalid_parameter_value using message = 'no_cancellation';
  end if;
  -- The side that asked cannot also answer.
  if interest.cancel_requested_side = my_side then raise insufficient_privilege using message = 'not_found'; end if;
  requester_side := interest.cancel_requested_side;
  if not coalesce(accept, false) then
    update internal.match_pool_interests set cancel_requested_side = null, cancel_requested_team_id = null,
      cancel_requested_by = null, cancel_requested_at = null, cancel_reason = null, updated_at = clock_timestamp()
    where id = interest.id;
    insert into internal.match_pool_messages(interest_id, side, body)
    values (interest.id, 'system', 'Avbokningen godkändes inte. Matchen gäller.');
    perform internal.notify_match_pool(interest.id, requester_side, 'matchpool.cancellation.declined.v1');
    return jsonb_build_object('cancelled', false);
  end if;
  insert into internal.match_pool_cancellations(listing_club_id, listing_team_id, interest_club_id, interest_team_id,
    requested_by_team_id, match_starts_at, requested_at)
  values (listing.club_id, listing.team_id, interest.club_id, interest.team_id, interest.cancel_requested_team_id,
    coalesce(listing.starts_at, interest.starts_at), interest.cancel_requested_at);
  update internal.match_pool_interests set state = 'cancelled', cancelled_at = clock_timestamp(),
    cancel_accepted_by = auth.uid(), updated_at = clock_timestamp()
  where id = interest.id;
  update internal.match_pool_listings set state = 'cancelled', updated_at = clock_timestamp() where id = listing.id;
  listing_cancelled := internal.match_pool_cancel_event(interest.listing_event_id);
  interest_cancelled := internal.match_pool_cancel_event(interest.interest_event_id);
  insert into internal.match_pool_messages(interest_id, side, body)
  values (interest.id, 'system', 'Matchen är avbokad på begäran av '
    || (select name from core.teams where id = interest.cancel_requested_team_id) || '.');
  perform internal.notify_match_pool(interest.id, requester_side, 'matchpool.cancellation.accepted.v1');
  return jsonb_build_object('cancelled', true, 'listing_event_cancelled', listing_cancelled,
    'interest_event_cancelled', interest_cancelled);
end;$$;

-- Watches: what a new listing is checked against.
create or replace function internal.notify_match_pool_watches(target_listing_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare listing internal.match_pool_listings%rowtype; added integer;
begin
  select * into listing from internal.match_pool_listings where id = target_listing_id;
  if listing.id is null or not internal.match_pool_listing_current(listing) then return 0; end if;
  insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select watch.club_id, gen_random_uuid(), 'matchpool.watch.matched.v1', 'match_pool', listing.id,
    watch.created_by, link.club_person_id,
    jsonb_build_object('listing_id', listing.id, 'team_id', watch.team_id, 'watch_id', watch.id)
  from internal.match_pool_watches watch
  join internal.match_pool_bases base on base.team_id = watch.team_id
  join core.teams team on team.id = watch.team_id and team.status = 'active'
  join core.clubs listing_club on listing_club.id = listing.club_id
  join lateral (select l.club_person_id from core.person_account_links l
    where l.profile_id = watch.created_by and l.club_id = watch.club_id and l.state = 'active'
    order by l.club_person_id limit 1) link on true
  where watch.team_id <> listing.team_id
    and (watch.kind = 'all' or watch.kind = listing.kind)
    and (watch.match_format is null or watch.match_format = listing.match_format)
    and (watch.gender is null or watch.gender = listing.gender)
    and (watch.age_class is null or strpos(lower(listing.age_class), lower(btrim(watch.age_class))) > 0)
    and (not watch.verified_only or listing_club.verification_status = 'official')
    and internal.km_between(base.latitude, base.longitude, listing.latitude, listing.longitude)
      <= case when listing.kind = 'away_wanted' then least(watch.max_distance_km, listing.max_distance_km)
         else watch.max_distance_km end
    and (select count(*) from internal.notification_outbox sent
      where sent.event_type = 'matchpool.watch.matched.v1' and sent.payload_ref->>'watch_id' = watch.id::text
        and sent.created_at > now() - interval '1 day') < 10
  on conflict do nothing;
  get diagnostics added = row_count;
  return added;
end;$$;

create or replace function internal.create_match_pool_watch_for_actor(target_team_id uuid, watch jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target_club uuid; new_id uuid;
begin
  if not internal.actor_pool_team(target_team_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if not exists (select 1 from internal.match_pool_bases where team_id = target_team_id) then
    raise invalid_parameter_value using message = 'no_base';
  end if;
  if (select count(*) from internal.match_pool_watches where team_id = target_team_id) >= 5 then
    raise insufficient_privilege using message = 'rate_limited';
  end if;
  if watch is null or jsonb_typeof(watch) <> 'object' then raise invalid_parameter_value using message = 'invalid_input'; end if;
  select club_id into target_club from core.teams where id = target_team_id;
  begin
    insert into internal.match_pool_watches(club_id, team_id, created_by, kind, max_distance_km, match_format, gender,
      age_class, verified_only)
    values (target_club, target_team_id, auth.uid(), coalesce(nullif(watch->>'kind', ''), 'all'),
      (watch->>'max_distance_km')::integer, nullif(watch->>'match_format', ''), nullif(watch->>'gender', ''),
      nullif(btrim(watch->>'age_class'), ''), coalesce((watch->>'verified_only')::boolean, false))
    returning id into new_id;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise invalid_parameter_value using message = 'invalid_input';
  end;
  return new_id;
end;$$;

create or replace function internal.delete_match_pool_watch_for_actor(target_watch_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare watch internal.match_pool_watches%rowtype;
begin
  select * into watch from internal.match_pool_watches where id = target_watch_id;
  if watch.id is null or not internal.actor_pool_team(watch.team_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  delete from internal.match_pool_watches where id = watch.id;
end;$$;

create or replace function internal.list_match_pool_watches_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', watch.id, 'team_id', watch.team_id, 'team_name', team.name,
      'kind', watch.kind, 'max_distance_km', watch.max_distance_km, 'match_format', watch.match_format,
      'gender', watch.gender, 'age_class', watch.age_class, 'verified_only', watch.verified_only,
      'mine', watch.created_by = auth.uid(), 'created_at', watch.created_at) order by team.name, watch.created_at), '[]'::jsonb)
  from internal.match_pool_watches watch join core.teams team on team.id = watch.team_id
  where watch.team_id in (select t.team_id from internal.actor_pool_teams() t)
$$;

-- One listing, for the app when a watch notification is opened.
create or replace function internal.get_match_pool_listing_for_actor(target_listing_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare listing internal.match_pool_listings%rowtype;
begin
  if not exists (select 1 from internal.actor_pool_teams()) then raise insufficient_privilege using message = 'not_leader'; end if;
  select * into listing from internal.match_pool_listings where id = target_listing_id;
  if listing.id is null or listing.state = 'hidden' then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.match_pool_listing_json(listing, null, null, false)
    || jsonb_build_object('current', internal.match_pool_listing_current(listing),
      'own', listing.team_id in (select t.team_id from internal.actor_pool_teams() t),
      'my_interest', (select jsonb_build_object('id', interest.id, 'state', interest.state)
        from internal.match_pool_interests interest where interest.listing_id = listing.id
          and interest.team_id in (select t.team_id from internal.actor_pool_teams() t)
        order by interest.created_at desc limit 1));
end;$$;

-- The listing's team puts a cancelled listing out again, as it was.
create or replace function internal.republish_match_pool_listing_for_actor(target_listing_id uuid, idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare listing internal.match_pool_listings%rowtype; new_id uuid;
begin
  select * into listing from internal.match_pool_listings where id = target_listing_id for update;
  if listing.id is null or not internal.actor_pool_team(listing.team_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if listing.republished_listing_id is not null then return listing.republished_listing_id; end if;
  if not internal.match_pool_can_republish(listing) then raise invalid_parameter_value using message = 'cannot_republish'; end if;
  insert into internal.match_pool_listings(club_id, team_id, created_by, kind, starts_at, ends_at, date_from, date_to,
    max_distance_km, place_label, latitude, longitude, venue_name, venue_surface, match_format, age_class, gender,
    level, note, idempotency_key)
  values (listing.club_id, listing.team_id, auth.uid(), listing.kind, listing.starts_at, listing.ends_at,
    -- greatest() skips nulls: only a range starts at today at the earliest.
    case when listing.kind = 'away_wanted'
      then greatest(listing.date_from, (now() at time zone 'Europe/Stockholm')::date) end, listing.date_to,
    listing.max_distance_km, listing.place_label, listing.latitude, listing.longitude, listing.venue_name,
    listing.venue_surface, listing.match_format, listing.age_class, listing.gender, listing.level, listing.note,
    republish_match_pool_listing_for_actor.idempotency_key)
  returning id into new_id;
  update internal.match_pool_listings set republished_listing_id = new_id, updated_at = clock_timestamp()
  where id = listing.id;
  perform internal.notify_match_pool_watches(new_id);
  return new_id;
end;$$;

-- As in 20261102090000; a new listing is checked against the watches.
create or replace function internal.create_match_pool_listing_for_actor(target_team_id uuid, listing jsonb,
  idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); target_club uuid; new_id uuid; new_kind text := listing->>'kind';
  today date := (now() at time zone 'Europe/Stockholm')::date;
  new_starts timestamptz; new_ends timestamptz; new_from date; new_to date;
begin
  if not internal.actor_pool_team(target_team_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if idempotency_key is null or listing is null or jsonb_typeof(listing) <> 'object' then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select id into new_id from internal.match_pool_listings existing
  where existing.created_by = actor_id and existing.idempotency_key = create_match_pool_listing_for_actor.idempotency_key;
  if new_id is not null then return new_id; end if;
  if (select count(*) from internal.match_pool_listings existing where existing.team_id = target_team_id
      and internal.match_pool_listing_current(existing)) >= 10
    or (select count(*) from internal.match_pool_listings existing where existing.created_by = actor_id
      and existing.created_at > now() - interval '1 day') >= 20 then
    raise insufficient_privilege using message = 'rate_limited';
  end if;
  begin
    if new_kind = 'home_slot' then
      new_starts := (listing->>'starts_at')::timestamptz; new_ends := (listing->>'ends_at')::timestamptz;
      if new_starts is null or new_starts <= now() or new_starts > now() + interval '365 days'
        or new_ends - new_starts not between interval '30 minutes' and interval '6 hours'
        or nullif(btrim(listing->>'venue_name'), '') is null then
        raise invalid_parameter_value using message = 'invalid_input';
      end if;
    elsif new_kind = 'away_wanted' then
      new_from := (listing->>'date_from')::date; new_to := (listing->>'date_to')::date;
      if new_from is null or new_to is null or new_from < today or new_to < new_from
        or new_to > today + 365 or new_to - new_from > 60
        or (listing->>'max_distance_km')::integer not between 5 and 500 then
        raise invalid_parameter_value using message = 'invalid_input';
      end if;
    else
      raise invalid_parameter_value using message = 'invalid_input';
    end if;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow
    or numeric_value_out_of_range then
    raise invalid_parameter_value using message = 'invalid_input';
  end;
  select club_id into target_club from core.teams where id = target_team_id;
  begin
    insert into internal.match_pool_listings(club_id, team_id, created_by, kind, starts_at, ends_at, date_from, date_to,
      max_distance_km, place_label, latitude, longitude, venue_name, venue_surface, match_format, age_class, gender,
      level, note, idempotency_key)
    values (target_club, target_team_id, actor_id, new_kind, new_starts, new_ends, new_from, new_to,
      case when new_kind = 'away_wanted' then (listing->>'max_distance_km')::integer end,
      btrim(listing->>'place_label'), round((listing->>'latitude')::numeric, 2), round((listing->>'longitude')::numeric, 2),
      case when new_kind = 'home_slot' then btrim(listing->>'venue_name') end,
      nullif(listing->>'venue_surface', ''), listing->>'match_format', btrim(listing->>'age_class'),
      listing->>'gender', nullif(listing->>'level', ''), nullif(btrim(listing->>'note'), ''),
      create_match_pool_listing_for_actor.idempotency_key)
    returning id into new_id;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise invalid_parameter_value using message = 'invalid_input';
  end;
  perform internal.notify_match_pool_watches(new_id);
  return new_id;
end;$$;

-- As in 20261103090000: watch notifications open the listing.
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
    when outbox.event_type like 'callup.%'
      and outbox.payload_ref->>'event_id'~'^[0-9a-fA-F-]{36}$'
      then '/calendar/event/'||(outbox.payload_ref->>'event_id')
    when outbox.aggregate_type='event'
      then '/calendar/event/'||outbox.aggregate_id::text
    else '/inbox'
  end;
$$;

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
  when event_type like 'callup.%.cancelled.%' then 'Kallelse återkallad'
  when event_type like 'callup.%.reminded.%' then 'Påminnelse om kallelse'
  when event_type like 'callup.%' then 'Ny kallelse'
  when event_type like 'event.%' then 'Kalendern har uppdaterats'
  else 'Ny aktivitet i TeamZone' end
$$;

-- Daily: as in 20261102090000, and the cancellation log is kept two years.
create or replace function internal.apply_match_pool_retention()
returns integer language plpgsql security definer set search_path = '' as $$
declare removed integer;
begin
  update internal.match_pool_interests interest set state = 'closed', updated_at = clock_timestamp()
  from internal.match_pool_listings listing
  where listing.id = interest.listing_id and interest.state = 'pending' and listing.state = 'open'
    and not internal.match_pool_listing_current(listing);
  update internal.match_pool_listings listing set state = 'expired', updated_at = clock_timestamp()
  where listing.state = 'open' and not internal.match_pool_listing_current(listing);
  delete from internal.match_pool_listings listing
  where listing.state <> 'open' and listing.updated_at < now() - interval '30 days'
    and not exists (select 1 from internal.match_pool_interests interest
      where interest.listing_id = listing.id and interest.updated_at >= now() - interval '30 days');
  get diagnostics removed = row_count;
  delete from internal.match_pool_cancellations where cancelled_at < now() - interval '2 years';
  return removed;
end;$$;

-- As in 20261102090000, with cancelled listings, republishing and watches.
create or replace function internal.get_match_pool_for_actor(origin_team_id uuid, max_km integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare base internal.match_pool_bases%rowtype; distance_limit integer := least(greatest(coalesce(max_km, 100), 5), 1000);
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not exists (select 1 from internal.actor_pool_teams()) then
    raise insufficient_privilege using message = 'not_leader';
  end if;
  if origin_team_id is not null then
    if not internal.actor_pool_team(origin_team_id) then raise insufficient_privilege using message = 'not_found'; end if;
    select * into base from internal.match_pool_bases where team_id = origin_team_id;
  end if;
  return jsonb_build_object(
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
        'team_id', team.id, 'team_name', team.name, 'club_name', club.name,
        'verified', club.verification_status = 'official', 'age_class', profile.age_class,
        'base', case when stored.team_id is null then null else jsonb_build_object(
          'place_label', stored.place_label, 'latitude', stored.latitude, 'longitude', stored.longitude) end)
        order by club.name, team.name)
      from internal.actor_pool_teams() mine
      join core.teams team on team.id = mine.team_id
      join core.clubs club on club.id = team.club_id
      left join core.team_profiles profile on profile.team_id = team.id
      left join internal.match_pool_bases stored on stored.team_id = team.id), '[]'::jsonb),
    'origin', case when base.team_id is null then null else jsonb_build_object(
      'team_id', base.team_id, 'place_label', base.place_label) end,
    'listings', coalesce((select jsonb_agg(item order by sort_key) from (
        select internal.match_pool_listing_json(listing, base.latitude, base.longitude, false)
            || jsonb_build_object('my_interest', (select jsonb_build_object('id', interest.id, 'state', interest.state)
              from internal.match_pool_interests interest
              where interest.listing_id = listing.id
                and interest.team_id in (select t.team_id from internal.actor_pool_teams() t)
              order by interest.created_at desc limit 1)) as item,
          coalesce(listing.starts_at, listing.date_from::timestamptz) as sort_key
        from internal.match_pool_listings listing
        join core.clubs club on club.id = listing.club_id and club.status = 'active'
        where internal.match_pool_listing_current(listing)
          and listing.team_id not in (select t.team_id from internal.actor_pool_teams() t)
          and (base.team_id is null or internal.km_between(base.latitude, base.longitude,
            listing.latitude, listing.longitude) <= case when listing.kind = 'away_wanted'
              then least(distance_limit, listing.max_distance_km) else distance_limit end)
        order by sort_key limit 300) rows), '[]'::jsonb),
    'mine', coalesce((select jsonb_agg(internal.match_pool_listing_json(listing, null, null, true)
        || jsonb_build_object('current', internal.match_pool_listing_current(listing),
          'can_republish', internal.match_pool_can_republish(listing),
          'interests', coalesce((select jsonb_agg(internal.match_pool_interest_json(interest, 'listing')
            order by interest.created_at) from internal.match_pool_interests interest
            where interest.listing_id = listing.id and interest.state <> 'withdrawn'), '[]'::jsonb))
        order by listing.created_at desc)
      from internal.match_pool_listings listing
      where listing.team_id in (select t.team_id from internal.actor_pool_teams() t)
        and listing.state in ('open', 'matched', 'hidden', 'cancelled')
        and listing.updated_at > now() - interval '30 days'), '[]'::jsonb),
    'sent', coalesce((select jsonb_agg(internal.match_pool_interest_json(interest, 'interest')
        || jsonb_build_object('listing', internal.match_pool_listing_json(listing, null, null,
          interest.state = 'accepted')) order by interest.created_at desc)
      from internal.match_pool_interests interest
      join internal.match_pool_listings listing on listing.id = interest.listing_id
      where interest.team_id in (select t.team_id from internal.actor_pool_teams() t)
        and interest.state <> 'withdrawn'
        and interest.updated_at > now() - interval '30 days'), '[]'::jsonb),
    'watches', internal.list_match_pool_watches_for_actor());
end;$$;

-- As in 20261102090000, with republishing.
create or replace function internal.get_match_pool_conversation_for_actor(target_interest_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare my_side text := internal.match_pool_actor_side(target_interest_id);
  interest internal.match_pool_interests%rowtype; listing internal.match_pool_listings%rowtype; result jsonb;
begin
  if my_side is null then raise insufficient_privilege using message = 'not_found'; end if;
  select * into interest from internal.match_pool_interests where id = target_interest_id;
  select * into listing from internal.match_pool_listings where id = interest.listing_id;
  result := jsonb_build_object(
    'my_side', my_side,
    -- The draft this side's calendar got when the match was booked.
    'my_event_id', case when my_side = 'listing' then interest.listing_event_id else interest.interest_event_id end,
    'listing', internal.match_pool_listing_json(listing, null, null, my_side = 'listing' or interest.state = 'accepted')
      || jsonb_build_object('current', internal.match_pool_listing_current(listing),
        'can_republish', my_side = 'listing' and internal.match_pool_can_republish(listing),
        'republished', listing.republished_listing_id is not null),
    'interest', internal.match_pool_interest_json(interest, my_side),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', message.id, 'side', message.side,
        'body', message.body, 'created_at', message.created_at,
        'author_name', nullif(btrim(profile.display_name), '')) order by message.created_at)
      from internal.match_pool_messages message
      left join core.profiles profile on profile.id = message.author_profile_id
      where message.interest_id = interest.id), '[]'::jsonb));
  insert into internal.match_pool_reads(interest_id, profile_id) values (interest.id, auth.uid())
  on conflict (interest_id, profile_id) do update set read_at = clock_timestamp();
  return result;
end;$$;

-- As in 20261102090000, with watches and cancellation.
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

create or replace function api.request_match_pool_cancellation(target_interest_id uuid, reason text default null)
returns void language sql security invoker set search_path = '' as
$$select internal.request_match_pool_cancellation_for_actor(target_interest_id, reason)$$;
create or replace function api.withdraw_match_pool_cancellation(target_interest_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.withdraw_match_pool_cancellation_for_actor(target_interest_id)$$;
create or replace function api.respond_match_pool_cancellation(target_interest_id uuid, accept boolean)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.respond_match_pool_cancellation_for_actor(target_interest_id, accept)$$;
create or replace function api.republish_match_pool_listing(target_listing_id uuid, idempotency_key uuid)
returns uuid language sql security invoker set search_path = '' as
$$select internal.republish_match_pool_listing_for_actor(target_listing_id, idempotency_key)$$;
create or replace function api.create_match_pool_watch(target_team_id uuid, watch jsonb)
returns uuid language sql security invoker set search_path = '' as
$$select internal.create_match_pool_watch_for_actor(target_team_id, watch)$$;
create or replace function api.delete_match_pool_watch(target_watch_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.delete_match_pool_watch_for_actor(target_watch_id)$$;
create or replace function api.list_match_pool_watches()
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_match_pool_watches_for_actor()$$;
create or replace function api.get_match_pool_listing(target_listing_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_match_pool_listing_for_actor(target_listing_id)$$;

revoke all on function internal.match_pool_dates_ahead(internal.match_pool_listings),
  internal.match_pool_can_republish(internal.match_pool_listings), internal.match_pool_cancel_event(uuid),
  internal.notify_match_pool_watches(uuid),
  internal.request_match_pool_cancellation_for_actor(uuid, text), internal.withdraw_match_pool_cancellation_for_actor(uuid),
  internal.respond_match_pool_cancellation_for_actor(uuid, boolean), internal.republish_match_pool_listing_for_actor(uuid, uuid),
  internal.create_match_pool_watch_for_actor(uuid, jsonb), internal.delete_match_pool_watch_for_actor(uuid),
  internal.list_match_pool_watches_for_actor(), internal.get_match_pool_listing_for_actor(uuid),
  api.request_match_pool_cancellation(uuid, text), api.withdraw_match_pool_cancellation(uuid),
  api.respond_match_pool_cancellation(uuid, boolean), api.republish_match_pool_listing(uuid, uuid),
  api.create_match_pool_watch(uuid, jsonb), api.delete_match_pool_watch(uuid), api.list_match_pool_watches(),
  api.get_match_pool_listing(uuid)
  from public, anon, authenticated;
grant execute on function
  internal.request_match_pool_cancellation_for_actor(uuid, text), internal.withdraw_match_pool_cancellation_for_actor(uuid),
  internal.respond_match_pool_cancellation_for_actor(uuid, boolean), internal.republish_match_pool_listing_for_actor(uuid, uuid),
  internal.create_match_pool_watch_for_actor(uuid, jsonb), internal.delete_match_pool_watch_for_actor(uuid),
  internal.list_match_pool_watches_for_actor(), internal.get_match_pool_listing_for_actor(uuid),
  api.request_match_pool_cancellation(uuid, text), api.withdraw_match_pool_cancellation(uuid),
  api.respond_match_pool_cancellation(uuid, boolean), api.republish_match_pool_listing(uuid, uuid),
  api.create_match_pool_watch(uuid, jsonb), api.delete_match_pool_watch(uuid), api.list_match_pool_watches(),
  api.get_match_pool_listing(uuid)
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261104090000_match_pool_watches_cancellation', 'greenfield',
  'POOL-02: match pool watches, cancellation by agreement and republishing'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261104090000_match_pool_watches_cancellation');
notify pgrst, 'reload schema';
