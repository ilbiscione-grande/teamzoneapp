-- MSG-03: an announcement is a single immutable information item, not a
-- conversation. Revision 1 is the newly created empty thread; only the
-- atomic initial send may advance it to revision 2.
create or replace function internal.send_message_for_actor(
  target_thread_id uuid,
  new_body text,
  idempotency_key uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  thread_row core.message_threads%rowtype;
  message_id uuid := gen_random_uuid();
  next_revision bigint;
  existing jsonb;
  sender_club uuid;
  domain_id uuid := gen_random_uuid();
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select result into existing
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'message.message.sent.v1'
    and internal.command_deduplication.idempotency_key = send_message_for_actor.idempotency_key;
  if existing is not null then
    return existing;
  end if;

  if length(btrim(new_body)) not between 1 and 4000
     or not internal.actor_can_access_thread(target_thread_id, true) then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select * into thread_row
  from core.message_threads
  where id = target_thread_id
  for update;

  if thread_row.thread_type = 'announcement' and thread_row.revision >= 2 then
    raise insufficient_privilege using message = 'announcement_closed';
  end if;
  if thread_row.thread_type = 'announcement' and not exists (
    select 1
    from core.thread_participants participant
    where participant.thread_id = target_thread_id
      and participant.profile_id = actor_id
      and participant.state = 'active'
      and participant.participant_role in ('creator', 'moderator')
  ) then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select club_id into sender_club
  from core.thread_participants
  where thread_id = target_thread_id
    and profile_id = actor_id
    and state = 'active';

  next_revision := thread_row.revision + 1;
  insert into core.messages(id, thread_id, sender_profile_id, club_id, body, revision)
  values(message_id, target_thread_id, actor_id, sender_club, btrim(new_body), next_revision);
  insert into audit.message_versions(
    message_id, thread_id, message_revision, body_snapshot, body_hash, action, actor_profile_id
  ) values(
    message_id, target_thread_id, 1, btrim(new_body),
    encode(extensions.digest(btrim(new_body), 'sha256'), 'hex'), 'sent', actor_id
  );
  update core.message_threads set revision = next_revision where id = target_thread_id;
  insert into internal.domain_outbox(
    id, club_id, event_type, aggregate_type, aggregate_id, aggregate_revision, payload
  ) values(
    domain_id, sender_club, 'message.message.sent.v1', 'message_thread',
    target_thread_id, next_revision, jsonb_build_object('message_id', message_id)
  );
  insert into internal.notification_outbox(
    club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref
  )
  select participant.club_id, domain_id, 'message.message.sent.v1', 'message',
    message_id, participant.profile_id, participant.club_person_id,
    jsonb_build_object('thread_id', target_thread_id, 'message_id', message_id)
  from core.thread_participants participant
  left join core.thread_mutes mute
    on mute.thread_id = participant.thread_id
   and mute.profile_id = participant.profile_id
  where participant.thread_id = target_thread_id
    and participant.state = 'active'
    and participant.profile_id <> actor_id
    and coalesce(
      mute.state = 'unmuted'
      or (mute.muted_until is not null and mute.muted_until <= now()),
      true
    );

  existing := jsonb_build_object('message_id', message_id, 'thread_revision', next_revision);
  insert into internal.command_deduplication(
    actor_profile_id, idempotency_key, command_type, result
  ) values(actor_id, idempotency_key, 'message.message.sent.v1', existing);
  return existing;
end
$$;

insert into internal.migration_provenance(
  migration_name, source_kind, source_reference
) values(
  '20260922131951_msg03_close_announcement_after_initial_message',
  'greenfield',
  'MSG-03 announcements are immutable after their atomic initial message'
);
