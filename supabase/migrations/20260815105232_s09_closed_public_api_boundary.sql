-- S09 preparation only. The public surface cannot be enabled until every
-- named P0 privacy/API/operations parameter has been approved and migrated.

create schema if not exists public_api;

revoke all on schema public_api from public, anon, authenticated;
alter default privileges for role postgres in schema public_api
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public_api
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public_api
  revoke execute on functions from public, anon, authenticated;

create table internal.publication_runtime_state (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false check(enabled = false),
  gate_version text not null default 's09-p0-open',
  changed_at timestamptz not null default now(),
  changed_by uuid references core.profiles(id),
  revision bigint not null default 1 check(revision > 0)
);

insert into internal.publication_runtime_state(singleton,enabled)
values(true,false);

alter table internal.publication_runtime_state enable row level security;
create policy publication_runtime_state_no_client_access
  on internal.publication_runtime_state for all to authenticated
  using(false) with check(false);

revoke all on table internal.publication_runtime_state from public,anon,authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260815105232_s09_closed_public_api_boundary',
  'greenfield',
  'PAR-PRIV-02/PAR-API-01/PAR-OPS-01/PAR-OPS-02 open; public surface structurally disabled'
);
