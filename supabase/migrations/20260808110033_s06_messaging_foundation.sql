-- S06 greenfield messaging foundation. Teamzone6 is not a source or target.

create table core.retention_classes (
  key text primary key,
  message_days integer not null check (message_days between 1 and 365),
  version_days integer not null check (version_days between 1 and message_days),
  attachment_days integer not null check (attachment_days between 1 and message_days),
  closed_thread_days integer not null check (closed_thread_days between 1 and message_days),
  approved_at timestamptz not null,
  revision bigint not null default 1 check (revision > 0)
);

insert into core.retention_classes(key,message_days,version_days,attachment_days,closed_thread_days,approved_at)
values ('standard_v1',365,30,365,90,'2026-08-08T00:00:00Z');

create table core.message_threads (
  id uuid primary key default gen_random_uuid(),
  club_id uuid references core.clubs(id),
  thread_type text not null check (thread_type in ('team','leader','group','direct','announcement','cross_club_direct')),
  state text not null default 'active' check (state in ('active','closed','hidden','legal_hold')),
  subject text check (subject is null or length(btrim(subject)) between 1 and 120),
  retention_class text not null default 'standard_v1' references core.retention_classes(key),
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  closed_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  unique(id,club_id),
  check ((thread_type='cross_club_direct' and club_id is null) or (thread_type<>'cross_club_direct' and club_id is not null)),
  check ((state='closed' and closed_at is not null) or state<>'closed')
);

create table core.thread_scopes (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references core.message_threads(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  team_id uuid,
  scope_role text not null check (scope_role in ('owner','member','peer')),
  created_at timestamptz not null default now(),
  unique(thread_id,club_id,team_id),
  foreign key(team_id,club_id) references core.teams(id,club_id)
);

create table core.thread_participants (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references core.message_threads(id) on delete cascade,
  profile_id uuid not null references core.profiles(id),
  club_id uuid not null references core.clubs(id),
  club_person_id uuid not null,
  participant_role text not null check (participant_role in ('member','creator','moderator')),
  state text not null default 'active' check (state in ('active','left','blocked','removed')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  revision bigint not null default 1 check(revision>0),
  unique(thread_id,profile_id),
  foreign key(club_person_id,club_id) references core.club_people(id,club_id),
  check ((state='active' and left_at is null) or state<>'active')
);

create table core.messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references core.message_threads(id) on delete cascade,
  sender_profile_id uuid not null references core.profiles(id),
  acting_as_person_id uuid,
  club_id uuid not null,
  body text not null check (length(btrim(body)) between 1 and 4000),
  state text not null default 'sent' check (state in ('sent','recalled','moderated')),
  created_at timestamptz not null default now(),
  revised_at timestamptz,
  recalled_at timestamptz,
  expires_at timestamptz not null default now()+interval '365 days',
  revision bigint not null check (revision>0),
  unique(thread_id,revision),
  foreign key(acting_as_person_id,club_id) references core.club_people(id,club_id)
);

create table audit.message_versions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references core.messages(id) on delete cascade,
  thread_id uuid not null references core.message_threads(id) on delete cascade,
  message_revision bigint not null check(message_revision>0),
  body_snapshot text,
  body_hash text not null,
  action text not null check(action in ('sent','revised','recalled','moderated')),
  actor_profile_id uuid not null references core.profiles(id),
  reason_code text,
  created_at timestamptz not null default now(),
  erase_body_at timestamptz not null default now()+interval '30 days',
  unique(message_id,message_revision)
);

create table core.message_reads (
  thread_id uuid not null references core.message_threads(id) on delete cascade,
  profile_id uuid not null references core.profiles(id),
  through_revision bigint not null check(through_revision>=0),
  read_at timestamptz not null default now(),
  device_revision bigint not null default 1 check(device_revision>0),
  primary key(thread_id,profile_id)
);

create table core.thread_mutes (
  thread_id uuid not null references core.message_threads(id) on delete cascade,
  profile_id uuid not null references core.profiles(id),
  muted_until timestamptz,
  state text not null check(state in ('muted','unmuted')),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check(revision>0),
  primary key(thread_id,profile_id),
  check ((state='muted' and (muted_until is null or muted_until>updated_at)) or (state='unmuted' and muted_until is null))
);

