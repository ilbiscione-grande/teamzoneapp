-- Attendance export to external systems (first receiver: laget.se).
--
-- TEMPORARY FEATURE. Everything lives in the attendance_export schema plus
-- thin api.attendance_export_* wrappers, so the feature can be removed with
-- supabase/removal/attendance_export_remove.sql without touching core tables.
-- Core attendance (core.attendance_facts) is only read, never changed.
-- No laget.se credentials are stored anywhere.

create schema if not exists attendance_export;
revoke all on schema attendance_export from public, anon, authenticated;

-- Per team and receiver: enabled flag, the team's identifier in the receiver
-- (for future sync) and receiver-specific settings.
create table attendance_export.team_integrations (
 club_id uuid not null,
 team_id uuid not null,
 provider text not null check (provider in ('laget_se')),
 enabled boolean not null default false,
 external_team_ref text check (external_team_ref is null or length(btrim(external_team_ref)) between 1 and 200),
 settings jsonb not null default '{}'::jsonb check (jsonb_typeof(settings) = 'object'),
 revision bigint not null default 1 check (revision > 0),
 changed_by uuid not null references core.profiles(id),
 changed_at timestamptz not null default now(),
 primary key (team_id, provider),
 foreign key (team_id, club_id) references core.teams(id, club_id) on delete cascade
);

-- One Teamzone person <-> one receiver person, per team. A person in several
-- teams has one link per team. source='import' is reserved for a future
-- member-list import (not implemented).
create table attendance_export.member_links (
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 team_id uuid not null,
 provider text not null check (provider in ('laget_se')),
 club_person_id uuid not null,
 external_id text not null check (external_id ~ '^[0-9]{1,20}$'),
 external_name text not null check (length(btrim(external_name)) between 1 and 160),
 external_role text not null check (external_role in ('player', 'leader')),
 source text not null default 'manual' check (source in ('manual', 'import')),
 revision bigint not null default 1 check (revision > 0),
 changed_by uuid not null references core.profiles(id),
 changed_at timestamptz not null default now(),
 unique (team_id, provider, club_person_id),
 -- The same external person can never be linked to two Teamzone people.
 unique (team_id, provider, external_id),
 foreign key (team_id, club_id) references core.teams(id, club_id) on delete cascade,
 foreign key (club_person_id, club_id) references core.club_people(id, club_id) on delete cascade
);

-- Teamzone event <-> receiver activity, per team (a shared event can map to
-- one activity per team) and per receiver.
create table attendance_export.activity_links (
 club_id uuid not null,
 event_id uuid not null,
 team_id uuid not null,
 provider text not null check (provider in ('laget_se')),
 external_activity_id text not null check (external_activity_id ~ '^[0-9]{1,20}$'),
 revision bigint not null default 1 check (revision > 0),
 changed_by uuid not null references core.profiles(id),
 changed_at timestamptz not null default now(),
 primary key (event_id, team_id, provider),
 unique (team_id, provider, external_activity_id),
 foreign key (event_id, club_id) references core.events(id, club_id) on delete cascade,
 foreign key (team_id, club_id) references core.teams(id, club_id) on delete cascade
);

-- Export log. Holds counts and a payload hash only, never names or the file.
-- 'file_created' does NOT mean synchronized; 'verified'/'rejected' are reserved
-- for future feedback from the external sync tool (not implemented).
create table attendance_export.exports (
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 team_id uuid not null,
 event_id uuid not null,
 provider text not null check (provider in ('laget_se')),
 state text not null check (state in ('file_created', 'failed', 'verified', 'rejected')),
 external_activity_id text check (external_activity_id is null or external_activity_id ~ '^[0-9]{1,20}$'),
 summary jsonb not null default '{}'::jsonb check (jsonb_typeof(summary) = 'object'),
 confirmed_complete boolean not null default false,
 payload_sha256 text check (payload_sha256 is null or payload_sha256 ~ '^[0-9a-f]{64}$'),
 error_code text check (error_code is null or length(error_code) <= 80),
 created_by uuid not null references core.profiles(id),
 created_at timestamptz not null default now(),
 verified_at timestamptz,
 verification_note text,
 check (state <> 'file_created' or (confirmed_complete and payload_sha256 is not null and external_activity_id is not null)),
 foreign key (event_id, club_id) references core.events(id, club_id) on delete cascade,
 foreign key (team_id, club_id) references core.teams(id, club_id) on delete cascade
);
create index exports_event_idx on attendance_export.exports(event_id, team_id, provider, created_at desc);
create index member_links_person_idx on attendance_export.member_links(club_person_id);

