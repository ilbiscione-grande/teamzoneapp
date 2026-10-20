-- Webtools Bokningshanterare: organisations own bookable resources (pitches,
-- locker rooms, minibuses, cameras...). It works without TeamZone: members
-- are invited by link. An organisation may be linked to a TeamZone club,
-- whose leaders and club functionaries then book without an invitation,
-- for one of their teams and, if they like, for one of its activities. The
-- activity shows its bookings in the app.

create table core.booking_organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 120),
  kind text not null default 'club' check (kind in ('club', 'association', 'company', 'school', 'other')),
  sport text check (sport is null or length(btrim(sport)) between 1 and 60),
  teamzone_club_id uuid unique references core.clubs(id),
  -- With a club link: the club's leaders and functionaries may book.
  club_members_can_book boolean not null default true,
  created_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0)
);

create table core.booking_members (
  organization_id uuid not null references core.booking_organizations(id) on delete cascade,
  profile_id uuid not null references core.profiles(id),
  role text not null check (role in ('admin', 'booker')),
  created_at timestamptz not null default now(),
  primary key (organization_id, profile_id)
);

create table core.booking_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references core.booking_organizations(id) on delete cascade,
  role text not null check (role in ('admin', 'booker')),
  token_hash bytea not null unique,
  created_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_by uuid references core.profiles(id),
  accepted_at timestamptz,
  revoked_at timestamptz
);

create table core.booking_resources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references core.booking_organizations(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  category text not null check (category in ('pitch', 'hall', 'locker_room', 'vehicle', 'equipment', 'room', 'other')),
  description text check (description is null or length(description) <= 2000),
  location text check (location is null or length(location) <= 200),
  capacity integer check (capacity is null or capacity between 1 and 10000),
  requires_approval boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (id, organization_id)
);

create table core.booking_bookings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  resource_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  title text check (title is null or length(btrim(title)) between 1 and 160),
  notes text check (notes is null or length(notes) <= 2000),
  status text not null check (status in ('pending', 'confirmed', 'declined', 'cancelled')),
  booked_by uuid not null references core.profiles(id),
  -- TeamZone: the team the booking is for and, optionally, its activity.
  team_id uuid references core.teams(id),
  event_id uuid references core.events(id),
  decided_by uuid references core.profiles(id),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  foreign key (resource_id, organization_id) references core.booking_resources(id, organization_id) on delete cascade,
  check (ends_at > starts_at),
  check (ends_at - starts_at <= interval '31 days'),
  check (event_id is null or team_id is not null)
);
create index booking_bookings_resource_time on core.booking_bookings (resource_id, starts_at);
create index booking_bookings_org_time on core.booking_bookings (organization_id, starts_at);
create index booking_bookings_event on core.booking_bookings (event_id) where event_id is not null;

alter table core.booking_organizations enable row level security;
alter table core.booking_members enable row level security;
alter table core.booking_invitations enable row level security;
alter table core.booking_resources enable row level security;
alter table core.booking_bookings enable row level security;
revoke all on core.booking_organizations, core.booking_members, core.booking_invitations,
  core.booking_resources, core.booking_bookings from public, anon, authenticated;

