create or replace function internal.mark_thread_read_for_actor(
  target_thread_id uuid,
  new_through_revision bigint,
  idempotency_key uuid
) returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  maximum bigint;
  current_value bigint;
  existing_result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'message.thread.read.v1'
    and internal.command_deduplication.idempotency_key = mark_thread_read_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result ->> 'revision')::bigint;
  end if;
  if not internal.actor_can_access_thread(target_thread_id, false) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select revision into maximum from core.message_threads where id = target_thread_id;
  if new_through_revision < 0 or new_through_revision > maximum then
    raise invalid_parameter_value using message = 'invalid_revision';
  end if;
  insert into core.message_reads(thread_id, profile_id, through_revision)
  values(target_thread_id, actor_id, new_through_revision)
  on conflict(thread_id, profile_id) do update
    set through_revision = greatest(core.message_reads.through_revision, excluded.through_revision),
        read_at = now(),
        device_revision = core.message_reads.device_revision + 1
  returning through_revision into current_value;
  insert into internal.command_deduplication(actor_profile_id, idempotency_key, command_type, result)
  values(actor_id, idempotency_key, 'message.thread.read.v1', jsonb_build_object('revision', current_value));
  return current_value;
end;
$$;

create or replace function internal.set_thread_mute_for_actor(
  target_thread_id uuid,
  new_state text,
  new_muted_until timestamptz,
  idempotency_key uuid
) returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  new_revision bigint;
  existing_result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'message.thread.mute.v1'
    and internal.command_deduplication.idempotency_key = set_thread_mute_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result ->> 'revision')::bigint;
  end if;
  if not internal.actor_can_access_thread(target_thread_id, false)
     or new_state not in ('muted', 'unmuted') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if new_state = 'muted' and new_muted_until is not null and new_muted_until <= now() then
    raise invalid_parameter_value using message = 'invalid_mute';
  end if;
  insert into core.thread_mutes(thread_id, profile_id, state, muted_until)
  values(target_thread_id, actor_id, new_state, case when new_state = 'muted' then new_muted_until end)
  on conflict(thread_id, profile_id) do update
    set state = excluded.state,
        muted_until = excluded.muted_until,
        updated_at = now(),
        revision = core.thread_mutes.revision + 1
  returning revision into new_revision;
  insert into internal.command_deduplication(actor_profile_id, idempotency_key, command_type, result)
  values(actor_id, idempotency_key, 'message.thread.mute.v1', jsonb_build_object('revision', new_revision));
  return new_revision;
exception
  when check_violation then
    raise invalid_parameter_value using message = 'invalid_mute';
end;
$$;

create or replace function internal.decide_contact_request_for_actor(
  target_request_id uuid,
  decision text,
  idempotency_key uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_row core.contact_controls%rowtype;
  actor_id uuid := auth.uid();
  thread_id uuid;
  requester_link record;
  target_link record;
  existing_result jsonb;
  command_result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'message.contact.decide.v1'
    and internal.command_deduplication.idempotency_key = decide_contact_request_for_actor.idempotency_key;
  if existing_result is not null then
    return existing_result;
  end if;
  select * into request_row
  from core.contact_controls
  where id = target_request_id and control_type = 'request'
  for update;
  if request_row.id is null or request_row.target_profile_id <> actor_id or request_row.state <> 'pending' then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if request_row.expires_at <= now() then
    update core.contact_controls
    set state = 'expired', decided_at = now(), revision = revision + 1
    where id = request_row.id;
    command_result := jsonb_build_object('state', 'expired');
    insert into internal.command_deduplication(actor_profile_id, idempotency_key, command_type, result)
    values(actor_id, idempotency_key, 'message.contact.decide.v1', command_result);
    return command_result;
  end if;
  if decision not in ('accepted', 'declined', 'blocked') then
    raise invalid_parameter_value using message = 'invalid_decision';
  end if;
  if decision = 'blocked' then
    insert into core.contact_controls(requester_profile_id, target_profile_id, control_type, state)
    values(actor_id, request_row.requester_profile_id, 'block', 'active')
    on conflict do nothing;
  end if;
  update core.contact_controls
  set state = case when decision = 'blocked' then 'declined' else decision end,
      decided_at = now(),
      revision = revision + 1
  where id = request_row.id;
  if decision = 'accepted' then
    select link.club_id, link.club_person_id into requester_link
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_id = link.club_id and assignment.club_person_id = link.club_person_id
    where link.profile_id = request_row.requester_profile_id and link.state = 'active'
      and assignment.role_package = 'leader' and assignment.state = 'active'
    limit 1;
    select link.club_id, link.club_person_id into target_link
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_id = link.club_id and assignment.club_person_id = link.club_person_id
    where link.profile_id = actor_id and link.state = 'active'
      and assignment.role_package = 'leader' and assignment.state = 'active'
    limit 1;
    insert into core.message_threads(club_id, thread_type, created_by)
    values(null, 'cross_club_direct', actor_id)
    returning id into thread_id;
    insert into core.thread_scopes(thread_id, club_id, scope_role)
    values(thread_id, requester_link.club_id, 'peer'), (thread_id, target_link.club_id, 'peer');
    insert into core.thread_participants(thread_id, profile_id, club_id, club_person_id, participant_role)
    values
      (thread_id, request_row.requester_profile_id, requester_link.club_id, requester_link.club_person_id, 'member'),
      (thread_id, actor_id, target_link.club_id, target_link.club_person_id, 'creator');
  end if;
  command_result := jsonb_build_object('state', decision, 'thread_id', thread_id);
  insert into internal.command_deduplication(actor_profile_id, idempotency_key, command_type, result)
  values(actor_id, idempotency_key, 'message.contact.decide.v1', command_result);
  return command_result;
end;
$$;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values('20260822120244_xobs_command_idempotency', 'greenfield', null);
