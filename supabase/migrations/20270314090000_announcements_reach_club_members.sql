-- Klubbens utskick når medlemmar utan lag.
--
-- An announcement to "Alla" took players, leaders, guardians and
-- functionaries, so a member of the club without a team (role 'member',
-- e.g. a supporting member) was never reached. 'Alla' now includes them,
-- and 'member' can be chosen on its own. In a team context nothing
-- changes: a club-wide member has no team.

do $patch$
declare
  def text;
  patched text;
begin
  def := pg_get_functiondef('internal.create_role_group_announcement_for_actor(uuid,text,text,text[],uuid)'::regprocedure);
  patched := replace(def,
    'normalized_roles := array[''player'', ''leader'', ''guardian'', ''club_functionary''];',
    'normalized_roles := array[''player'', ''leader'', ''guardian'', ''club_functionary'', ''member''];');
  patched := replace(patched,
    'where role_name not in (''player'', ''leader'', ''guardian'', ''club_functionary'')',
    'where role_name not in (''player'', ''leader'', ''guardian'', ''club_functionary'', ''member'')');
  if (length(def) - length(replace(def, '''club_functionary''', ''))) / length('''club_functionary''') < 2
    or patched = def or patched not like '%''club_functionary'', ''member'')%'
    or patched not like '%''club_functionary'', ''member''];%' then
    raise exception 'create_role_group_announcement_for_actor not patched';
  end if;
  execute patched;
end
$patch$;

notify pgrst, 'reload schema';
