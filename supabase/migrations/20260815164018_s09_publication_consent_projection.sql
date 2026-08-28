-- S09 consent and fail-closed publication projection foundation.
-- This migration creates no public client grant and does not enable publishing.

create table core.person_age_assertions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  club_person_id uuid not null,
  age_band text not null check (age_band in ('through_15', '16_plus')),
  state text not null default 'active' check (state in ('active', 'superseded', 'revoked')),
  verified_at timestamptz not null,
  valid_until date not null,
  evidence_hash bytea not null check (octet_length(evidence_hash) = 32),
  verified_by uuid not null references core.profiles(id),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  foreign key (club_person_id, club_id) references core.club_people(id, club_id),
  check (valid_until <= (verified_at at time zone 'UTC')::date + 366),
  check ((state = 'revoked') = (revoked_at is not null))
);

create unique index person_age_assertions_one_active_idx
  on core.person_age_assertions(club_id, club_person_id)
  where state = 'active';
create index person_age_assertions_validity_idx
  on core.person_age_assertions(club_id, valid_until, club_person_id)
  where state = 'active';
create index person_age_assertions_verified_by_idx
  on core.person_age_assertions(verified_by);

create table core.publication_consents (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  subject_club_person_id uuid not null,
  field_class text not null check (
    field_class in ('name', 'profile_media', 'position', 'individual_statistics')
  ),
  purpose_code text not null default 'public_team_profile_v1'
    check (purpose_code = 'public_team_profile_v1'),
  state text not null default 'active' check (state in ('active', 'withdrawn', 'expired', 'superseded')),
  subject_approved_at timestamptz not null,
  subject_approved_by uuid not null references core.profiles(id),
  guardian_club_person_id uuid,
  guardian_approved_at timestamptz,
  guardian_approved_by uuid references core.profiles(id),
  age_assertion_id uuid not null,
  season_ends_on date not null,
  expires_at timestamptz not null,
  withdrawn_at timestamptz,
  withdrawn_by uuid references core.profiles(id),
  withdrawal_reason text,
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  foreign key (subject_club_person_id, club_id) references core.club_people(id, club_id),
  foreign key (guardian_club_person_id, club_id) references core.club_people(id, club_id),
  foreign key (age_assertion_id, club_id) references core.person_age_assertions(id, club_id),
  check (expires_at > subject_approved_at),
  check (expires_at <= subject_approved_at + interval '366 days'),
  check (expires_at::date <= season_ends_on),
  check (
    (guardian_club_person_id is null and guardian_approved_at is null and guardian_approved_by is null)
    or
    (guardian_club_person_id is not null and guardian_approved_at is not null and guardian_approved_by is not null)
  ),
  check (
    (state = 'withdrawn' and withdrawn_at is not null and withdrawn_by is not null
      and length(btrim(withdrawal_reason)) between 2 and 500)
    or
    (state <> 'withdrawn' and withdrawn_at is null and withdrawn_by is null and withdrawal_reason is null)
  )
);

create unique index publication_consents_one_active_field_idx
  on core.publication_consents(club_id, subject_club_person_id, field_class, purpose_code)
  where state = 'active';
create index publication_consents_expiry_idx
  on core.publication_consents(club_id, expires_at, subject_club_person_id)
  where state = 'active';
create index publication_consents_age_assertion_idx
  on core.publication_consents(age_assertion_id, club_id);
create index publication_consents_guardian_idx
  on core.publication_consents(club_id, guardian_club_person_id)
  where guardian_club_person_id is not null;
create index publication_consents_subject_approved_by_idx
  on core.publication_consents(subject_approved_by);
create index publication_consents_guardian_approved_by_idx
  on core.publication_consents(guardian_approved_by)
  where guardian_approved_by is not null;
create index publication_consents_withdrawn_by_idx
  on core.publication_consents(withdrawn_by)
  where withdrawn_by is not null;

create table core.club_publication_settings (
  club_id uuid primary key references core.clubs(id),
  mode text not null default 'private' check (mode in ('private', 'draft')),
  public_id uuid not null default gen_random_uuid() unique,
  slug text not null unique check (
    slug = lower(slug) and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 2 and 80
  ),
  locality text,
  published_description text,
  public_profile_file_id uuid references core.file_objects(id),
  changed_at timestamptz not null default now(),
  changed_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  check (locality is null or length(btrim(locality)) between 1 and 120),
  check (published_description is null or length(published_description) <= 4000)
);

create index club_publication_settings_changed_by_idx
  on core.club_publication_settings(changed_by);
