-- POOL-03: age groups are picked from fixed choices (birth years and
-- Senior), several per listing or watch, instead of free text; a watch with
-- age groups matches a listing that shares one. Watches can be edited.
-- age_class stays as the readable label ("2012–2013") that everything shows.

alter table internal.match_pool_listings add column if not exists age_groups text[] not null default '{}';
alter table internal.match_pool_watches add column if not exists age_groups text[] not null default '{}';

-- The choices: a four-digit birth year or 'senior'. Checked per element.
create or replace function internal.match_pool_age_groups(value jsonb)
returns text[] language plpgsql immutable set search_path = '' as $$
declare groups text[];
begin
  if value is null or jsonb_typeof(value) = 'null' then return null; end if;
  if jsonb_typeof(value) <> 'array' then return null; end if;
  select array_agg(distinct element order by element) into groups from jsonb_array_elements_text(value) element;
  groups := coalesce(groups, '{}');
  if cardinality(groups) > 4 or exists (select 1 from unnest(groups) g where g !~ '^(19[5-9][0-9]|20[0-9][0-9]|senior)$') then
    return null;
  end if;
  return groups;
end;$$;

-- "2012", "2012–2013", "2010, 2012", "Senior" or "2007, Senior".
create or replace function internal.match_pool_age_label(groups text[])
returns text language sql immutable set search_path = '' as $$
  with years as (select g::integer y from unnest(groups) g where g ~ '^[0-9]{4}$'),
  runs as (select y, y - row_number() over (order by y) as run from years),
  spans as (select min(y) low, max(y) high from runs group by run)
  select nullif(concat_ws(', ',
    (select string_agg(case when low = high then low::text else low || '–' || high end, ', ' order by low) from spans),
    case when 'senior' = any(groups) then 'Senior' end), '')
$$;

alter table internal.match_pool_listings drop constraint if exists match_pool_listings_age_groups_check;
alter table internal.match_pool_listings add constraint match_pool_listings_age_groups_check
  check (cardinality(age_groups) <= 4);
alter table internal.match_pool_watches drop constraint if exists match_pool_watches_age_groups_check;
alter table internal.match_pool_watches add constraint match_pool_watches_age_groups_check
  check (cardinality(age_groups) <= 4);

-- Earlier listings and watches: the birth years written in their text.
update internal.match_pool_listings set age_groups = coalesce((select array_agg(distinct m[1] order by m[1])
  from regexp_matches(age_class, '((?:19|20)[0-9]{2})', 'g') m), '{}') where age_groups = '{}';
update internal.match_pool_watches set age_groups = coalesce((select array_agg(distinct m[1] order by m[1])
  from regexp_matches(age_class, '((?:19|20)[0-9]{2})', 'g') m), '{}') where age_groups = '{}' and age_class is not null;

-- As in 20261104090000, with age groups.
create or replace function internal.create_match_pool_listing_for_actor(target_team_id uuid, listing jsonb,
  idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); target_club uuid; new_id uuid; new_kind text := listing->>'kind';
  today date := (now() at time zone 'Europe/Stockholm')::date;
  new_starts timestamptz; new_ends timestamptz; new_from date; new_to date;
  groups text[] := internal.match_pool_age_groups(listing->'age_groups'); age_label text;
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
  -- Age groups are picked from the fixed choices; the old free text still works.
  if listing ? 'age_groups' and (groups is null or cardinality(groups) not between 1 and 4) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  age_label := coalesce(internal.match_pool_age_label(groups), btrim(listing->>'age_class'));
  select club_id into target_club from core.teams where id = target_team_id;
  begin
    insert into internal.match_pool_listings(club_id, team_id, created_by, kind, starts_at, ends_at, date_from, date_to,
      max_distance_km, place_label, latitude, longitude, venue_name, venue_surface, match_format, age_class, gender,
      level, note, idempotency_key, age_groups)
    values (target_club, target_team_id, actor_id, new_kind, new_starts, new_ends, new_from, new_to,
      case when new_kind = 'away_wanted' then (listing->>'max_distance_km')::integer end,
      btrim(listing->>'place_label'), round((listing->>'latitude')::numeric, 2), round((listing->>'longitude')::numeric, 2),
      case when new_kind = 'home_slot' then btrim(listing->>'venue_name') end,
      nullif(listing->>'venue_surface', ''), listing->>'match_format', age_label,
      listing->>'gender', nullif(listing->>'level', ''), nullif(btrim(listing->>'note'), ''),
      create_match_pool_listing_for_actor.idempotency_key, coalesce(groups, '{}'))
    returning id into new_id;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise invalid_parameter_value using message = 'invalid_input';
  end;
  perform internal.notify_match_pool_watches(new_id);
  return new_id;
end;$$;

