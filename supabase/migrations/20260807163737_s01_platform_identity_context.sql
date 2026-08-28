-- TeamZone S01 greenfield foundation.
-- This migration is intentionally independent of every previous database object.

create schema if not exists core;
create schema if not exists internal;
create schema if not exists audit;
create schema if not exists api;

revoke all on schema core, internal, audit, api from public, anon, authenticated;
grant usage on schema api to authenticated;

alter default privileges for role postgres in schema core
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema core
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema core
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema internal
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema internal
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema internal
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema audit
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema audit
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema audit
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema api
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema api
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema api
  revoke execute on functions from public, anon, authenticated;

create table core.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  locale text not null default 'sv' check (locale in ('sv', 'en')),
  timezone text not null default 'Europe/Stockholm',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0)
);

create table core.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 2 and 120),
  slug text not null unique check (slug = lower(slug)),
  status text not null default 'active' check (status in ('active', 'suspended', 'ended')),
  default_timezone text not null default 'Europe/Stockholm',
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0)
);

create table core.teams (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  name text not null check (length(btrim(name)) between 1 and 120),
  status text not null default 'active' check (status in ('active', 'suspended', 'ended')),
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  unique (club_id, name)
);

create table core.club_people (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  display_name text not null check (length(btrim(display_name)) between 1 and 120),
  status text not null default 'active' check (status in ('active', 'suspended', 'ended')),
  provenance text not null default 'created',
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id)
);

create table core.person_account_links (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  club_person_id uuid not null,
  profile_id uuid not null references core.profiles(id),
  state text not null default 'pending' check (state in ('pending', 'active', 'ended', 'rejected')),
  verified_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  foreign key (club_person_id, club_id) references core.club_people(id, club_id),
  check ((state = 'active' and verified_at is not null and ended_at is null) or state <> 'active')
);

create unique index person_account_links_one_active_person
  on core.person_account_links (club_person_id)
  where state = 'active';

create table core.assignments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  team_id uuid,
  club_person_id uuid not null,
  role_package text not null check (role_package in ('player', 'leader', 'guardian', 'club_functionary', 'guest')),
  state text not null default 'pending' check (state in ('pending', 'active', 'suspended', 'ended')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  foreign key (team_id, club_id) references core.teams(id, club_id),
  foreign key (club_person_id, club_id) references core.club_people(id, club_id),
  check (ends_at is null or ends_at > starts_at),
  check (role_package <> 'guest' or team_id is not null)
);

create index assignments_active_person_scope
  on core.assignments (club_person_id, club_id, team_id)
  where state = 'active';

create table core.capability_grants (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  assignment_id uuid not null references core.assignments(id) on delete cascade,
  capability text not null check (capability ~ '^[a-z]+(\.[a-z_]+)+$'),
  scope_type text not null check (scope_type in ('club', 'team')),
  scope_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  check (ends_at is null or ends_at > starts_at),
  unique (assignment_id, capability, scope_type, scope_id)
);

create table internal.command_deduplication (
  id uuid primary key default gen_random_uuid(),
  actor_profile_id uuid not null references core.profiles(id),
  idempotency_key uuid not null,
  command_type text not null,
  result jsonb,
  created_at timestamptz not null default now(),
  unique (actor_profile_id, idempotency_key, command_type)
);

create table internal.migration_provenance (
  id uuid primary key default gen_random_uuid(),
  migration_name text not null,
  source_kind text not null default 'greenfield' check (source_kind = 'greenfield'),
  source_reference text,
  created_at timestamptz not null default now()
);

create table internal.migration_exceptions (
  id uuid primary key default gen_random_uuid(),
  migration_name text not null,
  error_code text not null,
  source_reference_hash text,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table audit.command_events (
  id uuid primary key default gen_random_uuid(),
  club_id uuid,
  actor_profile_id uuid references core.profiles(id),
  command_type text not null,
  aggregate_type text not null,
  aggregate_id uuid,
  aggregate_revision bigint,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create function internal.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into core.profiles (id, display_name, locale)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), ''),
    case when new.raw_user_meta_data ->> 'locale' = 'en' then 'en' else 'sv' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function internal.handle_new_auth_user() from public, anon, authenticated;

create trigger teamzone_create_profile_after_auth_user
after insert on auth.users
for each row execute function internal.handle_new_auth_user();

alter table core.profiles enable row level security;
alter table core.clubs enable row level security;
alter table core.teams enable row level security;
alter table core.club_people enable row level security;
alter table core.person_account_links enable row level security;
alter table core.assignments enable row level security;
alter table core.capability_grants enable row level security;

create function internal.actor_has_club_access(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_person_id = link.club_person_id
     and assignment.club_id = link.club_id
    where link.profile_id = auth.uid()
      and link.club_id = target_club_id
      and link.state = 'active'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
  );
$$;

revoke all on function internal.actor_has_club_access(uuid) from public, anon, authenticated;

create policy profiles_select_own on core.profiles
for select to authenticated
using ((select auth.uid()) = id);

create policy profiles_update_own on core.profiles
for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy clubs_select_active_relation on core.clubs
for select to authenticated
using ((select internal.actor_has_club_access(id)));

create policy teams_select_active_relation on core.teams
for select to authenticated
using ((select internal.actor_has_club_access(club_id)));

create policy club_people_select_own_link on core.club_people
for select to authenticated
using (
  exists (
    select 1 from core.person_account_links link
    where link.club_person_id = club_people.id
      and link.club_id = club_people.club_id
      and link.profile_id = (select auth.uid())
      and link.state = 'active'
  )
);

create policy account_links_select_own on core.person_account_links
for select to authenticated
using (profile_id = (select auth.uid()));

