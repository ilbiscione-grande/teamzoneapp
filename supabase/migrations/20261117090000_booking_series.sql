-- Bokningshanterare: recurring bookings. A series repeats weekly on chosen
-- weekdays (every week or every second...) between two dates; each time is
-- an ordinary booking with the series' id, so the calendar, the clash check,
-- the app and notifications work as before. Times that clash are skipped.
-- A series asks for approval once, and is approved or declined as a whole.

create table core.booking_series (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references core.booking_organizations(id) on delete cascade,
  resource_id uuid not null references core.booking_resources(id) on delete cascade,
  booked_by uuid not null references core.profiles(id),
  team_id uuid references core.teams(id),
  title text check (title is null or length(btrim(title)) between 1 and 160),
  notes text check (notes is null or length(notes) <= 2000),
  weekdays smallint[] not null check (cardinality(weekdays) between 1 and 7 and weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]),
  interval_weeks smallint not null default 1 check (interval_weeks between 1 and 4),
  starts_on date not null,
  ends_on date not null,
  start_time time not null,
  end_time time not null,
  timezone text not null default 'Europe/Stockholm',
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on and ends_on - starts_on <= 366),
  check (end_time > start_time)
);
alter table core.booking_series enable row level security;
revoke all on core.booking_series from public, anon, authenticated;

alter table core.booking_bookings add column series_id uuid references core.booking_series(id) on delete cascade;
create index booking_bookings_series on core.booking_bookings (series_id) where series_id is not null;

-- The series' times, local dates and times turned into instants.
create or replace function internal.booking_series_times(
  series_weekdays smallint[], series_interval smallint, first_day date, last_day date,
  start_at time, end_at time, zone text
) returns table(starts_at timestamptz, ends_at timestamptz) language sql stable set search_path = '' as $$
  select (d.local_day + start_at) at time zone zone, (d.local_day + end_at) at time zone zone
  from generate_series(first_day, last_day, interval '1 day') generated(value)
  cross join lateral (select generated.value::date local_day) d
  where extract(isodow from d.local_day)::smallint = any(series_weekdays)
    and ((d.local_day - date_trunc('week', first_day)::date) / 7) % series_interval = 0
  order by d.local_day
$$;

-- As in 20261115090000, with the series the booking belongs to.
create or replace function internal.booking_json(booking core.booking_bookings, actor_role text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', booking.id, 'resource_id', booking.resource_id,
    'resource_name', (select resource.name from core.booking_resources resource where resource.id = booking.resource_id),
    'starts_at', booking.starts_at, 'ends_at', booking.ends_at,
    'title', booking.title, 'notes', booking.notes, 'status', booking.status,
    'booked_by_name', internal.booking_person_name(booking.booked_by),
    'is_mine', booking.booked_by = auth.uid(),
    'team_id', booking.team_id,
    'team_name', (select team.name from core.teams team where team.id = booking.team_id),
    'event_id', booking.event_id,
    'event_title', (select event_row.title from core.events event_row where event_row.id = booking.event_id),
    'series_id', booking.series_id,
    'series_remaining', case when booking.series_id is null then null else (select count(*) from core.booking_bookings other
      where other.series_id = booking.series_id and other.status in ('pending', 'confirmed') and other.ends_at > now()) end,
    'can_cancel', booking.status in ('pending', 'confirmed') and booking.ends_at > now()
      and (booking.booked_by = auth.uid() or actor_role = 'admin'),
    'can_decide', booking.status = 'pending' and actor_role = 'admin' and booking.ends_at > now()
  )
$$;

