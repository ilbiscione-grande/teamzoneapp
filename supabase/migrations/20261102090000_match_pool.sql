-- POOL-01: matchpoolen. Leaders (event.manage on a team) post friendly-match
-- listings ("har hemmatid" or "söker bortamatch"), other teams' leaders show
-- interest, and the two sides talk in a thread. When the listing's leader
-- accepts, the listing is matched, the other interested teams are told, and
-- the match is added to both teams' calendars as a draft, unless that side's
-- leader chose not to. Every listing shows whether the club is officially
-- verified. Positions are stored rounded to about a kilometre; the venue is
-- shown to the other side only once the match is booked. Nothing here is
-- public: everything goes through api.* for authenticated leaders.

create table if not exists internal.match_pool_bases (
  team_id uuid primary key references core.teams(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  place_label text not null check (length(btrim(place_label)) between 1 and 120),
  latitude numeric(5,2) not null check (latitude between -90 and 90),
  longitude numeric(5,2) not null check (longitude between -180 and 180),
  updated_by uuid not null references core.profiles(id),
  updated_at timestamptz not null default now()
);

create table if not exists internal.match_pool_listings (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  team_id uuid not null,
  created_by uuid not null references core.profiles(id),
  kind text not null check (kind in ('home_slot', 'away_wanted')),
  starts_at timestamptz,
  ends_at timestamptz,
  date_from date,
  date_to date,
  max_distance_km integer check (max_distance_km between 5 and 500),
  place_label text not null check (length(btrim(place_label)) between 1 and 120),
  latitude numeric(5,2) not null check (latitude between -90 and 90),
  longitude numeric(5,2) not null check (longitude between -180 and 180),
  venue_name text check (venue_name is null or length(btrim(venue_name)) between 1 and 160),
  venue_surface text check (venue_surface in ('grass', 'artificial', 'indoor', 'other')),
  match_format text not null check (match_format in ('3v3', '5v5', '7v7', '8v8', '9v9', '11v11')),
  age_class text not null check (length(btrim(age_class)) between 1 and 40),
  gender text not null check (gender in ('boys', 'girls', 'mixed', 'men', 'women')),
  level text check (level in ('beginner', 'intermediate', 'advanced')),
  note text check (note is null or length(note) <= 500),
  state text not null default 'open' check (state in ('open', 'matched', 'withdrawn', 'expired', 'hidden')),
  matched_interest_id uuid,
  idempotency_key uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (team_id, club_id) references core.teams(id, club_id),
  unique (created_by, idempotency_key),
  check (
    (kind = 'home_slot' and starts_at is not null and ends_at > starts_at and venue_name is not null
      and date_from is null and date_to is null and max_distance_km is null)
    or (kind = 'away_wanted' and starts_at is null and ends_at is null and venue_name is null
      and date_from is not null and date_to >= date_from and max_distance_km is not null)
  )
);
create index if not exists match_pool_listings_open_idx on internal.match_pool_listings(state, created_at);
create index if not exists match_pool_listings_team_idx on internal.match_pool_listings(team_id, state);

create table if not exists internal.match_pool_interests (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references internal.match_pool_listings(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  team_id uuid not null,
  created_by uuid not null references core.profiles(id),
  -- For a "söker bortamatch" listing the interested team hosts: its time and place.
  starts_at timestamptz,
  ends_at timestamptz,
  venue_name text check (venue_name is null or length(btrim(venue_name)) between 1 and 160),
  venue_surface text check (venue_surface in ('grass', 'artificial', 'indoor', 'other')),
  add_to_calendar boolean not null default true,
  state text not null default 'pending' check (state in ('pending', 'accepted', 'declined', 'withdrawn', 'closed')),
  listing_event_id uuid,
  interest_event_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (team_id, club_id) references core.teams(id, club_id),
  unique (listing_id, team_id),
  check ((starts_at is null) = (ends_at is null) and (ends_at is null or ends_at > starts_at))
);
create index if not exists match_pool_interests_team_idx on internal.match_pool_interests(team_id, state);

create table if not exists internal.match_pool_messages (
  id uuid primary key default gen_random_uuid(),
  interest_id uuid not null references internal.match_pool_interests(id) on delete cascade,
  author_profile_id uuid references core.profiles(id) on delete set null,
  side text not null check (side in ('listing', 'interest', 'system')),
  body text not null check (length(btrim(body)) between 1 and 2000),
  idempotency_key uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique (author_profile_id, idempotency_key)
);
create index if not exists match_pool_messages_thread_idx on internal.match_pool_messages(interest_id, created_at);

create table if not exists internal.match_pool_reads (
  interest_id uuid not null references internal.match_pool_interests(id) on delete cascade,
  profile_id uuid not null references core.profiles(id) on delete cascade,
  read_at timestamptz not null default clock_timestamp(),
  primary key (interest_id, profile_id)
);

create table if not exists internal.match_pool_reports (
  listing_id uuid not null references internal.match_pool_listings(id) on delete cascade,
  reporter_club_id uuid not null references core.clubs(id),
  reporter_profile_id uuid not null references core.profiles(id),
  reason text not null check (length(btrim(reason)) between 1 and 500),
  created_at timestamptz not null default now(),
  primary key (listing_id, reporter_club_id)
);

alter table internal.match_pool_bases enable row level security;
alter table internal.match_pool_listings enable row level security;
alter table internal.match_pool_interests enable row level security;
alter table internal.match_pool_messages enable row level security;
alter table internal.match_pool_reads enable row level security;
alter table internal.match_pool_reports enable row level security;
revoke all on internal.match_pool_bases, internal.match_pool_listings, internal.match_pool_interests,
  internal.match_pool_messages, internal.match_pool_reads, internal.match_pool_reports
  from public, anon, authenticated;

-- The teams the signed-in leader may act for in the pool.
create or replace function internal.actor_pool_teams()
returns table(team_id uuid, club_id uuid) language sql stable security definer set search_path = '' as $$
  select team.id, team.club_id
  from core.teams team
  join core.clubs club on club.id = team.club_id and club.status = 'active'
  where team.status = 'active'
    and team.club_id in (select link.club_id from core.person_account_links link
      where link.profile_id = auth.uid() and link.state = 'active')
    and internal.actor_has_capability(team.club_id, team.id, 'event.manage')
$$;

create or replace function internal.actor_pool_team(target_team_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from internal.actor_pool_teams() t where t.team_id = target_team_id)
$$;

-- Great-circle distance in km.
create or replace function internal.km_between(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric)
returns integer language sql immutable set search_path = '' as $$
  select round(6371 * 2 * asin(least(1, sqrt(
    power(sin(radians((lat2 - lat1)::double precision) / 2), 2)
    + cos(radians(lat1::double precision)) * cos(radians(lat2::double precision))
      * power(sin(radians((lon2 - lon1)::double precision) / 2), 2)))))::integer
$$;

-- Who hears about a team's pool activity: its event managers, or the club's
-- event managers when the team has none.
create or replace function internal.match_pool_recipients(target_club_id uuid, target_team_id uuid)
returns table(profile_id uuid, club_person_id uuid) language sql stable security definer set search_path = '' as $$
  with holders as (
    select distinct link.profile_id, link.club_person_id, grant_row.scope_type
    from core.person_account_links link
    join core.assignments assignment on assignment.club_person_id = link.club_person_id
      and assignment.club_id = link.club_id
    join core.capability_grants grant_row on grant_row.assignment_id = assignment.id
      and grant_row.club_id = assignment.club_id
    where link.club_id = target_club_id and link.state = 'active'
      and assignment.state = 'active' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
      and grant_row.capability = 'event.manage'
      and ((grant_row.scope_type = 'team' and grant_row.scope_id = target_team_id)
        or (grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id))
  ), team_managers as (
    select distinct on (h.profile_id) h.profile_id, h.club_person_id from holders h
    where h.scope_type = 'team' order by h.profile_id, h.club_person_id
  ), club_managers as (
    select distinct on (h.profile_id) h.profile_id, h.club_person_id from holders h
    where h.scope_type = 'club' order by h.profile_id, h.club_person_id
  )
  select profile_id, club_person_id from team_managers
  union all
  select profile_id, club_person_id from club_managers where not exists (select 1 from team_managers)
$$;

create or replace function internal.notify_match_pool(target_interest_id uuid, target_side text, new_event_type text)
returns integer language plpgsql security definer set search_path = '' as $$
declare interest internal.match_pool_interests%rowtype; listing internal.match_pool_listings%rowtype;
  target_club uuid; target_team uuid; added integer;
begin
  select * into interest from internal.match_pool_interests where id = target_interest_id;
  select * into listing from internal.match_pool_listings where id = interest.listing_id;
  if interest.id is null then return 0; end if;
  if target_side = 'listing' then target_club := listing.club_id; target_team := listing.team_id;
  else target_club := interest.club_id; target_team := interest.team_id; end if;
  insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select target_club, gen_random_uuid(), new_event_type, 'match_pool', interest.id,
    recipient.profile_id, recipient.club_person_id,
    jsonb_build_object('interest_id', interest.id, 'team_id', target_team)
  from internal.match_pool_recipients(target_club, target_team) recipient
  -- The one who acted is not told about their own action.
  where recipient.profile_id is distinct from auth.uid()
  on conflict do nothing;
  get diagnostics added = row_count;
  return added;
end;$$;

create or replace function internal.match_pool_surface_label(surface text)
returns text language sql immutable set search_path = '' as $$
  select case surface when 'grass' then 'Gräs' when 'artificial' then 'Konstgräs'
    when 'indoor' then 'Inomhus' when 'other' then 'Annat' end
$$;

create or replace function internal.match_pool_team_label(target_team_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select team.name || ' · ' || club.name from core.teams team join core.clubs club on club.id = team.club_id
  where team.id = target_team_id
$$;

-- An open listing whose date has passed is expired (also done daily).
create or replace function internal.match_pool_listing_current(listing internal.match_pool_listings)
returns boolean language sql stable set search_path = '' as $$
  select listing.state = 'open' and case listing.kind
    when 'home_slot' then listing.starts_at > now()
    else listing.date_to >= (now() at time zone 'Europe/Stockholm')::date end
$$;

create or replace function internal.match_pool_listing_json(listing internal.match_pool_listings, origin_lat numeric,
  origin_lon numeric, with_venue boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', listing.id, 'kind', listing.kind, 'state', listing.state,
    'team_id', listing.team_id, 'team_name', team.name, 'club_name', club.name,
    'verified', club.verification_status = 'official',
    'starts_at', listing.starts_at, 'ends_at', listing.ends_at,
    'date_from', listing.date_from, 'date_to', listing.date_to,
    'max_distance_km', listing.max_distance_km, 'place_label', listing.place_label,
    'distance_km', case when origin_lat is null then null
      else internal.km_between(origin_lat, origin_lon, listing.latitude, listing.longitude) end,
    'venue_name', case when with_venue then listing.venue_name end,
    'venue_surface', listing.venue_surface, 'match_format', listing.match_format,
    'age_class', listing.age_class, 'gender', listing.gender, 'level', listing.level,
    'note', listing.note, 'created_at', listing.created_at)
  from core.teams team join core.clubs club on club.id = team.club_id
  where team.id = listing.team_id
$$;

create or replace function internal.match_pool_unread(target_interest_id uuid, my_side text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from internal.match_pool_messages message
    where message.interest_id = target_interest_id and message.side <> my_side
      and message.created_at > coalesce((select read.read_at from internal.match_pool_reads read
        where read.interest_id = target_interest_id and read.profile_id = auth.uid()), '-infinity'))
$$;

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
    'created_at', interest.created_at)
  from core.teams team join core.clubs club on club.id = team.club_id
  where team.id = interest.team_id
$$;

-- The whole page: the leader's teams, open listings from other teams (with
-- distance from the chosen team's starting point), own listings with their
-- interests and the interests the leader's teams have sent.
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
          'interests', coalesce((select jsonb_agg(internal.match_pool_interest_json(interest, 'listing')
            order by interest.created_at) from internal.match_pool_interests interest
            where interest.listing_id = listing.id and interest.state <> 'withdrawn'), '[]'::jsonb))
        order by listing.created_at desc)
      from internal.match_pool_listings listing
      where listing.team_id in (select t.team_id from internal.actor_pool_teams() t)
        and listing.state in ('open', 'matched', 'hidden')
        and listing.updated_at > now() - interval '30 days'), '[]'::jsonb),
    'sent', coalesce((select jsonb_agg(internal.match_pool_interest_json(interest, 'interest')
        || jsonb_build_object('listing', internal.match_pool_listing_json(listing, null, null,
          interest.state = 'accepted')) order by interest.created_at desc)
      from internal.match_pool_interests interest
      join internal.match_pool_listings listing on listing.id = interest.listing_id
      where interest.team_id in (select t.team_id from internal.actor_pool_teams() t)
        and interest.state <> 'withdrawn'
        and interest.updated_at > now() - interval '30 days'), '[]'::jsonb));
