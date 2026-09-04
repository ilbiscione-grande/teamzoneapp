-- CAL-06's draft command rejects archived events. Keep this prerequisite
-- intentionally smaller than CAL-04 so unrelated, not-yet-published lifecycle
-- commands are not pulled into the REL-02 runtime rollout.

alter table core.events
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references core.profiles(id),
  add column if not exists archive_reason text;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conname = 'events_archive_shape_check'
      and constraint_row.conrelid = 'core.events'::regclass
  ) then
    alter table core.events
      add constraint events_archive_shape_check check (
        (archived_at is null and archived_by is null and archive_reason is null)
        or (
          archived_at is not null
          and archived_by is not null
          and length(btrim(archive_reason)) between 3 and 500
        )
      );
  end if;
end;
$$;

create index if not exists events_archived_idx
on core.events(archived_at, id)
where archived_at is not null;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260831201834_cal06_runtime_archival_prerequisite',
  'greenfield',
  'REL-02 targeted CAL-06 runtime prerequisite; CAL-04 remains separately gated'
)
on conflict do nothing;

notify pgrst, 'reload schema';
