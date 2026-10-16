-- Contact pages (TEAM-15): 20 submissions per address and hour instead of 5
-- (2026-10-16). Several people in one household or on one mobile network can
-- share an address, and Turnstile, not this limit, stops automated
-- submissions. The cap of 500 submissions per page is unchanged.

do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('internal.public_submit_intake(text,text,text,text,date,text,text,text,text)'::regprocedure);
  patched := replace(definition, $old$and s.created_at>now()-interval '1 hour')>=5$old$,
    $new$and s.created_at>now()-interval '1 hour')>=20$new$);
  if patched = definition then raise exception 'intake rate limit changed'; end if;
  execute patched;
end;
$migration$;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261031090000_intake_rate_limit', 'greenfield', 'Contact pages: 20 submissions per address and hour'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261031090000_intake_rate_limit');
notify pgrst, 'reload schema';