end;$$;

create or replace function internal.save_match_pool_base_for_actor(target_team_id uuid, new_place_label text,
  new_latitude numeric, new_longitude numeric)
returns void language plpgsql security definer set search_path = '' as $$
declare target_club uuid;
begin
  if not internal.actor_pool_team(target_team_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if length(btrim(coalesce(new_place_label, ''))) not between 1 and 120 or new_latitude not between -90 and 90
    or new_longitude not between -180 and 180 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select club_id into target_club from core.teams where id = target_team_id;
  insert into internal.match_pool_bases(team_id, club_id, place_label, latitude, longitude, updated_by)
  values (target_team_id, target_club, btrim(new_place_label), round(new_latitude, 2), round(new_longitude, 2), auth.uid())
  on conflict (team_id) do update set place_label = excluded.place_label, latitude = excluded.latitude,
    longitude = excluded.longitude, updated_by = excluded.updated_by, updated_at = now();
end;$$;

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
  return new_id;
end;$$;

create or replace function internal.withdraw_match_pool_listing_for_actor(target_listing_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare listing internal.match_pool_listings%rowtype; waiting uuid;
begin
  select * into listing from internal.match_pool_listings where id = target_listing_id for update;
  if listing.id is null or not internal.actor_pool_team(listing.team_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if listing.state <> 'open' then return; end if;
  update internal.match_pool_listings set state = 'withdrawn', updated_at = clock_timestamp() where id = listing.id;
  for waiting in select id from internal.match_pool_interests where listing_id = listing.id and state = 'pending' loop
    update internal.match_pool_interests set state = 'closed', updated_at = clock_timestamp() where id = waiting;
    insert into internal.match_pool_messages(interest_id, side, body)
    values (waiting, 'system', 'Annonsen är borttagen av laget som lade in den.');
    perform internal.notify_match_pool(waiting, 'interest', 'matchpool.interest.closed.v1');
  end loop;
end;$$;

create or replace function internal.express_match_pool_interest_for_actor(target_listing_id uuid, target_team_id uuid,
  interest jsonb, idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); listing internal.match_pool_listings%rowtype; target_club uuid;
  new_id uuid; existing internal.match_pool_interests%rowtype; new_starts timestamptz; new_ends timestamptz;
  local_day date; body text := btrim(coalesce(interest->>'message', ''));
begin
  if not internal.actor_pool_team(target_team_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if idempotency_key is null or interest is null or jsonb_typeof(interest) <> 'object'
    or length(body) not between 1 and 1000 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  -- A retry of the same request is the same interest.
  select message.interest_id into new_id from internal.match_pool_messages message
  where message.author_profile_id = actor_id and message.idempotency_key = express_match_pool_interest_for_actor.idempotency_key;
  if new_id is not null then return new_id; end if;
  select * into listing from internal.match_pool_listings where id = target_listing_id for update;
  if listing.id is null or listing.team_id = target_team_id
    or not exists (select 1 from core.clubs club where club.id = listing.club_id and club.status = 'active') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if not internal.match_pool_listing_current(listing) then raise invalid_parameter_value using message = 'listing_closed'; end if;
  if (select count(*) from internal.match_pool_interests sent where sent.created_by = actor_id
      and sent.created_at > now() - interval '1 day') >= 20 then
    raise insufficient_privilege using message = 'rate_limited';
  end if;
  if listing.kind = 'away_wanted' then
    begin
      new_starts := (interest->>'starts_at')::timestamptz; new_ends := (interest->>'ends_at')::timestamptz;
    exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise invalid_parameter_value using message = 'invalid_input';
    end;
    local_day := (new_starts at time zone 'Europe/Stockholm')::date;
    if new_starts is null or new_starts <= now() or local_day not between listing.date_from and listing.date_to
      or new_ends - new_starts not between interval '30 minutes' and interval '6 hours'
      or length(btrim(coalesce(interest->>'venue_name', ''))) not between 1 and 160
      or coalesce(nullif(interest->>'venue_surface', ''), 'grass') not in ('grass', 'artificial', 'indoor', 'other') then
      raise invalid_parameter_value using message = 'invalid_input';
    end if;
  end if;
  select club_id into target_club from core.teams where id = target_team_id;
  select * into existing from internal.match_pool_interests where listing_id = listing.id and team_id = target_team_id for update;
  if existing.id is not null and existing.state not in ('withdrawn') then
    raise invalid_parameter_value using message = 'already_interested';
  end if;
  if existing.id is not null then
    update internal.match_pool_interests set created_by = actor_id, starts_at = new_starts, ends_at = new_ends,
      venue_name = case when listing.kind = 'away_wanted' then btrim(interest->>'venue_name') end,
      venue_surface = case when listing.kind = 'away_wanted' then nullif(interest->>'venue_surface', '') end,
      add_to_calendar = coalesce((interest->>'add_to_calendar')::boolean, true),
      state = 'pending', updated_at = clock_timestamp()
    where id = existing.id returning id into new_id;
  else
    insert into internal.match_pool_interests(listing_id, club_id, team_id, created_by, starts_at, ends_at,
      venue_name, venue_surface, add_to_calendar)
    values (listing.id, target_club, target_team_id, actor_id, new_starts, new_ends,
      case when listing.kind = 'away_wanted' then btrim(interest->>'venue_name') end,
      case when listing.kind = 'away_wanted' then nullif(interest->>'venue_surface', '') end,
      coalesce((interest->>'add_to_calendar')::boolean, true))
    returning id into new_id;
  end if;
  insert into internal.match_pool_messages(interest_id, author_profile_id, side, body, idempotency_key)
  values (new_id, actor_id, 'interest', body, express_match_pool_interest_for_actor.idempotency_key);
  insert into internal.match_pool_reads(interest_id, profile_id) values (new_id, actor_id)
  on conflict (interest_id, profile_id) do update set read_at = clock_timestamp();
  perform internal.notify_match_pool(new_id, 'listing', 'matchpool.interest.received.v1');
  return new_id;
end;$$;

-- Which side of an interest the leader is on: 'listing', 'interest' or null.
create or replace function internal.match_pool_actor_side(target_interest_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when internal.actor_pool_team(listing.team_id) then 'listing'
    when internal.actor_pool_team(interest.team_id) then 'interest' end
  from internal.match_pool_interests interest
  join internal.match_pool_listings listing on listing.id = interest.listing_id
  where interest.id = target_interest_id
$$;

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
      || jsonb_build_object('current', internal.match_pool_listing_current(listing)),
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

create or replace function internal.send_match_pool_message_for_actor(target_interest_id uuid, message_body text,
  idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare my_side text := internal.match_pool_actor_side(target_interest_id); interest internal.match_pool_interests%rowtype;
  new_id uuid; body text := btrim(coalesce(message_body, ''));
begin
  if my_side is null then raise insufficient_privilege using message = 'not_found'; end if;
  if idempotency_key is null or length(body) not between 1 and 2000 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select id into new_id from internal.match_pool_messages message
  where message.author_profile_id = auth.uid() and message.idempotency_key = send_match_pool_message_for_actor.idempotency_key;
  if new_id is not null then return new_id; end if;
  select * into interest from internal.match_pool_interests where id = target_interest_id for update;
  if interest.state not in ('pending', 'accepted') then raise invalid_parameter_value using message = 'conversation_closed'; end if;
  if (select count(*) from internal.match_pool_messages message where message.interest_id = interest.id
      and message.created_at > now() - interval '1 day') >= 50 then
    raise insufficient_privilege using message = 'rate_limited';
  end if;
  insert into internal.match_pool_messages(interest_id, author_profile_id, side, body, idempotency_key)
  values (interest.id, auth.uid(), my_side, body, send_match_pool_message_for_actor.idempotency_key)
  returning id into new_id;
  update internal.match_pool_interests set updated_at = clock_timestamp() where id = interest.id;
  insert into internal.match_pool_reads(interest_id, profile_id) values (interest.id, auth.uid())
  on conflict (interest_id, profile_id) do update set read_at = clock_timestamp();
  perform internal.notify_match_pool(interest.id, case when my_side = 'listing' then 'interest' else 'listing' end,
    'matchpool.message.sent.v1');
  return new_id;
end;$$;

create or replace function internal.withdraw_match_pool_interest_for_actor(target_interest_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare interest internal.match_pool_interests%rowtype;
begin
  if internal.match_pool_actor_side(target_interest_id) is distinct from 'interest' then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into interest from internal.match_pool_interests where id = target_interest_id for update;
  if interest.state <> 'pending' then return; end if;
  update internal.match_pool_interests set state = 'withdrawn', updated_at = clock_timestamp() where id = interest.id;
  insert into internal.match_pool_messages(interest_id, side, body)
  values (interest.id, 'system', 'Intresset är återkallat.');
end;$$;

create or replace function internal.decline_match_pool_interest_for_actor(target_interest_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare interest internal.match_pool_interests%rowtype;
begin
  if internal.match_pool_actor_side(target_interest_id) is distinct from 'listing' then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into interest from internal.match_pool_interests where id = target_interest_id for update;
  if interest.state <> 'pending' then return; end if;
  update internal.match_pool_interests set state = 'declined', updated_at = clock_timestamp() where id = interest.id;
  insert into internal.match_pool_messages(interest_id, side, body)
  values (interest.id, 'system', 'Tack för intresset – det blev inte av den här gången.');
  perform internal.notify_match_pool(interest.id, 'interest', 'matchpool.interest.declined.v1');
end;$$;

-- Adds the booked match to one team's calendar as a draft, as the leader who
-- acted for that side (the accepting leader, or the leader who sent the
-- interest and did not opt out). That leader's own event.manage is checked
-- by the ordinary event command; the claim is switched only for that call.
-- A failure (the leader no longer manages the team) leaves the calendar
-- alone and is not an error for the booking.
create or replace function internal.match_pool_add_to_calendar(acting_profile_id uuid, target_club_id uuid,
  target_team_id uuid, opponent_team_id uuid, home boolean, new_starts timestamptz, new_ends timestamptz,
  venue text, surface text, dedup_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare previous text := current_setting('request.jwt.claim.sub', true); new_event uuid; opponent text;
begin
  opponent := left(internal.match_pool_team_label(opponent_team_id), 150);
  perform set_config('request.jwt.claim.sub', acting_profile_id::text, true);
  begin
    new_event := internal.create_event_v2_for_actor(target_club_id, target_team_id,
      left('Träningsmatch mot ' || opponent, 160), 'Bokad via matchpoolen på teamzoneapp.se.', 'match', 'draft',
      new_starts, new_ends, false, 'Europe/Stockholm', array['players', 'leaders', 'guardians'], venue,
      null, null, null,
      jsonb_build_object('opponent_name', opponent, 'home_away', case when home then 'home' else 'away' end,
        'match_notes', 'Träningsmatch bokad via matchpoolen.',
        'location_surface', internal.match_pool_surface_label(surface)),
      dedup_key);
  exception when others then
    new_event := null;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(previous, ''), true);
  return new_event;
end;$$;

create or replace function internal.accept_match_pool_interest_for_actor(target_interest_id uuid, add_to_calendar boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); interest internal.match_pool_interests%rowtype;
  listing internal.match_pool_listings%rowtype; host_is_listing boolean; match_starts timestamptz;
  match_ends timestamptz; venue text; surface text; waiting uuid; listing_event uuid; interest_event uuid;
begin
  if internal.match_pool_actor_side(target_interest_id) is distinct from 'listing' then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into interest from internal.match_pool_interests where id = target_interest_id for update;
  select * into listing from internal.match_pool_listings where id = interest.listing_id for update;
  if interest.state = 'accepted' then
    return jsonb_build_object('listing_event_id', interest.listing_event_id, 'interest_event_id', interest.interest_event_id);
  end if;
  if interest.state <> 'pending' or not internal.match_pool_listing_current(listing) then
    raise invalid_parameter_value using message = 'listing_closed';
  end if;
  host_is_listing := listing.kind = 'home_slot';
  match_starts := coalesce(listing.starts_at, interest.starts_at);
  match_ends := coalesce(listing.ends_at, interest.ends_at);
  venue := case when host_is_listing then listing.venue_name else interest.venue_name end;
  surface := case when host_is_listing then listing.venue_surface else interest.venue_surface end;

  update internal.match_pool_listings set state = 'matched', matched_interest_id = interest.id,
    updated_at = clock_timestamp() where id = listing.id;
  update internal.match_pool_interests set state = 'accepted', updated_at = clock_timestamp() where id = interest.id;
  insert into internal.match_pool_messages(interest_id, side, body)
  values (interest.id, 'system', 'Matchen är bokad.');
  for waiting in select id from internal.match_pool_interests
    where listing_id = listing.id and state = 'pending' and id <> interest.id loop
    update internal.match_pool_interests set state = 'closed', updated_at = clock_timestamp() where id = waiting;
    insert into internal.match_pool_messages(interest_id, side, body)
    values (waiting, 'system', 'Laget har bokat match med ett annat lag. Tack för intresset!');
    perform internal.notify_match_pool(waiting, 'interest', 'matchpool.interest.closed.v1');
  end loop;

  if coalesce(add_to_calendar, true) then
    listing_event := internal.match_pool_add_to_calendar(actor_id, listing.club_id, listing.team_id, interest.team_id,
      host_is_listing, match_starts, match_ends, venue, surface,
      md5('matchpool:' || interest.id || ':listing')::uuid);
  end if;
  if interest.add_to_calendar then
    interest_event := internal.match_pool_add_to_calendar(interest.created_by, interest.club_id, interest.team_id,
      listing.team_id, not host_is_listing, match_starts, match_ends, venue, surface,
      md5('matchpool:' || interest.id || ':interest')::uuid);
  end if;
  update internal.match_pool_interests set listing_event_id = listing_event, interest_event_id = interest_event
  where id = interest.id;
  perform internal.notify_match_pool(interest.id, 'interest', 'matchpool.interest.accepted.v1');
  return jsonb_build_object('listing_event_id', listing_event, 'interest_event_id', interest_event);
end;$$;

-- A report hides the listing once three different clubs have reported it.
create or replace function internal.report_match_pool_listing_for_actor(target_listing_id uuid, report_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare listing internal.match_pool_listings%rowtype; reporter_club uuid;
begin
  select * into listing from internal.match_pool_listings where id = target_listing_id;
  select t.club_id into reporter_club from internal.actor_pool_teams() t
  where t.club_id <> listing.club_id order by t.club_id limit 1;
  if listing.id is null or reporter_club is null then raise insufficient_privilege using message = 'not_found'; end if;
  if length(btrim(coalesce(report_reason, ''))) not between 1 and 500 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  insert into internal.match_pool_reports(listing_id, reporter_club_id, reporter_profile_id, reason)
  values (listing.id, reporter_club, auth.uid(), btrim(report_reason))
  on conflict (listing_id, reporter_club_id) do nothing;
  if listing.state = 'open' and (select count(*) from internal.match_pool_reports r where r.listing_id = listing.id) >= 3 then
    update internal.match_pool_listings set state = 'hidden', updated_at = clock_timestamp() where id = listing.id;
  end if;
end;$$;

-- For the app's inbox: whether the person is a leader in the pool and how
-- many conversations have something new.
create or replace function internal.get_match_pool_summary_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'leader', exists (select 1 from internal.actor_pool_teams()),
    'unread', (select count(*) from internal.match_pool_interests interest
      join internal.match_pool_listings listing on listing.id = interest.listing_id
      where interest.state in ('pending', 'accepted') and interest.updated_at > now() - interval '30 days'
        and ((listing.team_id in (select t.team_id from internal.actor_pool_teams() t)
            and internal.match_pool_unread(interest.id, 'listing'))
          or (interest.team_id in (select t.team_id from internal.actor_pool_teams() t)
            and internal.match_pool_unread(interest.id, 'interest')))))
$$;

-- Daily: past listings expire (their waiting interests close), and
-- everything that ended more than 30 days ago is deleted.
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
  return removed;
end;$$;

create or replace function internal.notification_title(event_type text)
returns text language sql immutable set search_path = '' as $$
 select case
  when event_type = 'message.message.sent.v1' then 'Nytt meddelande'
  when event_type = 'contact.message.received.v1' then 'Nytt meddelande via klubbsajten'
  when event_type = 'matchpool.interest.received.v1' then 'Intresse för er annons i matchpoolen'
  when event_type = 'matchpool.interest.accepted.v1' then 'Träningsmatchen är bokad'
  when event_type in ('matchpool.interest.declined.v1', 'matchpool.interest.closed.v1') then 'Besked från matchpoolen'
  when event_type = 'matchpool.message.sent.v1' then 'Nytt meddelande i matchpoolen'
  when event_type like 'callup.%.cancelled.%' then 'Kallelse återkallad'
  when event_type like 'callup.%.reminded.%' then 'Påminnelse om kallelse'
  when event_type like 'callup.%' then 'Ny kallelse'
  when event_type like 'event.%' then 'Kalendern har uppdaterats'
  else 'Ny aktivitet i TeamZone' end
$$;
create or replace function internal.notification_preview(event_type text)
returns text language sql immutable set search_path = '' as $$
 select case
  when event_type = 'message.message.sent.v1' then 'Öppna inkorgen för att läsa meddelandet.'
  when event_type = 'contact.message.received.v1' then 'Öppna inkorgen för att läsa och svara.'
  when event_type like 'matchpool.%' then 'Öppna matchpoolen på teamzoneapp.se.'
  when event_type like 'callup.%.cancelled.%' then 'En kallelse har återkallats.'
  when event_type like 'callup.%.reminded.%' then 'Du har en kallelse som behöver besvaras.'
  when event_type like 'callup.%' then 'Du har fått en kallelse.'
  when event_type like 'event.%' then 'Öppna kalendern för aktuell information.'
  else 'Öppna TeamZone för mer information.' end
$$;

-- As in 20261101090000, with the match pool.
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
  elsif outbox.event_type like 'matchpool.%' then
    -- The pool: what happened and the leader's own team, never the text.
    select team.name into team_name from core.teams team
    where outbox.payload_ref->>'team_id' ~ '^[0-9a-fA-F-]{36}$'
      and team.id = (outbox.payload_ref->>'team_id')::uuid;
    title := case outbox.event_type
      when 'matchpool.interest.received.v1' then case when swedish then 'Intresse för er annons i matchpoolen' else 'Interest in your match pool listing' end
      when 'matchpool.interest.accepted.v1' then case when swedish then 'Träningsmatchen är bokad' else 'The friendly is booked' end
      when 'matchpool.message.sent.v1' then case when swedish then 'Nytt meddelande i matchpoolen' else 'New message in the match pool' end
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

do $$
declare existing_job_id bigint;
begin
  for existing_job_id in select jobid from cron.job where jobname = 'match-pool-retention' loop
    perform cron.unschedule(existing_job_id);
  end loop;
  perform cron.schedule('match-pool-retention', '27 3 * * *', 'select internal.apply_match_pool_retention();');
end $$;

create or replace function api.get_match_pool(origin_team_id uuid default null, max_km integer default 100)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_match_pool_for_actor(origin_team_id, max_km)$$;
create or replace function api.save_match_pool_base(target_team_id uuid, place_label text, latitude numeric, longitude numeric)
returns void language sql security invoker set search_path = '' as
$$select internal.save_match_pool_base_for_actor(target_team_id, place_label, latitude, longitude)$$;
create or replace function api.create_match_pool_listing(target_team_id uuid, listing jsonb, idempotency_key uuid)
returns uuid language sql security invoker set search_path = '' as
$$select internal.create_match_pool_listing_for_actor(target_team_id, listing, idempotency_key)$$;
create or replace function api.withdraw_match_pool_listing(target_listing_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.withdraw_match_pool_listing_for_actor(target_listing_id)$$;
create or replace function api.express_match_pool_interest(target_listing_id uuid, target_team_id uuid, interest jsonb,
  idempotency_key uuid)
returns uuid language sql security invoker set search_path = '' as
$$select internal.express_match_pool_interest_for_actor(target_listing_id, target_team_id, interest, idempotency_key)$$;
create or replace function api.get_match_pool_conversation(target_interest_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_match_pool_conversation_for_actor(target_interest_id)$$;
create or replace function api.send_match_pool_message(target_interest_id uuid, message_body text, idempotency_key uuid)
returns uuid language sql security invoker set search_path = '' as
$$select internal.send_match_pool_message_for_actor(target_interest_id, message_body, idempotency_key)$$;
create or replace function api.withdraw_match_pool_interest(target_interest_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.withdraw_match_pool_interest_for_actor(target_interest_id)$$;
create or replace function api.decline_match_pool_interest(target_interest_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.decline_match_pool_interest_for_actor(target_interest_id)$$;
create or replace function api.accept_match_pool_interest(target_interest_id uuid, add_to_calendar boolean default true)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.accept_match_pool_interest_for_actor(target_interest_id, add_to_calendar)$$;
create or replace function api.report_match_pool_listing(target_listing_id uuid, reason text)
returns void language sql security invoker set search_path = '' as
$$select internal.report_match_pool_listing_for_actor(target_listing_id, reason)$$;
create or replace function api.get_match_pool_summary()
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_match_pool_summary_for_actor()$$;

revoke all on function internal.actor_pool_teams(), internal.actor_pool_team(uuid),
  internal.km_between(numeric, numeric, numeric, numeric), internal.match_pool_recipients(uuid, uuid),
  internal.notify_match_pool(uuid, text, text), internal.match_pool_surface_label(text),
  internal.match_pool_team_label(uuid), internal.match_pool_listing_current(internal.match_pool_listings),
  internal.match_pool_listing_json(internal.match_pool_listings, numeric, numeric, boolean),
  internal.match_pool_unread(uuid, text), internal.match_pool_interest_json(internal.match_pool_interests, text),
  internal.match_pool_actor_side(uuid),
  internal.match_pool_add_to_calendar(uuid, uuid, uuid, uuid, boolean, timestamptz, timestamptz, text, text, uuid),
  internal.apply_match_pool_retention(),
  internal.get_match_pool_for_actor(uuid, integer), internal.save_match_pool_base_for_actor(uuid, text, numeric, numeric),
  internal.create_match_pool_listing_for_actor(uuid, jsonb, uuid), internal.withdraw_match_pool_listing_for_actor(uuid),
  internal.express_match_pool_interest_for_actor(uuid, uuid, jsonb, uuid),
  internal.get_match_pool_conversation_for_actor(uuid), internal.send_match_pool_message_for_actor(uuid, text, uuid),
  internal.withdraw_match_pool_interest_for_actor(uuid), internal.decline_match_pool_interest_for_actor(uuid),
  internal.accept_match_pool_interest_for_actor(uuid, boolean), internal.report_match_pool_listing_for_actor(uuid, text),
  internal.get_match_pool_summary_for_actor(),
  api.get_match_pool(uuid, integer), api.save_match_pool_base(uuid, text, numeric, numeric),
  api.create_match_pool_listing(uuid, jsonb, uuid), api.withdraw_match_pool_listing(uuid),
  api.express_match_pool_interest(uuid, uuid, jsonb, uuid), api.get_match_pool_conversation(uuid),
  api.send_match_pool_message(uuid, text, uuid), api.withdraw_match_pool_interest(uuid),
  api.decline_match_pool_interest(uuid), api.accept_match_pool_interest(uuid, boolean),
  api.report_match_pool_listing(uuid, text), api.get_match_pool_summary()
  from public, anon, authenticated;
grant execute on function
  internal.get_match_pool_for_actor(uuid, integer), internal.save_match_pool_base_for_actor(uuid, text, numeric, numeric),
  internal.create_match_pool_listing_for_actor(uuid, jsonb, uuid), internal.withdraw_match_pool_listing_for_actor(uuid),
  internal.express_match_pool_interest_for_actor(uuid, uuid, jsonb, uuid),
  internal.get_match_pool_conversation_for_actor(uuid), internal.send_match_pool_message_for_actor(uuid, text, uuid),
  internal.withdraw_match_pool_interest_for_actor(uuid), internal.decline_match_pool_interest_for_actor(uuid),
  internal.accept_match_pool_interest_for_actor(uuid, boolean), internal.report_match_pool_listing_for_actor(uuid, text),
  internal.get_match_pool_summary_for_actor(),
  api.get_match_pool(uuid, integer), api.save_match_pool_base(uuid, text, numeric, numeric),
  api.create_match_pool_listing(uuid, jsonb, uuid), api.withdraw_match_pool_listing(uuid),
  api.express_match_pool_interest(uuid, uuid, jsonb, uuid), api.get_match_pool_conversation(uuid),
  api.send_match_pool_message(uuid, text, uuid), api.withdraw_match_pool_interest(uuid),
  api.decline_match_pool_interest(uuid), api.accept_match_pool_interest(uuid, boolean),
  api.report_match_pool_listing(uuid, text), api.get_match_pool_summary()
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261102090000_match_pool', 'greenfield',
  'POOL-01: matchpoolen, friendly-match listings between clubs for leaders'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261102090000_match_pool');
notify pgrst, 'reload schema';
