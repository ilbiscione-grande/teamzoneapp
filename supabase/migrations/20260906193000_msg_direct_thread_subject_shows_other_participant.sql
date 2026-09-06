-- Direct-message threads never had a subject, so the client always showed
-- the generic "Direktmeddelande" placeholder for every 1:1 conversation
-- (found via a physical walkthrough of the Inbox as Ledare). Falls back to
-- the other participant's display name for 'direct'/'cross_club_direct'
-- threads whose subject is still null, leaving group/announcement threads
-- (which already carry a real subject) untouched.
create or replace function internal.list_threads_for_actor(target_context_ids uuid[],page_before timestamptz default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if target_context_ids is null or cardinality(target_context_ids)=0 or cardinality(target_context_ids)>50 then raise invalid_parameter_value using message='invalid_context_selection';end if;
 if exists(select 1 from unnest(target_context_ids)requested where not exists(select 1 from internal.get_my_contexts_for_actor()context where context.context_id=requested))
 then raise insufficient_privilege using message='not_found';end if;
 return jsonb_build_object('schema_version',3,'generated_at',now(),'threads',coalesce((select jsonb_agg(row_value order by pinned desc,last_at desc,id)from(
  select thread.id,thread.thread_type,
   coalesce(thread.subject,case when thread.thread_type in('direct','cross_club_direct')then nullif(btrim(other_party.display_name),'')else null end)subject,
   thread.state,thread.revision,coalesce(last_message.created_at,thread.created_at)last_at,
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
  left join lateral(select other_profile.display_name from core.thread_participants other_participant
   join core.profiles other_profile on other_profile.id=other_participant.profile_id
   where other_participant.thread_id=thread.id and other_participant.profile_id<>auth.uid()
   order by other_participant.joined_at limit 1)other_party on thread.thread_type in('direct','cross_club_direct')
  where internal.actor_can_access_thread(thread.id,false)and thread.state<>'hidden'and not coalesce(visibility.hidden,false)
   and(page_before is null or coalesce(last_message.created_at,thread.created_at)<page_before)
  group by thread.id,last_message.created_at,last_message.revision,last_message.body,last_message.sender_name,message_read.through_revision,announcement_read.through_revision,
   mute.state,mute.muted_until,pin.pinned,participant.participant_role,other_party.display_name
  order by pinned desc,last_at desc,thread.id limit greatest(1,least(page_limit,100)))row_value),'[]'::jsonb));
end$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260906193000_msg_direct_thread_subject_shows_other_participant','greenfield','Physical walkthrough: DM threads should title as the other participant, not a generic placeholder');
notify pgrst,'reload schema';