create index club_publication_settings_file_idx
  on core.club_publication_settings(public_profile_file_id)
  where public_profile_file_id is not null;

create table core.team_publication_settings (
  team_id uuid primary key,
  club_id uuid not null,
  mode text not null default 'private' check (mode in ('private', 'draft')),
  public_id uuid not null default gen_random_uuid() unique,
  slug text not null check (
    slug = lower(slug) and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 1 and 80
  ),
  published_age_class text,
  changed_at timestamptz not null default now(),
  changed_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (club_id, slug),
  unique (team_id, club_id),
  foreign key (team_id, club_id) references core.teams(id, club_id),
  check (published_age_class is null or length(btrim(published_age_class)) between 1 and 80)
);

create index team_publication_settings_club_idx
  on core.team_publication_settings(club_id, team_id);
create index team_publication_settings_changed_by_idx
  on core.team_publication_settings(changed_by);

create table internal.publication_projection_jobs (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  aggregate_type text not null check (aggregate_type in ('club', 'team', 'event', 'publication', 'person')),
  aggregate_id uuid not null,
  requested_revision bigint not null check (requested_revision > 0),
  action text not null check (action in ('rebuild', 'remove', 'invalidate')),
  state text not null default 'pending' check (state in ('pending', 'processing', 'completed', 'failed')),
  affected_paths text[] not null default array[]::text[],
  attempts integer not null default 0 check (attempts between 0 and 20),
  available_at timestamptz not null default now(),
  completed_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  unique (club_id, aggregate_type, aggregate_id, requested_revision, action),
  check (cardinality(affected_paths) <= 20),
  check ((state = 'completed') = (completed_at is not null))
);

create index publication_projection_jobs_worker_idx
  on internal.publication_projection_jobs(state, available_at, created_at, id)
  where state in ('pending', 'failed');
create index publication_projection_jobs_club_idx
  on internal.publication_projection_jobs(club_id, created_at desc, id desc);
create index publication_projection_jobs_created_by_idx
  on internal.publication_projection_jobs(created_by)
  where created_by is not null;

create table public_api.club_projections (
  public_id uuid primary key,
  slug text not null unique,
  name text not null,
  locality text,
  description text,
  profile_media_path text,
  source_revision bigint not null check (source_revision > 0),
  projected_at timestamptz not null,
  check (slug = lower(slug) and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  check (profile_media_path is null or profile_media_path ~ '^/media/public/[A-Za-z0-9_-]+$')
);

create table public_api.team_projections (
  public_id uuid primary key,
  club_public_id uuid not null references public_api.club_projections(public_id) on delete cascade,
  club_slug text not null,
  slug text not null,
  name text not null,
  age_class text,
  source_revision bigint not null check (source_revision > 0),
  projected_at timestamptz not null,
  unique (club_public_id, slug),
  unique (club_slug, slug)
);

create index team_projections_club_cursor_idx
  on public_api.team_projections(club_public_id, slug, public_id);

alter table core.person_age_assertions enable row level security;
alter table core.publication_consents enable row level security;
alter table core.club_publication_settings enable row level security;
alter table core.team_publication_settings enable row level security;
alter table internal.publication_projection_jobs enable row level security;
alter table public_api.club_projections enable row level security;
alter table public_api.team_projections enable row level security;

create policy person_age_assertions_no_client_access
  on core.person_age_assertions for all to authenticated using (false) with check (false);
create policy publication_consents_no_client_access
  on core.publication_consents for all to authenticated using (false) with check (false);
create policy club_publication_settings_no_client_access
  on core.club_publication_settings for all to authenticated using (false) with check (false);
create policy team_publication_settings_no_client_access
  on core.team_publication_settings for all to authenticated using (false) with check (false);
create policy publication_projection_jobs_no_client_access
  on internal.publication_projection_jobs for all to authenticated using (false) with check (false);
create policy club_projections_no_client_access
  on public_api.club_projections for all to authenticated using (false) with check (false);
create policy team_projections_no_client_access
  on public_api.team_projections for all to authenticated using (false) with check (false);

revoke all on table
  core.person_age_assertions,
  core.publication_consents,
  core.club_publication_settings,
  core.team_publication_settings,
  internal.publication_projection_jobs,
  public_api.club_projections,
  public_api.team_projections
from public, anon, authenticated;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values (
  '20260815164018_s09_publication_consent_projection',
  'greenfield',
  'Approved PAR-PRIV-02/PAR-API-01/PAR-OPS-01/PAR-OPS-02; runtime remains structurally disabled'
);
