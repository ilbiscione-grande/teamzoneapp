-- Club membership managers may review the whole club. A team-scoped roster
-- manager may review only the explicitly requested team queue and decide only
-- applications whose target team is inside that same capability scope.
do $migration$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef(
    'internal.list_pending_membership_applications_for_actor(uuid,uuid)'::regprocedure
  );
  function_definition := replace(
    function_definition,
    $$if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') then$$,
    $$if not (
      internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
      or (
        target_team_id is not null
        and internal.actor_has_capability(
          target_club_id,target_team_id,'team.roster.manage'
        )
      )
    ) then$$
  );
  execute function_definition;

  function_definition := pg_get_functiondef(
    'internal.decide_membership_application_for_actor(uuid,text,uuid)'::regprocedure
  );
  function_definition := replace(
    function_definition,
    $$or not internal.actor_has_capability(row_value.club_id,row_value.team_id,'club.memberships.manage') then$$,
    $$or not (
       internal.actor_has_capability(
         row_value.club_id,row_value.team_id,'club.memberships.manage'
       )
       or internal.actor_has_capability(
         row_value.club_id,row_value.team_id,'team.roster.manage'
       )
     ) then$$
  );
  execute function_definition;
end
$migration$;
