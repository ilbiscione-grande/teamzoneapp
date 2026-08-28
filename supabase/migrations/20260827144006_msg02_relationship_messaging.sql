-- MSG-02 one relationship rule for search/create/add/send.

create function internal.messaging_relationship_allowed(actor_profile_id uuid,target_profile_id uuid,
 target_club_id uuid,target_team_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select actor_profile_id is not null and target_profile_id is not null and actor_profile_id<>target_profile_id
  and exists(
   select 1 from core.person_account_links actor_link
   join core.assignments actor_assignment on actor_assignment.club_id=actor_link.club_id
    and actor_assignment.club_person_id=actor_link.club_person_id
   join core.person_account_links target_link on target_link.profile_id=target_profile_id
    and target_link.club_id=actor_assignment.club_id and target_link.state='active'
   join core.assignments target_assignment on target_assignment.club_id=target_link.club_id
    and target_assignment.club_person_id=target_link.club_person_id
   where actor_link.profile_id=actor_profile_id and actor_link.state='active'
    and actor_assignment.club_id=target_club_id and target_assignment.club_id=target_club_id
    and(target_team_id is null or(actor_assignment.team_id=target_team_id and target_assignment.team_id=target_team_id))
    and actor_assignment.state='active' and actor_assignment.starts_at<=now()
    and(actor_assignment.ends_at is null or actor_assignment.ends_at>now())
    and target_assignment.state='active' and target_assignment.starts_at<=now()
    and(target_assignment.ends_at is null or target_assignment.ends_at>now())
    and(
     actor_assignment.role_package in('leader','club_functionary')
     or(actor_assignment.role_package='player' and target_assignment.role_package in('leader','guardian'))
     or(actor_assignment.role_package='guardian' and target_assignment.role_package='leader')
    )
  )
  and not exists(select 1 from core.contact_controls block where block.control_type='block' and block.state='active'
   and((block.requester_profile_id=actor_profile_id and block.target_profile_id=target_profile_id)
    or(block.target_profile_id=actor_profile_id and block.requester_profile_id=target_profile_id)));
$$;

create or replace function internal.resolve_allowed_recipients_for_actor(target_context_id uuid,search_text text default null)
returns table(profile_id uuid,display_name text,role_package text)
language plpgsql stable security definer set search_path='' as $$
declare actor_context record;
begin
 select * into actor_context from internal.get_my_contexts_for_actor() where context_id=target_context_id;
 if actor_context.context_id is null then raise insufficient_privilege using message='not_found';end if;
 if search_text is not null and length(search_text)>80 then raise invalid_parameter_value using message='invalid_search';end if;
 return query
 select distinct link.profile_id,profile.display_name,assignment.role_package
 from core.assignments assignment
 join core.person_account_links link on link.club_id=assignment.club_id
  and link.club_person_id=assignment.club_person_id and link.state='active'
 join core.profiles profile on profile.id=link.profile_id
 where assignment.club_id=actor_context.club_id
  and(actor_context.team_id is null or assignment.team_id=actor_context.team_id)
  and assignment.state='active' and assignment.starts_at<=now()
  and(assignment.ends_at is null or assignment.ends_at>now())
  and internal.messaging_relationship_allowed(auth.uid(),link.profile_id,actor_context.club_id,actor_context.team_id)
  and(search_text is null or profile.display_name ilike '%'||replace(replace(left(btrim(search_text),80),'%','\%'),'_','\_')||'%' escape '\')
 order by profile.display_name limit 50;
end;$$;

create or replace function internal.create_thread_for_actor(target_context_id uuid,new_type text,new_subject text,
 recipient_profile_ids uuid[],idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();context_row record;thread_id uuid:=gen_random_uuid();recipient_count integer;
 allowed_count integer;existing jsonb;actor_person uuid;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication d where d.actor_profile_id=actor_id
  and d.command_type='message.thread.created.v1' and d.idempotency_key=create_thread_for_actor.idempotency_key;
 if existing is not null then return(existing->>'thread_id')::uuid;end if;
 select * into context_row from internal.get_my_contexts_for_actor() where context_id=target_context_id;
 if context_row.context_id is null or new_type not in('group','direct') then raise insufficient_privilege using message='not_found';end if;
 if recipient_profile_ids is null or cardinality(recipient_profile_ids)<1 or cardinality(recipient_profile_ids)>50
  or array_position(recipient_profile_ids,null) is not null or(new_type='group' and length(btrim(coalesce(new_subject,''))) not between 1 and 120)
 then raise invalid_parameter_value using message='invalid_recipients';end if;
 select count(distinct value) into recipient_count from unnest(recipient_profile_ids)value;
 select count(*) into allowed_count from(select distinct value profile_id from unnest(recipient_profile_ids)value)requested
  where internal.messaging_relationship_allowed(actor_id,requested.profile_id,context_row.club_id,context_row.team_id);
 if recipient_count<>allowed_count or(new_type='direct' and recipient_count<>1)
 then raise insufficient_privilege using message='invalid_recipients';end if;
 select link.club_person_id into actor_person from core.person_account_links link
  where link.profile_id=actor_id and link.club_id=context_row.club_id and link.state='active';
 insert into core.message_threads(id,club_id,thread_type,subject,created_by)
 values(thread_id,context_row.club_id,new_type,case when new_type='group' then btrim(new_subject) end,actor_id);
 insert into core.thread_scopes(thread_id,club_id,team_id,scope_role)
 values(thread_id,context_row.club_id,context_row.team_id,'owner');
 insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role)
 values(thread_id,actor_id,context_row.club_id,actor_person,'creator');
 insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role)
 select distinct on(link.profile_id) thread_id,link.profile_id,link.club_id,link.club_person_id,'member'
 from core.person_account_links link where link.profile_id=any(recipient_profile_ids)
  and link.club_id=context_row.club_id and link.state='active' order by link.profile_id,link.created_at desc;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.thread.created.v1',jsonb_build_object('thread_id',thread_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(context_row.club_id,actor_id,'message.thread.created.v1','message_thread',thread_id,1,
  jsonb_build_object('type',new_type,'recipient_count',recipient_count));
 return thread_id;
