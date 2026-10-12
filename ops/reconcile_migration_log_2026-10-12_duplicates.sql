-- Removes 40 duplicate rows from Supabase's migration log. These migrations
-- were applied through a tool that logged them under its own timestamp; the
-- same migrations are now also logged under the repository's version (see
-- reconcile_migration_log_2026-10-11.sql). A row is only removed when another
-- row with the same name remains, so nothing is lost from the log.
-- Touches only supabase_migrations.schema_migrations; safe to run more than once.

delete from supabase_migrations.schema_migrations duplicate
where duplicate.version in (
  '20260923075257',
  '20260924103514',
  '20260924110419',
  '20260924143901',
  '20260924201050',
  '20260924201711',
  '20260924203441',
  '20260924204231',
  '20260925073924',
  '20260925180840',
  '20260925180846',
  '20260925202603',
  '20260925211405',
  '20260925211422',
  '20260926060035',
  '20260926060224',
  '20260926064927',
  '20260926145323',
  '20260926153041',
  '20260928110708',
  '20260929102208',
  '20261002091313',
  '20261002091330',
  '20261002102355',
  '20261002103941',
  '20261002123046',
  '20261002132928',
  '20261002140738',
  '20261002143344',
  '20261002190710',
  '20261003063444',
  '20261003065234',
  '20261003071501',
  '20261003072249',
  '20261003084903',
  '20261003091834',
  '20261003095804',
  '20261003100040',
  '20261003101053',
  '20261003111134'
)
and exists (
  select 1 from supabase_migrations.schema_migrations kept
  where kept.name = duplicate.name and kept.version <> duplicate.version
);
