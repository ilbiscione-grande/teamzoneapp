\set ON_ERROR_STOP on
set role postgres;
begin;
\ir ../migrations/20260822082158_s10b_board_mandate_commands.sql

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
 ((select assignment.id from core.assignments assignment join core.person_account_links link on link.club_person_id=assignment.club_person_id and link.club_id=assignment.club_id where link.profile_id='d2ae2b22-6ecd-4009-a512-765f80eff511' and assignment.state='active' limit 1),'board.read'),
 ((select assignment.id from core.assignments assignment join core.person_account_links link on link.club_person_id=assignment.club_person_id and link.club_id=assignment.club_id where link.profile_id='d2ae2b22-6ecd-4009-a512-765f80eff511' and assignment.state='active' limit 1),'board.approve')
) value(assignment_id,capability)
on conflict(assignment_id,capability,scope_type,scope_id) do update set ends_at=null;

select set_config('request.jwt.claim.sub','6379829a-1258-4893-aae7-d063979ef118',true);
select internal.create_board_mandate_change_for_actor(
 'e423cb36-eaf3-44a5-b6d0-0406914a21ae','d6c33c2f-a54c-4960-a470-b7d12650b469',null,
 'grant','treasurer',now(),now()+interval '1 year','Rollback board mandate test',
 '11111111-1111-4111-8111-111111111111'
) as change_id \gset
select set_config('test.change_id',:'change_id',true);

do $$ begin
 begin
  perform internal.approve_board_mandate_change_for_actor(
   current_setting('test.change_id')::uuid,'approved','Creator must fail','22222222-2222-4222-8222-222222222222');
  raise exception 'creator approval unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
end $$;

select set_config('request.jwt.claim.sub','1c59f7e1-64be-4c20-aecf-430edbd80e99',true);
select internal.approve_board_mandate_change_for_actor(
 :'change_id','approved','First independent approval','33333333-3333-4333-8333-333333333333');

select set_config('request.jwt.claim.sub','6379829a-1258-4893-aae7-d063979ef118',true);
do $$ begin
 begin
  perform internal.apply_board_mandate_change_for_actor(
   current_setting('test.change_id')::uuid,'44444444-4444-4444-8444-444444444444');
  raise exception 'one-of-two apply unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
end $$;

select set_config('request.jwt.claim.sub','d2ae2b22-6ecd-4009-a512-765f80eff511',true);
select internal.approve_board_mandate_change_for_actor(
 :'change_id','approved','Second independent approval','55555555-5555-4555-8555-555555555555');

select set_config('request.jwt.claim.sub','6379829a-1258-4893-aae7-d063979ef118',true);
select internal.apply_board_mandate_change_for_actor(
 :'change_id','66666666-6666-4666-8666-666666666666') as mandate_id \gset
select set_config('test.mandate_id',:'mandate_id',true);

do $$ begin
 if not exists(select 1 from core.board_mandates where id=current_setting('test.mandate_id')::uuid and office='treasurer' and state='active') then
  raise exception 'mandate was not applied';
 end if;
 if (select count(*) from core.board_mandate_change_approvals where change_id=current_setting('test.change_id')::uuid and decision='approved')<>2 then
  raise exception 'approval count mismatch';
 end if;
end $$;

rollback;
