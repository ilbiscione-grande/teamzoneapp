-- A player or guardian may only start conversations with leaders, but must
-- be able to answer anyone who is allowed to write to them: the chair, the
-- board, the treasurer, the club office … (club functionaries with
-- club.messaging.manage).
--
-- Sending in an existing group or direct conversation is now allowed when
-- every other participant is someone you may write to, OR someone who may
-- write to you, OR the conversation was started by someone who may write to
-- you (that person chose who takes part). Starting new conversations is
-- unchanged.

do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('internal.actor_can_access_thread(uuid,boolean)'::regprocedure);
  patched := replace(definition,
    'thread.thread_type not in(''group'',''direct'') or not exists(',
    'thread.thread_type not in(''group'',''direct'')
    or exists(select 1 from core.thread_participants creator join core.thread_scopes creator_scope on creator_scope.thread_id=thread.id
     where creator.thread_id=thread.id and creator.participant_role=''creator'' and creator.state=''active''
      and creator.profile_id<>auth.uid()
      and internal.messaging_relationship_allowed(creator.profile_id,auth.uid(),creator_scope.club_id,creator_scope.team_id))
    or not exists(');
  patched := replace(patched,
    'and not internal.messaging_relationship_allowed(auth.uid(),recipient.profile_id,scope.club_id,scope.team_id)))',
    'and not internal.messaging_relationship_allowed(auth.uid(),recipient.profile_id,scope.club_id,scope.team_id)
     and not internal.messaging_relationship_allowed(recipient.profile_id,auth.uid(),scope.club_id,scope.team_id)))');
  if patched = definition
     or patched not like '%creator.participant_role=''creator''%'
     or patched not like '%messaging_relationship_allowed(recipient.profile_id,auth.uid()%' then
    raise exception 'thread send contract changed';
  end if;
  execute patched;
end;
$migration$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261011090000_messaging_reply_to_club_functionaries','greenfield',
  'Players and guardians can answer club functionaries who may write to them');
notify pgrst,'reload schema';