alter table attendance_export.team_integrations enable row level security;
alter table attendance_export.member_links enable row level security;
alter table attendance_export.activity_links enable row level security;
alter table attendance_export.exports enable row level security;
revoke all on all tables in schema attendance_export from public, anon, authenticated;

-- Team administrators manage settings and member links.
create function attendance_export.assert_team_admin(target_team_id uuid)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare club uuid;
begin
 select club_id into club from core.teams where id = target_team_id;
 if auth.uid() is null or club is null
  or not internal.actor_has_capability(club, target_team_id, 'team.roster.manage') then
  raise insufficient_privilege using message = 'not_found';
 end if;
 return club;
end$$;

-- Exports and activity links follow the event's attendance permission, and
-- the event must belong to the team.
create function attendance_export.assert_event_exporter(target_event_id uuid, target_team_id uuid)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare club uuid;
begin
 select event_row.club_id into club from core.events event_row
 join core.event_teams relation on relation.event_id = event_row.id and relation.club_id = event_row.club_id
 where event_row.id = target_event_id and relation.team_id = target_team_id;
 if auth.uid() is null or club is null
  or not internal.actor_can_manage_attendance(target_event_id) then
  raise insufficient_privilege using message = 'not_found';
 end if;
 return club;
end$$;

create function attendance_export.links_json(target_team_id uuid, target_provider text)
returns jsonb language sql stable security definer set search_path = '' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
   'id', link.id, 'team_id', link.team_id, 'person_id', link.club_person_id,
   'person_name', person.display_name, 'external_id', link.external_id,
   'external_name', link.external_name, 'external_role', link.external_role,
   'source', link.source, 'revision', link.revision)
   order by person.display_name), '[]'::jsonb)
 from attendance_export.member_links link
 join core.club_people person on person.id = link.club_person_id and person.club_id = link.club_id
 where link.team_id = target_team_id and link.provider = target_provider
$$;

