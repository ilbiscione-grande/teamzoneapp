-- Found via a physical walkthrough (Ledare replying to a guardian DM):
-- sending ANY message failed outright. internal.send_message_for_actor
-- inserts into internal.notification_outbox for each active participant,
-- which fires internal.broadcast_notification_center_invalidation() — whose
-- declare-block computed target_profile_id via
--   case when tg_table_name='notification_outbox' then new.recipient_profile_id
--        else new.profile_id end
-- This same trigger function is also attached to core.notification_receipts
-- (which has profile_id but no recipient_profile_id). Referencing
-- new.<column> directly on a polymorphic NEW record is unsafe across two
-- differently-shaped tables sharing one trigger function: Postgres raised
-- "record \"new\" has no field \"profile_id\"" even when the *_outbox branch
-- was the one being taken, because the CASE's other branch still gets
-- resolved against NEW's actual row type. Switching to a JSONB-based lookup
-- makes the fallback resolve dynamically instead of failing to compile.
create or replace function internal.broadcast_notification_center_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile_id uuid := coalesce(
    (to_jsonb(new) ->> 'recipient_profile_id')::uuid,
    (to_jsonb(new) ->> 'profile_id')::uuid
  );
begin
  if target_profile_id is not null then
    perform realtime.send('{}'::jsonb,'invalidate','notification:center:'||target_profile_id::text,true);
  end if;
  return null;
end
$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260906201500_msg08_fix_notification_center_trigger_field_lookup','greenfield','Physical walkthrough: sending any message failed because of an unsafe NEW.field reference in a trigger shared by two differently-shaped tables');
notify pgrst,'reload schema';
