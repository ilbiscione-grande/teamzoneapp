-- MSG-06 hardening: an attachment send must replay successfully after the
-- original transaction activated its staged files but the response was lost.
create or replace function internal.send_message_with_files_for_actor(
  target_thread_id uuid,
  new_body text,
  staged_file_ids uuid[],
  idempotency_key uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  result jsonb;
  target_message uuid;
  expected_count integer;
  valid_count integer;
  attached_count integer;
  updated_count integer;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if staged_file_ids is null
     or cardinality(staged_file_ids) > 10
     or array_position(staged_file_ids, null) is not null then
    raise invalid_parameter_value using message = 'invalid_files';
  end if;
  select count(distinct value) into expected_count
  from unnest(staged_file_ids) value;

  select dedup.result into result
  from internal.command_deduplication dedup
  where dedup.actor_profile_id = actor_id
    and dedup.command_type = 'message.message.sent.v1'
    and dedup.idempotency_key = send_message_with_files_for_actor.idempotency_key;
  if result is not null then
    target_message := (result ->> 'message_id')::uuid;
    select count(*) into attached_count
    from core.file_objects file
    where file.message_id = target_message
      and file.thread_id = target_thread_id
      and file.owner_profile_id = actor_id;
    select count(*) into valid_count
    from core.file_objects file
    where file.id = any(staged_file_ids)
      and file.message_id = target_message
      and file.thread_id = target_thread_id
      and file.owner_profile_id = actor_id;
    if attached_count <> expected_count or valid_count <> expected_count then
      raise invalid_parameter_value using message = 'idempotency_payload_mismatch';
    end if;
    return result || jsonb_build_object('file_count', expected_count);
  end if;

  select count(*) into valid_count
  from core.file_objects file
  join storage.objects object
    on object.bucket_id = file.bucket_id
   and object.name = file.object_key
  where file.id = any(staged_file_ids)
    and file.thread_id = target_thread_id
    and file.owner_profile_id = actor_id
    and file.state = 'staged'
    and file.expires_at > now()
    and (object.metadata ->> 'size')::bigint = file.size_bytes;
  if valid_count <> expected_count then
    raise invalid_parameter_value using message = 'invalid_files';
  end if;

  result := internal.send_message_for_actor(
    target_thread_id,
    new_body,
    idempotency_key
  );
  target_message := (result ->> 'message_id')::uuid;
  update core.file_objects
  set message_id = target_message,
      state = 'active',
      finalized_at = now(),
      expires_at = now() + interval '365 days',
      revision = revision + 1
  where id = any(staged_file_ids)
    and thread_id = target_thread_id
    and owner_profile_id = actor_id
    and state = 'staged'
    and expires_at > now();
  get diagnostics updated_count = row_count;
  if updated_count <> expected_count then
    raise invalid_parameter_value using message = 'files_changed_during_send';
  end if;
  return result || jsonb_build_object('file_count', expected_count);
end;
$$;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values(
  '20260828105601_msg06_replay_safe_message_files',
  'greenfield',
  'MSG-06 replay-safe attachment send with payload matching'
);
