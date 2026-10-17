-- POOL-04: the map and support's view of reported listings.
--
-- The map: listings carry their position, which was rounded to about a
-- kilometre when saved (the place, never the pitch).
--
-- Reports: support administrators see reported listings with every
-- report (club and reason) and decide: hide the listing, or dismiss the
-- reports (a listing hidden automatically opens again if its date lies
-- ahead). Each decision is audited. Reports support has handled no longer
-- count toward hiding a listing automatically.

alter table internal.match_pool_reports
  add column if not exists resolved_at timestamptz,
  add column if not exists resolution text check (resolution in ('hidden', 'dismissed')),
  add column if not exists resolved_by uuid references core.profiles(id) on delete set null;
alter table internal.match_pool_listings
  add column if not exists hidden_by_support boolean not null default false;

-- As in 20261102090000, with the position.
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
    -- Rounded to about a kilometre when saved: the place, never the pitch.
    'latitude', listing.latitude, 'longitude', listing.longitude,
    'distance_km', case when origin_lat is null then null
      else internal.km_between(origin_lat, origin_lon, listing.latitude, listing.longitude) end,
    'venue_name', case when with_venue then listing.venue_name end,
    'venue_surface', listing.venue_surface, 'match_format', listing.match_format,
    'age_class', listing.age_class, 'gender', listing.gender, 'level', listing.level,
    'note', listing.note, 'created_at', listing.created_at)
  from core.teams team join core.clubs club on club.id = team.club_id
  where team.id = listing.team_id
$$;

-- As in 20261102090000; handled reports do not count again.
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
  -- Reports support has already looked at do not count again.
  if listing.state = 'open' and (select count(*) from internal.match_pool_reports r
      where r.listing_id = listing.id and r.resolved_at is null) >= 3 then
    update internal.match_pool_listings set state = 'hidden', updated_at = clock_timestamp() where id = listing.id;
  end if;
end;$$;

create or replace function internal.list_match_pool_reports_for_admin(only_open boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_is_support_admin() then raise insufficient_privilege using message = 'not_found'; end if;
  return coalesce((select jsonb_agg(item order by latest desc) from (
    select internal.match_pool_listing_json(listing, null, null, true)
        || jsonb_build_object(
          'hidden_by_support', listing.hidden_by_support,
          'open_reports', (select count(*) from internal.match_pool_reports r where r.listing_id = listing.id and r.resolved_at is null),
          'reports', (select jsonb_agg(jsonb_build_object('club_name', club.name, 'reason', r.reason, 'created_at', r.created_at,
              'resolution', r.resolution, 'resolved_at', r.resolved_at) order by r.created_at)
            from internal.match_pool_reports r join core.clubs club on club.id = r.reporter_club_id
            where r.listing_id = listing.id)) as item,
      (select max(r.created_at) from internal.match_pool_reports r where r.listing_id = listing.id) as latest
    from internal.match_pool_listings listing
    where exists (select 1 from internal.match_pool_reports r where r.listing_id = listing.id
      and (not coalesce(only_open, true) or r.resolved_at is null))
    order by latest desc limit 200) rows), '[]'::jsonb);
end;$$;

create or replace function internal.decide_match_pool_reports_for_admin(target_listing_id uuid, hide boolean, note text)
returns text language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); listing internal.match_pool_listings%rowtype; waiting uuid; new_state text;
begin
  if not internal.actor_is_support_admin() then raise insufficient_privilege using message = 'not_found'; end if;
  if length(btrim(coalesce(note, ''))) not between 5 and 1000 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  select * into listing from internal.match_pool_listings where id = target_listing_id for update;
  if listing.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  if coalesce(hide, false) then
    new_state := case when listing.state in ('open', 'hidden') then 'hidden' else listing.state end;
    update internal.match_pool_listings set state = new_state, hidden_by_support = true, updated_at = clock_timestamp()
    where id = listing.id;
    -- Teams waiting for an answer are told the listing is gone.
    for waiting in select id from internal.match_pool_interests where listing_id = listing.id and state = 'pending' loop
      update internal.match_pool_interests set state = 'closed', updated_at = clock_timestamp() where id = waiting;
      insert into internal.match_pool_messages(interest_id, side, body)
      values (waiting, 'system', 'Annonsen är borttagen av TeamZones support.');
      perform internal.notify_match_pool(waiting, 'interest', 'matchpool.interest.closed.v1');
    end loop;
  else
    new_state := case when listing.state = 'hidden' and internal.match_pool_dates_ahead(listing) then 'open'
      when listing.state = 'hidden' then 'expired' else listing.state end;
    update internal.match_pool_listings set state = new_state, hidden_by_support = false, updated_at = clock_timestamp()
    where id = listing.id;
  end if;
  update internal.match_pool_reports set resolved_at = now(), resolved_by = actor_id,
    resolution = case when coalesce(hide, false) then 'hidden' else 'dismissed' end
  where listing_id = listing.id and resolved_at is null;
  insert into audit.command_events(club_id, actor_profile_id, command_type, aggregate_type, aggregate_id,
    aggregate_revision, reason, metadata)
  values (listing.club_id, actor_id, 'support.match_pool_reports.decide.v1', 'match_pool_listing', listing.id, 1,
    btrim(note), jsonb_build_object('hide', coalesce(hide, false), 'state', new_state));
  return new_state;
end;$$;

create or replace function api.list_match_pool_reports(only_open boolean default true)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_match_pool_reports_for_admin(only_open)$$;
create or replace function api.decide_match_pool_reports(target_listing_id uuid, hide boolean, note text)
returns text language sql security invoker set search_path = '' as
$$select internal.decide_match_pool_reports_for_admin(target_listing_id, hide, note)$$;

revoke all on function internal.list_match_pool_reports_for_admin(boolean),
  internal.decide_match_pool_reports_for_admin(uuid, boolean, text),
  api.list_match_pool_reports(boolean), api.decide_match_pool_reports(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function internal.list_match_pool_reports_for_admin(boolean),
  internal.decide_match_pool_reports_for_admin(uuid, boolean, text),
  api.list_match_pool_reports(boolean), api.decide_match_pool_reports(uuid, boolean, text)
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261106090000_match_pool_map_reports', 'greenfield',
  'POOL-04: listing positions for the map, support view of reported listings'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261106090000_match_pool_map_reports');
notify pgrst, 'reload schema';
