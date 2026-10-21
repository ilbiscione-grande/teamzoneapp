-- Webtools Turneringsplanerare, part 1: a tournament with classes (P12,
-- F13...), an open registration link and fees paid outside the app. It
-- works without TeamZone: anyone with an account registers a team, the
-- organiser approves. The organiser may add officials, who later report
-- results. Groups, schedule and play-offs come next; a TeamZone link
-- (calendar, registering from the app) after that.

create table core.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 120),
  sport text check (sport is null or length(btrim(sport)) between 1 and 60),
  location text check (location is null or length(location) <= 200),
  starts_on date not null,
  ends_on date not null,
  description text check (description is null or length(description) <= 4000),
  contact_email text check (contact_email is null or length(contact_email) <= 200),
  -- Fees are paid outside the app: Swish, bankgiro... The organiser ticks
  -- off paid teams.
  payment_info text check (payment_info is null or length(payment_info) <= 1000),
  -- A draft is seen by its staff only; published, anyone with the link sees
  -- it, and registers while registration is open.
  status text not null default 'draft' check (status in ('draft', 'published', 'finished', 'cancelled')),
  registration_open boolean not null default false,
  registration_closes_at timestamptz,
  teamzone_club_id uuid references core.clubs(id),
  created_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  check (ends_on >= starts_on and ends_on - starts_on <= 31)
);

create table core.tournament_staff (
  tournament_id uuid not null references core.tournaments(id) on delete cascade,
  profile_id uuid not null references core.profiles(id),
  role text not null check (role in ('organizer', 'official')),
  created_at timestamptz not null default now(),
  primary key (tournament_id, profile_id)
);

create table core.tournament_staff_invitations (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references core.tournaments(id) on delete cascade,
  role text not null check (role in ('organizer', 'official')),
  token_hash bytea not null unique,
  created_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_by uuid references core.profiles(id),
  accepted_at timestamptz,
  revoked_at timestamptz
);

-- A class is played on its own: P12, F13, Herr... Group play and a play-off,
-- or pools without results and tables (the youngest).
create table core.tournament_classes (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references core.tournaments(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 60),
  description text check (description is null or length(description) <= 500),
  format text not null default 'groups_playoff' check (format in ('groups_playoff', 'pool')),
  max_teams integer check (max_teams is null or max_teams between 2 and 256),
  fee_sek integer check (fee_sek is null or fee_sek between 0 and 1000000),
  match_minutes integer check (match_minutes is null or match_minutes between 1 and 240),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (id, tournament_id),
  unique (tournament_id, name)
);

create table core.tournament_registrations (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null,
  class_id uuid not null,
  team_name text not null check (length(btrim(team_name)) between 1 and 120),
  club_name text check (club_name is null or length(btrim(club_name)) between 1 and 120),
  contact_name text not null check (length(btrim(contact_name)) between 1 and 120),
  contact_email text not null check (length(btrim(contact_email)) between 3 and 200),
  contact_phone text check (contact_phone is null or length(contact_phone) <= 40),
  notes text check (notes is null or length(notes) <= 2000),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'withdrawn')),
  paid boolean not null default false,
  paid_at timestamptz,
  registered_by uuid not null references core.profiles(id),
  -- TeamZone: the team that registered, when it did so from the app.
  teamzone_team_id uuid references core.teams(id),
  decided_by uuid references core.profiles(id),
  decided_at timestamptz,
  -- Registration order: first come, first listed.
  created_at timestamptz not null default clock_timestamp(),
  revision bigint not null default 1 check (revision > 0),
  foreign key (class_id, tournament_id) references core.tournament_classes(id, tournament_id) on delete cascade
);
create index tournament_registrations_class on core.tournament_registrations (class_id, status);
create index tournament_registrations_registrant on core.tournament_registrations (registered_by);
-- One active registration per team name in a class.
create unique index tournament_registrations_team_name on core.tournament_registrations (class_id, lower(btrim(team_name)))
  where status in ('pending', 'approved');

alter table core.tournaments enable row level security;
alter table core.tournament_staff enable row level security;
alter table core.tournament_staff_invitations enable row level security;
alter table core.tournament_classes enable row level security;
alter table core.tournament_registrations enable row level security;
revoke all on core.tournaments, core.tournament_staff, core.tournament_staff_invitations,
  core.tournament_classes, core.tournament_registrations from public, anon, authenticated;

