-- Enkäter: a registered player invited to an open survey hears of it
-- (push and the notification list). The notification names the survey and
-- opens the player's own link (/enkat/<token>; the app opens Webtools'
-- page). Queued by internal.team_survey_notify (20270417090000).

do $patch$
declare
  def text;
  patched text;
begin
  def := pg_get_functiondef('internal.notification_title(text)'::regprocedure);
  patched := replace(def, 'when event_type = ''club.application.received.v1'' then ''Ny medlemsansökan''',
    'when event_type = ''team.survey.invited.v1'' then ''Ny enkät från ledarna''
  when event_type = ''club.application.received.v1'' then ''Ny medlemsansökan''');
  if patched = def then raise exception 'notification_title not patched'; end if;
  execute patched;

  def := pg_get_functiondef('internal.notification_preview(text)'::regprocedure);
  patched := replace(def, 'when event_type = ''club.application.received.v1'' then',
    'when event_type = ''team.survey.invited.v1'' then ''Dina ledare vill att du svarar på en kort enkät.''
  when event_type = ''club.application.received.v1'' then');
  if patched = def then raise exception 'notification_preview not patched'; end if;
  execute patched;

  def := pg_get_functiondef('internal.notification_deep_link(internal.notification_outbox)'::regprocedure);
  patched := replace(def, 'when outbox.event_type = ''club.application.received.v1'' then',
    'when outbox.event_type = ''team.survey.invited.v1''
      and outbox.payload_ref->>''invite_id'' ~ ''^[0-9a-fA-F-]{36}$''
      then coalesce((select ''/enkat/''||invite.token from core.team_survey_invites invite
        where invite.id = (outbox.payload_ref->>''invite_id'')::uuid), ''/home'')
    when outbox.event_type = ''club.application.received.v1'' then');
  if patched = def then raise exception 'notification_deep_link not patched'; end if;
  execute patched;

  -- The push: the survey's title. Not sent once the survey is closed or
  -- the link is gone.
  def := pg_get_functiondef('internal.push_message_for_outbox(uuid)'::regprocedure);
  patched := replace(def, '  elsif outbox.event_type = ''club.application.received.v1'' then',
    '  elsif outbox.event_type = ''team.survey.invited.v1'' then
    select survey.title into team_name
    from core.team_survey_invites invite
    join core.team_surveys survey on survey.id = invite.survey_id and survey.state = ''open''
    where invite.id::text = outbox.payload_ref->>''invite_id'';
    if team_name is null then return null; end if;
    title := case when swedish then ''Ny enkät från ledarna'' else ''A new survey from your coaches'' end;
    body := team_name;
  elsif outbox.event_type = ''club.application.received.v1'' then');
  if patched = def then raise exception 'push_message_for_outbox not patched'; end if;
  execute patched;
end
$patch$;
