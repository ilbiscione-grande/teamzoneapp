do $$
declare definition text; corrected text;
begin
 definition:=pg_get_functiondef('internal.apply_match_command_v2(uuid,uuid,bigint,text,jsonb)'::regprocedure);
 corrected:=replace(
  definition,
  'select fact.id,p_event_id,fact.fact_revision,to_jsonb(fact),''voided'',auth.uid(),''reset'' from core.match_facts fact where fact.event_id=p_event_id and fact.state=''voided'' and fact.void_reason=''reset'';',
  'select f.id,p_event_id,f.fact_revision,to_jsonb(f),''voided'',auth.uid(),''reset'' from core.match_facts f where f.event_id=p_event_id and f.state=''voided'' and f.void_reason=''reset'' on conflict(fact_id,fact_revision) do nothing;'
 );
 if corrected=definition then raise exception 'S07 reset patch target not found'; end if;
 execute corrected;
end$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815080102_s07_fix_reset_fact_versioning','greenfield','S07 reset audit fix');
