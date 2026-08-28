\set ON_ERROR_STOP on
set role postgres;
begin;
\ir ../migrations/20260822082824_s10b_board_sandbox_pilot.sql

do $$ begin
 if (select count(*) from core.capability_grants
     where club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae'
       and ends_at is null and capability='board.read')<>3 then
  raise exception 'board read grants mismatch';
 end if;
 if (select count(*) from core.capability_grants
     where club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae'
       and ends_at is null and capability='board.approve')<>2 then
  raise exception 'board approve grants mismatch';
 end if;
 if (select count(*) from core.capability_grants
     where club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae'
       and ends_at is null and capability='board.manage')<>1 then
  raise exception 'board manage grants mismatch';
 end if;
end $$;

rollback;
