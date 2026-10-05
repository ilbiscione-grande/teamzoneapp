-- A reminder answers the "Obesvarade kallelser" warning for a while: an
-- unanswered callup reminded within the last 6 hours no longer counts,
-- matching the server's six-hour reminder cooldown: once another reminder
-- may be sent and the callup is still unanswered, the warning returns.
do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('internal.get_leader_home_for_actor(uuid)'::regprocedure);
  patched := replace(definition,
    'and event_row.state=''scheduled''and callup.state=''pending''',
    'and event_row.state=''scheduled''and callup.state=''pending''
    and(callup.last_reminded_at is null or callup.last_reminded_at<=observed_at-interval ''6 hours'')');
  if patched = definition then raise exception 'pending callups task contract changed'; end if;
  execute patched;
end;
$migration$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261005140000_assistant_pending_callups_reminder_quiet','greenfield',
  'A sent reminder quiets the unanswered-callups warning for 6 hours');
notify pgrst,'reload schema';
