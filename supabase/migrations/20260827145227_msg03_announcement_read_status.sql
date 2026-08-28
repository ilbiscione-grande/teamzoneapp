-- MSG-03 one-way announcements and a dedicated per-participant read model.

create table core.announcement_reads(
 thread_id uuid not null references core.message_threads(id) on delete cascade,
 profile_id uuid not null references core.profiles(id),
 through_revision bigint not null check(through_revision>=0),
 read_at timestamptz not null default now(),
 device_revision bigint not null default 1 check(device_revision>0),
 primary key(thread_id,profile_id)
);
alter table core.announcement_reads enable row level security;
create policy announcement_reads_no_direct_access on core.announcement_reads for all to authenticated using(false) with check(false);
create index announcement_reads_profile_idx on core.announcement_reads(profile_id,thread_id);

create function internal.create_announcement_for_actor(target_context_id uuid,new_subject text,
 recipient_profile_ids uuid[],idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();context_row record;thread_id uuid:=gen_random_uuid();actor_person uuid;
 recipient_count integer;allowed_count integer;existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication d where d.actor_profile_id=actor_id
  and d.command_type='message.announcement.created.v1' and d.idempotency_key=create_announcement_for_actor.idempotency_key;
 if existing is not null then return(existing->>'thread_id')::uuid;end if;
 select * into context_row from internal.get_my_contexts_for_actor() where context_id=target_context_id;
 if context_row.context_id is null or length(btrim(coalesce(new_subject,''))) not between 1 and 120
  or recipient_profile_ids is null or cardinality(recipient_profile_ids)<1 or cardinality(recipient_profile_ids)>50
  or array_position(recipient_profile_ids,null) is not null
 then raise insufficient_privilege using message='not_found';end if;
 if not exists(select 1 from core.person_account_links link join core.assignments assignment
   on assignment.club_id=link.club_id and assignment.club_person_id=link.club_person_id
   where link.profile_id=actor_id and link.club_id=context_row.club_id and link.state='active'
    and assignment.state='active' and assignment.starts_at<=now() and(assignment.ends_at is null or assignment.ends_at>now())
    and(context_row.team_id is null or assignment.team_id=context_row.team_id)
    and assignment.role_package in('leader','club_functionary'))
 then raise insufficient_privilege using message='not_found';end if;
 select count(distinct value) into recipient_count from unnest(recipient_profile_ids)value;
 select count(*) into allowed_count from(select distinct value profile_id from unnest(recipient_profile_ids)value)requested
  where internal.messaging_relationship_allowed(actor_id,requested.profile_id,context_row.club_id,context_row.team_id);
 if recipient_count<>allowed_count then raise insufficient_privilege using message='invalid_recipients';end if;
 select link.club_person_id into actor_person from core.person_account_links link where link.profile_id=actor_id
  and link.club_id=context_row.club_id and link.state='active' order by link.created_at desc limit 1;
 insert into core.message_threads(id,club_id,thread_type,subject,created_by)
 values(thread_id,context_row.club_id,'announcement',btrim(new_subject),actor_id);
 insert into core.thread_scopes(thread_id,club_id,team_id,scope_role)
 values(thread_id,context_row.club_id,context_row.team_id,'owner');
 insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role)
 values(thread_id,actor_id,context_row.club_id,actor_person,'creator');
 insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role)
 select distinct on(link.profile_id) thread_id,link.profile_id,link.club_id,link.club_person_id,'member'
 from core.person_account_links link where link.profile_id=any(recipient_profile_ids)
  and link.club_id=context_row.club_id and link.state='active' order by link.profile_id,link.created_at desc;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.announcement.created.v1',jsonb_build_object('thread_id',thread_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(context_row.club_id,actor_id,'message.announcement.created.v1','message_thread',thread_id,1,
  jsonb_build_object('recipient_count',recipient_count));
 return thread_id;
end;$$;

