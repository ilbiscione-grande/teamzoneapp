\set ON_ERROR_STOP on
set role postgres;
begin;

do $$
declare row record;
begin
  for row in
    select namespace.nspname as schema_name,class.relname as object_name,class.oid
    from pg_class class
    join pg_namespace namespace on namespace.oid=class.relnamespace
    where namespace.nspname in ('core','internal','audit')
      and class.relkind in ('r','p','v','m','S')
  loop
    if row.schema_name='core' and exists(
      select 1 from pg_class candidate
      where candidate.oid=row.oid and candidate.relkind in ('r','p')
        and not candidate.relrowsecurity
    ) then
      raise exception 'core table %.% does not have RLS enabled',row.schema_name,row.object_name;
    end if;
    if has_table_privilege('anon',row.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
       or has_table_privilege('authenticated',row.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
      raise exception 'direct client table privilege found on %.%',row.schema_name,row.object_name;
    end if;
  end loop;

  for row in
    select procedure.oid,namespace.nspname as schema_name,procedure.proname
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid=procedure.pronamespace
    where namespace.nspname='api'
  loop
    if has_function_privilege('anon',row.oid,'EXECUTE') then
      raise exception 'anon can execute custom API function %.%',row.schema_name,row.proname;
    end if;
  end loop;

  if has_schema_privilege('anon','api','USAGE')
     or has_schema_privilege('anon','internal','USAGE') then
    raise exception 'anon has custom schema usage';
  end if;
end$$;

select 'X-QA privilege diff passed' as result;
rollback;