create table core.contact_controls (
  id uuid primary key default gen_random_uuid(),
  requester_profile_id uuid not null references core.profiles(id),
  target_profile_id uuid not null references core.profiles(id),
  control_type text not null check(control_type in ('request','block')),
  state text not null check(state in ('pending','accepted','declined','expired','active','ended')),
  reason_code text,
  request_text text check(request_text is null or length(request_text)<=160),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  expires_at timestamptz,
  revision bigint not null default 1 check(revision>0),
  check(requester_profile_id<>target_profile_id),
  check((control_type='request' and expires_at is not null) or control_type='block')
);
create unique index contact_controls_one_pending_request_idx on core.contact_controls(requester_profile_id,target_profile_id) where control_type='request' and state='pending';
create unique index contact_controls_one_active_block_idx on core.contact_controls(requester_profile_id,target_profile_id) where control_type='block' and state='active';

create table core.message_reports (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references core.message_threads(id),
  message_id uuid references core.messages(id),
  reporter_profile_id uuid not null references core.profiles(id),
  reported_profile_id uuid not null references core.profiles(id),
  reason_code text not null check(reason_code in ('harassment','sexual_content','threat','spam','other')),
  state text not null default 'open' check(state in ('open','reviewing','resolved','dismissed','legal_hold')),
  evidence_hash text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  revision bigint not null default 1 check(revision>0),
  check(reporter_profile_id<>reported_profile_id)
);

create index message_threads_club_updated_idx on core.message_threads(club_id,created_at desc,id);
create index thread_scopes_club_team_idx on core.thread_scopes(club_id,team_id,thread_id);
create index thread_participants_profile_state_idx on core.thread_participants(profile_id,state,thread_id);
create index messages_thread_page_idx on core.messages(thread_id,revision desc);
create index messages_expiry_idx on core.messages(expires_at) where state<>'moderated';
create index message_versions_erase_idx on audit.message_versions(erase_body_at) where body_snapshot is not null;
create index contact_controls_target_state_idx on core.contact_controls(target_profile_id,state,created_at desc);
create index message_reports_state_idx on core.message_reports(state,created_at);

alter table core.retention_classes enable row level security;
alter table core.message_threads enable row level security;
alter table core.thread_scopes enable row level security;
alter table core.thread_participants enable row level security;
alter table core.messages enable row level security;
alter table audit.message_versions enable row level security;
alter table core.message_reads enable row level security;
alter table core.thread_mutes enable row level security;
alter table core.contact_controls enable row level security;
alter table core.message_reports enable row level security;

create function internal.actor_can_access_thread(target_thread_id uuid, require_send boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists(
    select 1 from core.thread_participants participant
    join core.person_account_links link on link.profile_id=participant.profile_id
      and link.club_id=participant.club_id and link.club_person_id=participant.club_person_id and link.state='active'
    join core.message_threads thread on thread.id=participant.thread_id
    where participant.thread_id=target_thread_id and participant.profile_id=auth.uid()
      and participant.state='active' and (not require_send or thread.state='active')
      and exists(
        select 1 from core.assignments assignment
        left join core.thread_scopes scope on scope.thread_id=participant.thread_id and scope.club_id=assignment.club_id
          and (scope.team_id is null or scope.team_id=assignment.team_id)
        where assignment.club_person_id=participant.club_person_id and assignment.club_id=participant.club_id
          and assignment.state='active' and assignment.starts_at<=now()
          and (assignment.ends_at is null or assignment.ends_at>now()) and scope.id is not null
      )
      and not exists(select 1 from core.contact_controls block where block.control_type='block' and block.state='active'
        and ((block.requester_profile_id=auth.uid() and block.target_profile_id in (select profile_id from core.thread_participants where thread_id=target_thread_id and state='active'))
          or (block.target_profile_id=auth.uid() and block.requester_profile_id in (select profile_id from core.thread_participants where thread_id=target_thread_id and state='active'))))
  );
$$;

create function internal.resolve_allowed_recipients_for_actor(target_context_id uuid, search_text text default null)
returns table(profile_id uuid,display_name text,role_package text)
language plpgsql stable security definer set search_path='' as $$
declare actor_context record;
begin
  select * into actor_context from internal.get_my_contexts_for_actor() where context_id=target_context_id;
  if actor_context.context_id is null then raise insufficient_privilege using message='not_found'; end if;
  return query
  select distinct link.profile_id,profile.display_name,assignment.role_package
  from core.assignments assignment
  join core.person_account_links link on link.club_id=assignment.club_id and link.club_person_id=assignment.club_person_id and link.state='active'
  join core.profiles profile on profile.id=link.profile_id
  where assignment.club_id=actor_context.club_id and (actor_context.team_id is null or assignment.team_id=actor_context.team_id)
    and assignment.state='active' and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())
    and link.profile_id<>auth.uid()
    and (search_text is null or profile.display_name ilike '%'||left(search_text,80)||'%')
    and (
      actor_context.role_package in ('leader','club_functionary')
      or (actor_context.role_package='player' and assignment.role_package in ('leader','guardian'))
      or (actor_context.role_package='guardian' and assignment.role_package='leader')
    )
    and not exists(select 1 from core.contact_controls block where block.control_type='block' and block.state='active'
      and ((block.requester_profile_id=auth.uid() and block.target_profile_id=link.profile_id) or (block.target_profile_id=auth.uid() and block.requester_profile_id=link.profile_id)))
  order by profile.display_name limit 50;
