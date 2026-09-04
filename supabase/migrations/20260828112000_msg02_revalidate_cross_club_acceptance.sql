-- MSG-02 hardening: revalidate the relationship when a cross-club request is accepted.
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
  if request_row.id is null
     or request_row.target_profile_id <> actor_id
     or request_row.state <> 'pending' then
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

  if decision = 'accepted' and (
    not internal.actor_is_verified_adult_leader(actor_id)
    or not internal.actor_is_verified_adult_leader(request_row.requester_profile_id)
    or internal.actors_share_active_club(actor_id, request_row.requester_profile_id)
    or exists(
      select 1
      from core.contact_controls block
      where block.control_type = 'block'
        and block.state = 'active'
        and (
          (block.requester_profile_id = actor_id and block.target_profile_id = request_row.requester_profile_id)
          or (block.target_profile_id = actor_id and block.requester_profile_id = request_row.requester_profile_id)
        )
    )
  ) then
    raise insufficient_privilege using message = 'relationship_changed';
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
      on assignment.club_id = link.club_id
     and assignment.club_person_id = link.club_person_id
    where link.profile_id = request_row.requester_profile_id
      and link.state = 'active'
      and assignment.role_package = 'leader'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
    order by assignment.starts_at desc, link.created_at desc
    limit 1;
    select link.club_id, link.club_person_id into target_link
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_id = link.club_id
     and assignment.club_person_id = link.club_person_id
    where link.profile_id = actor_id
      and link.state = 'active'
      and assignment.role_package = 'leader'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
    order by assignment.starts_at desc, link.created_at desc
    limit 1;
    if requester_link.club_id is null or target_link.club_id is null then
      raise insufficient_privilege using message = 'relationship_changed';
    end if;

    insert into core.message_threads(club_id, thread_type, created_by)
    values(null, 'cross_club_direct', actor_id)
    returning id into thread_id;
    insert into core.thread_scopes(thread_id, club_id, scope_role)
    values
      (thread_id, requester_link.club_id, 'peer'),
      (thread_id, target_link.club_id, 'peer');
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
values(
  '20260828112000_msg02_revalidate_cross_club_acceptance',
  'greenfield',
  'MSG-02 acceptance-time relationship revalidation'
);