end;$$;

create function internal.add_thread_participants_for_actor(target_thread_id uuid,new_profile_ids uuid[],idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();thread_row core.message_threads%rowtype;scope_row core.thread_scopes%rowtype;
 existing jsonb;requested_count integer;allowed_count integer;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication d where d.actor_profile_id=actor_id
  and d.command_type='message.thread.participants_added.v1' and d.idempotency_key=add_thread_participants_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 select * into thread_row from core.message_threads where id=target_thread_id for update;
 select * into scope_row from core.thread_scopes where thread_id=target_thread_id order by(scope_role='owner')desc limit 1;
 if thread_row.id is null or thread_row.thread_type<>'group' or thread_row.state<>'active'
  or not exists(select 1 from core.thread_participants participant where participant.thread_id=thread_row.id
   and participant.profile_id=actor_id and participant.state='active' and participant.participant_role in('creator','moderator'))
  or new_profile_ids is null or cardinality(new_profile_ids)<1 or cardinality(new_profile_ids)>50
  or array_position(new_profile_ids,null) is not null
 then raise insufficient_privilege using message='not_found';end if;
 select count(distinct value) into requested_count from unnest(new_profile_ids)value;
 select count(*) into allowed_count from(select distinct value profile_id from unnest(new_profile_ids)value)requested
  where internal.messaging_relationship_allowed(actor_id,requested.profile_id,scope_row.club_id,scope_row.team_id);
 if requested_count<>allowed_count then raise insufficient_privilege using message='invalid_recipients';end if;
 insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role,state,left_at)
 select distinct on(link.profile_id) thread_row.id,link.profile_id,link.club_id,link.club_person_id,'member','active',null
 from core.person_account_links link where link.profile_id=any(new_profile_ids)
  and link.club_id=scope_row.club_id and link.state='active' order by link.profile_id,link.created_at desc
 on conflict(thread_id,profile_id) do update set state='active',left_at=null,club_person_id=excluded.club_person_id,
  revision=core.thread_participants.revision+1;
 update core.message_threads set revision=revision+1 where id=thread_row.id returning revision into new_revision;
 existing:=jsonb_build_object('thread_id',thread_row.id,'added_count',requested_count,'thread_revision',new_revision);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'message.thread.participants_added.v1',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(scope_row.club_id,actor_id,'message.thread.participants_added.v1','message_thread',thread_row.id,new_revision,
  jsonb_build_object('recipient_count',requested_count));
 return existing;
