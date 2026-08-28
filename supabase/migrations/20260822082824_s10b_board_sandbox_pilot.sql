-- Explicit sandbox-only Board pilot for Thomas club.

insert into core.capability_grants(
 club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by
)
select 'e423cb36-eaf3-44a5-b6d0-0406914a21ae',assignment_id,capability,'club',
 'e423cb36-eaf3-44a5-b6d0-0406914a21ae',now(),'6379829a-1258-4893-aae7-d063979ef118'
from (values
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'board.read'),
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'board.manage'),
 ('d6c33c2f-a54c-4960-a470-b7d12650b469'::uuid,'board.read'),
 ('d6c33c2f-a54c-4960-a470-b7d12650b469'::uuid,'board.approve'),
 ((select assignment.id from core.assignments assignment
   join core.person_account_links link on link.club_person_id=assignment.club_person_id and link.club_id=assignment.club_id
   where link.profile_id='d2ae2b22-6ecd-4009-a512-765f80eff511' and link.state='active'
     and assignment.club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae' and assignment.state='active' limit 1),'board.read'),
 ((select assignment.id from core.assignments assignment
   join core.person_account_links link on link.club_person_id=assignment.club_person_id and link.club_id=assignment.club_id
   where link.profile_id='d2ae2b22-6ecd-4009-a512-765f80eff511' and link.state='active'
     and assignment.club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae' and assignment.state='active' limit 1),'board.approve')
) value(assignment_id,capability)
on conflict(assignment_id,capability,scope_type,scope_id) do update set
 ends_at=null,starts_at=least(core.capability_grants.starts_at,excluded.starts_at),
 revision=core.capability_grants.revision+1;

do $$ begin
 if (select count(*) from core.capability_grants grant_row
     where grant_row.club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae'
       and grant_row.ends_at is null and grant_row.capability='board.read')<>3 then
  raise exception 'board_pilot_read_count_mismatch';
 end if;
 if (select count(*) from core.capability_grants grant_row
     where grant_row.club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae'
       and grant_row.ends_at is null and grant_row.capability='board.approve')<>2 then
  raise exception 'board_pilot_approve_count_mismatch';
 end if;
 if (select count(*) from core.capability_grants grant_row
     where grant_row.club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae'
       and grant_row.ends_at is null and grant_row.capability='board.manage')<>1 then
  raise exception 'board_pilot_manage_count_mismatch';
 end if;
end$$;

insert into audit.command_events(
 club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata
) values(
 'e423cb36-eaf3-44a5-b6d0-0406914a21ae','6379829a-1258-4893-aae7-d063979ef118',
 'board.sandbox_pilot.activated.v1','club','e423cb36-eaf3-44a5-b6d0-0406914a21ae',
 'Explicit S10B Board sandbox pilot approval',jsonb_build_object('readers',3,'approvers',2,'managers',1)
);

insert into internal.migration_provenance(migration_name,source_kind)
values('20260822082824_s10b_board_sandbox_pilot','greenfield');