-- Your role in an organisation: admin or booker by membership; through the
-- club link, club admins are admins and leaders or functionaries bookers.
create or replace function internal.booking_actor_role(target_organization_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when auth.uid() is null then null
    when exists (select 1 from core.booking_members member
      where member.organization_id = target_organization_id and member.profile_id = auth.uid() and member.role = 'admin')
      then 'admin'
    when exists (select 1 from core.booking_organizations org
      where org.id = target_organization_id and org.teamzone_club_id is not null
        and internal.actor_has_capability(org.teamzone_club_id, null, 'club.memberships.manage'))
      then 'admin'
    when exists (select 1 from core.booking_members member
      where member.organization_id = target_organization_id and member.profile_id = auth.uid())
      then 'booker'
    when exists (select 1 from core.booking_organizations org
      join core.person_account_links link on link.club_id = org.teamzone_club_id
        and link.profile_id = auth.uid() and link.state = 'active'
      join core.assignments assignment on assignment.club_id = link.club_id
        and assignment.club_person_id = link.club_person_id and assignment.state = 'active'
        and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
        and assignment.role_package in ('leader', 'club_functionary')
      where org.id = target_organization_id and org.club_members_can_book)
      then 'booker'
  end
$$;

-- Teams you lead in the organisation's linked club.
create or replace function internal.booking_actor_teams(target_organization_id uuid)
returns table(team_id uuid, team_name text) language sql stable security definer set search_path = '' as $$
  select distinct team.id, team.name
  from core.booking_organizations org
  join core.person_account_links link on link.club_id = org.teamzone_club_id
    and link.profile_id = auth.uid() and link.state = 'active'
  join core.assignments assignment on assignment.club_id = link.club_id
    and assignment.club_person_id = link.club_person_id and assignment.state = 'active'
    and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
    and assignment.role_package = 'leader'
  join core.teams team on team.id = assignment.team_id and team.club_id = org.teamzone_club_id and team.status = 'active'
  where org.id = target_organization_id
$$;

create or replace function internal.booking_person_name(target_profile_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(
    nullif(btrim(profile.display_name), ''),
    (select person.display_name from core.person_account_links link
      join core.club_people person on person.id = link.club_person_id
      where link.profile_id = profile.id and link.state = 'active'
      order by link.club_id limit 1),
    split_part((select users.email from auth.users users where users.id = profile.id), '@', 1)
  )
  from core.profiles profile where profile.id = target_profile_id
$$;

create or replace function internal.list_booking_organizations_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', org.id, 'name', org.name, 'kind', org.kind, 'sport', org.sport,
    'teamzone_club_id', org.teamzone_club_id,
    'teamzone_club_name', (select club.name from core.clubs club where club.id = org.teamzone_club_id),
    'role', internal.booking_actor_role(org.id)
  ) order by org.name), '[]'::jsonb)
  from core.booking_organizations org
  where internal.booking_actor_role(org.id) is not null
$$;

create or replace function internal.create_booking_organization_for_actor(org_name text, org_kind text, org_sport text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare created uuid;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  insert into core.booking_organizations (name, kind, sport, created_by)
  values (btrim(org_name), coalesce(org_kind, 'club'), nullif(btrim(org_sport), ''), auth.uid())
  returning id into created;
  insert into core.booking_members (organization_id, profile_id, role) values (created, auth.uid(), 'admin');
  return created;
end;
$$;

create or replace function internal.update_booking_organization_for_actor(
  target_organization_id uuid, org_name text, org_kind text, org_sport text, members_can_book boolean
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if internal.booking_actor_role(target_organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  update core.booking_organizations set
    name = btrim(org_name), kind = org_kind, sport = nullif(btrim(org_sport), ''),
    club_members_can_book = coalesce(members_can_book, club_members_can_book),
    revision = revision + 1
  where id = target_organization_id;
end;
$$;

-- The link needs both: admin of the organisation and admin of the club.
create or replace function internal.set_booking_organization_club_for_actor(target_organization_id uuid, target_club_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare current_club uuid;
begin
  if internal.booking_actor_role(target_organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  select teamzone_club_id into current_club from core.booking_organizations where id = target_organization_id;
  if target_club_id is not null and not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_club_admin';
  end if;
  if target_club_id is null and current_club is not null
    and not internal.actor_has_capability(current_club, null, 'club.memberships.manage')
    and not exists (select 1 from core.booking_members member where member.organization_id = target_organization_id
      and member.profile_id = auth.uid() and member.role = 'admin') then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  if target_club_id is not null and exists (select 1 from core.booking_organizations
    where teamzone_club_id = target_club_id and id <> target_organization_id) then
    raise unique_violation using message = 'club_already_linked';
  end if;
  update core.booking_organizations set teamzone_club_id = target_club_id, revision = revision + 1
  where id = target_organization_id;
  -- Bookings for teams of another club no longer belong here.
  if target_club_id is distinct from current_club then
    update core.booking_bookings set team_id = null, event_id = null, revision = revision + 1
    where organization_id = target_organization_id and team_id is not null;
  end if;
end;
$$;

-- The clubs you administer, to offer for a link.
create or replace function internal.list_booking_linkable_clubs_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('club_id', club.id, 'name', club.name) order by club.name), '[]'::jsonb)
  from core.clubs club
  where internal.actor_has_capability(club.id, null, 'club.memberships.manage')
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
        from internal.booking_actor_teams(org.id) t), '[]'::jsonb),
      'pending_count', case when actor_role = 'admin' then (select count(*) from core.booking_bookings booking
        where booking.organization_id = org.id and booking.status = 'pending' and booking.ends_at > now()) end
    )
    from core.booking_organizations org where org.id = target_organization_id
  );
