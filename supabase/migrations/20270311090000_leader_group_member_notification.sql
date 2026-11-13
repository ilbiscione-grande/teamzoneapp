-- Ledargrupper: whoever joins a group hears of it (push and the
-- notification list), whether added by name, as a leader of one of the
-- group's teams, or when they start leading such a team. The notification
-- names the group and opens its chat. The one who made the change is not
-- told about themself.

create or replace function internal.notify_leader_group_member_added()
returns trigger language plpgsql security definer set search_path = '' as $$
declare group_row core.leader_groups%rowtype;
begin
  if new.state <> 'active' or (tg_op = 'UPDATE' and old.state = 'active') then return new; end if;
  select * into group_row from core.leader_groups
  where thread_id = new.thread_id and state = 'active';
  if group_row.id is null or new.club_person_id is null
    or new.profile_id is not distinct from auth.uid() then
    return new;
  end if;
  insert into internal.notification_outbox (club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  values (group_row.club_id, gen_random_uuid(), 'leader_group.member.added.v1', 'leader_group', group_row.id,
    new.profile_id, new.club_person_id,
    jsonb_build_object('group_id', group_row.id, 'thread_id', new.thread_id))
  on conflict do nothing;
  return new;
end
$$;

revoke all on function internal.notify_leader_group_member_added() from public, anon, authenticated;

drop trigger if exists thread_participants_leader_group_added on core.thread_participants;
create trigger thread_participants_leader_group_added
  after insert or update of state on core.thread_participants
  for each row execute function internal.notify_leader_group_member_added();

do $patch$
declare
  def text;
  patched text;
begin
  def := pg_get_functiondef('internal.notification_title(text)'::regprocedure);
  patched := replace(def, 'when event_type = ''club.application.received.v1'' then ''Ny medlemsansökan''',
    'when event_type = ''leader_group.member.added.v1'' then ''Du är med i en ledargrupp''
  when event_type = ''club.application.received.v1'' then ''Ny medlemsansökan''');
  if patched = def then raise exception 'notification_title not patched'; end if;
  execute patched;

  def := pg_get_functiondef('internal.notification_preview(text)'::regprocedure);
  patched := replace(def, 'when event_type = ''club.application.received.v1'' then',
    'when event_type = ''leader_group.member.added.v1'' then ''Du har lagts till i en ledargrupp. Öppna chatten för att skriva med gruppen.''
  when event_type = ''club.application.received.v1'' then');
  if patched = def then raise exception 'notification_preview not patched'; end if;
  execute patched;

  def := pg_get_functiondef('internal.notification_deep_link(internal.notification_outbox)'::regprocedure);
  patched := replace(def, 'when outbox.event_type = ''club.application.received.v1'' then',
    'when outbox.event_type = ''leader_group.member.added.v1''
      and outbox.payload_ref->>''thread_id'' ~ ''^[0-9a-fA-F-]{36}$''
      then ''/inbox?thread=''||(outbox.payload_ref->>''thread_id'')
    when outbox.event_type = ''club.application.received.v1'' then');
  if patched = def then raise exception 'notification_deep_link not patched'; end if;
  execute patched;

  -- The push: the group's name. Not sent once the group is gone or the
  -- person has left it again.
  def := pg_get_functiondef('internal.push_message_for_outbox(uuid)'::regprocedure);
  patched := replace(def, '  elsif outbox.event_type = ''club.application.received.v1'' then',
    '  elsif outbox.event_type = ''leader_group.member.added.v1'' then
    select group_row.name into team_name
    from core.leader_groups group_row
    join core.thread_participants participant on participant.thread_id = group_row.thread_id
      and participant.profile_id = outbox.recipient_profile_id and participant.state = ''active''
    where group_row.id = outbox.aggregate_id and group_row.state = ''active'';
    if team_name is null then return null; end if;
    title := case when swedish then ''Du är med i en ledargrupp'' else ''You were added to a leader group'' end;
    body := team_name;
  elsif outbox.event_type = ''club.application.received.v1'' then');
  if patched = def then raise exception 'push_message_for_outbox not patched'; end if;
  execute patched;
end
$patch$;

notify pgrst, 'reload schema';
