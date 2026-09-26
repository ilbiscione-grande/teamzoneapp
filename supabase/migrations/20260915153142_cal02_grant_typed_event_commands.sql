-- CAL-02 follow-up: API wrappers are security invokers and therefore need
-- authenticated callers to be able to enter the guarded internal commands.
grant execute on function internal.create_event_v2_for_actor(
  uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,text,text[],
  text,text,integer,integer,jsonb,uuid
) to authenticated;
grant execute on function internal.revise_event_v3_for_actor(
  uuid,text,jsonb,bigint,uuid
) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260915153142_cal02_grant_typed_event_commands','greenfield','CAL-02 authenticated API wrapper execution fix');
notify pgrst,'reload schema';
