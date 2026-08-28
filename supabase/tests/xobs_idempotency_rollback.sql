begin;
set local role postgres;

do $$
declare
  actor_id uuid;
  thread_id uuid;
  thread_revision bigint;
  read_key uuid := gen_random_uuid();
  mute_key uuid := gen_random_uuid();
  contact_key uuid := gen_random_uuid();
  first_result bigint;
  second_result bigint;
  first_contact jsonb;
  second_contact jsonb;
begin
  select participant.profile_id, participant.thread_id, thread.revision
  into actor_id, thread_id, thread_revision
  from core.thread_participants participant
  join core.message_threads thread on thread.id = participant.thread_id
  where participant.state = 'active'
  order by participant.joined_at
  limit 1;

  if actor_id is null then
    raise exception 'xobs fixture requires one existing thread participant';
  end if;

  perform set_config('request.jwt.claim.sub', actor_id::text, true);

  first_result := internal.mark_thread_read_for_actor(thread_id, thread_revision, read_key);
  second_result := internal.mark_thread_read_for_actor(thread_id, thread_revision, read_key);
  if first_result is distinct from second_result then
    raise exception 'mark read replay changed result';
  end if;

  first_result := internal.set_thread_mute_for_actor(thread_id, 'unmuted', null, mute_key);
  second_result := internal.set_thread_mute_for_actor(thread_id, 'unmuted', null, mute_key);
  if first_result is distinct from second_result then
    raise exception 'mute replay changed revision';
  end if;

  insert into internal.command_deduplication(
    actor_profile_id, idempotency_key, command_type, result
  ) values (
    actor_id,
    contact_key,
    'message.contact.decide.v1',
    jsonb_build_object('state', 'declined', 'thread_id', null)
  );
  first_contact := internal.decide_contact_request_for_actor(gen_random_uuid(), 'declined', contact_key);
  second_contact := internal.decide_contact_request_for_actor(gen_random_uuid(), 'declined', contact_key);
  if first_contact is distinct from second_contact then
    raise exception 'contact decision replay changed result';
  end if;

  if (
    select count(*) <> 3
    from internal.command_deduplication
    where actor_profile_id = actor_id
      and idempotency_key in (read_key, mute_key, contact_key)
  ) then
    raise exception 'unexpected deduplication row count';
  end if;
end;
$$;

rollback;
