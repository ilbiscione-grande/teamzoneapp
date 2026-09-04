-- MSG-07 hardening: ordinary erasure is exactly dual control. The technical
-- service application attributes the action to the independent approver;
-- only TeamZone-review cases require a third human reviewer.
create or replace function api.apply_thread_erasure(
  target_request_id uuid,
  reviewer_profile_id uuid,
  reason text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_row core.message_thread_erasure_requests%rowtype;
  message_row core.messages%rowtype;
  version_number bigint;
  review_actor uuid;
begin
  if current_user not in ('service_role', 'postgres') then
    raise insufficient_privilege using message = 'service_role_required';
  end if;
  select * into request_row
  from core.message_thread_erasure_requests
  where id = target_request_id
  for update;
  if request_row.id is null then
    raise check_violation using message = 'invalid_review';
  end if;
  if request_row.state = 'completed' then
    return;
  end if;
  if request_row.state not in ('approved', 'teamzone_review')
     or request_row.approved_by is null
     or length(btrim(coalesce(reason, ''))) not between 2 and 500 then
    raise check_violation using message = 'invalid_review';
  end if;

  if request_row.state = 'approved' then
    if reviewer_profile_id is distinct from request_row.approved_by then
      raise check_violation using message = 'approved_reviewer_required';
    end if;
    review_actor := request_row.approved_by;
  else
    if reviewer_profile_id is null
       or reviewer_profile_id in (request_row.initiated_by, request_row.approved_by)
       or not exists(
         select 1 from core.profiles profile
         where profile.id = reviewer_profile_id
       ) then
      raise check_violation using message = 'independent_teamzone_reviewer_required';
    end if;
    review_actor := reviewer_profile_id;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('thread-erasure:' || request_row.thread_id::text, 0)
  );
  for message_row in
    select * from core.messages
    where thread_id = request_row.thread_id
    for update
  loop
    select coalesce(max(message_revision), 0) + 1 into version_number
    from audit.message_versions
    where message_id = message_row.id;
    insert into audit.message_versions(
      message_id,
      thread_id,
      message_revision,
      body_snapshot,
      body_hash,
      action,
      actor_profile_id,
      reason_code,
      erase_body_at
    ) values(
      message_row.id,
      message_row.thread_id,
      version_number,
      null,
      encode(extensions.digest(message_row.body, 'sha256'), 'hex'),
      'moderated',
      review_actor,
      'global_erasure',
      now()
    );
  end loop;
  update core.messages
  set body = 'Meddelandet är borttaget',
      state = 'moderated',
      revised_at = now()
  where thread_id = request_row.thread_id;
  update core.file_objects
  set state = 'withdrawn',
      expires_at = now(),
      revision = revision + 1
  where thread_id = request_row.thread_id
    and state in ('staged', 'active');
  update internal.notification_outbox
  set payload_ref = jsonb_build_object(
        'thread_id', request_row.thread_id,
        'preview_key', 'removed'
      ),
      updated_at = now()
  where event_type = 'message.message.sent.v1'
    and payload_ref ->> 'thread_id' = request_row.thread_id::text;
  update core.message_threads
  set state = 'hidden',
      subject = null,
      closed_at = null,
      revision = revision + 1
  where id = request_row.thread_id;
  update core.message_thread_erasure_requests
  set state = 'completed',
      completed_at = now(),
      revision = revision + 1
  where id = request_row.id;
  insert into audit.command_events(
    club_id,
    actor_profile_id,
    command_type,
    aggregate_type,
    aggregate_id,
    aggregate_revision,
    reason,
    metadata
  ) values(
    request_row.club_id,
    review_actor,
    'message.thread.erasure.apply.v1',
    'message_thread_erasure',
    request_row.id,
    request_row.revision + 1,
    btrim(reason),
    jsonb_build_object(
      'thread_id', request_row.thread_id,
      'initiated_by', request_row.initiated_by,
      'approved_by', request_row.approved_by,
      'review_mode', case
        when request_row.requires_teamzone_review then 'teamzone_review'
        else 'dual_control'
      end,
      'tombstone_preserves_ordering', true
    )
  );
end;
$$;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values(
  '20260828115514_msg07_dual_control_erasure_application',
  'greenfield',
  'MSG-07 exact dual control, independent TeamZone review and replay-safe application'
);
