-- POOL-05: fixes from the review of the match pool.
--
-- 1. Erasing an account (auth user deleted) was blocked by the pool's
--    references to the profile; they are now cleared instead.
-- 2. Retention deleted a booked match's conversation 30 days after the last
--    message, even when the match was still ahead.
-- 3. Watch notifications kept going to someone who no longer leads the team,
--    and listings of ended teams stayed in the list and in watches.
-- 4. A match could be "cancelled" after it had started.
-- 5. A leader of two teams in one club (a club administrator) could show
--    interest in the club's own listing and then act for both sides.

alter table internal.match_pool_listings alter column created_by drop not null;
alter table internal.match_pool_listings drop constraint if exists match_pool_listings_created_by_fkey;
alter table internal.match_pool_listings add constraint match_pool_listings_created_by_fkey
  foreign key (created_by) references core.profiles(id) on delete set null;
alter table internal.match_pool_interests alter column created_by drop not null;
alter table internal.match_pool_interests drop constraint if exists match_pool_interests_created_by_fkey;
alter table internal.match_pool_interests add constraint match_pool_interests_created_by_fkey
  foreign key (created_by) references core.profiles(id) on delete set null;
alter table internal.match_pool_reports alter column reporter_profile_id drop not null;
alter table internal.match_pool_reports drop constraint if exists match_pool_reports_reporter_profile_id_fkey;
alter table internal.match_pool_reports add constraint match_pool_reports_reporter_profile_id_fkey
  foreign key (reporter_profile_id) references core.profiles(id) on delete set null;
alter table internal.match_pool_bases alter column updated_by drop not null;
alter table internal.match_pool_bases drop constraint if exists match_pool_bases_updated_by_fkey;
alter table internal.match_pool_bases add constraint match_pool_bases_updated_by_fkey
  foreign key (updated_by) references core.profiles(id) on delete set null;

-- As in 20261102090000; nobody to act as when the leader is erased.
create or replace function internal.match_pool_add_to_calendar(acting_profile_id uuid, target_club_id uuid,
  target_team_id uuid, opponent_team_id uuid, home boolean, new_starts timestamptz, new_ends timestamptz,
  venue text, surface text, dedup_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare previous text := current_setting('request.jwt.claim.sub', true); new_event uuid; opponent text;
begin
  -- The leader may have been erased since: nobody to act as.
  if acting_profile_id is null then return null; end if;
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

-- As in 20261104090000; booked matches are kept until played.
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
      where interest.listing_id = listing.id and (interest.updated_at >= now() - interval '30 days'
        -- A booked match is kept until 30 days after it was played.
        or (interest.state = 'accepted'
          and coalesce(listing.starts_at, interest.starts_at) >= now() - interval '30 days')));
  get diagnostics removed = row_count;
  delete from internal.match_pool_cancellations where cancelled_at < now() - interval '2 years';
  return removed;
end;$$;

-- As in 20261105090000; only current leaders, only active teams.
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
  join core.teams listing_team on listing_team.id = listing.team_id and listing_team.status = 'active'
  join core.clubs listing_club on listing_club.id = listing.club_id
  join lateral (select l.club_person_id from core.person_account_links l
    where l.profile_id = watch.created_by and l.club_id = watch.club_id and l.state = 'active'
    order by l.club_person_id limit 1) link on true
  where watch.team_id <> listing.team_id
    -- The one who saved the watch must still lead the team.
    and exists (select 1 from internal.match_pool_recipients(watch.club_id, watch.team_id) recipient
      where recipient.profile_id = watch.created_by)
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

-- As in 20261104090000; not once the match has started.
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
  if coalesce(listing.starts_at, interest.starts_at) <= now() then raise invalid_parameter_value using message = 'match_started'; end if;
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

-- As in 20261104090000; not once the match has started.
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
  if coalesce(listing.starts_at, interest.starts_at) <= now() then raise invalid_parameter_value using message = 'match_started'; end if;
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

-- As in 20261102090000; not from the listing's own club, not to ended teams.
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
    or listing.club_id = (select team.club_id from core.teams team where team.id = target_team_id)
    or not exists (select 1 from core.clubs club where club.id = listing.club_id and club.status = 'active')
    or not exists (select 1 from core.teams team where team.id = listing.team_id and team.status = 'active') then
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

-- As in 20261104090000; not the leader's own clubs, not ended teams.
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
        join core.teams listing_team on listing_team.id = listing.team_id and listing_team.status = 'active'
        where internal.match_pool_listing_current(listing)
          and listing.team_id not in (select t.team_id from internal.actor_pool_teams() t)
          -- Teams of the leader's own clubs find each other without the pool.
          and listing.club_id not in (select t.club_id from internal.actor_pool_teams() t)
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

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261107090000_match_pool_review_fixes', 'greenfield', 'POOL-05: fixes from the match pool review'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261107090000_match_pool_review_fixes');
notify pgrst, 'reload schema';