create or replace function internal.send_message_for_actor(target_thread_id uuid,new_body text,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();thread_row core.message_threads%rowtype;message_id uuid:=gen_random_uuid();
 next_revision bigint;existing jsonb;sender_club uuid;domain_id uuid:=gen_random_uuid();
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.message.sent.v1' and internal.command_deduplication.idempotency_key=send_message_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 if length(btrim(new_body)) not between 1 and 4000 or not internal.actor_can_access_thread(target_thread_id,true)
 then raise insufficient_privilege using message='not_found';end if;
 select * into thread_row from core.message_threads where id=target_thread_id for update;
 if thread_row.thread_type='announcement' and not exists(select 1 from core.thread_participants participant
   where participant.thread_id=target_thread_id and participant.profile_id=actor_id and participant.state='active'
    and participant.participant_role in('creator','moderator'))
 then raise insufficient_privilege using message='not_found';end if;
 select club_id into sender_club from core.thread_participants where thread_id=target_thread_id and profile_id=actor_id and state='active';
 next_revision:=thread_row.revision+1;
 insert into core.messages(id,thread_id,sender_profile_id,club_id,body,revision)
 values(message_id,target_thread_id,actor_id,sender_club,btrim(new_body),next_revision);
 insert into audit.message_versions(message_id,thread_id,message_revision,body_snapshot,body_hash,action,actor_profile_id)
 values(message_id,target_thread_id,1,btrim(new_body),encode(extensions.digest(btrim(new_body),'sha256'),'hex'),'sent',actor_id);
 update core.message_threads set revision=next_revision where id=target_thread_id;
 insert into internal.domain_outbox(id,club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
 values(domain_id,sender_club,'message.message.sent.v1','message_thread',target_thread_id,next_revision,jsonb_build_object('message_id',message_id));
 insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,aggregate_id,recipient_profile_id,recipient_person_id,payload_ref)
 select participant.club_id,domain_id,'message.message.sent.v1','message',message_id,participant.profile_id,participant.club_person_id,
  jsonb_build_object('thread_id',target_thread_id,'message_id',message_id)
 from core.thread_participants participant left join core.thread_mutes mute on mute.thread_id=participant.thread_id and mute.profile_id=participant.profile_id
 where participant.thread_id=target_thread_id and participant.state='active' and participant.profile_id<>actor_id
  and coalesce(mute.state='unmuted' or(mute.muted_until is not null and mute.muted_until<=now()),true);
 existing:=jsonb_build_object('message_id',message_id,'thread_revision',next_revision);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.message.sent.v1',existing);
 return existing;
end;$$;

create or replace function internal.list_threads_for_actor(target_context_ids uuid[],page_before timestamptz default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if target_context_ids is null or cardinality(target_context_ids)=0 or cardinality(target_context_ids)>50
 then raise invalid_parameter_value using message='invalid_context_selection';end if;
 if exists(select 1 from unnest(target_context_ids) requested where not exists(
  select 1 from internal.get_my_contexts_for_actor() context where context.context_id=requested))
 then raise insufficient_privilege using message='not_found';end if;
 return jsonb_build_object('schema_version',1,'generated_at',now(),'threads',coalesce((select jsonb_agg(row_value order by last_at desc,id) from(
  select thread.id,thread.thread_type,thread.subject,thread.state,thread.revision,
   coalesce(last_message.created_at,thread.created_at)last_at,last_message.body last_message_preview,last_message.sender_name,
   greatest(thread.revision-coalesce(case when thread.thread_type='announcement' then announcement_read.through_revision
    else message_read.through_revision end,1),0)unread_count,
   coalesce(mute.state='muted' and(mute.muted_until is null or mute.muted_until>now()),false)muted,
   (thread.thread_type<>'announcement' or participant.participant_role in('creator','moderator'))can_send
  from core.message_threads thread join core.thread_participants participant on participant.thread_id=thread.id
   and participant.profile_id=auth.uid() and participant.state='active'
  join core.thread_scopes scope on scope.thread_id=thread.id join internal.get_my_contexts_for_actor() context
   on context.context_id=any(target_context_ids) and context.club_id=scope.club_id and(context.team_id is null or context.team_id=scope.team_id)
  left join core.message_reads message_read on message_read.thread_id=thread.id and message_read.profile_id=auth.uid()
  left join core.announcement_reads announcement_read on announcement_read.thread_id=thread.id and announcement_read.profile_id=auth.uid()
  left join core.thread_mutes mute on mute.thread_id=thread.id and mute.profile_id=auth.uid()
  left join lateral(select message.created_at,case when message.state='sent' then left(message.body,160)else null end body,
   profile.display_name sender_name from core.messages message join core.profiles profile on profile.id=message.sender_profile_id
   where message.thread_id=thread.id order by message.revision desc limit 1)last_message on true
  where internal.actor_can_access_thread(thread.id,false) and(page_before is null or coalesce(last_message.created_at,thread.created_at)<page_before)
  group by thread.id,last_message.created_at,last_message.body,last_message.sender_name,message_read.through_revision,
   announcement_read.through_revision,mute.state,mute.muted_until,participant.participant_role order by last_at desc,thread.id
  limit greatest(1,least(page_limit,100)))row_value),'[]'::jsonb));
end;$$;

create or replace function internal.mark_thread_read_for_actor(target_thread_id uuid,new_through_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();maximum bigint;current_value bigint;thread_kind text;existing_result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.thread.read.v1' and internal.command_deduplication.idempotency_key=mark_thread_read_for_actor.idempotency_key;
 if existing_result is not null then return(existing_result->>'revision')::bigint;end if;
 if not internal.actor_can_access_thread(target_thread_id,false) then raise insufficient_privilege using message='not_found';end if;
 select revision,thread_type into maximum,thread_kind from core.message_threads where id=target_thread_id;
 if new_through_revision<0 or new_through_revision>maximum then raise invalid_parameter_value using message='invalid_revision';end if;
 if thread_kind='announcement' then
  insert into core.announcement_reads(thread_id,profile_id,through_revision) values(target_thread_id,actor_id,new_through_revision)
  on conflict(thread_id,profile_id)do update set through_revision=greatest(core.announcement_reads.through_revision,excluded.through_revision),
   read_at=now(),device_revision=core.announcement_reads.device_revision+1 returning through_revision into current_value;
 else
  insert into core.message_reads(thread_id,profile_id,through_revision) values(target_thread_id,actor_id,new_through_revision)
  on conflict(thread_id,profile_id)do update set through_revision=greatest(core.message_reads.through_revision,excluded.through_revision),
   read_at=now(),device_revision=core.message_reads.device_revision+1 returning through_revision into current_value;
 end if;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.thread.read.v1',jsonb_build_object('revision',current_value));
 return current_value;
end;$$;

create function internal.mark_all_threads_read_for_actor(target_context_ids uuid[],idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();existing jsonb;affected integer:=0;announcement_affected integer:=0;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='message.all.read.v1' and internal.command_deduplication.idempotency_key=mark_all_threads_read_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 if target_context_ids is null or cardinality(target_context_ids)=0 or cardinality(target_context_ids)>50
  or exists(select 1 from unnest(target_context_ids)requested where not exists(
   select 1 from internal.get_my_contexts_for_actor()context where context.context_id=requested))
 then raise insufficient_privilege using message='not_found';end if;
 with accessible as(select distinct thread.id,thread.revision from core.message_threads thread
  join core.thread_scopes scope on scope.thread_id=thread.id join internal.get_my_contexts_for_actor()context
   on context.context_id=any(target_context_ids) and context.club_id=scope.club_id and(context.team_id is null or context.team_id=scope.team_id)
  where thread.thread_type<>'announcement' and internal.actor_can_access_thread(thread.id,false))
 insert into core.message_reads(thread_id,profile_id,through_revision)select id,actor_id,revision from accessible
 on conflict(thread_id,profile_id)do update set through_revision=greatest(core.message_reads.through_revision,excluded.through_revision),
  read_at=now(),device_revision=core.message_reads.device_revision+1;
 get diagnostics affected=row_count;
 with accessible as(select distinct thread.id,thread.revision from core.message_threads thread
  join core.thread_scopes scope on scope.thread_id=thread.id join internal.get_my_contexts_for_actor()context
   on context.context_id=any(target_context_ids) and context.club_id=scope.club_id and(context.team_id is null or context.team_id=scope.team_id)
  where thread.thread_type='announcement' and internal.actor_can_access_thread(thread.id,false))
 insert into core.announcement_reads(thread_id,profile_id,through_revision)select id,actor_id,revision from accessible
 on conflict(thread_id,profile_id)do update set through_revision=greatest(core.announcement_reads.through_revision,excluded.through_revision),
  read_at=now(),device_revision=core.announcement_reads.device_revision+1;
 get diagnostics announcement_affected=row_count;
 affected:=affected+announcement_affected;
 existing:=jsonb_build_object('marked_count',affected);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.all.read.v1',existing);
 return existing;
end;$$;

create function api.create_announcement(context_id uuid,subject text,participant_profile_ids uuid[],idempotency_key uuid)
returns uuid language sql security invoker set search_path='' as
$$select internal.create_announcement_for_actor(context_id,subject,participant_profile_ids,idempotency_key)$$;
create function api.mark_all_threads_read(context_ids uuid[],idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.mark_all_threads_read_for_actor(context_ids,idempotency_key)$$;

revoke all on table core.announcement_reads from public,anon,authenticated;
revoke all on function internal.create_announcement_for_actor(uuid,text,uuid[],uuid),
 internal.mark_all_threads_read_for_actor(uuid[],uuid),api.create_announcement(uuid,text,uuid[],uuid),
 api.mark_all_threads_read(uuid[],uuid) from public,anon,authenticated;
grant execute on function internal.create_announcement_for_actor(uuid,text,uuid[],uuid),
 internal.mark_all_threads_read_for_actor(uuid[],uuid),api.create_announcement(uuid,text,uuid[],uuid),
 api.mark_all_threads_read(uuid[],uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827145227_msg03_announcement_read_status','greenfield','MSG-03 one-way announcement and separate participant read model');
notify pgrst,'reload schema';
