-- Handlers that caught a conflict as serialization_failure also catch PT409.
-- 20270213090000 changed every conflict raise from 40001 to PT409, so a
-- handler that only caught serialization_failure stopped catching them. The
-- series plan worker (internal.run_booking_series_plans) skipped a plan whose
-- author or configuration won the lock and retried next run; without this it
-- would pause the plan as generation_failed instead.
-- Rerunning is safe: a changed handler no longer matches.
do $migration$
declare target oid; definition text; changed integer := 0;
begin
  for target in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.prokind in ('f', 'p') and n.nspname not in ('pg_catalog', 'information_schema')
      and p.prosrc ~* 'when\s+serialization_failure\s+then'
  loop
    definition := regexp_replace(pg_get_functiondef(target),
      'when\s+serialization_failure\s+then', 'when serialization_failure or sqlstate ''PT409'' then', 'gi');
    execute definition; changed := changed + 1;
  end loop;
  raise notice 'conflict handlers with PT409: % functions', changed;
end;
$migration$;