-- As in 20261104090000, with age groups.
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
    level, note, idempotency_key, age_groups)
  values (listing.club_id, listing.team_id, auth.uid(), listing.kind, listing.starts_at, listing.ends_at,
    -- greatest() skips nulls: only a range starts at today at the earliest.
    case when listing.kind = 'away_wanted'
      then greatest(listing.date_from, (now() at time zone 'Europe/Stockholm')::date) end, listing.date_to,
    listing.max_distance_km, listing.place_label, listing.latitude, listing.longitude, listing.venue_name,
    listing.venue_surface, listing.match_format, listing.age_class, listing.gender, listing.level, listing.note,
    republish_match_pool_listing_for_actor.idempotency_key, listing.age_groups)
  returning id into new_id;
  update internal.match_pool_listings set republished_listing_id = new_id, updated_at = clock_timestamp()
  where id = listing.id;
  perform internal.notify_match_pool_watches(new_id);
  return new_id;
end;$$;

-- As in 20261104090000: shared age groups match.
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
    and (case when cardinality(watch.age_groups) > 0 then watch.age_groups && listing.age_groups
      else watch.age_class is null or strpos(lower(listing.age_class), lower(btrim(watch.age_class))) > 0 end)
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

-- As in 20261104090000, with age groups.
create or replace function internal.create_match_pool_watch_for_actor(target_team_id uuid, watch jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target_club uuid; new_id uuid; groups text[] := internal.match_pool_age_groups(watch->'age_groups');
begin
  if not internal.actor_pool_team(target_team_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if not exists (select 1 from internal.match_pool_bases where team_id = target_team_id) then
    raise invalid_parameter_value using message = 'no_base';
  end if;
  if (select count(*) from internal.match_pool_watches where team_id = target_team_id) >= 5 then
    raise insufficient_privilege using message = 'rate_limited';
  end if;
  if watch is null or jsonb_typeof(watch) <> 'object' or (watch ? 'age_groups' and groups is null) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select club_id into target_club from core.teams where id = target_team_id;
  begin
    insert into internal.match_pool_watches(club_id, team_id, created_by, kind, max_distance_km, match_format, gender,
      age_class, verified_only, age_groups)
    values (target_club, target_team_id, auth.uid(), coalesce(nullif(watch->>'kind', ''), 'all'),
      (watch->>'max_distance_km')::integer, nullif(watch->>'match_format', ''), nullif(watch->>'gender', ''),
      coalesce(internal.match_pool_age_label(groups), nullif(btrim(watch->>'age_class'), '')),
      coalesce((watch->>'verified_only')::boolean, false), coalesce(groups, '{}'))
    returning id into new_id;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise invalid_parameter_value using message = 'invalid_input';
  end;
  return new_id;
end;$$;

-- As in 20261104090000, with age groups.
create or replace function internal.list_match_pool_watches_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', watch.id, 'team_id', watch.team_id, 'team_name', team.name,
      'kind', watch.kind, 'max_distance_km', watch.max_distance_km, 'match_format', watch.match_format,
      'gender', watch.gender, 'age_class', watch.age_class, 'age_groups', to_jsonb(watch.age_groups), 'verified_only', watch.verified_only,
      'mine', watch.created_by = auth.uid(), 'created_at', watch.created_at) order by team.name, watch.created_at), '[]'::jsonb)
  from internal.match_pool_watches watch join core.teams team on team.id = watch.team_id
  where watch.team_id in (select t.team_id from internal.actor_pool_teams() t)
$$;

create or replace function internal.update_match_pool_watch_for_actor(target_watch_id uuid, watch jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare existing internal.match_pool_watches%rowtype; groups text[] := internal.match_pool_age_groups(watch->'age_groups');
begin
  select * into existing from internal.match_pool_watches where id = target_watch_id for update;
  if existing.id is null or not internal.actor_pool_team(existing.team_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if watch is null or jsonb_typeof(watch) <> 'object' or (watch ? 'age_groups' and groups is null) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  begin
    update internal.match_pool_watches set
      kind = coalesce(nullif(watch->>'kind', ''), 'all'),
      max_distance_km = (watch->>'max_distance_km')::integer,
      match_format = nullif(watch->>'match_format', ''),
      gender = nullif(watch->>'gender', ''),
      age_groups = coalesce(groups, '{}'),
      age_class = coalesce(internal.match_pool_age_label(groups), nullif(btrim(watch->>'age_class'), '')),
      verified_only = coalesce((watch->>'verified_only')::boolean, false)
    where id = existing.id;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise invalid_parameter_value using message = 'invalid_input';
  end;
end;$$;

create or replace function api.update_match_pool_watch(target_watch_id uuid, watch jsonb)
returns void language sql security invoker set search_path = '' as
$$select internal.update_match_pool_watch_for_actor(target_watch_id, watch)$$;

revoke all on function internal.match_pool_age_groups(jsonb), internal.match_pool_age_label(text[]),
  internal.update_match_pool_watch_for_actor(uuid, jsonb), api.update_match_pool_watch(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function internal.update_match_pool_watch_for_actor(uuid, jsonb), api.update_match_pool_watch(uuid, jsonb)
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261105090000_match_pool_age_groups', 'greenfield',
  'POOL-03: age groups as choices, editable watches'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261105090000_match_pool_age_groups');
notify pgrst, 'reload schema';
