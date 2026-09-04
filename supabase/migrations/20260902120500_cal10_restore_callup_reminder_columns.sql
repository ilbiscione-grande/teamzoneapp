-- Restore CAL-07 columns required by the current squad projection.
alter table core.callups
  add column if not exists last_reminded_at timestamptz;

alter table core.callups
  add column if not exists reminder_count integer not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid='core.callups'::regclass
      and conname='callups_reminder_count_nonnegative'
  ) then
    alter table core.callups
      add constraint callups_reminder_count_nonnegative
      check(reminder_count>=0);
  end if;
end;
$$;

create index if not exists callups_reminder_due_idx
  on core.callups(last_reminded_at,event_id)
  where state='pending';

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values (
  '20260902120500_cal10_restore_callup_reminder_columns',
  'greenfield',
  'CAL-10 explicit CAL-07 reminder-column dependency repair'
);

notify pgrst,'reload schema';
