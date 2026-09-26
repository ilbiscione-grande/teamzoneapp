-- EventDetails has its own canonical route. Notification links are computed
-- when the center is read, so existing callup/event notifications benefit too.

create or replace function internal.notification_deep_link(
  outbox internal.notification_outbox)
returns text
language sql
stable
set search_path=''
as $$
  select case
    when outbox.event_type='message.message.sent.v1'
      and outbox.payload_ref->>'thread_id'~'^[0-9a-fA-F-]{36}$'
      then '/inbox?thread='||(outbox.payload_ref->>'thread_id')
    when outbox.event_type like 'callup.%'
      and outbox.payload_ref->>'event_id'~'^[0-9a-fA-F-]{36}$'
      then '/calendar/event/'||(outbox.payload_ref->>'event_id')
    when outbox.aggregate_type='event'
      then '/calendar/event/'||outbox.aggregate_id::text
    else '/inbox'
  end;
$$;

revoke all on function internal.notification_deep_link(internal.notification_outbox)
from public, anon, authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20260924143236_msg08_event_notification_deep_link','greenfield',
  'Canonical EventDetails route for existing and new notifications'
where not exists (
  select 1 from internal.migration_provenance
  where migration_name='20260924143236_msg08_event_notification_deep_link'
);
