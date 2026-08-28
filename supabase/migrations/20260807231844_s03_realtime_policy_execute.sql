create function internal.actor_can_subscribe_calendar_topic(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from core.person_account_links link
      join core.assignments assignment
        on assignment.club_person_id = link.club_person_id
       and assignment.club_id = link.club_id
      where link.profile_id = auth.uid()
        and link.club_id = target_club_id
        and link.state = 'active'
        and assignment.state = 'active'
        and assignment.starts_at <= now()
        and (assignment.ends_at is null or assignment.ends_at > now())
    );
$$;

revoke all on function internal.actor_can_subscribe_calendar_topic(uuid)
from public, anon, authenticated;
grant execute on function internal.actor_can_subscribe_calendar_topic(uuid)
to authenticated;

drop policy teamzone_calendar_broadcast_select on realtime.messages;

create policy teamzone_calendar_broadcast_select
on realtime.messages for select to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (select realtime.topic()) ~ '^calendar:club:[0-9a-fA-F-]{36}$'
  and internal.actor_can_subscribe_calendar_topic(
    substring((select realtime.topic()) from '^calendar:club:([0-9a-fA-F-]{36})$')::uuid
  )
);

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260807231844_s03_realtime_policy_execute','greenfield',null);
