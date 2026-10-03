-- Two-way, case-bound conversation for protected-name reviews.
-- Message bodies stay inside the support boundary and are not copied to audit.

create table internal.protected_name_support_messages (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references internal.protected_name_support_cases(id) on delete cascade,
  sender_profile_id uuid not null references core.profiles(id),
  sender_kind text not null check (sender_kind in ('requester','support')),
  body text not null check (length(btrim(body)) between 2 and 2000),
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  unique(sender_profile_id,idempotency_key)
);

create index protected_name_support_messages_case_created_idx
  on internal.protected_name_support_messages(case_id,created_at,id);

alter table internal.protected_name_support_messages enable row level security;
revoke all on table internal.protected_name_support_messages
from public,anon,authenticated;

create function internal.list_my_protected_name_support_case_details_for_actor()
returns table(
  case_id uuid,requester_profile_id uuid,candidate_club_name text,
  candidate_team_name text,status text,message text,resolution_note text,
  revision bigint,created_at timestamptz,updated_at timestamptz
)
language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  return query
  select support_case.id,support_case.requester_profile_id,
    support_case.candidate_club_name,support_case.candidate_team_name,
    support_case.status,support_case.message,support_case.resolution_note,
    support_case.revision,support_case.created_at,support_case.updated_at
  from internal.protected_name_support_cases support_case
  where support_case.requester_profile_id=actor_id
  order by support_case.updated_at desc,support_case.id desc;
end
$$;

create function internal.list_protected_name_support_messages_for_actor(
  target_case_id uuid
)
returns table(
  message_id uuid,sender_kind text,sender_name text,body text,created_at timestamptz
)
language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null or not exists(
    select 1 from internal.protected_name_support_cases support_case
    where support_case.id=target_case_id
      and (
        support_case.requester_profile_id=actor_id
        or internal.actor_is_support_admin()
      )
  ) then
    raise insufficient_privilege using message='not_found';
  end if;
  return query
  select support_message.id,support_message.sender_kind,
    coalesce(nullif(btrim(profile.display_name),''),
      case when support_message.sender_kind='support' then 'TeamZone support'
           else 'Sökande' end),
    support_message.body,support_message.created_at
  from internal.protected_name_support_messages support_message
  left join core.profiles profile on profile.id=support_message.sender_profile_id
  where support_message.case_id=target_case_id
  order by support_message.created_at,support_message.id;
end
$$;

create function internal.send_protected_name_support_message_for_actor(
  target_case_id uuid,
  message_body text,
  send_as_support boolean,
  idempotency_key uuid
)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  support_case internal.protected_name_support_cases%rowtype;
  normalized_body text:=btrim(message_body);
  existing_result jsonb;
  new_message_id uuid;
  next_revision bigint;
  message_sender_kind text;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  if idempotency_key is null or length(normalized_body) not between 2 and 2000 then
    raise invalid_parameter_value using message='invalid_message';
  end if;
  select result into existing_result
  from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id
    and dedupe.command_type='support.protected_name.message.v1'
    and dedupe.idempotency_key=
      send_protected_name_support_message_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result->>'message_id')::uuid;
  end if;

  select * into support_case
  from internal.protected_name_support_cases row_value
  where row_value.id=target_case_id
  for update;
  if support_case.id is null or support_case.status not in ('pending','in_review') then
    raise invalid_parameter_value using message='case_closed';
  end if;
  if send_as_support then
    if not internal.actor_is_support_admin() then
      raise insufficient_privilege using message='not_found';
    end if;
    message_sender_kind:='support';
  else
    if support_case.requester_profile_id<>actor_id then
      raise insufficient_privilege using message='not_found';
    end if;
    message_sender_kind:='requester';
  end if;

  insert into internal.protected_name_support_messages(
    case_id,sender_profile_id,sender_kind,body,idempotency_key
  ) values(
    support_case.id,actor_id,message_sender_kind,normalized_body,idempotency_key
  ) returning id into new_message_id;

  next_revision:=support_case.revision+1;
  update internal.protected_name_support_cases set
    status=case when send_as_support and status='pending' then 'in_review' else status end,
    updated_at=now(),revision=next_revision
  where id=support_case.id;

  if not send_as_support then
    insert into internal.support_email_outbox(case_type,case_id,case_revision)
    values('protected_name',support_case.id,next_revision)
    on conflict(case_type,case_id,case_revision) do nothing;
  end if;

  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values(
    actor_id,idempotency_key,'support.protected_name.message.v1',
    jsonb_build_object('message_id',new_message_id)
  );
  insert into audit.command_events(
    actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision,metadata
  ) values(
    actor_id,'support.protected_name.message.v1',
    'protected_name_support_case',support_case.id,next_revision,
    jsonb_build_object(
      'message_id',new_message_id,'sender_kind',message_sender_kind
    )
  );
  return new_message_id;
end
$$;

create function api.list_my_protected_name_support_case_details()
returns table(
  case_id uuid,requester_profile_id uuid,candidate_club_name text,
  candidate_team_name text,status text,message text,resolution_note text,
  revision bigint,created_at timestamptz,updated_at timestamptz
)
language sql stable security invoker set search_path=''
as $$select * from internal.list_my_protected_name_support_case_details_for_actor()$$;

create function api.list_protected_name_support_messages(target_case_id uuid)
returns table(
  message_id uuid,sender_kind text,sender_name text,body text,created_at timestamptz
)
language sql stable security invoker set search_path=''
as $$select * from internal.list_protected_name_support_messages_for_actor(target_case_id)$$;

create function api.send_protected_name_support_message(
  target_case_id uuid,message_body text,send_as_support boolean,idempotency_key uuid
)
returns uuid language sql security invoker set search_path=''
as $$select internal.send_protected_name_support_message_for_actor(
  target_case_id,message_body,send_as_support,idempotency_key
)$$;

revoke all on function
  internal.list_my_protected_name_support_case_details_for_actor(),
  internal.list_protected_name_support_messages_for_actor(uuid),
  internal.send_protected_name_support_message_for_actor(uuid,text,boolean,uuid),
  api.list_my_protected_name_support_case_details(),
  api.list_protected_name_support_messages(uuid),
  api.send_protected_name_support_message(uuid,text,boolean,uuid)
from public,anon,authenticated;
grant execute on function
  internal.list_my_protected_name_support_case_details_for_actor(),
  internal.list_protected_name_support_messages_for_actor(uuid),
  internal.send_protected_name_support_message_for_actor(uuid,text,boolean,uuid),
  api.list_my_protected_name_support_case_details(),
  api.list_protected_name_support_messages(uuid),
  api.send_protected_name_support_message(uuid,text,boolean,uuid)
to authenticated;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
)
values(
  '20261003180000_protected_name_support_conversation','greenfield',
  'Two-way case-bound messaging between protected-name requester and support admin with privacy-minimal audit metadata'
);

notify pgrst,'reload schema';
