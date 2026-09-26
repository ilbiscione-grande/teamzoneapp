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
    'context.team_id = scope.team_id',
    '(scope.team_id IS NULL OR context.team_id = scope.team_id)'
  );

  if updated_definition = function_definition then
    raise exception 'msg02_club_scope_visibility_patch_not_applied';
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
  '20260921202524_msg02_show_club_scoped_threads_in_team_contexts',
  'greenfield',
  'MSG-02 club-scoped participant threads remain visible from team-only contexts'
);

notify pgrst, 'reload schema';
