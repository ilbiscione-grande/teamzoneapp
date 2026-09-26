-- A callup response changes Home even when it creates no notification-outbox
-- row. Broadcast only an empty invalidation to accounts that can already act
-- for the called person; every client reloads its authorized projection.

create function internal.broadcast_callup_response_home_invalidation()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare target_profile_id uuid;
begin
  for target_profile_id in
    select distinct recipient.profile_id
    from (
      select new.actor_profile_id as profile_id
      union
      select link.profile_id
      from core.callups callup
      join core.person_account_links link
        on link.club_id=callup.club_id
       and link.club_person_id=callup.club_person_id
       and link.state='active'
      where callup.id=new.callup_id
      union
      select guardian_link.profile_id
      from core.callups callup
      join core.guardian_relations relation
        on relation.club_id=callup.club_id
       and relation.child_person_id=callup.club_person_id
       and relation.state='active'
       and relation.starts_at<=statement_timestamp()
       and (relation.ends_at is null or relation.ends_at>statement_timestamp())
      join core.person_account_links guardian_link
        on guardian_link.club_id=relation.club_id
       and guardian_link.club_person_id=relation.guardian_person_id
       and guardian_link.state='active'
      where callup.id=new.callup_id
    ) recipient
    where recipient.profile_id is not null
  loop
    perform realtime.send(
      '{}'::jsonb,
      'invalidate',
      'notification:center:'||target_profile_id::text,
      true
    );
  end loop;
  return null;
end;
$$;

revoke all on function internal.broadcast_callup_response_home_invalidation()
from public, anon, authenticated;

create trigger callup_response_home_invalidation
after insert on core.callup_responses
for each row execute function internal.broadcast_callup_response_home_invalidation();

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20260924105355_home_callup_response_invalidation','greenfield',
  'Empty private Home resync after revisioned callup response'
where not exists (
  select 1 from internal.migration_provenance
  where migration_name='20260924105355_home_callup_response_invalidation'
);
