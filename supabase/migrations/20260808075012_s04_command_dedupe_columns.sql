do $$
declare function_row record; definition text;
begin
  for function_row in
    select procedure.oid
    from pg_proc procedure join pg_namespace namespace on namespace.oid=procedure.pronamespace
    where namespace.nspname='internal' and procedure.proname in (
      'lock_squad_for_actor','send_callups_for_actor','respond_callup_for_actor',
      'cancel_or_remind_callup_for_actor','record_attendance_for_actor'
    )
  loop
    definition:=pg_get_functiondef(function_row.oid);
    definition:=replace(definition,
      'insert into internal.command_deduplication values(actor_id,idempotency_key,',
      'insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result,created_at) values(actor_id,idempotency_key,');
    execute definition;
  end loop;
end $$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808075012_s04_command_dedupe_columns','greenfield',null);
