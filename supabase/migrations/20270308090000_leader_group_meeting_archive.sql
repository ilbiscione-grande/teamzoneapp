-- Ledargruppers möten: whoever manages leader groups archives, restores and
-- deletes a group meeting like a team's own activity. These, and sharing,
-- go by internal.actor_can_manage_event_sharing, which so far only knew the
-- holding team's event managers; a cancelled meeting could not be archived.

do $patch$
declare
  def text;
  patched text;
begin
  def := pg_get_functiondef('internal.actor_can_manage_event_sharing(uuid)'::regprocedure);
  patched := regexp_replace(def, 'select exists\(',
    'select internal.actor_can_manage_leader_group_meeting(target_event_id) or exists(');
  if patched = def then raise exception 'actor_can_manage_event_sharing not patched'; end if;
  execute patched;
end
$patch$;
