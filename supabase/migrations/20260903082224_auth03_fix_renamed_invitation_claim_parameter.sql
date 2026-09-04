-- Renaming the inner claim function does not rewrite qualified PL/pgSQL
-- parameter references in its stored body. Repair that reference explicitly.
do $$
declare
  definition text;
  broken_reference constant text:=
    'claim_roster_invitation_v2.idempotency_key';
  fixed_reference constant text:=
    'claim_roster_invitation_link_only_v2.idempotency_key';
begin
  select pg_get_functiondef(
    'internal.claim_roster_invitation_link_only_v2(text,uuid)'::regprocedure
  ) into definition;
  if definition is null or position(broken_reference in definition)=0 then
    raise exception 'invitation_claim_rename_reference_not_found';
  end if;
  execute replace(definition,broken_reference,fixed_reference);
end;
$$;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values (
  '20260903082224_auth03_fix_renamed_invitation_claim_parameter',
  'greenfield',
  'AUTH-03 repair qualified parameter after invitation claim rename'
);

notify pgrst,'reload schema';