-- Your role in a tournament: organizer or official, or null.
create or replace function internal.tournament_actor_role(target_tournament_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select staff.role from core.tournament_staff staff
  where staff.tournament_id = target_tournament_id and staff.profile_id = auth.uid()
$$;

create or replace function internal.tournament_require_organizer(target_tournament_id uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if internal.tournament_actor_role(target_tournament_id) is distinct from 'organizer' then
    raise insufficient_privilege using message = 'not_organizer';
  end if;
end;
$$;

-- Whether registration takes new teams now.
create or replace function internal.tournament_registration_is_open(tournament core.tournaments)
returns boolean language sql stable security definer set search_path = '' as $$
  select tournament.status = 'published' and tournament.registration_open
    and (tournament.registration_closes_at is null or tournament.registration_closes_at > now())
$$;

create or replace function internal.tournament_registration_json(registration core.tournament_registrations, staff boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', registration.id, 'class_id', registration.class_id,
    'class_name', (select class.name from core.tournament_classes class where class.id = registration.class_id),
    'team_name', registration.team_name, 'club_name', registration.club_name,
    'contact_name', registration.contact_name, 'contact_email', registration.contact_email,
    'contact_phone', registration.contact_phone, 'notes', registration.notes,
    'status', registration.status, 'paid', registration.paid,
    'is_mine', registration.registered_by = auth.uid(),
    'registered_by_name', case when staff then internal.booking_person_name(registration.registered_by) end,
    'teamzone_team_id', registration.teamzone_team_id,
    'created_at', registration.created_at
  )
$$;

create or replace function internal.tournament_class_json(class core.tournament_classes)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', class.id, 'name', class.name, 'description', class.description, 'format', class.format,
    'max_teams', class.max_teams, 'fee_sek', class.fee_sek, 'match_minutes', class.match_minutes,
    'sort_order', class.sort_order,
    'approved', (select count(*) from core.tournament_registrations registration
      where registration.class_id = class.id and registration.status = 'approved'),
    'pending', (select count(*) from core.tournament_registrations registration
      where registration.class_id = class.id and registration.status = 'pending')
  )
$$;

-- Tournaments you organise, officiate or have registered a team in.
create or replace function internal.list_my_tournaments_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tournament.id, 'name', tournament.name, 'sport', tournament.sport, 'location', tournament.location,
    'starts_on', tournament.starts_on, 'ends_on', tournament.ends_on, 'status', tournament.status,
    'registration_open', internal.tournament_registration_is_open(tournament),
    'role', coalesce(internal.tournament_actor_role(tournament.id), 'participant'),
    'pending', case when internal.tournament_actor_role(tournament.id) = 'organizer' then
      (select count(*) from core.tournament_registrations registration
        where registration.tournament_id = tournament.id and registration.status = 'pending') end
  ) order by tournament.starts_on desc, tournament.name), '[]'::jsonb)
  from core.tournaments tournament
  where internal.tournament_actor_role(tournament.id) is not null
    or (tournament.status <> 'draft' and exists (select 1 from core.tournament_registrations registration
      where registration.tournament_id = tournament.id and registration.registered_by = auth.uid()))
$$;

create or replace function internal.create_tournament_for_actor(
  tournament_name text, tournament_sport text, tournament_location text, tournament_starts_on date, tournament_ends_on date
) returns uuid language plpgsql security definer set search_path = '' as $$
declare created uuid;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if tournament_starts_on is null or tournament_ends_on is null or tournament_ends_on < tournament_starts_on
    or tournament_ends_on - tournament_starts_on > 31 then
    raise invalid_parameter_value using message = 'invalid_dates';
  end if;
  insert into core.tournaments (name, sport, location, starts_on, ends_on, created_by)
  values (btrim(tournament_name), nullif(btrim(tournament_sport), ''), nullif(btrim(tournament_location), ''),
    tournament_starts_on, tournament_ends_on, auth.uid())
  returning id into created;
  insert into core.tournament_staff (tournament_id, profile_id, role) values (created, auth.uid(), 'organizer');
  return created;
