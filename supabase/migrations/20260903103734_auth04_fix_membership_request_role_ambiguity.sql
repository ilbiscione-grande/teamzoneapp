-- PostgreSQL treats the input parameter and the conflict-target column named
-- requested_role as ambiguous inside the original PL/pgSQL function. Keep the
-- public RPC parameter contract intact while making the resolution explicit.
do $$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef(
    'internal.request_team_membership_for_actor(uuid,text,uuid)'::regprocedure
  );

  if position('#variable_conflict use_column' in function_definition) = 0 then
    function_definition := replace(
      function_definition,
      'AS $function$',
      'AS $function$' || E'\n#variable_conflict use_column'
    );
  end if;

  function_definition := replace(
    function_definition,
    'values(actor_id,target_club_id,target_team_id,requested_role)',
    'values(actor_id,target_club_id,target_team_id,' ||
      'request_team_membership_for_actor.requested_role)'
  );

  execute function_definition;
end
$$;
