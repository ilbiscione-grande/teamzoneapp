-- Support conversations belong in the account Inbox. This migration adds
-- per-account read cursors and private, case-bound attachments. Direct table
-- access stays closed; the API exposes only actor-checked commands.

alter table internal.protected_name_support_messages
  drop constraint protected_name_support_messages_body_check;
alter table internal.protected_name_support_messages
  alter column body drop not null;
alter table internal.protected_name_support_messages
  add constraint protected_name_support_messages_body_check
  check(body is null or length(btrim(body)) between 2 and 2000);

create table internal.protected_name_support_reads(
  case_id uuid not null references internal.protected_name_support_cases(id) on delete cascade,
  profile_id uuid not null references core.profiles(id),
  last_read_at timestamptz not null default now(),
  primary key(case_id,profile_id)
);
create index protected_name_support_reads_profile_idx
  on internal.protected_name_support_reads(profile_id,last_read_at desc);

create table internal.protected_name_support_files(
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references internal.protected_name_support_cases(id) on delete cascade,
  message_id uuid references internal.protected_name_support_messages(id) on delete cascade,
  owner_profile_id uuid not null references core.profiles(id),
  bucket_id text not null default 'support-case-files' check(bucket_id='support-case-files'),
  object_key text not null unique,
  original_name text not null check(length(btrim(original_name)) between 1 and 160),
  mime_type text not null,
  size_bytes bigint not null check(size_bytes between 1 and 10485760),
  state text not null default 'staged' check(state in('staged','active')),
  created_at timestamptz not null default now(),
  finalized_at timestamptz,
  expires_at timestamptz not null default now()+interval '1 hour',
  check((state='active' and message_id is not null and finalized_at is not null)
    or (state='staged' and message_id is null and finalized_at is null))
);
create index protected_name_support_files_case_message_idx
  on internal.protected_name_support_files(case_id,message_id,created_at,id);
create index protected_name_support_files_staged_expiry_idx
  on internal.protected_name_support_files(expires_at) where state='staged';

