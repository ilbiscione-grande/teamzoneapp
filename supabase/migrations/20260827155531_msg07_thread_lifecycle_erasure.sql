-- MSG-07: reversible personal lifecycle, scoped closing and dual-control erasure.

alter table core.messages add column reply_to_message_id uuid references core.messages(id);
create index messages_reply_to_idx on core.messages(reply_to_message_id)where reply_to_message_id is not null;

create table core.thread_personal_visibility(
 thread_id uuid not null references core.message_threads(id) on delete cascade,
 profile_id uuid not null references core.profiles(id),
 hidden boolean not null default true,hidden_at timestamptz,updated_at timestamptz not null default now(),
 revision bigint not null default 1 check(revision>0),primary key(thread_id,profile_id),
 check((hidden and hidden_at is not null)or(not hidden and hidden_at is null))
);
alter table core.thread_personal_visibility enable row level security;
create policy thread_personal_visibility_no_direct_access on core.thread_personal_visibility
 for all to authenticated using(false)with check(false);
create index thread_personal_visibility_profile_idx on core.thread_personal_visibility(profile_id,hidden,thread_id);
create trigger visibility_inbox_invalidation after insert or update on core.thread_personal_visibility
 for each row execute function internal.broadcast_inbox_invalidation();

create table core.message_thread_erasure_requests(
 id uuid primary key default gen_random_uuid(),thread_id uuid not null references core.message_threads(id),
 club_id uuid not null references core.clubs(id),state text not null default 'requested'
  check(state in('requested','approved','rejected','completed','teamzone_review')),
 reason text not null check(length(btrim(reason))between 2 and 500),
 initiated_by uuid not null references core.profiles(id),approved_by uuid references core.profiles(id),
 requires_teamzone_review boolean not null default false,created_at timestamptz not null default now(),
 decided_at timestamptz,completed_at timestamptz,revision bigint not null default 1 check(revision>0),
 check(approved_by is null or approved_by<>initiated_by)
);
create unique index message_thread_erasure_one_open_idx on core.message_thread_erasure_requests(thread_id)
 where state in('requested','approved','teamzone_review');
create index message_thread_erasure_club_state_idx on core.message_thread_erasure_requests(club_id,state,created_at desc);
alter table core.message_thread_erasure_requests enable row level security;
create policy message_thread_erasure_no_direct_access on core.message_thread_erasure_requests
 for all to authenticated using(false)with check(false);

-- Existing club membership managers receive the explicit messaging moderation capability.
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by)
select grant_row.club_id,grant_row.assignment_id,'message.moderate',grant_row.scope_type,grant_row.scope_id,
 grant_row.starts_at,grant_row.created_by from core.capability_grants grant_row
where grant_row.capability='club.memberships.manage'
on conflict(assignment_id,capability,scope_type,scope_id)do nothing;

