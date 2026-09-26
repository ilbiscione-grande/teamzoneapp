-- Preserve the requester's question as the first message when a cross-club
-- contact request is accepted. The helper is internal-only and the caller
-- already holds the request row lock, so an idempotent decision cannot seed
-- the same thread twice.
create or replace function internal.seed_contact_request_first_message(
  target_request_id uuid,
  target_thread_id uuid,
  requester_profile_id uuid,
  requester_club_id uuid,
  request_text text,
  reason_code text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_message_id uuid := gen_random_uuid();
  new_domain_id uuid := gen_random_uuid();
  next_revision bigint;
  message_body text;
begin
  message_body := coalesce(
    nullif(btrim(request_text), ''),
    case reason_code
      when 'match' then 'Kontaktförfrågan: Match'
      when 'event' then 'Kontaktförfrågan: Event'
      when 'transfer' then 'Kontaktförfrågan: Spelarövergång'
      when 'club_business' then 'Kontaktförfrågan: Klubbärende'
      else 'Kontaktförfrågan'
    end
  );

  if exists (
    select 1 from core.messages where thread_id = target_thread_id
  ) then
    return null;
  end if;

  select revision + 1
  into next_revision
  from core.message_threads
  where id = target_thread_id
  for update;

  insert into core.messages (
    id, thread_id, sender_profile_id, club_id, body, revision
  ) values (
    new_message_id,
    target_thread_id,
    requester_profile_id,
    requester_club_id,
    message_body,
    next_revision
  );

  insert into audit.message_versions (
    message_id,
    thread_id,
    message_revision,
    body_snapshot,
    body_hash,
    action,
    actor_profile_id
  ) values (
    new_message_id,
    target_thread_id,
    1,
    message_body,
    encode(extensions.digest(message_body, 'sha256'), 'hex'),
    'sent',
    requester_profile_id
  );

  update core.message_threads
  set revision = next_revision
  where id = target_thread_id;

  insert into internal.domain_outbox (
    id,
    club_id,
    event_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision,
    payload
  ) values (
    new_domain_id,
    requester_club_id,
    'message.message.sent.v1',
    'message_thread',
    target_thread_id,
    next_revision,
    jsonb_build_object(
      'message_id', new_message_id,
      'contact_request_id', target_request_id
    )
  );

  insert into internal.notification_outbox (
    club_id,
    domain_event_id,
    event_type,
    aggregate_type,
    aggregate_id,
    recipient_profile_id,
    recipient_person_id,
    payload_ref
  )
  select
    participant.club_id,
    new_domain_id,
    'message.message.sent.v1',
    'message',
    new_message_id,
    participant.profile_id,
    participant.club_person_id,
    jsonb_build_object(
      'thread_id', target_thread_id,
      'message_id', new_message_id,
      'contact_request_id', target_request_id
    )
  from core.thread_participants participant
  where participant.thread_id = target_thread_id
    and participant.state = 'active'
    and participant.profile_id <> requester_profile_id;

  return new_message_id;
end
$$;

revoke all on function internal.seed_contact_request_first_message(
  uuid, uuid, uuid, uuid, text, text
) from public, anon, authenticated;

-- Extend the current hardened decision function without replacing its access,
-- expiry, block, and idempotency checks.
do $$
declare
  function_definition text;
  updated_definition text;
begin
  function_definition := pg_get_functiondef(
    'internal.decide_contact_request_for_actor(uuid,text,uuid)'::regprocedure
  );

  updated_definition := replace(
    function_definition,
    '      (thread_id, actor_id, target_link.club_id, target_link.club_person_id, ''creator'');',
    '      (thread_id, actor_id, target_link.club_id, target_link.club_person_id, ''creator'');

    perform internal.seed_contact_request_first_message(
      request_row.id,
      thread_id,
      request_row.requester_profile_id,
      requester_link.club_id,
      request_row.request_text,
      request_row.reason_code
    );'
  );

  if updated_definition = function_definition then
    raise exception 'msg02_contact_request_seed_patch_not_applied';
  end if;

  execute updated_definition;
end
$$;

-- Repair already accepted, still-empty threads by matching the same two
-- participants and the thread created closest to the decision timestamp.
do $$
declare
  accepted_request record;
  matched_thread_id uuid;
  requester_club_id uuid;
begin
  for accepted_request in
    select request.*
    from core.contact_controls request
    where request.control_type = 'request'
      and request.state = 'accepted'
      and request.decided_at is not null
  loop
    select thread.id, requester_participant.club_id
    into matched_thread_id, requester_club_id
    from core.message_threads thread
    join core.thread_participants requester_participant
      on requester_participant.thread_id = thread.id
     and requester_participant.profile_id = accepted_request.requester_profile_id
    join core.thread_participants target_participant
      on target_participant.thread_id = thread.id
     and target_participant.profile_id = accepted_request.target_profile_id
    where thread.thread_type = 'cross_club_direct'
      and not exists (
        select 1 from core.messages message where message.thread_id = thread.id
      )
      and abs(extract(epoch from (thread.created_at - accepted_request.decided_at))) <= 60
    order by abs(extract(epoch from (thread.created_at - accepted_request.decided_at)))
    limit 1;

    if matched_thread_id is not null then
      perform internal.seed_contact_request_first_message(
        accepted_request.id,
        matched_thread_id,
        accepted_request.requester_profile_id,
        requester_club_id,
        accepted_request.request_text,
        accepted_request.reason_code
      );
    end if;

    matched_thread_id := null;
    requester_club_id := null;
  end loop;
end
$$;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260921210307_msg02_contact_request_becomes_first_message',
  'greenfield',
  'MSG-02 accepted contact request question becomes the first conversation message'
);

notify pgrst, 'reload schema';
