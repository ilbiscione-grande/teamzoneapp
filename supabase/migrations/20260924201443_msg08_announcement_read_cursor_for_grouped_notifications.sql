-- MSG-08 follow-up: announcement threads use core.announcement_reads, while
-- ordinary conversation threads use core.message_reads.

create or replace function internal.list_notification_center_for_actor(
  page_before timestamptz default null, page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); result jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;

  with source as materialized (
    select outbox.id, outbox.event_type, outbox.created_at,
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
    where outbox.recipient_profile_id=actor_id
      and lower(outbox.event_type) not like '%watchpoint%'
      and lower(outbox.event_type) not like '%assistant%'
      and lower(outbox.event_type) not like '%ac_signal%'
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
    select latest.id, latest.event_type, latest.category,
      latest.canonical_key, latest.priority, latest.title, latest.preview,
      latest.deep_link, grouped.unread_items>0 unread, latest.created_at,
      case when latest.event_type='message.message.sent.v1'
        then grouped.unread_items else null end message_count
    from latest join grouped using(canonical_key)
    order by latest.priority, latest.created_at desc, latest.id
    limit greatest(1,least(page_limit,100))
  )
  select jsonb_build_object(
    'schema_version',4,
    'unread_count',(select count(*) from grouped where unread_items>0),
    'items',coalesce((select jsonb_agg(to_jsonb(limited)
      order by limited.priority,limited.created_at desc,limited.id)
      from limited),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create trigger announcement_reads_center_invalidation_insert
after insert on core.announcement_reads for each row
execute function internal.broadcast_notification_center_invalidation();

create trigger announcement_reads_center_invalidation_advance
after update of through_revision on core.announcement_reads for each row
when (new.through_revision>old.through_revision)
execute function internal.broadcast_notification_center_invalidation();

revoke all on function internal.list_notification_center_for_actor(
  timestamptz,integer) from public, anon, authenticated;
grant execute on function internal.list_notification_center_for_actor(
  timestamptz,integer) to authenticated;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference)
values('20260924201443_msg08_announcement_read_cursor_for_grouped_notifications',
  'greenfield','MSG-08 announcement notifications follow announcement read cursor');
notify pgrst,'reload schema';
