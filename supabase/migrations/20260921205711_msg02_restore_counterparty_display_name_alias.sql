-- Restore the lateral result column name consumed by the surrounding query.
do $$
declare
  function_definition text;
  updated_definition text;
begin
  function_definition := pg_get_functiondef(
    'internal.list_threads_for_actor(uuid[],timestamp with time zone,integer)'::regprocedure
  );

  updated_definition := replace(
    function_definition,
    'select COALESCE(NULLIF(btrim(other_profile.display_name), ''''), NULLIF(btrim(other_club_person.display_name), ''''), ''Deltagare'')',
    'select COALESCE(NULLIF(btrim(other_profile.display_name), ''''), NULLIF(btrim(other_club_person.display_name), ''''), ''Deltagare'') as display_name'
  );

  if updated_definition = function_definition then
    raise exception 'msg02_counterparty_display_name_alias_patch_not_applied';
  end if;

  execute updated_definition;
end
$$;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260921205711_msg02_restore_counterparty_display_name_alias',
  'greenfield',
  'MSG-02 restore lateral counterparty display_name alias after fallback expansion'
);

notify pgrst, 'reload schema';
