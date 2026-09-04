-- Performance: Auth RLS Initialization Plan advisor flagged
-- teamzone_inbox_broadcast_select and teamzone_notification_center_broadcast_select
-- for re-evaluating auth.uid() per row instead of once per statement.
-- realtime.topic() was already wrapped in (select ...); auth.uid() was not.
-- No behavior change: same predicate, just evaluated once per statement.

drop policy if exists teamzone_inbox_broadcast_select on realtime.messages;
create policy teamzone_inbox_broadcast_select on realtime.messages for select to authenticated using(
 realtime.messages.extension='broadcast' and(select realtime.topic())='message:inbox:'||(select auth.uid())::text
);

drop policy if exists teamzone_notification_center_broadcast_select on realtime.messages;
create policy teamzone_notification_center_broadcast_select on realtime.messages for select to authenticated using(
 realtime.messages.extension='broadcast'and(select realtime.topic())='notification:center:'||(select auth.uid())::text
);