-- Plans (dry run) or books a series. Returns every time with whether it
-- clashes; without a dry run the free ones are booked.
create or replace function internal.create_booking_series_for_actor(
  target_resource_id uuid, series_weekdays smallint[], series_interval smallint,
  first_day date, last_day date, start_at time, end_at time, zone text,
  booking_title text, booking_notes text, target_team_id uuid, dry_run boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  resource core.booking_resources;
  actor_role text;
  new_series uuid;
  status text;
  times jsonb := '[]'::jsonb;
  occurrence record;
  clash boolean;
  created integer := 0;
begin
  select * into resource from core.booking_resources where id = target_resource_id;
  actor_role := internal.booking_actor_role(resource.organization_id);
  if resource.id is null or actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  if not resource.active then raise invalid_parameter_value using message = 'resource_inactive'; end if;
  if series_weekdays is null or cardinality(series_weekdays) = 0 or not (series_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[])
    or series_interval not between 1 and 4 or last_day < first_day or last_day - first_day > 366 or end_at <= start_at then
    raise invalid_parameter_value using message = 'invalid_series';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = zone) then
    raise invalid_parameter_value using message = 'invalid_series';
  end if;
  if target_team_id is not null and not exists (
    select 1 from internal.booking_actor_teams(resource.organization_id) t where t.team_id = target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  if (select count(*) from internal.booking_series_times(series_weekdays, series_interval, first_day, last_day, start_at, end_at, zone)
      where ends_at > now()) > 200 then
    raise invalid_parameter_value using message = 'series_too_long';
  end if;
  status := case when resource.requires_approval and actor_role <> 'admin' then 'pending' else 'confirmed' end;
  perform pg_advisory_xact_lock(hashtextextended(target_resource_id::text, 0));
  if not dry_run then
    insert into core.booking_series (organization_id, resource_id, booked_by, team_id, title, notes, weekdays, interval_weeks,
      starts_on, ends_on, start_time, end_time, timezone)
    values (resource.organization_id, resource.id, auth.uid(), target_team_id, nullif(btrim(booking_title), ''),
      nullif(btrim(booking_notes), ''), series_weekdays, series_interval, first_day, last_day, start_at, end_at, zone)
    returning id into new_series;
  end if;
  for occurrence in
    select * from internal.booking_series_times(series_weekdays, series_interval, first_day, last_day, start_at, end_at, zone)
    where ends_at > now()
  loop
    clash := exists (select 1 from core.booking_bookings other
      where other.resource_id = target_resource_id and other.status in ('pending', 'confirmed')
        and other.starts_at < occurrence.ends_at and other.ends_at > occurrence.starts_at);
    times := times || jsonb_build_object('starts_at', occurrence.starts_at, 'ends_at', occurrence.ends_at, 'clash', clash);
    if not clash and not dry_run then
      insert into core.booking_bookings (organization_id, resource_id, starts_at, ends_at, title, notes, status, booked_by,
        team_id, series_id, decided_by, decided_at)
      values (resource.organization_id, resource.id, occurrence.starts_at, occurrence.ends_at, nullif(btrim(booking_title), ''),
        nullif(btrim(booking_notes), ''), status, auth.uid(), target_team_id, new_series,
        case when status = 'confirmed' then auth.uid() end, case when status = 'confirmed' then now() end);
      created := created + 1;
    end if;
  end loop;
  if not dry_run then
    if created = 0 then
      delete from core.booking_series where id = new_series;
      raise exclusion_violation using message = 'resource_busy';
    end if;
    -- One request for the whole series.
    if status = 'pending' then
      perform internal.booking_notify(
        (select b.id from core.booking_bookings b where b.series_id = new_series order by b.starts_at limit 1),
        'requested', array(select profile_id from internal.booking_admin_profiles(resource.organization_id)));
    end if;
  end if;
  return jsonb_build_object('series_id', new_series, 'status', status, 'created', created, 'times', times);
end;
$$;

-- Approves or declines every pending time of a series at once.
create or replace function internal.decide_booking_series_for_actor(target_series_id uuid, approve boolean)
returns integer language plpgsql security definer set search_path = '' as $$
declare series core.booking_series; changed integer; first_booking uuid;
begin
  select * into series from core.booking_series where id = target_series_id;
  if series.id is null or internal.booking_actor_role(series.organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  select id into first_booking from core.booking_bookings
  where series_id = series.id and status = 'pending' and ends_at > now() order by starts_at limit 1;
  update core.booking_bookings set status = case when approve then 'confirmed' else 'declined' end,
    decided_by = auth.uid(), decided_at = now(), revision = revision + 1
  where series_id = series.id and status = 'pending' and ends_at > now();
  get diagnostics changed = row_count;
  if changed = 0 then raise invalid_parameter_value using message = 'not_pending'; end if;
  perform internal.booking_notify(first_booking, case when approve then 'approved' else 'declined' end, array[series.booked_by]);
  return changed;
end;
$$;

-- Cancels the coming times of a series (the one who booked, or an admin).
create or replace function internal.cancel_booking_series_for_actor(target_series_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare series core.booking_series; changed integer; first_booking uuid;
begin
  select * into series from core.booking_series where id = target_series_id;
  if series.id is null or internal.booking_actor_role(series.organization_id) is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if series.booked_by <> auth.uid() and internal.booking_actor_role(series.organization_id) <> 'admin' then
    raise insufficient_privilege using message = 'not_allowed';
  end if;
  select id into first_booking from core.booking_bookings
  where series_id = series.id and status in ('pending', 'confirmed') and starts_at > now() order by starts_at limit 1;
  update core.booking_bookings set status = 'cancelled', revision = revision + 1
  where series_id = series.id and status in ('pending', 'confirmed') and starts_at > now();
  get diagnostics changed = row_count;
  if changed = 0 then raise invalid_parameter_value using message = 'not_active'; end if;
  if series.booked_by <> auth.uid() then
    perform internal.booking_notify(first_booking, 'cancelled', array[series.booked_by]);
  end if;
  return changed;
end;
$$;

create or replace function api.create_booking_series(
  target_resource_id uuid, series_weekdays smallint[], series_interval smallint,
  first_day date, last_day date, start_at time, end_at time, zone text,
  booking_title text, booking_notes text, target_team_id uuid, dry_run boolean
) returns jsonb language sql security invoker set search_path = '' as
$$ select internal.create_booking_series_for_actor(target_resource_id, series_weekdays, series_interval, first_day, last_day,
  start_at, end_at, zone, booking_title, booking_notes, target_team_id, dry_run) $$;
create or replace function api.decide_booking_series(target_series_id uuid, approve boolean) returns integer language sql security invoker set search_path = '' as
$$ select internal.decide_booking_series_for_actor(target_series_id, approve) $$;
create or replace function api.cancel_booking_series(target_series_id uuid) returns integer language sql security invoker set search_path = '' as
$$ select internal.cancel_booking_series_for_actor(target_series_id) $$;

revoke all on function
  internal.booking_series_times(smallint[], smallint, date, date, time, time, text),
  internal.create_booking_series_for_actor(uuid, smallint[], smallint, date, date, time, time, text, text, text, uuid, boolean),
  internal.decide_booking_series_for_actor(uuid, boolean), internal.cancel_booking_series_for_actor(uuid),
  api.create_booking_series(uuid, smallint[], smallint, date, date, time, time, text, text, text, uuid, boolean),
  api.decide_booking_series(uuid, boolean), api.cancel_booking_series(uuid)
from public, anon, authenticated;
grant execute on function
  internal.create_booking_series_for_actor(uuid, smallint[], smallint, date, date, time, time, text, text, text, uuid, boolean),
  internal.decide_booking_series_for_actor(uuid, boolean), internal.cancel_booking_series_for_actor(uuid),
  api.create_booking_series(uuid, smallint[], smallint, date, date, time, time, text, text, text, uuid, boolean),
  api.decide_booking_series(uuid, boolean), api.cancel_booking_series(uuid)
to authenticated;
