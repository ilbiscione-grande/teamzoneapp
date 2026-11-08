-- Booking safety: preserve legacy RPCs while making every writer obey the
-- same storage invariant. Fail migration if existing active bookings overlap;
-- never silently cancel or rewrite customer reservations.
create extension if not exists btree_gist with schema extensions;
alter table core.booking_bookings add constraint booking_no_overlap
  exclude using gist (resource_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
  where (status in ('pending', 'confirmed'));

create table internal.booking_audit (
  id bigint generated always as identity primary key,
  booking_id uuid not null,
  organization_id uuid not null,
  actor_id uuid,
  changed_at timestamptz not null default clock_timestamp(),
  operation text not null,
  before_row jsonb,
  after_row jsonb
);
alter table internal.booking_audit enable row level security;
revoke all on internal.booking_audit from public, anon, authenticated;
create index booking_audit_booking on internal.booking_audit(booking_id, id);

create function internal.audit_booking_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into internal.booking_audit(booking_id, organization_id, actor_id, operation, before_row, after_row)
  values (coalesce(new.id, old.id), coalesce(new.organization_id, old.organization_id), auth.uid(), tg_op,
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new, old);
end; $$;
revoke all on function internal.audit_booking_change() from public, anon, authenticated;
create trigger booking_audit after insert or update or delete on core.booking_bookings
  for each row execute function internal.audit_booking_change();

-- Administrators may book for a linked club's teams, but never another club.
create function internal.booking_actor_can_book_team(org_id uuid, team uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from internal.booking_actor_teams(org_id) t where t.team_id = team)
    or (internal.booking_actor_role(org_id) = 'admin' and exists (
      select 1 from core.booking_organizations o join core.teams t on t.club_id = o.teamzone_club_id
      where o.id = org_id and t.id = team and t.status = 'active'))
$$;
revoke all on function internal.booking_actor_can_book_team(uuid, uuid) from public, anon, authenticated;


create or replace function internal.create_booking_for_actor(
  target_resource_id uuid, booking_starts_at timestamptz, booking_ends_at timestamptz,
  booking_title text, booking_notes text, target_team_id uuid, target_event_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  resource core.booking_resources;
  actor_role text;
  created core.booking_bookings;
  event_row core.events;
begin
  select * into resource from core.booking_resources where id = target_resource_id for share;
  actor_role := internal.booking_actor_role(resource.organization_id);
  if resource.id is null or actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  if not resource.active then raise invalid_parameter_value using message = 'resource_inactive'; end if;
  if booking_ends_at <= booking_starts_at or booking_ends_at - booking_starts_at > interval '31 days' then
    raise invalid_parameter_value using message = 'invalid_time';
  end if;
  if booking_ends_at <= now() then raise invalid_parameter_value using message = 'in_the_past'; end if;
  if target_team_id is not null and not internal.booking_actor_can_book_team(resource.organization_id, target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  if target_event_id is not null then
    if not exists (select 1 from core.events e join core.booking_organizations o on o.teamzone_club_id = e.club_id where e.id = target_event_id and o.id = resource.organization_id and e.archived_at is null and e.state in ('draft', 'scheduled')) then raise insufficient_privilege using message = 'event_not_found'; end if;
    if target_team_id is null then raise invalid_parameter_value using message = 'event_needs_team'; end if;
    select * into event_row from core.events where id = target_event_id;
    if event_row.id is null or not internal.actor_can_read_event(target_event_id)
      or not exists (select 1 from core.event_teams relation where relation.event_id = target_event_id and relation.team_id = target_team_id) then
      raise insufficient_privilege using message = 'event_not_found';
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_resource_id::text, 0));
  if exists (select 1 from core.booking_bookings other
    where other.resource_id = target_resource_id and other.status in ('pending', 'confirmed')
      and other.starts_at < booking_ends_at and other.ends_at > booking_starts_at) then
    raise exclusion_violation using message = 'resource_busy';
  end if;
  insert into core.booking_bookings (organization_id, resource_id, starts_at, ends_at, title, notes, status, booked_by, team_id, event_id,
    decided_by, decided_at)
  values (resource.organization_id, resource.id, booking_starts_at, booking_ends_at, nullif(btrim(booking_title), ''),
    nullif(btrim(booking_notes), ''),
    case when resource.requires_approval and actor_role <> 'admin' then 'pending' else 'confirmed' end,
    auth.uid(), target_team_id, target_event_id,
    case when resource.requires_approval and actor_role <> 'admin' then null else auth.uid() end,
    case when resource.requires_approval and actor_role <> 'admin' then null else now() end)
  returning * into created;
  if created.status = 'pending' then
    perform internal.booking_notify(created.id, 'requested',
      array(select profile_id from internal.booking_admin_profiles(resource.organization_id)));
  end if;
  return internal.booking_json(created, actor_role);
end;
$$;

create or replace function internal.create_booking_group_for_actor(
  target_resource_ids uuid[], booking_starts_at timestamptz, booking_ends_at timestamptz,
  booking_title text, booking_notes text, target_team_id uuid, target_event_id uuid, dry_run boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  organization uuid;
  actor_role text;
  resource core.booking_resources;
  new_group uuid := gen_random_uuid();
  items jsonb := '[]'::jsonb;
  busy boolean;
  any_busy boolean := false;
  status text;
  first_pending uuid;
  created_id uuid;
begin
  if target_resource_ids is null or cardinality(target_resource_ids) not between 1 and 10
    or (select count(distinct value) from unnest(target_resource_ids) value) <> cardinality(target_resource_ids) then
    raise invalid_parameter_value using message = 'invalid_resources';
  end if;
  select min(organization_id::text)::uuid, count(distinct organization_id) = 1 and count(*) = cardinality(target_resource_ids)
  into organization, busy
  from core.booking_resources where id = any(target_resource_ids);
  if not coalesce(busy, false) then raise invalid_parameter_value using message = 'invalid_resources'; end if;
  actor_role := internal.booking_actor_role(organization);
  if actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  if booking_ends_at <= booking_starts_at or booking_ends_at - booking_starts_at > interval '31 days' then
    raise invalid_parameter_value using message = 'invalid_time';
  end if;
  if booking_ends_at <= now() then raise invalid_parameter_value using message = 'in_the_past'; end if;
  if target_team_id is not null and not internal.booking_actor_can_book_team(organization, target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  if target_event_id is not null then
    if not exists (select 1 from core.events e join core.booking_organizations o on o.teamzone_club_id = e.club_id where e.id = target_event_id and o.id = organization and e.archived_at is null and e.state in ('draft', 'scheduled')) then raise insufficient_privilege using message = 'event_not_found'; end if;
    if target_team_id is null then raise invalid_parameter_value using message = 'event_needs_team'; end if;
    if not exists (select 1 from core.events where id = target_event_id) or not internal.actor_can_read_event(target_event_id)
      or not exists (select 1 from core.event_teams relation where relation.event_id = target_event_id and relation.team_id = target_team_id) then
      raise insufficient_privilege using message = 'event_not_found';
    end if;
  end if;
  perform 1 from core.booking_resources where id = any(target_resource_ids) order by id for share;
  -- Locks in a fixed order, so two groups cannot wait for each other.
  perform pg_advisory_xact_lock(hashtextextended(value::text, 0))
  from unnest(target_resource_ids) value order by value;
  for resource in select * from core.booking_resources where id = any(target_resource_ids) order by category, name loop
    busy := not resource.active or exists (select 1 from core.booking_bookings other
      where other.resource_id = resource.id and other.status in ('pending', 'confirmed')
        and other.starts_at < booking_ends_at and other.ends_at > booking_starts_at);
    any_busy := any_busy or busy;
    items := items || jsonb_build_object('resource_id', resource.id, 'name', resource.name, 'busy', busy,
      'requires_approval', resource.requires_approval and actor_role <> 'admin');
  end loop;
  if dry_run then return jsonb_build_object('group_id', null, 'items', items); end if;
  if any_busy then raise exclusion_violation using message = 'resource_busy'; end if;
  for resource in select * from core.booking_resources where id = any(target_resource_ids) order by category, name loop
    status := case when resource.requires_approval and actor_role <> 'admin' then 'pending' else 'confirmed' end;
    insert into core.booking_bookings (organization_id, resource_id, starts_at, ends_at, title, notes, status, booked_by,
      team_id, event_id, group_id, decided_by, decided_at)
    values (organization, resource.id, booking_starts_at, booking_ends_at, nullif(btrim(booking_title), ''),
      nullif(btrim(booking_notes), ''), status, auth.uid(), target_team_id, target_event_id, new_group,
      case when status = 'confirmed' then auth.uid() end, case when status = 'confirmed' then now() end)
    returning id into created_id;
    if status = 'pending' and first_pending is null then first_pending := created_id; end if;
  end loop;
  -- One request for the group's resources that need approval.
  if first_pending is not null then
    perform internal.booking_notify(first_pending, 'requested',
      array(select profile_id from internal.booking_admin_profiles(organization)));
  end if;
  return jsonb_build_object('group_id', new_group, 'items', items,
    'pending', (select count(*) from core.booking_bookings b where b.group_id = new_group and b.status = 'pending'));
end;
$$;

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
  select * into resource from core.booking_resources where id = target_resource_id for share;
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
  if target_team_id is not null and not internal.booking_actor_can_book_team(resource.organization_id, target_team_id) then
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

create or replace function internal.decide_booking_for_actor(target_booking_id uuid, approve boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare booking core.booking_bookings;
begin
  perform 1 from core.booking_bookings where id = target_booking_id order by id for update;
  select * into booking from core.booking_bookings where id = target_booking_id;
  if booking.id is null or internal.booking_actor_role(booking.organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  if booking.status <> 'pending' or booking.ends_at <= now() then raise invalid_parameter_value using message = 'not_pending'; end if;
  update core.booking_bookings set status = case when approve then 'confirmed' else 'declined' end,
    decided_by = auth.uid(), decided_at = now(), revision = revision + 1
  where id = target_booking_id;
  if not found then raise invalid_parameter_value using message = 'not_pending'; end if;
  perform internal.booking_notify(booking.id, case when approve then 'approved' else 'declined' end, array[booking.booked_by]);
end;
$$;

create or replace function internal.cancel_booking_for_actor(target_booking_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare booking core.booking_bookings;
begin
  perform 1 from core.booking_bookings where id = target_booking_id order by id for update;
  select * into booking from core.booking_bookings where id = target_booking_id;
  if booking.id is null or (internal.booking_actor_role(booking.organization_id) is null
    and not internal.booking_actor_leads_team(booking.organization_id, booking.team_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if booking.status not in ('pending', 'confirmed') then raise invalid_parameter_value using message = 'not_active'; end if;
  if not internal.booking_actor_can_cancel(booking) then
    raise insufficient_privilege using message = 'not_allowed';
  end if;
  update core.booking_bookings set status = 'cancelled', revision = revision + 1 where id = target_booking_id;
  if booking.booked_by <> auth.uid() then
    perform internal.booking_notify(booking.id, 'cancelled', array[booking.booked_by]);
  end if;
end;
$$;

create or replace function internal.decide_booking_group_for_actor(target_group_id uuid, approve boolean)
returns integer language plpgsql security definer set search_path = '' as $$
declare first_booking core.booking_bookings; changed integer;
begin
  perform 1 from core.booking_bookings where group_id = target_group_id order by id for update;
  select * into first_booking from core.booking_bookings
  where group_id = target_group_id and status = 'pending' and ends_at > now() order by created_at limit 1;
  if first_booking.id is null then raise invalid_parameter_value using message = 'not_pending'; end if;
  if internal.booking_actor_role(first_booking.organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  update core.booking_bookings set status = case when approve then 'confirmed' else 'declined' end,
    decided_by = auth.uid(), decided_at = now(), revision = revision + 1
  where group_id = target_group_id and status = 'pending' and ends_at > now();
  get diagnostics changed = row_count;
  if changed = 0 then raise invalid_parameter_value using message = 'not_pending'; end if;
  perform internal.booking_notify(first_booking.id, case when approve then 'approved' else 'declined' end, array[first_booking.booked_by]);
  return changed;
end;
$$;

create or replace function internal.cancel_booking_group_for_actor(target_group_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare first_booking core.booking_bookings; changed integer;
begin
  perform 1 from core.booking_bookings where group_id = target_group_id order by id for update;
  select * into first_booking from core.booking_bookings
  where group_id = target_group_id and status in ('pending', 'confirmed') and ends_at > now() order by created_at limit 1;
  if first_booking.id is null or (internal.booking_actor_role(first_booking.organization_id) is null
    and not internal.booking_actor_leads_team(first_booking.organization_id, first_booking.team_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if not internal.booking_actor_can_cancel(first_booking) then
    raise insufficient_privilege using message = 'not_allowed';
  end if;
  update core.booking_bookings set status = 'cancelled', revision = revision + 1
  where group_id = target_group_id and status in ('pending', 'confirmed') and ends_at > now();
  get diagnostics changed = row_count;
  if first_booking.booked_by <> auth.uid() then
    perform internal.booking_notify(first_booking.id, 'cancelled', array[first_booking.booked_by]);
  end if;
  return changed;
end;
$$;

create or replace function internal.decide_booking_series_for_actor(target_series_id uuid, approve boolean)
returns integer language plpgsql security definer set search_path = '' as $$
declare series core.booking_series; changed integer; first_booking uuid;
begin
  perform 1 from core.booking_bookings where series_id = target_series_id order by id for update;
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

create or replace function internal.cancel_booking_series_for_actor(target_series_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare series core.booking_series; changed integer; first_booking uuid;
begin
  perform 1 from core.booking_bookings where series_id = target_series_id order by id for update;
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

create or replace function internal.get_booking_organization_for_actor(target_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor_role text := internal.booking_actor_role(target_organization_id);
begin
  if actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  return (
    select jsonb_build_object(
      'id', org.id, 'name', org.name, 'kind', org.kind, 'sport', org.sport,
      'teamzone_club_id', org.teamzone_club_id,
      'teamzone_club_name', (select club.name from core.clubs club where club.id = org.teamzone_club_id),
      'club_members_can_book', org.club_members_can_book,
      'role', actor_role,
      'resources', coalesce((select jsonb_agg(jsonb_build_object(
          'id', resource.id, 'name', resource.name, 'category', resource.category,
          'description', resource.description, 'location', resource.location,
          'capacity', resource.capacity, 'requires_approval', resource.requires_approval,
          'active', resource.active, 'revision', resource.revision
        ) order by resource.active desc, resource.category, resource.name)
        from core.booking_resources resource
        where resource.organization_id = org.id and (resource.active or actor_role = 'admin')), '[]'::jsonb),
      'members', case when actor_role = 'admin' then coalesce((select jsonb_agg(jsonb_build_object(
          'profile_id', member.profile_id, 'name', internal.booking_person_name(member.profile_id),
          'role', member.role, 'is_self', member.profile_id = auth.uid()
        ) order by member.role, internal.booking_person_name(member.profile_id))
        from core.booking_members member where member.organization_id = org.id), '[]'::jsonb) end,
      'teams', coalesce((select jsonb_agg(jsonb_build_object('team_id', t.team_id, 'name', t.team_name) order by t.team_name)
        from (select team.id team_id, team.name team_name from core.teams team where team.club_id = org.teamzone_club_id and team.status = 'active' and internal.booking_actor_can_book_team(org.id, team.id)) t), '[]'::jsonb),
      'pending_count', case when actor_role = 'admin' then (select count(*) from core.booking_bookings booking
        where booking.organization_id = org.id and booking.status = 'pending' and booking.ends_at > now()) end
    )
    from core.booking_organizations org where org.id = target_organization_id
  );
end;
$$;

create or replace function internal.list_booking_team_events_for_actor(target_organization_id uuid, target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.booking_actor_can_book_team(target_organization_id, target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'event_id', event_row.id, 'title', event_row.title, 'event_type', event_row.event_type,
      'starts_at', event_row.starts_at, 'ends_at', event_row.ends_at,
      'home_away', event_row.home_away, 'opponent_name', event_row.opponent_name
    ) order by event_row.starts_at)
    from core.events event_row
    join core.event_teams relation on relation.event_id = event_row.id and relation.team_id = target_team_id
    where event_row.state in ('draft', 'scheduled') and event_row.archived_at is null
      and internal.actor_can_read_event(event_row.id)
      and event_row.ends_at > now() and event_row.starts_at < now() + interval '60 days'), '[]'::jsonb);
end;
$$;

create or replace function internal.list_event_booking_targets_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_can_read_event(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'organization_id', org.id, 'name', org.name,
      'team_id', (select relation.team_id from core.event_teams relation join core.teams team on team.id = relation.team_id where relation.event_id = target_event_id and internal.booking_actor_can_book_team(org.id, relation.team_id) order by team.name, team.id limit 1)
    ) order by org.name)
    from core.booking_organizations org
    join core.events event_row on event_row.id = target_event_id and event_row.club_id = org.teamzone_club_id
    where internal.booking_actor_role(org.id) is not null and event_row.archived_at is null and event_row.state in ('draft', 'scheduled') and exists (select 1 from core.event_teams r where r.event_id = target_event_id and internal.booking_actor_can_book_team(org.id, r.team_id))), '[]'::jsonb);
end;
$$;


-- Revision vectors include every member of a series/group, including terminal
-- members. The same vector travels with each row, including the Flutter view.
create function internal.booking_revision_vector(booking core.booking_bookings)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_object_agg(b.id::text, b.revision) from core.booking_bookings b
  where b.id = booking.id or (booking.group_id is not null and b.group_id = booking.group_id)
    or (booking.series_id is not null and b.series_id = booking.series_id)
$$;
revoke all on function internal.booking_revision_vector(core.booking_bookings) from public, anon, authenticated;


create or replace function internal.booking_json(booking core.booking_bookings, actor_role text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', booking.id, 'revision', booking.revision, 'revisions', internal.booking_revision_vector(booking), 'resource_id', booking.resource_id,
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
    'group_id', booking.group_id,
    'group_resources', case when booking.group_id is null then null else (select jsonb_agg(resource.name order by resource.name)
      from core.booking_bookings other join core.booking_resources resource on resource.id = other.resource_id
      where other.group_id = booking.group_id and other.status in ('pending', 'confirmed')) end,
    'can_cancel', internal.booking_actor_can_cancel(booking),
    'can_decide', booking.status = 'pending' and actor_role = 'admin' and booking.ends_at > now()
  )
$$;

create or replace function internal.list_event_bookings_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_can_read_event(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', booking.id, 'revision', booking.revision, 'revisions', internal.booking_revision_vector(booking), 'resource_name', resource.name, 'category', resource.category,
      'organization_name', org.name, 'starts_at', booking.starts_at, 'ends_at', booking.ends_at,
      'status', booking.status, 'title', booking.title, 'group_id', booking.group_id,
      'can_cancel', internal.booking_actor_can_cancel(booking)
    ) order by booking.starts_at, resource.name)
    from core.booking_bookings booking
    join core.booking_resources resource on resource.id = booking.resource_id
    join core.booking_organizations org on org.id = booking.organization_id
    where booking.event_id = target_event_id and booking.status in ('pending', 'confirmed')), '[]'::jsonb);
end;
$$;


create table internal.booking_commands (
  actor_id uuid not null,
  command_id uuid not null,
  command_type text not null,
  payload jsonb not null,
  expected_revisions jsonb,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key(actor_id, command_id)
);
alter table internal.booking_commands enable row level security;
revoke all on internal.booking_commands from public, anon, authenticated;

create function internal.execute_booking_command_for_actor(
  command_id uuid, command_type text, payload jsonb, expected_revisions jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid(); prior internal.booking_commands; result jsonb;
  target uuid; affected uuid[]; actual jsonb; p jsonb := payload;
begin
  if actor is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if command_id is null or jsonb_typeof(p) is distinct from 'object' then
    raise invalid_parameter_value using message = 'invalid_command'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text || command_id::text, 1));
  select * into prior from internal.booking_commands c where c.actor_id = actor and c.command_id = execute_booking_command_for_actor.command_id;
  if found then
    if prior.command_type is distinct from command_type or prior.payload is distinct from p
      or prior.expected_revisions is distinct from expected_revisions then
      raise invalid_parameter_value using message = 'idempotency_conflict'; end if;
    return prior.result;
  end if;
  if command_type in ('cancel_booking', 'decide_booking', 'cancel_booking_group', 'decide_booking_group', 'cancel_booking_series', 'decide_booking_series') then
    target := coalesce(p->>'target_booking_id', p->>'target_group_id', p->>'target_series_id')::uuid;
    select array_agg(b.id order by b.id) into affected from core.booking_bookings b
    where (command_type in ('cancel_booking', 'decide_booking') and b.id = target)
      or (command_type in ('cancel_booking_group', 'decide_booking_group') and b.group_id = target)
      or (command_type in ('cancel_booking_series', 'decide_booking_series') and b.series_id = target);
    if affected is null then raise insufficient_privilege using message = 'not_found'; end if;
    -- Authorize before exposing whether a revision is stale.
    if exists (select 1 from core.booking_bookings b where b.id = any(affected) and
      case when command_type like 'decide_%' then internal.booking_actor_role(b.organization_id) is distinct from 'admin'
      else (internal.booking_actor_role(b.organization_id) is null and not internal.booking_actor_leads_team(b.organization_id,b.team_id))
        or not (b.booked_by = actor or internal.booking_actor_role(b.organization_id) = 'admin' or internal.booking_actor_leads_team(b.organization_id,b.team_id)) end)
    then raise insufficient_privilege using message = 'not_allowed'; end if;
    perform 1 from core.booking_bookings b where b.id = any(affected) order by b.id for update;
    select jsonb_object_agg(b.id::text, b.revision) into actual from core.booking_bookings b where b.id = any(affected);
    if expected_revisions is null then raise invalid_parameter_value using message = 'revision_required'; end if;
    if actual is distinct from expected_revisions then raise sqlstate 'PT409' using message = 'stale_revision'; end if;
  end if;
  case command_type
    when 'create_booking' then
      result := internal.create_booking_for_actor((p->>'target_resource_id')::uuid, (p->>'booking_starts_at')::timestamptz,
        (p->>'booking_ends_at')::timestamptz,p->>'booking_title',p->>'booking_notes',(p->>'target_team_id')::uuid,(p->>'target_event_id')::uuid);
    when 'create_booking_group' then
      if coalesce((p->>'dry_run')::boolean,false) then raise invalid_parameter_value using message='invalid_command'; end if;
      result := internal.create_booking_group_for_actor(array(select value::uuid from jsonb_array_elements_text(p->'target_resource_ids')),
        (p->>'booking_starts_at')::timestamptz,(p->>'booking_ends_at')::timestamptz,p->>'booking_title',p->>'booking_notes',
        (p->>'target_team_id')::uuid,(p->>'target_event_id')::uuid,false);
    when 'create_booking_series' then
      if coalesce((p->>'dry_run')::boolean,false) then raise invalid_parameter_value using message='invalid_command'; end if;
      result := internal.create_booking_series_for_actor((p->>'target_resource_id')::uuid,
        array(select value::smallint from jsonb_array_elements_text(p->'series_weekdays')),(p->>'series_interval')::smallint,
        (p->>'first_day')::date,(p->>'last_day')::date,(p->>'start_at')::time,(p->>'end_at')::time,p->>'zone',
        p->>'booking_title',p->>'booking_notes',(p->>'target_team_id')::uuid,false);
    when 'cancel_booking' then perform internal.cancel_booking_for_actor(target); result := 'null'::jsonb;
    when 'decide_booking' then
      if p->>'approve' is null then raise invalid_parameter_value using message='invalid_command'; end if;
      perform internal.decide_booking_for_actor(target,(p->>'approve')::boolean); result := 'null'::jsonb;
    when 'cancel_booking_group' then result := to_jsonb(internal.cancel_booking_group_for_actor(target));
    when 'decide_booking_group' then
      if p->>'approve' is null then raise invalid_parameter_value using message='invalid_command'; end if;
      result := to_jsonb(internal.decide_booking_group_for_actor(target,(p->>'approve')::boolean));
    when 'cancel_booking_series' then result := to_jsonb(internal.cancel_booking_series_for_actor(target));
    when 'decide_booking_series' then
      if p->>'approve' is null then raise invalid_parameter_value using message='invalid_command'; end if;
      result := to_jsonb(internal.decide_booking_series_for_actor(target,(p->>'approve')::boolean));
    else raise invalid_parameter_value using message = 'invalid_command';
  end case;
  insert into internal.booking_commands(actor_id,command_id,command_type,payload,expected_revisions,result)
    values(actor,command_id,command_type,p,expected_revisions,result);
  return result;
end; $$;

create function api.execute_booking_command(command_id uuid, command_type text, payload jsonb, expected_revisions jsonb default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select internal.execute_booking_command_for_actor(command_id,command_type,payload,expected_revisions)
$$;
revoke all on function internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb),
  api.execute_booking_command(uuid,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb),
  api.execute_booking_command(uuid,text,jsonb,jsonb) to authenticated;

create function api.list_booking_history(target_booking_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare org uuid;
begin
  select organization_id into org from core.booking_bookings where id = target_booking_id;
  if internal.booking_actor_role(org) is distinct from 'admin' then raise insufficient_privilege using message = 'not_found'; end if;
  return coalesce((select jsonb_agg(to_jsonb(a) order by a.id) from internal.booking_audit a where a.booking_id = target_booking_id),'[]'::jsonb);
end; $$;
revoke all on function api.list_booking_history(uuid) from public, anon, authenticated;
grant execute on function api.list_booking_history(uuid) to authenticated;
