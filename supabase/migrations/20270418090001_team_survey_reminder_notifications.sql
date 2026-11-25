-- Enkäter: the reminder (team.survey.reminded.v1, queued by
-- internal.remind_team_survey_for_actor in 20270418090002) in the
-- notification list and as a push, opening the player's own link like the
-- invitation. No push once answered or closed.

do $patch$
declare
  def text;
  patched text;
begin
  def := pg_get_functiondef('internal.notification_title(text)'::regprocedure);
  patched := replace(def, 'when event_type = ''team.survey.invited.v1'' then ''Ny enkät från ledarna''',
    'when event_type = ''team.survey.reminded.v1'' then ''Påminnelse om enkät''
  when event_type = ''team.survey.invited.v1'' then ''Ny enkät från ledarna''');
  if patched = def then raise exception 'notification_title not patched'; end if;
  execute patched;

  def := pg_get_functiondef('internal.notification_preview(text)'::regprocedure);
  patched := replace(def, 'when event_type = ''team.survey.invited.v1'' then',
    'when event_type = ''team.survey.reminded.v1'' then ''Du har inte svarat på ledarnas enkät ännu.''
  when event_type = ''team.survey.invited.v1'' then');
  if patched = def then raise exception 'notification_preview not patched'; end if;
  execute patched;

  def := pg_get_functiondef('internal.notification_deep_link(internal.notification_outbox)'::regprocedure);
  patched := replace(def, 'when outbox.event_type = ''team.survey.invited.v1''',
    'when outbox.event_type in (''team.survey.invited.v1'', ''team.survey.reminded.v1'')');
  if patched = def then raise exception 'notification_deep_link not patched'; end if;
  execute patched;

  def := pg_get_functiondef('internal.push_message_for_outbox(uuid)'::regprocedure);
  patched := replace(def, '  elsif outbox.event_type = ''team.survey.invited.v1'' then
    select survey.title into team_name
    from core.team_survey_invites invite
    join core.team_surveys survey on survey.id = invite.survey_id and survey.state = ''open''
    where invite.id::text = outbox.payload_ref->>''invite_id'';
    if team_name is null then return null; end if;
    title := case when swedish then ''Ny enkät från ledarna'' else ''A new survey from your coaches'' end;',
    '  elsif outbox.event_type in (''team.survey.invited.v1'', ''team.survey.reminded.v1'') then
    select survey.title into team_name
    from core.team_survey_invites invite
    join core.team_surveys survey on survey.id = invite.survey_id and survey.state = ''open''
    where invite.id::text = outbox.payload_ref->>''invite_id''
      and (outbox.event_type = ''team.survey.invited.v1'' or not exists (
        select 1 from core.team_survey_responses response where response.invite_id = invite.id));
    if team_name is null then return null; end if;
    title := case
      when outbox.event_type = ''team.survey.reminded.v1'' then
        case when swedish then ''Påminnelse: enkät från ledarna'' else ''Reminder: a survey from your coaches'' end
      when swedish then ''Ny enkät från ledarna'' else ''A new survey from your coaches'' end;');
  if patched = def then raise exception 'push_message_for_outbox not patched'; end if;
  execute patched;
end
$patch$;

notify pgrst,'reload schema';