create policy assignments_select_own on core.assignments
for select to authenticated
using (
  exists (
    select 1 from core.person_account_links link
    where link.club_person_id = assignments.club_person_id
      and link.club_id = assignments.club_id
      and link.profile_id = (select auth.uid())
      and link.state = 'active'
  )
);

create policy capability_grants_select_own on core.capability_grants
for select to authenticated
using (
  exists (
    select 1
    from core.assignments assignment
    join core.person_account_links link
      on link.club_person_id = assignment.club_person_id
     and link.club_id = assignment.club_id
    where assignment.id = capability_grants.assignment_id
      and link.profile_id = (select auth.uid())
      and link.state = 'active'
  )
);

create function internal.get_profile_for_actor()
returns table (id uuid, display_name text, locale text, timezone text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  return query
  select profile.id, profile.display_name, profile.locale, profile.timezone
  from core.profiles profile
  where profile.id = auth.uid();
end;
$$;

create function internal.get_my_contexts_for_actor()
returns table (
  context_id uuid,
  club_id uuid,
  club_name text,
  team_id uuid,
  team_name text,
  role_package text,
  capabilities text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  return query
  select
    assignment.id,
    club.id,
    club.name,
    team.id,
    team.name,
    assignment.role_package,
    coalesce(
      array_agg(distinct capability.capability order by capability.capability)
        filter (
          where capability.id is not null
            and capability.starts_at <= now()
            and (capability.ends_at is null or capability.ends_at > now())
            and (
              (capability.scope_type = 'club' and capability.scope_id = assignment.club_id)
              or
              (capability.scope_type = 'team' and capability.scope_id = assignment.team_id)
            )
        ),
      array[]::text[]
    )
  from core.person_account_links link
  join core.assignments assignment
    on assignment.club_person_id = link.club_person_id
   and assignment.club_id = link.club_id
  join core.clubs club on club.id = assignment.club_id and club.status = 'active'
  left join core.teams team
    on team.id = assignment.team_id
   and team.club_id = assignment.club_id
   and team.status = 'active'
  left join core.capability_grants capability
    on capability.assignment_id = assignment.id
   and capability.club_id = assignment.club_id
  where link.profile_id = auth.uid()
    and link.state = 'active'
    and assignment.state = 'active'
    and assignment.starts_at <= now()
    and (assignment.ends_at is null or assignment.ends_at > now())
    and (assignment.team_id is null or team.id is not null)
  group by assignment.id, club.id, club.name, team.id, team.name, assignment.role_package
  order by club.name, team.name nulls first, assignment.id;
end;
$$;

create function internal.set_profile_preferences_for_actor(
  new_locale text,
  new_timezone text,
  new_idempotency_key uuid
)
returns table (id uuid, display_name text, locale text, timezone text, revision bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if new_locale not in ('sv', 'en') then
    raise invalid_parameter_value using message = 'invalid_locale';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new_timezone) then
    raise invalid_parameter_value using message = 'invalid_timezone';
  end if;

  insert into internal.command_deduplication (
    actor_profile_id,
    idempotency_key,
    command_type
  ) values (
    actor_id,
    new_idempotency_key,
    'identity.set_profile_preferences.v1'
  ) on conflict do nothing;

  if found then
    update core.profiles profile
    set locale = new_locale,
        timezone = new_timezone,
        updated_at = now(),
        revision = profile.revision + 1
    where profile.id = actor_id;

    insert into audit.command_events (
      actor_profile_id,
      command_type,
      aggregate_type,
      aggregate_id,
      aggregate_revision
    )
    select
      actor_id,
      'identity.set_profile_preferences.v1',
      'profile',
      profile.id,
      profile.revision
    from core.profiles profile
    where profile.id = actor_id;
  end if;

  return query
  select profile.id, profile.display_name, profile.locale, profile.timezone, profile.revision
  from core.profiles profile
  where profile.id = actor_id;
end;
$$;

revoke all on function internal.get_profile_for_actor() from public, anon, authenticated;
revoke all on function internal.get_my_contexts_for_actor() from public, anon, authenticated;
revoke all on function internal.set_profile_preferences_for_actor(text, text, uuid) from public, anon, authenticated;
grant usage on schema internal to authenticated;
grant execute on function internal.get_profile_for_actor() to authenticated;
grant execute on function internal.get_my_contexts_for_actor() to authenticated;
grant execute on function internal.set_profile_preferences_for_actor(text, text, uuid) to authenticated;

create function api.get_profile()
returns table (id uuid, display_name text, locale text, timezone text)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from internal.get_profile_for_actor();
$$;

create function api.get_my_contexts()
returns table (
  context_id uuid,
  club_id uuid,
  club_name text,
  team_id uuid,
  team_name text,
  role_package text,
  capabilities text[]
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from internal.get_my_contexts_for_actor();
$$;

create function api.set_profile_preferences(
  new_locale text,
  new_timezone text,
  idempotency_key uuid
)
returns table (id uuid, display_name text, locale text, timezone text, revision bigint)
language sql
security invoker
set search_path = ''
as $$
  select *
  from internal.set_profile_preferences_for_actor(
    new_locale,
    new_timezone,
    idempotency_key
  );
$$;

revoke all on function api.get_profile() from public, anon;
revoke all on function api.get_my_contexts() from public, anon;
revoke all on function api.set_profile_preferences(text, text, uuid) from public, anon;
grant execute on function api.get_profile() to authenticated;
grant execute on function api.get_my_contexts() to authenticated;
grant execute on function api.set_profile_preferences(text, text, uuid) to authenticated;

revoke all on all tables in schema core, internal, audit from public, anon, authenticated;
revoke all on all sequences in schema core, internal, audit from public, anon, authenticated;

insert into internal.migration_provenance (migration_name)
values ('20260807163737_s01_platform_identity_context');