end; $$;

create function internal.create_thread_for_actor(target_context_id uuid,new_type text,new_subject text,recipient_profile_ids uuid[],idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); context_row record; thread_id uuid:=gen_random_uuid(); recipient_count integer; allowed_count integer; existing jsonb; actor_person uuid;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type='message.thread.created.v1' and internal.command_deduplication.idempotency_key=create_thread_for_actor.idempotency_key;
  if existing is not null then return (existing->>'thread_id')::uuid; end if;
  select * into context_row from internal.get_my_contexts_for_actor() where context_id=target_context_id;
  if context_row.context_id is null or new_type not in ('group','direct') then raise insufficient_privilege using message='not_found'; end if;
  if recipient_profile_ids is null or cardinality(recipient_profile_ids)<1 or cardinality(recipient_profile_ids)>50 or array_position(recipient_profile_ids,null) is not null then raise invalid_parameter_value using message='invalid_recipients'; end if;
  select count(distinct value) into recipient_count from unnest(recipient_profile_ids)value;
  select count(*) into allowed_count from (select distinct value profile_id from unnest(recipient_profile_ids)value) requested join internal.resolve_allowed_recipients_for_actor(target_context_id,null) allowed using(profile_id);
  if recipient_count<>allowed_count or (new_type='direct' and recipient_count<>1) then raise insufficient_privilege using message='invalid_recipients'; end if;
  select link.club_person_id into actor_person from core.person_account_links link where link.profile_id=actor_id and link.club_id=context_row.club_id and link.state='active';
  insert into core.message_threads(id,club_id,thread_type,subject,created_by) values(thread_id,context_row.club_id,new_type,nullif(btrim(new_subject),''),actor_id);
  insert into core.thread_scopes(thread_id,club_id,team_id,scope_role) values(thread_id,context_row.club_id,context_row.team_id,'owner');
  insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role) values(thread_id,actor_id,context_row.club_id,actor_person,'creator');
  insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role)
  select thread_id,link.profile_id,link.club_id,link.club_person_id,'member' from core.person_account_links link where link.profile_id=any(recipient_profile_ids) and link.club_id=context_row.club_id and link.state='active';
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'message.thread.created.v1',jsonb_build_object('thread_id',thread_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata) values(context_row.club_id,actor_id,'message.thread.created.v1','message_thread',thread_id,1,jsonb_build_object('type',new_type,'recipient_count',recipient_count));
  return thread_id;
end; $$;

create function internal.send_message_for_actor(target_thread_id uuid,new_body text,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); thread_row core.message_threads%rowtype; message_id uuid:=gen_random_uuid(); next_revision bigint; existing jsonb; sender_club uuid; domain_id uuid:=gen_random_uuid();
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type='message.message.sent.v1' and internal.command_deduplication.idempotency_key=send_message_for_actor.idempotency_key;
  if existing is not null then return existing; end if;
  if length(btrim(new_body)) not between 1 and 4000 or not internal.actor_can_access_thread(target_thread_id,true) then raise insufficient_privilege using message='not_found'; end if;
  select * into thread_row from core.message_threads where id=target_thread_id for update;
  select club_id into sender_club from core.thread_participants where thread_id=target_thread_id and profile_id=actor_id and state='active';
  next_revision:=thread_row.revision+1;
  insert into core.messages(id,thread_id,sender_profile_id,club_id,body,revision) values(message_id,target_thread_id,actor_id,sender_club,btrim(new_body),next_revision);
  insert into audit.message_versions(message_id,thread_id,message_revision,body_snapshot,body_hash,action,actor_profile_id) values(message_id,target_thread_id,1,btrim(new_body),encode(extensions.digest(btrim(new_body),'sha256'),'hex'),'sent',actor_id);
  update core.message_threads set revision=next_revision where id=target_thread_id;
  insert into internal.domain_outbox(id,club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload) values(domain_id,sender_club,'message.message.sent.v1','message_thread',target_thread_id,next_revision,jsonb_build_object('message_id',message_id));
  insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,aggregate_id,recipient_profile_id,recipient_person_id,payload_ref)
  select participant.club_id,domain_id,'message.message.sent.v1','message',message_id,participant.profile_id,participant.club_person_id,jsonb_build_object('thread_id',target_thread_id,'message_id',message_id)
  from core.thread_participants participant left join core.thread_mutes mute on mute.thread_id=participant.thread_id and mute.profile_id=participant.profile_id
  where participant.thread_id=target_thread_id and participant.state='active' and participant.profile_id<>actor_id
    and coalesce(mute.state='unmuted' or (mute.muted_until is not null and mute.muted_until<=now()),true);
  existing:=jsonb_build_object('message_id',message_id,'thread_revision',next_revision);
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'message.message.sent.v1',existing);
  return existing;