end;
$$;

create or replace function internal.save_booking_resource_for_actor(
  target_organization_id uuid, target_resource_id uuid, resource_name text, resource_category text,
  resource_description text, resource_location text, resource_capacity integer,
  resource_requires_approval boolean, resource_active boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare saved uuid;
begin
  if internal.booking_actor_role(target_organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  if target_resource_id is null then
    insert into core.booking_resources (organization_id, name, category, description, location, capacity, requires_approval, active)
    values (target_organization_id, btrim(resource_name), resource_category, nullif(btrim(resource_description), ''),
      nullif(btrim(resource_location), ''), resource_capacity, coalesce(resource_requires_approval, false), coalesce(resource_active, true))
    returning id into saved;
  else
    update core.booking_resources set
      name = btrim(resource_name), category = resource_category,
      description = nullif(btrim(resource_description), ''), location = nullif(btrim(resource_location), ''),
      capacity = resource_capacity, requires_approval = coalesce(resource_requires_approval, false),
      active = coalesce(resource_active, true), revision = revision + 1
    where id = target_resource_id and organization_id = target_organization_id
    returning id into saved;
    if saved is null then raise insufficient_privilege using message = 'not_found'; end if;
  end if;
  return saved;
end;
$$;

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
    'can_cancel', booking.status in ('pending', 'confirmed') and booking.ends_at > now()
      and (booking.booked_by = auth.uid() or actor_role = 'admin'),
    'can_decide', booking.status = 'pending' and actor_role = 'admin' and booking.ends_at > now()
  )
$$;

create or replace function internal.list_bookings_for_actor(target_organization_id uuid, range_start timestamptz, range_end timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor_role text := internal.booking_actor_role(target_organization_id);
begin
  if actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  if range_end <= range_start or range_end - range_start > interval '62 days' then
    raise invalid_parameter_value using message = 'invalid_range';
  end if;
  return coalesce((select jsonb_agg(internal.booking_json(booking, actor_role) order by booking.starts_at)
    from core.booking_bookings booking
    where booking.organization_id = target_organization_id
      and booking.status in ('pending', 'confirmed')
      and booking.starts_at < range_end and booking.ends_at > range_start), '[]'::jsonb);
end;
$$;

-- Pending requests to decide, for admins.
create or replace function internal.list_pending_bookings_for_actor(target_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if internal.booking_actor_role(target_organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  return coalesce((select jsonb_agg(internal.booking_json(booking, 'admin') order by booking.starts_at)
    from core.booking_bookings booking
    where booking.organization_id = target_organization_id and booking.status = 'pending' and booking.ends_at > now()), '[]'::jsonb);
end;
$$;

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
  select * into resource from core.booking_resources where id = target_resource_id;
  actor_role := internal.booking_actor_role(resource.organization_id);
  if resource.id is null or actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  if not resource.active then raise invalid_parameter_value using message = 'resource_inactive'; end if;
  if booking_ends_at <= booking_starts_at or booking_ends_at - booking_starts_at > interval '31 days' then
    raise invalid_parameter_value using message = 'invalid_time';
  end if;
  if booking_ends_at <= now() then raise invalid_parameter_value using message = 'in_the_past'; end if;
  if target_team_id is not null and not exists (
    select 1 from internal.booking_actor_teams(resource.organization_id) t where t.team_id = target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  if target_event_id is not null then
    if target_team_id is null then raise invalid_parameter_value using message = 'event_needs_team'; end if;
    select * into event_row from core.events where id = target_event_id;
    if event_row.id is null or not internal.actor_can_read_event(target_event_id)
      or not exists (select 1 from core.event_teams relation where relation.event_id = target_event_id and relation.team_id = target_team_id) then
      raise insufficient_privilege using message = 'event_not_found';
    end if;
  end if;
  -- One booking at a time per resource: no two can slip past the check.
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
  return internal.booking_json(created, actor_role);
end;
$$;

create or replace function internal.cancel_booking_for_actor(target_booking_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare booking core.booking_bookings;
begin
  select * into booking from core.booking_bookings where id = target_booking_id;
  if booking.id is null or internal.booking_actor_role(booking.organization_id) is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if booking.booked_by <> auth.uid() and internal.booking_actor_role(booking.organization_id) <> 'admin' then
    raise insufficient_privilege using message = 'not_allowed';
  end if;
  if booking.status not in ('pending', 'confirmed') then raise invalid_parameter_value using message = 'not_active'; end if;
  update core.booking_bookings set status = 'cancelled', revision = revision + 1 where id = target_booking_id;
end;
$$;

create or replace function internal.decide_booking_for_actor(target_booking_id uuid, approve boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare booking core.booking_bookings;
begin
  select * into booking from core.booking_bookings where id = target_booking_id;
  if booking.id is null or internal.booking_actor_role(booking.organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  if booking.status <> 'pending' then raise invalid_parameter_value using message = 'not_pending'; end if;
  update core.booking_bookings set status = case when approve then 'confirmed' else 'declined' end,
    decided_by = auth.uid(), decided_at = now(), revision = revision + 1
  where id = target_booking_id;
end;
$$;

-- Invitations are links: the token is shown once, only its hash is kept.
create or replace function internal.create_booking_invitation_for_actor(target_organization_id uuid, invite_role text)
returns text language plpgsql security definer set search_path = '' as $$
declare token text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  if internal.booking_actor_role(target_organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  insert into core.booking_invitations (organization_id, role, token_hash, created_by, expires_at)
  values (target_organization_id, coalesce(invite_role, 'booker'), sha256(convert_to(token, 'UTF8')), auth.uid(), now() + interval '14 days');
  return token;
end;
$$;

create or replace function internal.accept_booking_invitation_for_actor(invite_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare invitation core.booking_invitations;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into invitation from core.booking_invitations
  where token_hash = sha256(convert_to(coalesce(invite_token, ''), 'UTF8')) for update;
  if invitation.id is null or invitation.revoked_at is not null or invitation.expires_at <= now()
    or (invitation.accepted_at is not null and invitation.accepted_by <> auth.uid()) then
    raise invalid_parameter_value using message = 'invitation_invalid';
  end if;
  insert into core.booking_members (organization_id, profile_id, role)
  values (invitation.organization_id, auth.uid(), invitation.role)
  on conflict (organization_id, profile_id) do update
    set role = case when core.booking_members.role = 'admin' then 'admin' else excluded.role end;
  update core.booking_invitations set accepted_by = auth.uid(), accepted_at = coalesce(accepted_at, now())
  where id = invitation.id;
  return invitation.organization_id;
end;
$$;

create or replace function internal.set_booking_member_for_actor(target_organization_id uuid, target_profile_id uuid, member_role text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if internal.booking_actor_role(target_organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  if target_profile_id = auth.uid() then raise invalid_parameter_value using message = 'not_self'; end if;
  if member_role is null then
    delete from core.booking_members where organization_id = target_organization_id and profile_id = target_profile_id;
  else
    update core.booking_members set role = member_role
    where organization_id = target_organization_id and profile_id = target_profile_id;
  end if;
end;
$$;

-- For the booking form: your teams in the linked club and their activities
-- in the coming days, to attach a booking to.
create or replace function internal.list_booking_team_events_for_actor(target_organization_id uuid, target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from internal.booking_actor_teams(target_organization_id) t where t.team_id = target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'event_id', event_row.id, 'title', event_row.title, 'event_type', event_row.event_type,
      'starts_at', event_row.starts_at, 'ends_at', event_row.ends_at
    ) order by event_row.starts_at)
    from core.events event_row
    join core.event_teams relation on relation.event_id = event_row.id and relation.team_id = target_team_id
    where event_row.state in ('draft', 'scheduled') and event_row.archived_at is null
      and event_row.ends_at > now() and event_row.starts_at < now() + interval '60 days'), '[]'::jsonb);
end;
$$;

-- The app: an activity's bookings, for those who see the activity.
create or replace function internal.list_event_bookings_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_can_read_event(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', booking.id, 'resource_name', resource.name, 'category', resource.category,
      'organization_name', org.name, 'starts_at', booking.starts_at, 'ends_at', booking.ends_at,
      'status', booking.status, 'title', booking.title
    ) order by booking.starts_at)
    from core.booking_bookings booking
    join core.booking_resources resource on resource.id = booking.resource_id
    join core.booking_organizations org on org.id = booking.organization_id
    where booking.event_id = target_event_id and booking.status in ('pending', 'confirmed')), '[]'::jsonb);
end;
$$;

create or replace function api.list_booking_organizations() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_booking_organizations_for_actor() $$;
create or replace function api.create_booking_organization(org_name text, org_kind text, org_sport text) returns uuid language sql security invoker set search_path = '' as
$$ select internal.create_booking_organization_for_actor(org_name, org_kind, org_sport) $$;
create or replace function api.update_booking_organization(target_organization_id uuid, org_name text, org_kind text, org_sport text, members_can_book boolean)
returns void language sql security invoker set search_path = '' as
$$ select internal.update_booking_organization_for_actor(target_organization_id, org_name, org_kind, org_sport, members_can_book) $$;
create or replace function api.set_booking_organization_club(target_organization_id uuid, target_club_id uuid) returns void language sql security invoker set search_path = '' as
$$ select internal.set_booking_organization_club_for_actor(target_organization_id, target_club_id) $$;
create or replace function api.list_booking_linkable_clubs() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_booking_linkable_clubs_for_actor() $$;
create or replace function api.get_booking_organization(target_organization_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.get_booking_organization_for_actor(target_organization_id) $$;
create or replace function api.save_booking_resource(
  target_organization_id uuid, target_resource_id uuid, resource_name text, resource_category text,
  resource_description text, resource_location text, resource_capacity integer,
  resource_requires_approval boolean, resource_active boolean
) returns uuid language sql security invoker set search_path = '' as
$$ select internal.save_booking_resource_for_actor(target_organization_id, target_resource_id, resource_name, resource_category,
  resource_description, resource_location, resource_capacity, resource_requires_approval, resource_active) $$;
create or replace function api.list_bookings(target_organization_id uuid, range_start timestamptz, range_end timestamptz) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_bookings_for_actor(target_organization_id, range_start, range_end) $$;
create or replace function api.list_pending_bookings(target_organization_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_pending_bookings_for_actor(target_organization_id) $$;
create or replace function api.create_booking(
  target_resource_id uuid, booking_starts_at timestamptz, booking_ends_at timestamptz,
  booking_title text, booking_notes text, target_team_id uuid, target_event_id uuid
) returns jsonb language sql security invoker set search_path = '' as
$$ select internal.create_booking_for_actor(target_resource_id, booking_starts_at, booking_ends_at, booking_title, booking_notes, target_team_id, target_event_id) $$;
create or replace function api.cancel_booking(target_booking_id uuid) returns void language sql security invoker set search_path = '' as
$$ select internal.cancel_booking_for_actor(target_booking_id) $$;
create or replace function api.decide_booking(target_booking_id uuid, approve boolean) returns void language sql security invoker set search_path = '' as
$$ select internal.decide_booking_for_actor(target_booking_id, approve) $$;
create or replace function api.create_booking_invitation(target_organization_id uuid, invite_role text) returns text language sql security invoker set search_path = '' as
$$ select internal.create_booking_invitation_for_actor(target_organization_id, invite_role) $$;
create or replace function api.accept_booking_invitation(invite_token text) returns uuid language sql security invoker set search_path = '' as
$$ select internal.accept_booking_invitation_for_actor(invite_token) $$;
create or replace function api.set_booking_member(target_organization_id uuid, target_profile_id uuid, member_role text) returns void language sql security invoker set search_path = '' as
$$ select internal.set_booking_member_for_actor(target_organization_id, target_profile_id, member_role) $$;
create or replace function api.list_booking_team_events(target_organization_id uuid, target_team_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_booking_team_events_for_actor(target_organization_id, target_team_id) $$;
create or replace function api.list_event_bookings(target_event_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_event_bookings_for_actor(target_event_id) $$;

revoke all on function
  internal.booking_actor_role(uuid), internal.booking_actor_teams(uuid), internal.booking_person_name(uuid),
  internal.list_booking_organizations_for_actor(), internal.create_booking_organization_for_actor(text, text, text),
  internal.update_booking_organization_for_actor(uuid, text, text, text, boolean),
  internal.set_booking_organization_club_for_actor(uuid, uuid), internal.list_booking_linkable_clubs_for_actor(),
  internal.get_booking_organization_for_actor(uuid),
  internal.save_booking_resource_for_actor(uuid, uuid, text, text, text, text, integer, boolean, boolean),
  internal.booking_json(core.booking_bookings, text),
  internal.list_bookings_for_actor(uuid, timestamptz, timestamptz), internal.list_pending_bookings_for_actor(uuid),
  internal.create_booking_for_actor(uuid, timestamptz, timestamptz, text, text, uuid, uuid),
  internal.cancel_booking_for_actor(uuid), internal.decide_booking_for_actor(uuid, boolean),
  internal.create_booking_invitation_for_actor(uuid, text), internal.accept_booking_invitation_for_actor(text),
  internal.set_booking_member_for_actor(uuid, uuid, text), internal.list_booking_team_events_for_actor(uuid, uuid),
  internal.list_event_bookings_for_actor(uuid),
  api.list_booking_organizations(), api.create_booking_organization(text, text, text),
  api.update_booking_organization(uuid, text, text, text, boolean), api.set_booking_organization_club(uuid, uuid),
  api.list_booking_linkable_clubs(), api.get_booking_organization(uuid),
  api.save_booking_resource(uuid, uuid, text, text, text, text, integer, boolean, boolean),
  api.list_bookings(uuid, timestamptz, timestamptz), api.list_pending_bookings(uuid),
  api.create_booking(uuid, timestamptz, timestamptz, text, text, uuid, uuid),
  api.cancel_booking(uuid), api.decide_booking(uuid, boolean),
  api.create_booking_invitation(uuid, text), api.accept_booking_invitation(text),
  api.set_booking_member(uuid, uuid, text), api.list_booking_team_events(uuid, uuid), api.list_event_bookings(uuid)
from public, anon, authenticated;

grant execute on function
  internal.booking_actor_role(uuid), internal.booking_actor_teams(uuid), internal.booking_person_name(uuid),
  internal.list_booking_organizations_for_actor(), internal.create_booking_organization_for_actor(text, text, text),
  internal.update_booking_organization_for_actor(uuid, text, text, text, boolean),
  internal.set_booking_organization_club_for_actor(uuid, uuid), internal.list_booking_linkable_clubs_for_actor(),
  internal.get_booking_organization_for_actor(uuid),
  internal.save_booking_resource_for_actor(uuid, uuid, text, text, text, text, integer, boolean, boolean),
  internal.booking_json(core.booking_bookings, text),
  internal.list_bookings_for_actor(uuid, timestamptz, timestamptz), internal.list_pending_bookings_for_actor(uuid),
  internal.create_booking_for_actor(uuid, timestamptz, timestamptz, text, text, uuid, uuid),
  internal.cancel_booking_for_actor(uuid), internal.decide_booking_for_actor(uuid, boolean),
  internal.create_booking_invitation_for_actor(uuid, text), internal.accept_booking_invitation_for_actor(text),
  internal.set_booking_member_for_actor(uuid, uuid, text), internal.list_booking_team_events_for_actor(uuid, uuid),
  internal.list_event_bookings_for_actor(uuid),
  api.list_booking_organizations(), api.create_booking_organization(text, text, text),
  api.update_booking_organization(uuid, text, text, text, boolean), api.set_booking_organization_club(uuid, uuid),
  api.list_booking_linkable_clubs(), api.get_booking_organization(uuid),
  api.save_booking_resource(uuid, uuid, text, text, text, text, integer, boolean, boolean),
  api.list_bookings(uuid, timestamptz, timestamptz), api.list_pending_bookings(uuid),
  api.create_booking(uuid, timestamptz, timestamptz, text, text, uuid, uuid),
  api.cancel_booking(uuid), api.decide_booking(uuid, boolean),
  api.create_booking_invitation(uuid, text), api.accept_booking_invitation(text),
  api.set_booking_member(uuid, uuid, text), api.list_booking_team_events(uuid, uuid), api.list_event_bookings(uuid)
to authenticated;
