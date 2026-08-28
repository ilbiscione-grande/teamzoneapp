\set ON_ERROR_STOP on
set role postgres;
begin;

insert into auth.users(id,raw_user_meta_data) values
 ('82000000-0000-0000-0000-000000000001','{"display_name":"Admin A"}'),
 ('82000000-0000-0000-0000-000000000002','{"display_name":"Admin B"}'),
 ('82000000-0000-0000-0000-000000000003','{"display_name":"Claimant"}'),
 ('82000000-0000-0000-0000-000000000004','{"display_name":"Guardian"}');
insert into core.clubs(id,name,slug) values
 ('82100000-0000-0000-0000-000000000001','S02 Klubb A','s02-klubb-a'),
 ('82100000-0000-0000-0000-000000000002','S02 Klubb B','s02-klubb-b');
insert into core.teams(id,club_id,name) values
 ('82200000-0000-0000-0000-000000000001','82100000-0000-0000-0000-000000000001','Lag A'),
 ('82200000-0000-0000-0000-000000000002','82100000-0000-0000-0000-000000000002','Lag B');
insert into core.club_people(id,club_id,display_name) values
 ('82300000-0000-0000-0000-000000000001','82100000-0000-0000-0000-000000000001','Admin A'),
 ('82300000-0000-0000-0000-000000000002','82100000-0000-0000-0000-000000000002','Admin B'),
 ('82300000-0000-0000-0000-000000000004','82100000-0000-0000-0000-000000000001','Guardian');
insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at) values
 ('82100000-0000-0000-0000-000000000001','82300000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','active',now()),
 ('82100000-0000-0000-0000-000000000002','82300000-0000-0000-0000-000000000002','82000000-0000-0000-0000-000000000002','active',now()),
 ('82100000-0000-0000-0000-000000000001','82300000-0000-0000-0000-000000000004','82000000-0000-0000-0000-000000000004','active',now());
insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at) values
 ('82400000-0000-0000-0000-000000000001','82100000-0000-0000-0000-000000000001','82200000-0000-0000-0000-000000000001','82300000-0000-0000-0000-000000000001','club_functionary','active',now()-interval '1 day'),
 ('82400000-0000-0000-0000-000000000002','82100000-0000-0000-0000-000000000002','82200000-0000-0000-0000-000000000002','82300000-0000-0000-0000-000000000002','club_functionary','active',now()-interval '1 day');
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at) values
 ('82100000-0000-0000-0000-000000000001','82400000-0000-0000-0000-000000000001','club.memberships.manage','club','82100000-0000-0000-0000-000000000001',now()-interval '1 day'),
 ('82100000-0000-0000-0000-000000000001','82400000-0000-0000-0000-000000000001','team.roster.view','team','82200000-0000-0000-0000-000000000001',now()-interval '1 day'),
 ('82100000-0000-0000-0000-000000000001','82400000-0000-0000-0000-000000000001','club.safeguarding.manage','club','82100000-0000-0000-0000-000000000001',now()-interval '1 day'),
 ('82100000-0000-0000-0000-000000000002','82400000-0000-0000-0000-000000000002','club.memberships.manage','club','82100000-0000-0000-0000-000000000002',now()-interval '1 day');

set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000001',true);
select api.create_roster_person('82100000-0000-0000-0000-000000000001','82200000-0000-0000-0000-000000000001','S02 Spelare','F2012',now()-interval '1 day','82500000-0000-0000-0000-000000000001');
select api.create_roster_person('82100000-0000-0000-0000-000000000001','82200000-0000-0000-0000-000000000001','S02 Spelare','F2012',now()-interval '1 day','82500000-0000-0000-0000-000000000001');

do $$
declare person_id uuid; invite_id uuid;
begin
 select club_person_id into person_id from api.list_club_people('82100000-0000-0000-0000-000000000001','82200000-0000-0000-0000-000000000001') where display_name='S02 Spelare';
 if person_id is null then raise exception 'created roster person missing'; end if;
 select api.issue_roster_invite(person_id,'S02-token-abcdefghijklmnopqrstuvwxyz-123456',now()+interval '1 day','82500000-0000-0000-0000-000000000002') into invite_id;
 if invite_id is null then raise exception 'invite missing'; end if;
end $$;

set local role postgres;
do $$ begin
 if (select count(*) from core.club_people where display_name='S02 Spelare')<>1 then raise exception 'idempotency created duplicate person'; end if;
 if (select count(*) from audit.command_events where command_type='roster.person.create.v1')<>1 then raise exception 'idempotency created duplicate audit'; end if;
end $$;

