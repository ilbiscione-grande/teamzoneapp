do $$
declare
  definition text;
begin
  select pg_get_functiondef(procedure.oid) into definition
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'internal'
    and procedure.proname = 'get_main_surfaces_for_actor';

  if definition is null then
    raise exception 'get_main_surfaces_for_actor_not_found';
  end if;

  definition := replace(
    definition,
    'person.state = ''active''',
    'person.status = ''active'''
  );
  execute definition;
end;
$$;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values ('20260808095006_s05_fix_club_person_status', 'greenfield', null);