create function attendance_export.get_team_integration(target_team_id uuid, target_provider text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare club uuid; setting attendance_export.team_integrations%rowtype;
begin
 club := attendance_export.assert_team_admin(target_team_id);
 select * into setting from attendance_export.team_integrations
 where team_id = target_team_id and provider = target_provider;
 return jsonb_build_object(
  'team_id', target_team_id, 'provider', target_provider,
  'enabled', coalesce(setting.enabled, false),
  'external_team_ref', setting.external_team_ref,
  'settings', coalesce(setting.settings, '{}'::jsonb),
  'revision', coalesce(setting.revision, 0),
  'members', coalesce((
   select jsonb_agg(jsonb_build_object('person_id', member.person_id, 'name', member.name,
     'role_packages', member.roles) order by member.name)
   from (select assignment.club_person_id person_id, person.display_name name,
     jsonb_agg(distinct assignment.role_package) roles
    from core.assignments assignment
    join core.club_people person on person.id = assignment.club_person_id and person.club_id = assignment.club_id
    where assignment.club_id = club and assignment.team_id = target_team_id
     and assignment.state = 'active' and assignment.role_package in ('player', 'leader')
     and person.status = 'active'
    group by assignment.club_person_id, person.display_name) member), '[]'::jsonb),
  'links', attendance_export.links_json(target_team_id, target_provider));
end$$;

create function attendance_export.set_team_integration(target_team_id uuid, target_provider text,
 new_enabled boolean, new_external_team_ref text, expected_revision bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare club uuid; current_revision bigint; next_revision bigint;
begin
 club := attendance_export.assert_team_admin(target_team_id);
 perform pg_advisory_xact_lock(hashtextextended('attendance-export-team:' || target_team_id::text, 0));
 select revision into current_revision from attendance_export.team_integrations
 where team_id = target_team_id and provider = target_provider;
 if coalesce(current_revision, 0) <> expected_revision then
  raise serialization_failure using message = 'revision_conflict';
 end if;
 if new_enabled is null then raise invalid_parameter_value using message = 'invalid_settings'; end if;
 insert into attendance_export.team_integrations(club_id, team_id, provider, enabled, external_team_ref, changed_by)
 values (club, target_team_id, target_provider, new_enabled, nullif(btrim(new_external_team_ref), ''), auth.uid())
 on conflict (team_id, provider) do update set enabled = excluded.enabled,
  external_team_ref = excluded.external_team_ref, revision = attendance_export.team_integrations.revision + 1,
  changed_by = excluded.changed_by, changed_at = now()
 returning revision into next_revision;
 insert into audit.command_events(club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
 values (club, auth.uid(), 'attendance_export.team.configure', 'team', target_team_id, next_revision,
  jsonb_build_object('provider', target_provider, 'enabled', new_enabled));
 return attendance_export.get_team_integration(target_team_id, target_provider);
end$$;

create function attendance_export.save_member_link(target_team_id uuid, target_provider text,
 target_person_id uuid, new_external_id text, new_external_name text, new_external_role text, expected_revision bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare club uuid; current_revision bigint;
begin
 club := attendance_export.assert_team_admin(target_team_id);
 perform pg_advisory_xact_lock(hashtextextended('attendance-export-team:' || target_team_id::text, 0));
 if not exists (select 1 from core.club_people where id = target_person_id and club_id = club) then
  raise insufficient_privilege using message = 'not_found';
 end if;
 if new_external_id is null or new_external_id !~ '^[0-9]{1,20}$' then
  raise invalid_parameter_value using message = 'invalid_external_id';
 end if;
 if new_external_name is null or length(btrim(new_external_name)) not between 1 and 160 then
  raise invalid_parameter_value using message = 'invalid_external_name';
 end if;
 if new_external_role is null or new_external_role not in ('player', 'leader') then
  raise invalid_parameter_value using message = 'invalid_external_role';
 end if;
 if exists (select 1 from attendance_export.member_links where team_id = target_team_id
   and provider = target_provider and external_id = new_external_id and club_person_id <> target_person_id) then
  raise unique_violation using message = 'external_id_taken';
 end if;
 select revision into current_revision from attendance_export.member_links
 where team_id = target_team_id and provider = target_provider and club_person_id = target_person_id;
 if coalesce(current_revision, 0) <> expected_revision then
  raise serialization_failure using message = 'revision_conflict';
 end if;
 insert into attendance_export.member_links(club_id, team_id, provider, club_person_id, external_id,
  external_name, external_role, changed_by)
 values (club, target_team_id, target_provider, target_person_id, new_external_id, btrim(new_external_name),
  new_external_role, auth.uid())
 on conflict (team_id, provider, club_person_id) do update set external_id = excluded.external_id,
  external_name = excluded.external_name, external_role = excluded.external_role, source = 'manual',
  revision = attendance_export.member_links.revision + 1, changed_by = excluded.changed_by, changed_at = now();
 return attendance_export.get_team_integration(target_team_id, target_provider);
end$$;

create function attendance_export.delete_member_link(target_team_id uuid, target_provider text,
 target_person_id uuid, expected_revision bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare deleted int;
begin
 perform attendance_export.assert_team_admin(target_team_id);
 delete from attendance_export.member_links where team_id = target_team_id and provider = target_provider
  and club_person_id = target_person_id and revision = expected_revision;
 get diagnostics deleted = row_count;
 if deleted = 0 then raise serialization_failure using message = 'revision_conflict'; end if;
 return attendance_export.get_team_integration(target_team_id, target_provider);
end$$;

-- Everything the export needs besides the attendance itself (which the app
-- reads through the existing api.get_event_squad).
create function attendance_export.get_export_context(target_event_id uuid, target_team_id uuid, target_provider text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare club uuid; event_row core.events%rowtype; setting attendance_export.team_integrations%rowtype;
begin
 club := attendance_export.assert_event_exporter(target_event_id, target_team_id);
 select * into event_row from core.events where id = target_event_id;
 select * into setting from attendance_export.team_integrations
 where team_id = target_team_id and provider = target_provider;
 return jsonb_build_object(
  'event_id', event_row.id, 'team_id', target_team_id,
  'team_name', (select name from core.teams where id = target_team_id),
  'provider', target_provider,
  'enabled', coalesce(setting.enabled, false),
  'activity_link', (select jsonb_build_object('external_activity_id', link.external_activity_id,
    'team_id', link.team_id, 'revision', link.revision)
   from attendance_export.activity_links link
   where link.event_id = target_event_id and link.team_id = target_team_id and link.provider = target_provider),
  -- The team's player/leader assignments valid at the event, so the app can
  -- tell team members from guests and members of other (shared) teams.
  'team_roster', coalesce((select jsonb_agg(jsonb_build_object(
    'person_id', assignment.club_person_id, 'role_package', assignment.role_package))
   from core.assignments assignment
   where assignment.club_id = club and assignment.team_id = target_team_id
    and assignment.state = 'active' and assignment.role_package in ('player', 'leader')
    and assignment.starts_at <= event_row.starts_at
    and (assignment.ends_at is null or assignment.ends_at > event_row.starts_at)), '[]'::jsonb),
  'links', attendance_export.links_json(target_team_id, target_provider),
  'exports', coalesce((select jsonb_agg(jsonb_build_object('id', export_row.id, 'state', export_row.state,
    'external_activity_id', export_row.external_activity_id, 'summary', export_row.summary,
    'payload_sha256', export_row.payload_sha256, 'error_code', export_row.error_code,
    'created_at', export_row.created_at, 'verified_at', export_row.verified_at)
    order by export_row.created_at desc)
   from (select * from attendance_export.exports
    where event_id = target_event_id and team_id = target_team_id and provider = target_provider
    order by created_at desc limit 10) export_row), '[]'::jsonb));
end$$;

create function attendance_export.set_activity_link(target_event_id uuid, target_team_id uuid,
 target_provider text, new_external_activity_id text, expected_revision bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare club uuid; current_revision bigint;
begin
 club := attendance_export.assert_event_exporter(target_event_id, target_team_id);
 perform pg_advisory_xact_lock(hashtextextended('attendance-export-team:' || target_team_id::text, 0));
 select revision into current_revision from attendance_export.activity_links
 where event_id = target_event_id and team_id = target_team_id and provider = target_provider;
 if coalesce(current_revision, 0) <> expected_revision then
  raise serialization_failure using message = 'revision_conflict';
 end if;
 if new_external_activity_id is null then
  delete from attendance_export.activity_links
  where event_id = target_event_id and team_id = target_team_id and provider = target_provider;
  return attendance_export.get_export_context(target_event_id, target_team_id, target_provider);
 end if;
 if new_external_activity_id !~ '^[0-9]{1,20}$' then
  raise invalid_parameter_value using message = 'invalid_external_activity_id';
 end if;
 if exists (select 1 from attendance_export.activity_links where team_id = target_team_id
   and provider = target_provider and external_activity_id = new_external_activity_id and event_id <> target_event_id) then
  raise unique_violation using message = 'external_activity_taken';
 end if;
 insert into attendance_export.activity_links(club_id, event_id, team_id, provider, external_activity_id, changed_by)
 values (club, target_event_id, target_team_id, target_provider, new_external_activity_id, auth.uid())
 on conflict (event_id, team_id, provider) do update set external_activity_id = excluded.external_activity_id,
  revision = attendance_export.activity_links.revision + 1, changed_by = excluded.changed_by, changed_at = now();
 return attendance_export.get_export_context(target_event_id, target_team_id, target_provider);
end$$;

-- Logs a created file or a failed attempt. The server re-checks the rules it
-- can see: integration enabled, event ended and not cancelled, activity link.
create function attendance_export.record_export(target_event_id uuid, target_team_id uuid, target_provider text,
 new_state text, new_external_activity_id text, new_summary jsonb, new_confirmed_complete boolean,
 new_payload_sha256 text, new_error_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare club uuid; event_row core.events%rowtype; new_id uuid;
begin
 club := attendance_export.assert_event_exporter(target_event_id, target_team_id);
 if new_state not in ('file_created', 'failed') then
  raise invalid_parameter_value using message = 'invalid_state';
 end if;
 if new_state = 'file_created' then
  select * into event_row from core.events where id = target_event_id;
  if not coalesce((select enabled from attendance_export.team_integrations
    where team_id = target_team_id and provider = target_provider), false) then
   raise invalid_parameter_value using message = 'integration_disabled';
  end if;
  if event_row.state not in ('scheduled', 'completed') or event_row.ends_at > now() then
   raise invalid_parameter_value using message = 'event_not_ended';
  end if;
  if not exists (select 1 from attendance_export.activity_links where event_id = target_event_id
    and team_id = target_team_id and provider = target_provider
    and external_activity_id = new_external_activity_id) then
   raise invalid_parameter_value using message = 'activity_link_mismatch';
  end if;
  if not coalesce(new_confirmed_complete, false) then
   raise invalid_parameter_value using message = 'not_confirmed';
  end if;
 end if;
 insert into attendance_export.exports(club_id, team_id, event_id, provider, state, external_activity_id,
  summary, confirmed_complete, payload_sha256, error_code, created_by)
 values (club, target_team_id, target_event_id, target_provider, new_state, new_external_activity_id,
  coalesce(new_summary, '{}'::jsonb), coalesce(new_confirmed_complete, false), new_payload_sha256,
  left(new_error_code, 80), auth.uid())
 returning id into new_id;
 return new_id;
end$$;

create function api.attendance_export_get_team_integration(team_id uuid, provider text)
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.get_team_integration(team_id, provider)$$;
create function api.attendance_export_set_team_integration(team_id uuid, provider text, enabled boolean,
 external_team_ref text, expected_revision bigint)
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.set_team_integration(team_id, provider, enabled, external_team_ref, expected_revision)$$;
create function api.attendance_export_save_member_link(team_id uuid, provider text, person_id uuid,
 external_id text, external_name text, external_role text, expected_revision bigint)
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.save_member_link(team_id, provider, person_id, external_id, external_name, external_role, expected_revision)$$;
create function api.attendance_export_delete_member_link(team_id uuid, provider text, person_id uuid, expected_revision bigint)
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.delete_member_link(team_id, provider, person_id, expected_revision)$$;
create function api.attendance_export_get_context(event_id uuid, team_id uuid, provider text)
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.get_export_context(event_id, team_id, provider)$$;
create function api.attendance_export_set_activity_link(event_id uuid, team_id uuid, provider text,
 external_activity_id text, expected_revision bigint)
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.set_activity_link(event_id, team_id, provider, external_activity_id, expected_revision)$$;
create function api.attendance_export_record(event_id uuid, team_id uuid, provider text, state text,
 external_activity_id text, summary jsonb, confirmed_complete boolean, payload_sha256 text, error_code text)
returns uuid language sql security invoker set search_path = '' as
$$select attendance_export.record_export(event_id, team_id, provider, state, external_activity_id, summary, confirmed_complete, payload_sha256, error_code)$$;

revoke all on all functions in schema attendance_export from public, anon, authenticated;
revoke all on function api.attendance_export_get_team_integration(uuid, text),
 api.attendance_export_set_team_integration(uuid, text, boolean, text, bigint),
 api.attendance_export_save_member_link(uuid, text, uuid, text, text, text, bigint),
 api.attendance_export_delete_member_link(uuid, text, uuid, bigint),
 api.attendance_export_get_context(uuid, uuid, text),
 api.attendance_export_set_activity_link(uuid, uuid, text, text, bigint),
 api.attendance_export_record(uuid, uuid, text, text, text, jsonb, boolean, text, text)
 from public, anon;
-- The SQL wrappers run as the caller, so the caller needs USAGE on the schema
-- and EXECUTE on the guarded entry points (the tables stay closed).
grant usage on schema attendance_export to authenticated;
grant execute on function attendance_export.get_team_integration(uuid, text),
 attendance_export.set_team_integration(uuid, text, boolean, text, bigint),
 attendance_export.save_member_link(uuid, text, uuid, text, text, text, bigint),
 attendance_export.delete_member_link(uuid, text, uuid, bigint),
 attendance_export.get_export_context(uuid, uuid, text),
 attendance_export.set_activity_link(uuid, uuid, text, text, bigint),
 attendance_export.record_export(uuid, uuid, text, text, text, jsonb, boolean, text, text)
 to authenticated;
grant execute on function api.attendance_export_get_team_integration(uuid, text),
 api.attendance_export_set_team_integration(uuid, text, boolean, text, bigint),
 api.attendance_export_save_member_link(uuid, text, uuid, text, text, text, bigint),
 api.attendance_export_delete_member_link(uuid, text, uuid, bigint),
 api.attendance_export_get_context(uuid, uuid, text),
 api.attendance_export_set_activity_link(uuid, uuid, text, text, bigint),
 api.attendance_export_record(uuid, uuid, text, text, text, jsonb, boolean, text, text)
 to authenticated;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values ('20261013090000_attendance_export_laget_se', 'greenfield',
 'Temporary, removable attendance export to laget.se (own schema attendance_export)');
notify pgrst, 'reload schema';
