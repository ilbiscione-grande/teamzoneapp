-- Renaming the inner claim function does not rewrite qualified PL/pgSQL
-- parameter references in its stored body. Repair that reference explicitly.
do $$
declare
  definition text;
  broken_reference constant text:=
    'accept_guardian_invite_for_actor.idempotency_key';
  fixed_reference constant text:=
    'accept_guardian_invite_and_link_for_actor.idempotency_key';
begin
  select pg_get_functiondef(
    'internal.accept_guardian_invite_and_link_for_actor(text,uuid)'::regprocedure
  ) into definition;
  if definition is null or position(broken_reference in definition)=0 then
    raise exception 'guardian_claim_rename_reference_not_found';
  end if;
  execute replace(definition,broken_reference,fixed_reference);
end;
$$;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values (
  '20260902215140_team05_fix_renamed_guardian_claim_parameter',
  'greenfield',
  'TEAM-05 repair qualified parameter after guardian claim rename'
);

notify pgrst,'reload schema';