end; $$;

create function internal.list_threads_for_actor(target_context_ids uuid[],page_before timestamptz default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if target_context_ids is null or cardinality(target_context_ids)=0 or cardinality(target_context_ids)>50 then raise invalid_parameter_value using message='invalid_context_selection'; end if;
  if exists(select 1 from unnest(target_context_ids) requested where not exists(select 1 from internal.get_my_contexts_for_actor() context where context.context_id=requested)) then raise insufficient_privilege using message='not_found'; end if;
  return jsonb_build_object('schema_version',1,'generated_at',now(),'threads',coalesce((select jsonb_agg(row_value order by last_at desc,id) from (
    select thread.id,thread.thread_type,thread.subject,thread.state,thread.revision,coalesce(last_message.created_at,thread.created_at) last_at,
      last_message.body last_message_preview,last_message.sender_name,
      greatest(thread.revision-coalesce(read_marker.through_revision,0),0) unread_count,
      coalesce(mute.state='muted' and (mute.muted_until is null or mute.muted_until>now()),false) muted
    from core.message_threads thread join core.thread_participants participant on participant.thread_id=thread.id and participant.profile_id=auth.uid() and participant.state='active'
    join core.thread_scopes scope on scope.thread_id=thread.id
    join internal.get_my_contexts_for_actor() context on context.context_id=any(target_context_ids) and context.club_id=scope.club_id and (context.team_id is null or context.team_id=scope.team_id)
    left join core.message_reads read_marker on read_marker.thread_id=thread.id and read_marker.profile_id=auth.uid()
    left join core.thread_mutes mute on mute.thread_id=thread.id and mute.profile_id=auth.uid()
    left join lateral(select message.created_at,case when message.state='sent' then left(message.body,160) else null end body,profile.display_name sender_name from core.messages message join core.profiles profile on profile.id=message.sender_profile_id where message.thread_id=thread.id order by message.revision desc limit 1)last_message on true
    where internal.actor_can_access_thread(thread.id,false) and (page_before is null or coalesce(last_message.created_at,thread.created_at)<page_before)
    group by thread.id,last_message.created_at,last_message.body,last_message.sender_name,read_marker.through_revision,mute.state,mute.muted_until order by last_at desc,thread.id limit greatest(1,least(page_limit,100))
  )row_value),'[]'::jsonb));
end; $$;

create function internal.list_messages_for_actor(target_thread_id uuid,before_revision bigint default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not internal.actor_can_access_thread(target_thread_id,false) then raise insufficient_privilege using message='not_found'; end if;
  return jsonb_build_object('schema_version',1,'thread_id',target_thread_id,'messages',coalesce((select jsonb_agg(row_value order by revision) from (
    select message.id,message.revision,message.state,case when message.state='sent' then message.body else null end body,message.created_at,profile.display_name sender_name,message.sender_profile_id=auth.uid() mine
    from core.messages message join core.profiles profile on profile.id=message.sender_profile_id where message.thread_id=target_thread_id and (before_revision is null or message.revision<before_revision)
    order by message.revision desc limit greatest(1,least(page_limit,100)))row_value),'[]'::jsonb));
end; $$;

create function internal.mark_thread_read_for_actor(target_thread_id uuid,new_through_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare maximum bigint; current_value bigint;
begin
 if not internal.actor_can_access_thread(target_thread_id,false) then raise insufficient_privilege using message='not_found'; end if;
 select revision into maximum from core.message_threads where id=target_thread_id;
 if new_through_revision<0 or new_through_revision>maximum then raise invalid_parameter_value using message='invalid_revision'; end if;
 insert into core.message_reads(thread_id,profile_id,through_revision) values(target_thread_id,auth.uid(),new_through_revision)
 on conflict(thread_id,profile_id) do update set through_revision=greatest(core.message_reads.through_revision,excluded.through_revision),read_at=now(),device_revision=core.message_reads.device_revision+1 returning through_revision into current_value;
 return current_value;
end; $$;

create function internal.set_thread_mute_for_actor(target_thread_id uuid,new_state text,new_muted_until timestamptz,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare new_revision bigint;
begin
 if not internal.actor_can_access_thread(target_thread_id,false) or new_state not in ('muted','unmuted') then raise insufficient_privilege using message='not_found'; end if;
 if new_state='muted' and new_muted_until is not null and new_muted_until<=now() then raise invalid_parameter_value using message='invalid_mute'; end if;
 insert into core.thread_mutes(thread_id,profile_id,state,muted_until) values(target_thread_id,auth.uid(),new_state,case when new_state='muted' then new_muted_until end)
 on conflict(thread_id,profile_id) do update set state=excluded.state,muted_until=excluded.muted_until,updated_at=now(),revision=core.thread_mutes.revision+1 returning revision into new_revision;
 return new_revision;
exception when others then if sqlstate='23514' then raise invalid_parameter_value using message='invalid_mute'; else raise; end if;
end; $$;

revoke all on function internal.actor_can_access_thread(uuid,boolean),internal.resolve_allowed_recipients_for_actor(uuid,text),internal.create_thread_for_actor(uuid,text,text,uuid[],uuid),internal.send_message_for_actor(uuid,text,uuid),internal.list_threads_for_actor(uuid[],timestamptz,integer),internal.list_messages_for_actor(uuid,bigint,integer),internal.mark_thread_read_for_actor(uuid,bigint,uuid),internal.set_thread_mute_for_actor(uuid,text,timestamptz,uuid) from public,anon,authenticated;
grant execute on function internal.resolve_allowed_recipients_for_actor(uuid,text),internal.create_thread_for_actor(uuid,text,text,uuid[],uuid),internal.send_message_for_actor(uuid,text,uuid),internal.list_threads_for_actor(uuid[],timestamptz,integer),internal.list_messages_for_actor(uuid,bigint,integer),internal.mark_thread_read_for_actor(uuid,bigint,uuid),internal.set_thread_mute_for_actor(uuid,text,timestamptz,uuid) to authenticated;

create function api.resolve_allowed_recipients(context_id uuid,query text default null) returns table(profile_id uuid,display_name text,role_package text) language sql stable security invoker set search_path='' as $$select * from internal.resolve_allowed_recipients_for_actor(context_id,query)$$;
create function api.create_thread(context_id uuid,thread_type text,subject text,participant_profile_ids uuid[],idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$select internal.create_thread_for_actor(context_id,thread_type,subject,participant_profile_ids,idempotency_key)$$;
create function api.send_message(thread_id uuid,body text,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as $$select internal.send_message_for_actor(thread_id,body,idempotency_key)$$;
create function api.list_threads(context_ids uuid[],page_before timestamptz default null,page_limit integer default 50) returns jsonb language sql stable security invoker set search_path='' as $$select internal.list_threads_for_actor(context_ids,page_before,page_limit)$$;
create function api.list_messages(thread_id uuid,before_revision bigint default null,page_limit integer default 50) returns jsonb language sql stable security invoker set search_path='' as $$select internal.list_messages_for_actor(thread_id,before_revision,page_limit)$$;
create function api.mark_thread_read(thread_id uuid,through_revision bigint,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$select internal.mark_thread_read_for_actor(thread_id,through_revision,idempotency_key)$$;
create function api.set_thread_mute(thread_id uuid,state text,muted_until timestamptz,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$select internal.set_thread_mute_for_actor(thread_id,state,muted_until,idempotency_key)$$;

revoke all on function api.resolve_allowed_recipients(uuid,text),api.create_thread(uuid,text,text,uuid[],uuid),api.send_message(uuid,text,uuid),api.list_threads(uuid[],timestamptz,integer),api.list_messages(uuid,bigint,integer),api.mark_thread_read(uuid,bigint,uuid),api.set_thread_mute(uuid,text,timestamptz,uuid) from public,anon;
grant execute on function api.resolve_allowed_recipients(uuid,text),api.create_thread(uuid,text,text,uuid[],uuid),api.send_message(uuid,text,uuid),api.list_threads(uuid[],timestamptz,integer),api.list_messages(uuid,bigint,integer),api.mark_thread_read(uuid,bigint,uuid),api.set_thread_mute(uuid,text,timestamptz,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808110033_s06_messaging_foundation','greenfield',null);