alter table internal.protected_name_support_reads enable row level security;
alter table internal.protected_name_support_files enable row level security;
revoke all on table internal.protected_name_support_reads,
  internal.protected_name_support_files from public,anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('support-case-files','support-case-files',false,10485760,array[
  'application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv',
  'application/msword','application/vnd.ms-excel','application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.oasis.opendocument.text','application/vnd.oasis.opendocument.spreadsheet'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

create function internal.actor_can_access_protected_name_support_case(target_case_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select auth.uid() is not null and exists(
    select 1 from internal.protected_name_support_cases support_case
    where support_case.id=target_case_id and (
      support_case.requester_profile_id=auth.uid()
      or internal.actor_is_support_admin()
    )
  )
$$;

create function internal.actor_can_upload_protected_name_support_file(
  target_bucket text,target_key text
)
returns boolean language sql stable security definer set search_path=''
as $$
  select target_bucket='support-case-files' and exists(
    select 1 from internal.protected_name_support_files support_file
    join internal.protected_name_support_cases support_case
      on support_case.id=support_file.case_id
    where support_file.bucket_id=target_bucket
      and support_file.object_key=target_key
      and support_file.owner_profile_id=auth.uid()
      and support_file.state='staged'
      and support_file.expires_at>now()
      and support_case.status in('pending','in_review')
      and internal.actor_can_access_protected_name_support_case(support_file.case_id)
  )
$$;

create function internal.actor_can_read_protected_name_support_file(
  target_bucket text,target_key text
)
returns boolean language sql stable security definer set search_path=''
as $$
  select target_bucket='support-case-files' and exists(
    select 1 from internal.protected_name_support_files support_file
    where support_file.bucket_id=target_bucket
      and support_file.object_key=target_key
      and support_file.state='active'
      and internal.actor_can_access_protected_name_support_case(support_file.case_id)
  )
$$;

create policy protected_name_support_files_insert on storage.objects
for insert to authenticated with check(
  bucket_id='support-case-files'
  and owner_id=(select auth.uid()::text)
  and internal.actor_can_upload_protected_name_support_file(bucket_id,name)
);
create policy protected_name_support_files_select on storage.objects
for select to authenticated using(
  bucket_id='support-case-files'
  and internal.actor_can_read_protected_name_support_file(bucket_id,name)
);

drop function api.list_my_protected_name_support_case_details();
drop function internal.list_my_protected_name_support_case_details_for_actor();
create function internal.list_my_protected_name_support_case_details_for_actor()
returns table(
  case_id uuid,requester_profile_id uuid,candidate_club_name text,
  candidate_team_name text,status text,message text,resolution_note text,
  revision bigint,created_at timestamptz,updated_at timestamptz,unread_count bigint
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
    support_case.revision,support_case.created_at,support_case.updated_at,
    (select count(*) from internal.protected_name_support_messages support_message
      where support_message.case_id=support_case.id
        and support_message.sender_kind='support'
        and support_message.created_at>coalesce(support_read.last_read_at,'epoch'::timestamptz))
  from internal.protected_name_support_cases support_case
  left join internal.protected_name_support_reads support_read
    on support_read.case_id=support_case.id and support_read.profile_id=actor_id
  where support_case.requester_profile_id=actor_id
  order by support_case.updated_at desc,support_case.id desc;
end
$$;

create function api.list_my_protected_name_support_case_details()
returns table(
  case_id uuid,requester_profile_id uuid,candidate_club_name text,
  candidate_team_name text,status text,message text,resolution_note text,
  revision bigint,created_at timestamptz,updated_at timestamptz,unread_count bigint
)
language sql stable security invoker set search_path=''
as $$select * from internal.list_my_protected_name_support_case_details_for_actor()$$;

drop function api.list_protected_name_support_cases(text);
drop function internal.list_protected_name_support_cases_for_admin(text);
create function internal.list_protected_name_support_cases_for_admin(
  requested_status text default null
)
returns table(
  case_id uuid,requester_profile_id uuid,candidate_club_name text,
  candidate_team_name text,status text,message text,resolution_note text,
  revision bigint,created_at timestamptz,updated_at timestamptz,unread_count bigint
)
language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null or not internal.actor_is_support_admin() then
    raise insufficient_privilege using message='not_found';
  end if;
  if requested_status is not null
    and requested_status not in('pending','in_review','resolved','rejected') then
    raise invalid_parameter_value using message='invalid_status';
  end if;
  return query
  select support_case.id,support_case.requester_profile_id,
    support_case.candidate_club_name,support_case.candidate_team_name,
    support_case.status,support_case.message,support_case.resolution_note,
    support_case.revision,support_case.created_at,support_case.updated_at,
    (select count(*) from internal.protected_name_support_messages support_message
      where support_message.case_id=support_case.id
        and support_message.sender_kind='requester'
        and support_message.created_at>coalesce(support_read.last_read_at,'epoch'::timestamptz))
  from internal.protected_name_support_cases support_case
  left join internal.protected_name_support_reads support_read
    on support_read.case_id=support_case.id and support_read.profile_id=actor_id
  where requested_status is null or support_case.status=requested_status
  order by case when support_case.status='pending' then 0
      when support_case.status='in_review' then 1 else 2 end,
    support_case.updated_at desc,support_case.id desc;
end
$$;

create function api.list_protected_name_support_cases(requested_status text default null)
returns table(
  case_id uuid,requester_profile_id uuid,candidate_club_name text,
  candidate_team_name text,status text,message text,resolution_note text,
  revision bigint,created_at timestamptz,updated_at timestamptz,unread_count bigint
)
language sql stable security invoker set search_path=''
as $$select * from internal.list_protected_name_support_cases_for_admin(requested_status)$$;

drop function api.list_protected_name_support_messages(uuid);
drop function internal.list_protected_name_support_messages_for_actor(uuid);
create function internal.list_protected_name_support_messages_for_actor(
  target_case_id uuid
)
returns table(
  message_id uuid,sender_kind text,sender_name text,body text,
  created_at timestamptz,attachments jsonb
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not internal.actor_can_access_protected_name_support_case(target_case_id) then
    raise insufficient_privilege using message='not_found';
  end if;
  return query
  select support_message.id,support_message.sender_kind,
    coalesce(nullif(btrim(profile.display_name),''),
      case when support_message.sender_kind='support' then 'TeamZone support'
           else 'Sökande' end),
    support_message.body,support_message.created_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'file_id',support_file.id,'name',support_file.original_name,
        'mime_type',support_file.mime_type,'size_bytes',support_file.size_bytes
      ) order by support_file.created_at,support_file.id)
      from internal.protected_name_support_files support_file
      where support_file.message_id=support_message.id and support_file.state='active'
    ),'[]'::jsonb)
  from internal.protected_name_support_messages support_message
  left join core.profiles profile on profile.id=support_message.sender_profile_id
  where support_message.case_id=target_case_id
  order by support_message.created_at,support_message.id;
end
$$;

create function api.list_protected_name_support_messages(target_case_id uuid)
returns table(
  message_id uuid,sender_kind text,sender_name text,body text,
  created_at timestamptz,attachments jsonb
)
language sql stable security invoker set search_path=''
as $$select * from internal.list_protected_name_support_messages_for_actor(target_case_id)$$;

create function internal.mark_protected_name_support_case_read_for_actor(target_case_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if not internal.actor_can_access_protected_name_support_case(target_case_id) then
    raise insufficient_privilege using message='not_found';
  end if;
  insert into internal.protected_name_support_reads(case_id,profile_id,last_read_at)
  values(target_case_id,auth.uid(),now())
  on conflict(case_id,profile_id) do update set last_read_at=excluded.last_read_at;
end
$$;

create function api.mark_protected_name_support_case_read(target_case_id uuid)
returns void language sql security invoker set search_path=''
as $$select internal.mark_protected_name_support_case_read_for_actor(target_case_id)$$;

create function internal.stage_protected_name_support_file_for_actor(
  target_case_id uuid,file_name text,mime_type text,size_bytes bigint
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  support_case internal.protected_name_support_cases%rowtype;
  file_id uuid:=gen_random_uuid();
  clean_name text:=btrim(coalesce(file_name,''));
  object_key text;
begin
  if actor_id is null or not internal.actor_can_access_protected_name_support_case(target_case_id) then
    raise insufficient_privilege using message='not_found';
  end if;
  select * into support_case from internal.protected_name_support_cases
    where id=target_case_id;
  if support_case.status not in('pending','in_review') then
    raise invalid_parameter_value using message='case_closed';
  end if;
  if length(clean_name) not between 1 and 160
    or size_bytes not between 1 and 10485760
    or mime_type not in(
      'application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv',
      'application/msword','application/vnd.ms-excel','application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'application/vnd.oasis.opendocument.text','application/vnd.oasis.opendocument.spreadsheet'
    ) then
    raise invalid_parameter_value using message='invalid_file';
  end if;
  if (select count(*) from internal.protected_name_support_files
      where case_id=target_case_id and state='staged' and expires_at>now())>=10 then
    raise check_violation using message='too_many_files';
  end if;
  object_key:=target_case_id::text||'/'||actor_id::text||'/'||file_id::text;
  insert into internal.protected_name_support_files(
    id,case_id,owner_profile_id,object_key,original_name,mime_type,size_bytes
  ) values(file_id,target_case_id,actor_id,object_key,clean_name,mime_type,size_bytes);
  return jsonb_build_object(
    'file_id',file_id,'bucket_id','support-case-files','object_key',object_key,
    'name',clean_name,'mime_type',mime_type,'size_bytes',size_bytes
  );
end
$$;

create function api.stage_protected_name_support_file(
  target_case_id uuid,file_name text,mime_type text,size_bytes bigint
)
returns jsonb language sql security invoker set search_path=''
as $$select internal.stage_protected_name_support_file_for_actor(
  target_case_id,file_name,mime_type,size_bytes
)$$;

create function internal.send_protected_name_support_message_v2_for_actor(
  target_case_id uuid,message_body text,send_as_support boolean,
  staged_file_ids uuid[],idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  support_case internal.protected_name_support_cases%rowtype;
  normalized_body text:=nullif(btrim(coalesce(message_body,'')),'');
  existing_result jsonb;
  new_message_id uuid;
  next_revision bigint;
  message_sender_kind text;
  requested_file_count integer;
  valid_file_count integer;
  updated_file_count integer;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if idempotency_key is null or (normalized_body is not null and length(normalized_body) not between 2 and 2000)
    or staged_file_ids is null or cardinality(staged_file_ids)>5
    or array_position(staged_file_ids,null) is not null then
    raise invalid_parameter_value using message='invalid_message';
  end if;
  select count(distinct value) into requested_file_count from unnest(staged_file_ids) value;
  if requested_file_count<>cardinality(staged_file_ids)
    or (normalized_body is null and requested_file_count=0) then
    raise invalid_parameter_value using message='invalid_message';
  end if;
  select result into existing_result from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id
    and dedupe.command_type='support.protected_name.message.v2'
    and dedupe.idempotency_key=send_protected_name_support_message_v2_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'message_id')::uuid; end if;

  select * into support_case from internal.protected_name_support_cases row_value
    where row_value.id=target_case_id for update;
  if support_case.id is null or support_case.status not in('pending','in_review') then
    raise invalid_parameter_value using message='case_closed';
  end if;
  if send_as_support then
    if not internal.actor_is_support_admin() then raise insufficient_privilege using message='not_found'; end if;
    message_sender_kind:='support';
  else
    if support_case.requester_profile_id<>actor_id then raise insufficient_privilege using message='not_found'; end if;
    message_sender_kind:='requester';
  end if;

  select count(*) into valid_file_count
  from internal.protected_name_support_files support_file
  join storage.objects object on object.bucket_id=support_file.bucket_id
    and object.name=support_file.object_key
  where support_file.id=any(staged_file_ids)
    and support_file.case_id=target_case_id
    and support_file.owner_profile_id=actor_id
    and support_file.state='staged' and support_file.expires_at>now()
    and (object.metadata->>'size')::bigint=support_file.size_bytes;
  if valid_file_count<>requested_file_count then
    raise invalid_parameter_value using message='invalid_files';
  end if;

  insert into internal.protected_name_support_messages(
    case_id,sender_profile_id,sender_kind,body,idempotency_key
  ) values(target_case_id,actor_id,message_sender_kind,normalized_body,idempotency_key)
  returning id into new_message_id;

  update internal.protected_name_support_files set state='active',message_id=new_message_id,
    finalized_at=now(),expires_at=now()+interval '365 days'
  where id=any(staged_file_ids) and case_id=target_case_id
    and owner_profile_id=actor_id and state='staged' and expires_at>now();
  get diagnostics updated_file_count=row_count;
  if updated_file_count<>requested_file_count then
    raise invalid_parameter_value using message='files_changed_during_send';
  end if;

  next_revision:=support_case.revision+1;
  update internal.protected_name_support_cases set
    status=case when send_as_support and status='pending' then 'in_review' else status end,
    updated_at=now(),revision=next_revision
  where id=target_case_id;
  if not send_as_support then
    insert into internal.support_email_outbox(case_type,case_id,case_revision)
    values('protected_name',target_case_id,next_revision)
    on conflict(case_type,case_id,case_revision) do nothing;
  end if;
  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values(actor_id,idempotency_key,'support.protected_name.message.v2',
    jsonb_build_object('message_id',new_message_id));
  insert into audit.command_events(
    actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata
  ) values(actor_id,'support.protected_name.message.v2','protected_name_support_case',
    target_case_id,next_revision,jsonb_build_object(
      'message_id',new_message_id,'sender_kind',message_sender_kind,
      'file_count',requested_file_count));
  return new_message_id;
end
$$;

create function api.send_protected_name_support_message_v2(
  target_case_id uuid,message_body text,send_as_support boolean,
  staged_file_ids uuid[],idempotency_key uuid
)
returns uuid language sql security invoker set search_path=''
as $$select internal.send_protected_name_support_message_v2_for_actor(
  target_case_id,message_body,send_as_support,staged_file_ids,idempotency_key
)$$;

create function internal.authorize_protected_name_support_file_for_actor(target_file_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare support_file internal.protected_name_support_files%rowtype;
begin
  select * into support_file from internal.protected_name_support_files
    where id=target_file_id and state='active';
  if support_file.id is null
    or not internal.actor_can_access_protected_name_support_case(support_file.case_id) then
    raise insufficient_privilege using message='not_found';
  end if;
  return jsonb_build_object(
    'bucket_id',support_file.bucket_id,'object_key',support_file.object_key,
    'expires_in_seconds',120,'name',support_file.original_name,
    'mime_type',support_file.mime_type
  );
end
$$;

create function api.authorize_protected_name_support_file(target_file_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.authorize_protected_name_support_file_for_actor(target_file_id)$$;

revoke all on function
  internal.actor_can_access_protected_name_support_case(uuid),
  internal.actor_can_upload_protected_name_support_file(text,text),
  internal.actor_can_read_protected_name_support_file(text,text),
  internal.list_my_protected_name_support_case_details_for_actor(),
  api.list_my_protected_name_support_case_details(),
  internal.list_protected_name_support_cases_for_admin(text),
  api.list_protected_name_support_cases(text),
  internal.list_protected_name_support_messages_for_actor(uuid),
  api.list_protected_name_support_messages(uuid),
  internal.mark_protected_name_support_case_read_for_actor(uuid),
  api.mark_protected_name_support_case_read(uuid),
  internal.stage_protected_name_support_file_for_actor(uuid,text,text,bigint),
  api.stage_protected_name_support_file(uuid,text,text,bigint),
  internal.send_protected_name_support_message_v2_for_actor(uuid,text,boolean,uuid[],uuid),
  api.send_protected_name_support_message_v2(uuid,text,boolean,uuid[],uuid),
  internal.authorize_protected_name_support_file_for_actor(uuid),
  api.authorize_protected_name_support_file(uuid)
from public,anon,authenticated;

-- Storage policies call these helpers as the authenticated user.
grant execute on function
  internal.actor_can_upload_protected_name_support_file(text,text),
  internal.actor_can_read_protected_name_support_file(text,text)
to authenticated;
grant execute on function
  internal.list_my_protected_name_support_case_details_for_actor(),
  api.list_my_protected_name_support_case_details(),
  internal.list_protected_name_support_cases_for_admin(text),
  api.list_protected_name_support_cases(text),
  internal.list_protected_name_support_messages_for_actor(uuid),
  api.list_protected_name_support_messages(uuid),
  internal.mark_protected_name_support_case_read_for_actor(uuid),
  api.mark_protected_name_support_case_read(uuid),
  internal.stage_protected_name_support_file_for_actor(uuid,text,text,bigint),
  api.stage_protected_name_support_file(uuid,text,text,bigint),
  internal.send_protected_name_support_message_v2_for_actor(uuid,text,boolean,uuid[],uuid),
  api.send_protected_name_support_message_v2(uuid,text,boolean,uuid[],uuid),
  internal.authorize_protected_name_support_file_for_actor(uuid),
  api.authorize_protected_name_support_file(uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261004133943_support_inbox_unread_attachments','greenfield',
  'Inbox support unread cursors and private case-bound attachment exchange');

notify pgrst,'reload schema';
