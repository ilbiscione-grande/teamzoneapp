-- REL-02 targeted runtime prerequisite for HOME-02/HOME-03.
-- This is the exact private visibility model introduced by MSG-07, made
-- idempotent so the regular migration tail can be applied later.

create table if not exists core.thread_personal_visibility (
  thread_id uuid not null references core.message_threads(id) on delete cascade,
  profile_id uuid not null references core.profiles(id),
  hidden boolean not null default true,
  hidden_at timestamptz,
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  primary key (thread_id, profile_id),
  check ((hidden and hidden_at is not null) or (not hidden and hidden_at is null))
);

alter table core.thread_personal_visibility enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'core'
      and tablename = 'thread_personal_visibility'
      and policyname = 'thread_personal_visibility_no_direct_access'
  ) then
    create policy thread_personal_visibility_no_direct_access
      on core.thread_personal_visibility
      for all to authenticated
      using (false)
      with check (false);
  end if;
end
$$;

create index if not exists thread_personal_visibility_profile_idx
  on core.thread_personal_visibility (profile_id, hidden, thread_id);

revoke all on table core.thread_personal_visibility
  from public, anon, authenticated;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
select
  '20260831055301_rel02_home_projection_runtime_prerequisites',
  'greenfield',
  'REL-02 private hidden-thread prerequisite for targeted role home rollout'
where not exists (
  select 1
  from internal.migration_provenance
  where migration_name = '20260831055301_rel02_home_projection_runtime_prerequisites'
);