end;$$;

create or replace function internal.actor_can_access_thread(target_thread_id uuid,require_send boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from core.thread_participants participant
  join core.person_account_links link on link.profile_id=participant.profile_id and link.club_id=participant.club_id
   and link.club_person_id=participant.club_person_id and link.state='active'
  join core.message_threads thread on thread.id=participant.thread_id
  where participant.thread_id=target_thread_id and participant.profile_id=auth.uid() and participant.state='active'
   and(not require_send or thread.state='active')
   and exists(select 1 from core.assignments assignment join core.thread_scopes scope
    on scope.thread_id=participant.thread_id and scope.club_id=assignment.club_id
     and(scope.team_id is null or scope.team_id=assignment.team_id)
    where assignment.club_person_id=participant.club_person_id and assignment.club_id=participant.club_id
     and assignment.state='active' and assignment.starts_at<=now() and(assignment.ends_at is null or assignment.ends_at>now()))
   and(not exists(select 1 from core.system_thread_bindings binding where binding.thread_id=thread.id and binding.thread_kind='leader')
    or exists(select 1 from core.system_thread_bindings binding where binding.thread_id=thread.id and binding.thread_kind='leader'
     and internal.actor_has_capability(binding.club_id,binding.team_id,'team.roster.view')))
   and(not require_send or thread.thread_type not in('group','direct') or not exists(
    select 1 from core.thread_participants recipient join core.thread_scopes scope on scope.thread_id=thread.id
    where recipient.thread_id=thread.id and recipient.state='active' and recipient.profile_id<>auth.uid()
     and not internal.messaging_relationship_allowed(auth.uid(),recipient.profile_id,scope.club_id,scope.team_id)))
   and(not require_send or thread.thread_type<>'cross_club_direct' or(
    internal.actor_is_verified_adult_leader(auth.uid()) and not exists(select 1 from core.thread_participants recipient
     where recipient.thread_id=thread.id and recipient.state='active' and recipient.profile_id<>auth.uid()
      and not internal.actor_is_verified_adult_leader(recipient.profile_id))))
   and not exists(select 1 from core.contact_controls block where block.control_type='block' and block.state='active'
    and((block.requester_profile_id=auth.uid() and block.target_profile_id in(select profile_id from core.thread_participants where thread_id=target_thread_id and state='active'))
     or(block.target_profile_id=auth.uid() and block.requester_profile_id in(select profile_id from core.thread_participants where thread_id=target_thread_id and state='active'))))
 );
$$;

create function api.add_thread_participants(thread_id uuid,profile_ids uuid[],idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.add_thread_participants_for_actor(thread_id,profile_ids,idempotency_key)$$;
revoke all on function internal.messaging_relationship_allowed(uuid,uuid,uuid,uuid),
 internal.add_thread_participants_for_actor(uuid,uuid[],uuid),api.add_thread_participants(uuid,uuid[],uuid)
 from public,anon,authenticated;
grant execute on function internal.add_thread_participants_for_actor(uuid,uuid[],uuid),
 api.add_thread_participants(uuid,uuid[],uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827144006_msg02_relationship_messaging','greenfield','MSG-02 one relationship rule for recipient search, create, add and send; player-direct disabled');
notify pgrst,'reload schema';
