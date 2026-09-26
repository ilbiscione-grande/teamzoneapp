-- MSG-08: remove message notifications for threads the actor can no longer read.
-- Outbox history remains intact; only the actor-scoped projection changes.

create or replace function internal.list_notification_center_for_actor(
  page_before timestamptz default null, page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;

  with source as materialized (
    select outbox.id, outbox.aggregate_id, outbox.event_type, outbox.created_at,
      internal.notification_attention_key(outbox) canonical_key,
      internal.notification_attention_kind(outbox.event_type) category,
      internal.attention_priority(
        internal.notification_attention_kind(outbox.event_type)) priority,
      internal.notification_title(outbox.event_type) title,
      internal.notification_preview(outbox.event_type) preview,
      internal.notification_deep_link(outbox) deep_link,
      receipt.state receipt_state,
      (receipt.notification_id is null and (
        outbox.event_type<>'message.message.sent.v1' or
        (message.id is not null and message.revision>coalesce(
          case when thread.thread_type='announcement'
            then announcement_read.through_revision
            else message_read.through_revision end,0))
      )) unread
    from internal.notification_outbox outbox
    left join core.notification_receipts receipt
      on receipt.notification_id=outbox.id and receipt.profile_id=actor_id
    left join core.messages message
      on outbox.event_type='message.message.sent.v1'
      and message.id=outbox.aggregate_id
    left join core.message_threads thread on thread.id=message.thread_id
    left join core.message_reads message_read
      on message_read.thread_id=message.thread_id
      and message_read.profile_id=actor_id
    left join core.announcement_reads announcement_read
      on announcement_read.thread_id=message.thread_id
      and announcement_read.profile_id=actor_id
    left join core.thread_personal_visibility source_visibility
      on source_visibility.thread_id=thread.id
      and source_visibility.profile_id=actor_id
    where outbox.recipient_profile_id=actor_id
      and lower(outbox.event_type) not like '%watchpoint%'
      and lower(outbox.event_type) not like '%assistant%'
      and lower(outbox.event_type) not like '%ac_signal%'
      and (outbox.event_type<>'message.message.sent.v1' or (
        message.id is not null and thread.state<>'hidden'
        and not coalesce(source_visibility.hidden,false)
        and internal.actor_can_access_thread(thread.id,false)))
  ), grouped as (
    select canonical_key, count(*) filter(where unread)::integer unread_items
    from source group by canonical_key
  ), latest as (
    select distinct on(source.canonical_key) source.*
    from source
    where source.receipt_state is distinct from 'dismissed'
      and (page_before is null or source.created_at<page_before)
    order by source.canonical_key, source.created_at desc, source.id
  ), limited as (
    select latest.id, latest.aggregate_id, latest.event_type, latest.category,
      latest.canonical_key, latest.priority, latest.title, latest.preview,
      latest.deep_link, grouped.unread_items>0 unread, latest.created_at,
      case when latest.event_type='message.message.sent.v1'
        then grouped.unread_items else null end message_count
    from latest join grouped using(canonical_key)
    order by latest.priority, latest.created_at desc, latest.id
    limit greatest(1,least(page_limit,100))
  ), enriched as (
    select limited.id, limited.event_type, limited.category,
      limited.canonical_key, limited.priority, limited.title, limited.preview,
      limited.deep_link, limited.unread, limited.created_at,
      limited.message_count, safe.sender_name, safe.chat_name,
      safe.message_preview
    from limited
    left join core.messages latest_message
      on limited.event_type='message.message.sent.v1'
      and latest_message.id=limited.aggregate_id
    left join core.message_threads latest_thread
      on latest_thread.id=latest_message.thread_id
    left join core.profiles sender
      on sender.id=latest_message.sender_profile_id
    left join core.thread_personal_visibility visibility
      on visibility.thread_id=latest_thread.id
      and visibility.profile_id=actor_id
    left join lateral (
      select other_profile.display_name
      from core.thread_participants other_participant
      join core.profiles other_profile
        on other_profile.id=other_participant.profile_id
      where other_participant.thread_id=latest_thread.id
        and other_participant.profile_id<>actor_id
      order by other_participant.joined_at
      limit 1
    ) other_party on latest_thread.thread_type in ('direct','cross_club_direct')
    left join lateral (
      select sender.display_name sender_name,
        coalesce(nullif(btrim(latest_thread.subject),''),
          case when latest_thread.thread_type in ('direct','cross_club_direct')
            then nullif(btrim(other_party.display_name),'') end,
          case latest_thread.thread_type
            when 'announcement' then 'Anslag'
            when 'team' then 'Lagchatt'
            when 'leader' then 'Ledarchatt'
            else 'Konversation' end) chat_name,
        case when latest_message.state='sent' then
          left(btrim(regexp_replace(latest_message.body,
            '[[:space:]]+',' ','g')),140) end message_preview
      where latest_thread.state<>'hidden'
        and not coalesce(visibility.hidden,false)
        and internal.actor_can_access_thread(latest_thread.id,false)
    ) safe on true
  )
  select jsonb_build_object(
    'schema_version',5,
    'unread_count',(select count(*) from grouped where unread_items>0),
    'items',coalesce((select jsonb_agg(to_jsonb(enriched)
      order by enriched.priority,enriched.created_at desc,enriched.id)
      from enriched),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function internal.list_notification_center_for_actor(
  timestamptz,integer) from public, anon, authenticated;
grant execute on function internal.list_notification_center_for_actor(
  timestamptz,integer) to authenticated;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference)
values('20260924224500_msg08_hide_inaccessible_message_notifications',
  'greenfield','MSG-08 suppress inaccessible message groups from actor projection');
notify pgrst,'reload schema';
