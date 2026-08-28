\set ON_ERROR_STOP on
set role postgres;
begin;
\ir ../migrations/20260822090354_s10b_board_effective_period.sql

insert into core.board_mandates(id,club_id,assignment_id,office,starts_at,ends_at,state)
values
 ('71000000-0000-4000-8000-000000000001','e423cb36-eaf3-44a5-b6d0-0406914a21ae','b7089d1b-2fa4-4efc-bcda-f779bfeea868','auditor',now()-interval '2 days',now()-interval '1 day','active'),
 ('71000000-0000-4000-8000-000000000002','e423cb36-eaf3-44a5-b6d0-0406914a21ae','b7089d1b-2fa4-4efc-bcda-f779bfeea868','member',now()+interval '1 day',now()+interval '2 days','active');

select set_config('request.jwt.claim.sub','6379829a-1258-4893-aae7-d063979ef118',true);

do $$
declare board jsonb:=internal.get_board_for_actor('e423cb36-eaf3-44a5-b6d0-0406914a21ae');
begin
 if not jsonb_path_exists(board,'$.mandates[*] ? (@.id == "71000000-0000-4000-8000-000000000001" && @.state == "ended")') then
  raise exception 'expired mandate was not projected as ended';
 end if;
 if not jsonb_path_exists(board,'$.mandates[*] ? (@.id == "71000000-0000-4000-8000-000000000002" && @.state == "scheduled")') then
  raise exception 'future mandate was not projected as scheduled';
 end if;
end$$;

rollback;