create function internal.set_thread_visibility_for_actor(target_thread_id uuid,new_hidden boolean,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();existing jsonb;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.thread.visibility.v1' and internal.command_deduplication.idempotency_key=set_thread_visibility_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 if not internal.actor_can_access_thread(target_thread_id,false)then raise insufficient_privilege using message='not_found';end if;
 insert into core.thread_personal_visibility(thread_id,profile_id,hidden,hidden_at)
 values(target_thread_id,actor_id,new_hidden,case when new_hidden then now()else null end)
 on conflict(thread_id,profile_id)do update set hidden=excluded.hidden,hidden_at=excluded.hidden_at,
  updated_at=now(),revision=core.thread_personal_visibility.revision+1 returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.thread.visibility.v1',jsonb_build_object('revision',new_revision));
 return new_revision;
end$$;

create function internal.leave_thread_for_actor(target_thread_id uuid,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();thread_row core.message_threads%rowtype;existing jsonb;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.thread.leave.v1' and internal.command_deduplication.idempotency_key=leave_thread_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select thread.* into thread_row from core.message_threads thread join core.thread_participants participant
  on participant.thread_id=thread.id and participant.profile_id=actor_id and participant.state='active'
 where thread.id=target_thread_id for update of thread;
 if thread_row.id is null or thread_row.thread_type not in('group','direct','cross_club_direct')
  or exists(select 1 from core.system_thread_bindings where thread_id=target_thread_id)
 then raise insufficient_privilege using message='not_found';end if;
 update core.thread_participants set state='left',left_at=now(),revision=revision+1
  where thread_id=target_thread_id and profile_id=actor_id returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.thread.leave.v1',jsonb_build_object('revision',new_revision));
 return new_revision;
end$$;

create function internal.close_thread_for_actor(target_thread_id uuid,reason text,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();thread_row core.message_threads%rowtype;scope_row record;existing jsonb;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.thread.close.v1' and internal.command_deduplication.idempotency_key=close_thread_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into thread_row from core.message_threads where id=target_thread_id for update;
 select club_id,team_id into scope_row from core.thread_scopes where thread_id=target_thread_id and scope_role='owner' limit 1;
 if thread_row.id is null or thread_row.club_id is null or thread_row.thread_type not in('group','announcement')
  or length(btrim(coalesce(reason,'')))not between 2 and 240
  or not internal.actor_has_capability(scope_row.club_id,scope_row.team_id,'message.moderate')
 then raise insufficient_privilege using message='not_found';end if;
 if thread_row.state<>'active' then raise check_violation using message='invalid_transition';end if;
 update core.message_threads set state='closed',closed_at=now(),revision=revision+1 where id=target_thread_id returning revision into new_revision;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason)
 values(thread_row.club_id,actor_id,'message.thread.close.v1','message_thread',target_thread_id,new_revision,btrim(reason));
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.thread.close.v1',jsonb_build_object('revision',new_revision));
 return new_revision;
end$$;

create function internal.request_thread_erasure_for_actor(target_thread_id uuid,reason text,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();thread_row core.message_threads%rowtype;scope_row record;existing jsonb;request_id uuid;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.thread.erasure.request.v1' and internal.command_deduplication.idempotency_key=request_thread_erasure_for_actor.idempotency_key;
 if existing is not null then return(existing->>'request_id')::uuid;end if;
 select * into thread_row from core.message_threads where id=target_thread_id;
 select club_id,team_id into scope_row from core.thread_scopes where thread_id=target_thread_id and scope_role='owner' limit 1;
 if thread_row.id is null or length(btrim(coalesce(reason,'')))not between 2 and 500
  or not internal.actor_has_capability(scope_row.club_id,scope_row.team_id,'message.moderate')
 then raise insufficient_privilege using message='not_found';end if;
 insert into core.message_thread_erasure_requests(thread_id,club_id,reason,initiated_by,requires_teamzone_review)
 values(target_thread_id,scope_row.club_id,btrim(reason),actor_id,
  thread_row.thread_type='cross_club_direct'or lower(reason)~'(integritet|privacy|personuppgift)')returning id into request_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason)
 values(scope_row.club_id,actor_id,'message.thread.erasure.request.v1','message_thread_erasure',request_id,1,btrim(reason));
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.thread.erasure.request.v1',jsonb_build_object('request_id',request_id));
 return request_id;
end$$;

create function internal.approve_thread_erasure_for_actor(target_request_id uuid,expected_revision bigint,reason text,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();request_row core.message_thread_erasure_requests%rowtype;scope_row record;existing jsonb;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.thread.erasure.approve.v1' and internal.command_deduplication.idempotency_key=approve_thread_erasure_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into request_row from core.message_thread_erasure_requests where id=target_request_id for update;
 select club_id,team_id into scope_row from core.thread_scopes where thread_id=request_row.thread_id and scope_role='owner' limit 1;
 if request_row.id is null or not internal.actor_has_capability(scope_row.club_id,scope_row.team_id,'message.moderate')
 then raise insufficient_privilege using message='not_found';end if;
 if request_row.initiated_by=actor_id then raise insufficient_privilege using message='separate_approver_required';end if;
 if request_row.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if request_row.state<>'requested' then raise check_violation using message='invalid_transition';end if;
 update core.message_thread_erasure_requests set state=case when requires_teamzone_review then 'teamzone_review'else'approved'end,
  approved_by=actor_id,decided_at=now(),revision=revision+1 where id=request_row.id returning revision into new_revision;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,metadata)
 values(request_row.club_id,actor_id,'message.thread.erasure.approve.v1','message_thread_erasure',request_row.id,new_revision,
  nullif(btrim(reason),''),jsonb_build_object('initiated_by',request_row.initiated_by));
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.thread.erasure.approve.v1',jsonb_build_object('revision',new_revision));
 return new_revision;
end$$;

create function api.apply_thread_erasure(target_request_id uuid,reviewer_profile_id uuid,reason text)
returns void language plpgsql security definer set search_path='' as $$
declare request_row core.message_thread_erasure_requests%rowtype;message_row core.messages%rowtype;version_number bigint;
begin
 if current_user not in('service_role','postgres')then raise insufficient_privilege using message='service_role_required';end if;
 select * into request_row from core.message_thread_erasure_requests where id=target_request_id for update;
 if request_row.id is null or request_row.state not in('approved','teamzone_review')
  or reviewer_profile_id in(request_row.initiated_by,request_row.approved_by)
  or length(btrim(coalesce(reason,'')))not between 2 and 500
 then raise check_violation using message='invalid_review';end if;
 perform pg_advisory_xact_lock(hashtextextended('thread-erasure:'||request_row.thread_id::text,0));
 for message_row in select * from core.messages where thread_id=request_row.thread_id for update loop
  select coalesce(max(message_revision),0)+1 into version_number from audit.message_versions where message_id=message_row.id;
  insert into audit.message_versions(message_id,thread_id,message_revision,body_snapshot,body_hash,action,actor_profile_id,reason_code,erase_body_at)
  values(message_row.id,message_row.thread_id,version_number,null,encode(extensions.digest(message_row.body,'sha256'),'hex'),
   'moderated',reviewer_profile_id,'global_erasure',now());
 end loop;
 update core.messages set body='Meddelandet är borttaget',state='moderated',revised_at=now() where thread_id=request_row.thread_id;
 update core.file_objects set state='withdrawn',expires_at=now(),revision=revision+1
  where thread_id=request_row.thread_id and state in('staged','active');
 update internal.notification_outbox set payload_ref=jsonb_build_object('thread_id',request_row.thread_id,'preview_key','removed'),updated_at=now()
  where event_type='message.message.sent.v1'and payload_ref->>'thread_id'=request_row.thread_id::text;
 update core.message_threads set state='hidden',subject=null,closed_at=null,revision=revision+1 where id=request_row.thread_id;
 update core.message_thread_erasure_requests set state='completed',completed_at=now(),revision=revision+1 where id=request_row.id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,
  metadata)values(request_row.club_id,reviewer_profile_id,'message.thread.erasure.apply.v1','message_thread_erasure',request_row.id,
  request_row.revision+1,btrim(reason),jsonb_build_object('thread_id',request_row.thread_id,'initiated_by',request_row.initiated_by,
  'approved_by',request_row.approved_by,'tombstone_preserves_ordering',true));
end$$;

create function api.set_thread_visibility(thread_id uuid,hidden boolean,idempotency_key uuid)returns bigint
 language sql security invoker set search_path=''as $$select internal.set_thread_visibility_for_actor(thread_id,hidden,idempotency_key)$$;
create function api.leave_thread(thread_id uuid,idempotency_key uuid)returns bigint
 language sql security invoker set search_path=''as $$select internal.leave_thread_for_actor(thread_id,idempotency_key)$$;
create function api.close_thread(thread_id uuid,reason text,idempotency_key uuid)returns bigint
 language sql security invoker set search_path=''as $$select internal.close_thread_for_actor(thread_id,reason,idempotency_key)$$;
create function api.request_thread_erasure(thread_id uuid,reason text,idempotency_key uuid)returns uuid
 language sql security invoker set search_path=''as $$select internal.request_thread_erasure_for_actor(thread_id,reason,idempotency_key)$$;
create function api.approve_thread_erasure(request_id uuid,expected_revision bigint,reason text,idempotency_key uuid)returns bigint
 language sql security invoker set search_path=''as $$select internal.approve_thread_erasure_for_actor(request_id,expected_revision,reason,idempotency_key)$$;

revoke all on table core.thread_personal_visibility,core.message_thread_erasure_requests from public,anon,authenticated;
revoke all on function internal.set_thread_visibility_for_actor(uuid,boolean,uuid),internal.leave_thread_for_actor(uuid,uuid),
 internal.close_thread_for_actor(uuid,text,uuid),internal.request_thread_erasure_for_actor(uuid,text,uuid),
 internal.approve_thread_erasure_for_actor(uuid,bigint,text,uuid),api.set_thread_visibility(uuid,boolean,uuid),
 api.leave_thread(uuid,uuid),api.close_thread(uuid,text,uuid),api.request_thread_erasure(uuid,text,uuid),
 api.approve_thread_erasure(uuid,bigint,text,uuid),api.apply_thread_erasure(uuid,uuid,text)from public,anon,authenticated;
grant execute on function internal.set_thread_visibility_for_actor(uuid,boolean,uuid),internal.leave_thread_for_actor(uuid,uuid),
 internal.close_thread_for_actor(uuid,text,uuid),internal.request_thread_erasure_for_actor(uuid,text,uuid),
 internal.approve_thread_erasure_for_actor(uuid,bigint,text,uuid),api.set_thread_visibility(uuid,boolean,uuid),
 api.leave_thread(uuid,uuid),api.close_thread(uuid,text,uuid),api.request_thread_erasure(uuid,text,uuid),
 api.approve_thread_erasure(uuid,bigint,text,uuid)to authenticated;
grant execute on function api.apply_thread_erasure(uuid,uuid,text)to service_role;

-- Keep closed history visible, omit personal hides and globally erased threads, and expose only server-calculated actions.
create or replace function internal.list_threads_for_actor(target_context_ids uuid[],page_before timestamptz default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if target_context_ids is null or cardinality(target_context_ids)=0 or cardinality(target_context_ids)>50 then raise invalid_parameter_value using message='invalid_context_selection';end if;
 if exists(select 1 from unnest(target_context_ids)requested where not exists(select 1 from internal.get_my_contexts_for_actor()context where context.context_id=requested))
 then raise insufficient_privilege using message='not_found';end if;
 return jsonb_build_object('schema_version',3,'generated_at',now(),'threads',coalesce((select jsonb_agg(row_value order by pinned desc,last_at desc,id)from(
  select thread.id,thread.thread_type,thread.subject,thread.state,thread.revision,coalesce(last_message.created_at,thread.created_at)last_at,
   last_message.body last_message_preview,last_message.sender_name,greatest(coalesce(last_message.revision,1)-coalesce(case when thread.thread_type='announcement'
    then announcement_read.through_revision else message_read.through_revision end,1),0)unread_count,
   coalesce(mute.state='muted'and(mute.muted_until is null or mute.muted_until>now()),false)muted,coalesce(pin.pinned,false)pinned,
   (thread.state='active'and(thread.thread_type<>'announcement'or participant.participant_role in('creator','moderator')))can_send,
   (thread.state='active'and thread.club_id is not null and thread.thread_type in('group','announcement')and
    bool_or(internal.actor_has_capability(scope.club_id,scope.team_id,'message.moderate')))can_manage,
   (thread.thread_type in('group','direct','cross_club_direct')and not exists(select 1 from core.system_thread_bindings where thread_id=thread.id))can_leave
  from core.message_threads thread join core.thread_participants participant on participant.thread_id=thread.id and participant.profile_id=auth.uid()and participant.state='active'
  join core.thread_scopes scope on scope.thread_id=thread.id join internal.get_my_contexts_for_actor()context on context.context_id=any(target_context_ids)
   and context.club_id=scope.club_id and(context.team_id is null or context.team_id=scope.team_id)
  left join core.message_reads message_read on message_read.thread_id=thread.id and message_read.profile_id=auth.uid()
  left join core.announcement_reads announcement_read on announcement_read.thread_id=thread.id and announcement_read.profile_id=auth.uid()
  left join core.thread_mutes mute on mute.thread_id=thread.id and mute.profile_id=auth.uid()
  left join core.thread_pins pin on pin.thread_id=thread.id and pin.profile_id=auth.uid()
  left join core.thread_personal_visibility visibility on visibility.thread_id=thread.id and visibility.profile_id=auth.uid()
  left join lateral(select message.created_at,message.revision,case when message.state='sent'then left(message.body,160)else null end body,profile.display_name sender_name
   from core.messages message join core.profiles profile on profile.id=message.sender_profile_id where message.thread_id=thread.id order by message.revision desc limit 1)last_message on true
  where internal.actor_can_access_thread(thread.id,false)and thread.state<>'hidden'and not coalesce(visibility.hidden,false)
   and(page_before is null or coalesce(last_message.created_at,thread.created_at)<page_before)
  group by thread.id,last_message.created_at,last_message.revision,last_message.body,last_message.sender_name,message_read.through_revision,announcement_read.through_revision,
   mute.state,mute.muted_until,pin.pinned,participant.participant_role
  order by pinned desc,last_at desc,thread.id limit greatest(1,least(page_limit,100)))row_value),'[]'::jsonb));
end$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827155531_msg07_thread_lifecycle_erasure','greenfield','MSG-07 personal lifecycle, dual control and neutral tombstones');
notify pgrst,'reload schema';