update core.club_people
set safeguarding_required=true
where display_name='S02 Spelare';

set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000001',true);
select api.issue_guardian_invite(
 '82300000-0000-0000-0000-000000000004',
 (select club_person_id from api.list_club_people('82100000-0000-0000-0000-000000000001','82200000-0000-0000-0000-000000000001') where display_name='S02 Spelare'),
 'S02-guardian-token-abcdefghijklmnopqrstuvwxyz',
 now()+interval '1 day',
 '82500000-0000-0000-0000-000000000009');

select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000003',true);
do $$ begin
 begin
  perform api.accept_guardian_invite('S02-guardian-token-abcdefghijklmnopqrstuvwxyz','82500000-0000-0000-0000-000000000010');
  raise exception 'wrong account accepted guardian invite';
 exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000004',true);
select api.accept_guardian_invite('S02-guardian-token-abcdefghijklmnopqrstuvwxyz','82500000-0000-0000-0000-000000000011');
do $$ begin
 begin
  perform api.accept_guardian_invite('S02-guardian-token-abcdefghijklmnopqrstuvwxyz','82500000-0000-0000-0000-000000000012');
  raise exception 'guardian token replay accepted';
 exception when invalid_parameter_value then null; end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000003',true);
select api.claim_club_person('S02-token-abcdefghijklmnopqrstuvwxyz-123456','82500000-0000-0000-0000-000000000003');
do $$ begin
 begin
  perform api.claim_club_person('S02-token-abcdefghijklmnopqrstuvwxyz-123456','82500000-0000-0000-0000-000000000004');
  raise exception 'consumed claim token reused';
 exception when invalid_parameter_value then null; end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000002',true);
do $$ begin
 begin
  perform * from api.list_club_people('82100000-0000-0000-0000-000000000001',null);
  raise exception 'cross-club roster leaked';
 exception when insufficient_privilege then null; end;
 begin
  perform api.set_guardian_relation();
  raise exception 'guardian mutation unexpectedly enabled';
 exception when feature_not_supported then null; end;
end $$;

set local role postgres;
do $$ begin
 begin
  insert into core.team_assignments(club_id,team_id,club_person_id,starts_at)
  select club_id,'82200000-0000-0000-0000-000000000001',id,now()-interval '2 days' from core.club_people where display_name='S02 Spelare';
  raise exception 'overlapping assignment accepted';
 exception when exclusion_violation then null; end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000001',true);
select api.request_transfer(
 (select club_person_id from api.list_club_people('82100000-0000-0000-0000-000000000001','82200000-0000-0000-0000-000000000001') where display_name='S02 Spelare'),
 '82200000-0000-0000-0000-000000000001','82100000-0000-0000-0000-000000000002','82200000-0000-0000-0000-000000000002',now()+interval '1 hour','82500000-0000-0000-0000-000000000005');
set local role postgres;
select internal.decide_transfer_for_actor((select id from core.transfer_cases where state='requested'),'approved','source ok',1,'82500000-0000-0000-0000-000000000006');

select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000002',true);
select internal.decide_transfer_for_actor((select id from core.transfer_cases where state='requested'),'approved','target ok',1,'82500000-0000-0000-0000-000000000007');
do $$ begin
 if (select state from core.transfer_cases limit 1)<>'requested' then raise exception 'minor transfer approved without guardian'; end if;
end $$;
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000004',true);
select internal.decide_transfer_for_actor((select id from core.transfer_cases where state='requested'),'approved','guardian ok',1,'82500000-0000-0000-0000-000000000013');
update core.transfer_cases set effective_at=now()-interval '1 second' where state='approved';
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000002',true);
select internal.complete_transfer_for_actor((select id from core.transfer_cases where state='approved'),2,'82500000-0000-0000-0000-000000000008');

do $$ begin
 if (select state from core.transfer_cases limit 1)<>'completed' then raise exception 'transfer not completed'; end if;
 if (select count(*) from audit.transfer_approvals)<>3 then raise exception 'transfer approvals missing'; end if;
 if (select count(*) from core.club_people where display_name='S02 Spelare')<>2 then raise exception 'source history or target representation missing'; end if;
 if exists(select 1 from core.team_assignments where club_id='82100000-0000-0000-0000-000000000001' and state='active' and club_person_id in(select id from core.club_people where display_name='S02 Spelare')) then raise exception 'source assignment still active'; end if;
 if not exists(select 1 from core.team_assignments where club_id='82100000-0000-0000-0000-000000000002' and state='active' and club_person_id in(select id from core.club_people where display_name='S02 Spelare')) then raise exception 'target assignment missing'; end if;
end $$;

rollback;
reset role;
