-- A conflict ("someone saved first") is no longer raised as SQLSTATE 40001.
--
-- PostgREST 14 takes 40001 (serialization_failure) as a passing clash and
-- runs the whole call again, with no end: a stale save of a tactics project
-- on 2026-11-07 ran about 330 times a second for hours and drove production
-- CPU over 80 %. Supabase documents the fault (fixed in PostgREST 16).
--
-- Every function that raises serialization_failure is defined again with
-- SQLSTATE PT409 instead: PostgREST answers HTTP 409 with the same message
-- (stale_revision and the others), so clients that read the message see no
-- change. Clients that read the code accept PT409 as well as 40001.
--
-- The definitions are taken from the database itself, so whatever is there,
-- in whichever order its migrations ran, is covered. create or replace keeps
-- each function's owner, grants, settings and comment.
-- supabase/tests/conflicts_without_retry.local.mjs keeps 40001 out of later
-- migrations.
do $migration$
declare
  target oid;
  definition text;
  changed integer := 0;
begin
  for target in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prokind in ('f', 'p')
      and n.nspname not in ('pg_catalog', 'information_schema')
      and p.prosrc ~* 'raise\s+serialization_failure'
  loop
    definition := regexp_replace(pg_get_functiondef(target), 'raise\s+serialization_failure\s+using', 'raise sqlstate ''PT409'' using', 'gi');
    if definition ~* 'raise\s+serialization_failure' then
      raise exception 'conflict code left in %', target::regprocedure;
    end if;
    execute definition;
    changed := changed + 1;
  end loop;
  raise notice 'conflicts without retry: % functions', changed;
end;
$migration$;