end;
$$;

create or replace function internal.update_tournament_for_actor(
  target_tournament_id uuid, tournament_name text, tournament_sport text, tournament_location text,
  tournament_starts_on date, tournament_ends_on date, tournament_description text, tournament_contact_email text,
  tournament_payment_info text, tournament_status text, tournament_registration_open boolean,
  tournament_registration_closes_at timestamptz
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform internal.tournament_require_organizer(target_tournament_id);
  if tournament_starts_on is null or tournament_ends_on is null or tournament_ends_on < tournament_starts_on
    or tournament_ends_on - tournament_starts_on > 31 then
    raise invalid_parameter_value using message = 'invalid_dates';
  end if;
  if tournament_status not in ('draft', 'published', 'finished', 'cancelled') then
    raise invalid_parameter_value using message = 'invalid_status';
  end if;
  -- Teams have seen a published tournament: it is cancelled, not hidden.
  if tournament_status = 'draft' and exists (select 1 from core.tournament_registrations
    where tournament_id = target_tournament_id) then
    raise invalid_parameter_value using message = 'has_registrations';
  end if;
  update core.tournaments set
    name = btrim(tournament_name), sport = nullif(btrim(tournament_sport), ''),
    location = nullif(btrim(tournament_location), ''),
    starts_on = tournament_starts_on, ends_on = tournament_ends_on,
    description = nullif(btrim(tournament_description), ''),
    contact_email = nullif(btrim(tournament_contact_email), ''),
    payment_info = nullif(btrim(tournament_payment_info), ''),
    status = tournament_status,
    registration_open = coalesce(tournament_registration_open, false) and tournament_status = 'published',
    registration_closes_at = tournament_registration_closes_at,
    revision = revision + 1
  where id = target_tournament_id;
end;
$$;

-- The tournament: staff see everything; anyone else a published one, its
-- classes with places left and their own registrations.
create or replace function internal.get_tournament_for_actor(target_tournament_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  tournament core.tournaments;
  actor_role text := internal.tournament_actor_role(target_tournament_id);
begin
  select * into tournament from core.tournaments where id = target_tournament_id;
  if tournament.id is null or (actor_role is null and tournament.status = 'draft') or auth.uid() is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'id', tournament.id, 'name', tournament.name, 'sport', tournament.sport, 'location', tournament.location,
    'starts_on', tournament.starts_on, 'ends_on', tournament.ends_on, 'description', tournament.description,
    'contact_email', tournament.contact_email, 'payment_info', tournament.payment_info,
    'status', tournament.status, 'registration_open', tournament.registration_open,
    'registration_closes_at', tournament.registration_closes_at,
    'registration_is_open', internal.tournament_registration_is_open(tournament),
    'role', actor_role,
    'organizer_name', internal.booking_person_name(tournament.created_by),
    'classes', coalesce((select jsonb_agg(internal.tournament_class_json(class) order by class.sort_order, class.name)
      from core.tournament_classes class where class.tournament_id = tournament.id), '[]'::jsonb),
    'my_registrations', coalesce((select jsonb_agg(internal.tournament_registration_json(registration, false) order by registration.created_at)
      from core.tournament_registrations registration
      where registration.tournament_id = tournament.id and registration.registered_by = auth.uid()), '[]'::jsonb),
    'staff', case when actor_role = 'organizer' then coalesce((select jsonb_agg(jsonb_build_object(
        'profile_id', staff.profile_id, 'name', internal.booking_person_name(staff.profile_id),
        'role', staff.role, 'is_self', staff.profile_id = auth.uid()) order by staff.role desc, staff.created_at)
      from core.tournament_staff staff where staff.tournament_id = tournament.id), '[]'::jsonb) end
  );
end;
$$;

create or replace function internal.save_tournament_class_for_actor(
  target_tournament_id uuid, target_class_id uuid, class_name text, class_description text, class_format text,
  class_max_teams integer, class_fee_sek integer, class_match_minutes integer, class_sort_order integer
) returns uuid language plpgsql security definer set search_path = '' as $$
declare saved uuid;
begin
  perform internal.tournament_require_organizer(target_tournament_id);
  if class_format not in ('groups_playoff', 'pool') then raise invalid_parameter_value using message = 'invalid_format'; end if;
  if exists (select 1 from core.tournament_classes where tournament_id = target_tournament_id
    and lower(btrim(name)) = lower(btrim(class_name)) and id is distinct from target_class_id) then
    raise invalid_parameter_value using message = 'class_name_taken';
  end if;
  if target_class_id is null then
    insert into core.tournament_classes (tournament_id, name, description, format, max_teams, fee_sek, match_minutes, sort_order)
    values (target_tournament_id, btrim(class_name), nullif(btrim(class_description), ''), class_format,
      class_max_teams, class_fee_sek, class_match_minutes, coalesce(class_sort_order, 0))
    returning id into saved;
  else
    update core.tournament_classes set name = btrim(class_name), description = nullif(btrim(class_description), ''),
      format = class_format, max_teams = class_max_teams, fee_sek = class_fee_sek,
      match_minutes = class_match_minutes, sort_order = coalesce(class_sort_order, 0), revision = revision + 1
    where id = target_class_id and tournament_id = target_tournament_id
    returning id into saved;
    if saved is null then raise invalid_parameter_value using message = 'not_found'; end if;
  end if;
  return saved;
end;
$$;

-- A class goes only while no team has registered in it.
create or replace function internal.delete_tournament_class_for_actor(target_class_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare class core.tournament_classes;
begin
  select * into class from core.tournament_classes where id = target_class_id;
  if class.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tournament_require_organizer(class.tournament_id);
  if exists (select 1 from core.tournament_registrations where class_id = class.id) then
    raise invalid_parameter_value using message = 'has_registrations';
  end if;
  delete from core.tournament_classes where id = class.id;
end;
$$;

-- Anyone with an account registers a team while registration is open; the
-- organiser approves. A full class takes no more registrations.
create or replace function internal.register_tournament_team_for_actor(
  target_class_id uuid, registration_team_name text, registration_club_name text, registration_contact_name text,
  registration_contact_email text, registration_contact_phone text, registration_notes text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  class core.tournament_classes;
  tournament core.tournaments;
  created core.tournament_registrations;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into class from core.tournament_classes where id = target_class_id;
  select * into tournament from core.tournaments where id = class.tournament_id;
  if class.id is null or (tournament.status = 'draft' and internal.tournament_actor_role(tournament.id) is null) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if not internal.tournament_registration_is_open(tournament) then
    raise invalid_parameter_value using message = 'registration_closed';
  end if;
  if registration_contact_email is null or registration_contact_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
    raise invalid_parameter_value using message = 'invalid_email';
  end if;
  -- Registrations in a class are taken one at a time.
  perform pg_advisory_xact_lock(hashtextextended('tournament_class:' || class.id::text, 0));
  if class.max_teams is not null and (select count(*) from core.tournament_registrations
    where class_id = class.id and status = 'approved') >= class.max_teams then
    raise invalid_parameter_value using message = 'class_full';
  end if;
  if exists (select 1 from core.tournament_registrations where class_id = class.id
    and status in ('pending', 'approved') and lower(btrim(team_name)) = lower(btrim(registration_team_name))) then
    raise invalid_parameter_value using message = 'team_name_taken';
  end if;
  insert into core.tournament_registrations (tournament_id, class_id, team_name, club_name, contact_name,
    contact_email, contact_phone, notes, registered_by)
  values (tournament.id, class.id, btrim(registration_team_name), nullif(btrim(registration_club_name), ''),
    btrim(registration_contact_name), btrim(registration_contact_email), nullif(btrim(registration_contact_phone), ''),
    nullif(btrim(registration_notes), ''), auth.uid())
  returning * into created;
  return internal.tournament_registration_json(created, false);
end;
$$;

-- The one who registered withdraws; so may the organiser.
create or replace function internal.withdraw_tournament_registration_for_actor(target_registration_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare registration core.tournament_registrations;
begin
  select * into registration from core.tournament_registrations where id = target_registration_id;
  if registration.id is null or (registration.registered_by is distinct from auth.uid()
    and internal.tournament_actor_role(registration.tournament_id) is distinct from 'organizer') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if registration.status not in ('pending', 'approved') then raise invalid_parameter_value using message = 'not_active'; end if;
  update core.tournament_registrations set status = 'withdrawn', revision = revision + 1 where id = registration.id;
end;
$$;

create or replace function internal.list_tournament_registrations_for_actor(target_tournament_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if internal.tournament_actor_role(target_tournament_id) is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((select jsonb_agg(internal.tournament_registration_json(registration, true)
      order by class.sort_order, class.name, registration.created_at)
    from core.tournament_registrations registration
    join core.tournament_classes class on class.id = registration.class_id
    where registration.tournament_id = target_tournament_id), '[]'::jsonb);
end;
$$;

create or replace function internal.decide_tournament_registration_for_actor(target_registration_id uuid, approve boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare registration core.tournament_registrations; class core.tournament_classes;
begin
  select * into registration from core.tournament_registrations where id = target_registration_id;
  if registration.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tournament_require_organizer(registration.tournament_id);
  if registration.status <> 'pending' then raise invalid_parameter_value using message = 'not_pending'; end if;
  select * into class from core.tournament_classes where id = registration.class_id;
  perform pg_advisory_xact_lock(hashtextextended('tournament_class:' || class.id::text, 0));
  if approve and class.max_teams is not null and (select count(*) from core.tournament_registrations
    where class_id = class.id and status = 'approved') >= class.max_teams then
    raise invalid_parameter_value using message = 'class_full';
  end if;
  update core.tournament_registrations set status = case when approve then 'approved' else 'declined' end,
    decided_by = auth.uid(), decided_at = now(), revision = revision + 1
  where id = registration.id;
end;
$$;

create or replace function internal.set_tournament_registration_paid_for_actor(target_registration_id uuid, is_paid boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare registration core.tournament_registrations;
begin
  select * into registration from core.tournament_registrations where id = target_registration_id;
  if registration.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tournament_require_organizer(registration.tournament_id);
  update core.tournament_registrations set paid = coalesce(is_paid, false),
    paid_at = case when coalesce(is_paid, false) then coalesce(paid_at, now()) end, revision = revision + 1
  where id = registration.id;
end;
$$;

-- Staff are invited by link, as in the booking manager: shown once, only
-- the hash kept, single use, 14 days.
create or replace function internal.create_tournament_staff_invitation_for_actor(target_tournament_id uuid, invite_role text)
returns text language plpgsql security definer set search_path = '' as $$
declare token text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  perform internal.tournament_require_organizer(target_tournament_id);
  if invite_role not in ('organizer', 'official') then raise invalid_parameter_value using message = 'invalid_role'; end if;
  insert into core.tournament_staff_invitations (tournament_id, role, token_hash, created_by, expires_at)
  values (target_tournament_id, invite_role, sha256(convert_to(token, 'UTF8')), auth.uid(), now() + interval '14 days');
  return token;
end;
$$;

create or replace function internal.accept_tournament_staff_invitation_for_actor(invite_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare invitation core.tournament_staff_invitations;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into invitation from core.tournament_staff_invitations
  where token_hash = sha256(convert_to(coalesce(invite_token, ''), 'UTF8'))
    and accepted_at is null and revoked_at is null and expires_at > now()
  for update;
  if invitation.id is null then raise invalid_parameter_value using message = 'invitation_invalid'; end if;
  update core.tournament_staff_invitations set accepted_by = auth.uid(), accepted_at = now() where id = invitation.id;
  -- An organiser stays one; an official may be raised to organiser.
  insert into core.tournament_staff (tournament_id, profile_id, role)
  values (invitation.tournament_id, auth.uid(), invitation.role)
  on conflict (tournament_id, profile_id) do update set role = case
    when core.tournament_staff.role = 'organizer' then 'organizer' else excluded.role end;
  return invitation.tournament_id;
end;
$$;

-- The organiser removes staff; the last organiser stays.
create or replace function internal.remove_tournament_staff_for_actor(target_tournament_id uuid, target_profile_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform internal.tournament_require_organizer(target_tournament_id);
  if (select role from core.tournament_staff where tournament_id = target_tournament_id and profile_id = target_profile_id) = 'organizer'
    and (select count(*) from core.tournament_staff where tournament_id = target_tournament_id and role = 'organizer') <= 1 then
    raise invalid_parameter_value using message = 'last_organizer';
  end if;
  delete from core.tournament_staff where tournament_id = target_tournament_id and profile_id = target_profile_id;
end;
$$;

create or replace function api.list_my_tournaments() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_my_tournaments_for_actor() $$;
create or replace function api.create_tournament(tournament_name text, tournament_sport text, tournament_location text, tournament_starts_on date, tournament_ends_on date)
returns uuid language sql security invoker set search_path = '' as
$$ select internal.create_tournament_for_actor(tournament_name, tournament_sport, tournament_location, tournament_starts_on, tournament_ends_on) $$;
create or replace function api.update_tournament(
  target_tournament_id uuid, tournament_name text, tournament_sport text, tournament_location text,
  tournament_starts_on date, tournament_ends_on date, tournament_description text, tournament_contact_email text,
  tournament_payment_info text, tournament_status text, tournament_registration_open boolean,
  tournament_registration_closes_at timestamptz
) returns void language sql security invoker set search_path = '' as
$$ select internal.update_tournament_for_actor(target_tournament_id, tournament_name, tournament_sport, tournament_location,
  tournament_starts_on, tournament_ends_on, tournament_description, tournament_contact_email, tournament_payment_info,
  tournament_status, tournament_registration_open, tournament_registration_closes_at) $$;
create or replace function api.get_tournament(target_tournament_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.get_tournament_for_actor(target_tournament_id) $$;
create or replace function api.save_tournament_class(
  target_tournament_id uuid, target_class_id uuid, class_name text, class_description text, class_format text,
  class_max_teams integer, class_fee_sek integer, class_match_minutes integer, class_sort_order integer
) returns uuid language sql security invoker set search_path = '' as
$$ select internal.save_tournament_class_for_actor(target_tournament_id, target_class_id, class_name, class_description,
  class_format, class_max_teams, class_fee_sek, class_match_minutes, class_sort_order) $$;
create or replace function api.delete_tournament_class(target_class_id uuid) returns void language sql security invoker set search_path = '' as
$$ select internal.delete_tournament_class_for_actor(target_class_id) $$;
create or replace function api.register_tournament_team(
  target_class_id uuid, registration_team_name text, registration_club_name text, registration_contact_name text,
  registration_contact_email text, registration_contact_phone text, registration_notes text
) returns jsonb language sql security invoker set search_path = '' as
$$ select internal.register_tournament_team_for_actor(target_class_id, registration_team_name, registration_club_name,
  registration_contact_name, registration_contact_email, registration_contact_phone, registration_notes) $$;
create or replace function api.withdraw_tournament_registration(target_registration_id uuid) returns void language sql security invoker set search_path = '' as
$$ select internal.withdraw_tournament_registration_for_actor(target_registration_id) $$;
create or replace function api.list_tournament_registrations(target_tournament_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_tournament_registrations_for_actor(target_tournament_id) $$;
create or replace function api.decide_tournament_registration(target_registration_id uuid, approve boolean) returns void language sql security invoker set search_path = '' as
$$ select internal.decide_tournament_registration_for_actor(target_registration_id, approve) $$;
create or replace function api.set_tournament_registration_paid(target_registration_id uuid, is_paid boolean) returns void language sql security invoker set search_path = '' as
$$ select internal.set_tournament_registration_paid_for_actor(target_registration_id, is_paid) $$;
create or replace function api.create_tournament_staff_invitation(target_tournament_id uuid, invite_role text) returns text language sql security invoker set search_path = '' as
$$ select internal.create_tournament_staff_invitation_for_actor(target_tournament_id, invite_role) $$;
create or replace function api.accept_tournament_staff_invitation(invite_token text) returns uuid language sql security invoker set search_path = '' as
$$ select internal.accept_tournament_staff_invitation_for_actor(invite_token) $$;
create or replace function api.remove_tournament_staff(target_tournament_id uuid, target_profile_id uuid) returns void language sql security invoker set search_path = '' as
$$ select internal.remove_tournament_staff_for_actor(target_tournament_id, target_profile_id) $$;

revoke all on function
  internal.tournament_actor_role(uuid), internal.tournament_require_organizer(uuid),
  internal.tournament_registration_is_open(core.tournaments),
  internal.tournament_registration_json(core.tournament_registrations, boolean),
  internal.tournament_class_json(core.tournament_classes),
  internal.list_my_tournaments_for_actor(),
  internal.create_tournament_for_actor(text, text, text, date, date),
  internal.update_tournament_for_actor(uuid, text, text, text, date, date, text, text, text, text, boolean, timestamptz),
  internal.get_tournament_for_actor(uuid),
  internal.save_tournament_class_for_actor(uuid, uuid, text, text, text, integer, integer, integer, integer),
  internal.delete_tournament_class_for_actor(uuid),
  internal.register_tournament_team_for_actor(uuid, text, text, text, text, text, text),
  internal.withdraw_tournament_registration_for_actor(uuid),
  internal.list_tournament_registrations_for_actor(uuid),
  internal.decide_tournament_registration_for_actor(uuid, boolean),
  internal.set_tournament_registration_paid_for_actor(uuid, boolean),
  internal.create_tournament_staff_invitation_for_actor(uuid, text),
  internal.accept_tournament_staff_invitation_for_actor(text),
  internal.remove_tournament_staff_for_actor(uuid, uuid),
  api.list_my_tournaments(), api.create_tournament(text, text, text, date, date),
  api.update_tournament(uuid, text, text, text, date, date, text, text, text, text, boolean, timestamptz),
  api.get_tournament(uuid),
  api.save_tournament_class(uuid, uuid, text, text, text, integer, integer, integer, integer),
  api.delete_tournament_class(uuid),
  api.register_tournament_team(uuid, text, text, text, text, text, text),
  api.withdraw_tournament_registration(uuid), api.list_tournament_registrations(uuid),
  api.decide_tournament_registration(uuid, boolean), api.set_tournament_registration_paid(uuid, boolean),
  api.create_tournament_staff_invitation(uuid, text), api.accept_tournament_staff_invitation(text),
  api.remove_tournament_staff(uuid, uuid)
from public, anon, authenticated;
grant execute on function
  internal.tournament_actor_role(uuid), internal.tournament_require_organizer(uuid),
  internal.tournament_registration_is_open(core.tournaments),
  internal.tournament_registration_json(core.tournament_registrations, boolean),
  internal.tournament_class_json(core.tournament_classes),
  internal.list_my_tournaments_for_actor(),
  internal.create_tournament_for_actor(text, text, text, date, date),
  internal.update_tournament_for_actor(uuid, text, text, text, date, date, text, text, text, text, boolean, timestamptz),
  internal.get_tournament_for_actor(uuid),
  internal.save_tournament_class_for_actor(uuid, uuid, text, text, text, integer, integer, integer, integer),
  internal.delete_tournament_class_for_actor(uuid),
  internal.register_tournament_team_for_actor(uuid, text, text, text, text, text, text),
  internal.withdraw_tournament_registration_for_actor(uuid),
  internal.list_tournament_registrations_for_actor(uuid),
  internal.decide_tournament_registration_for_actor(uuid, boolean),
  internal.set_tournament_registration_paid_for_actor(uuid, boolean),
  internal.create_tournament_staff_invitation_for_actor(uuid, text),
  internal.accept_tournament_staff_invitation_for_actor(text),
  internal.remove_tournament_staff_for_actor(uuid, uuid),
  api.list_my_tournaments(), api.create_tournament(text, text, text, date, date),
  api.update_tournament(uuid, text, text, text, date, date, text, text, text, text, boolean, timestamptz),
  api.get_tournament(uuid),
  api.save_tournament_class(uuid, uuid, text, text, text, integer, integer, integer, integer),
  api.delete_tournament_class(uuid),
  api.register_tournament_team(uuid, text, text, text, text, text, text),
  api.withdraw_tournament_registration(uuid), api.list_tournament_registrations(uuid),
  api.decide_tournament_registration(uuid, boolean), api.set_tournament_registration_paid(uuid, boolean),
  api.create_tournament_staff_invitation(uuid, text), api.accept_tournament_staff_invitation(text),
  api.remove_tournament_staff(uuid, uuid)
to authenticated;
