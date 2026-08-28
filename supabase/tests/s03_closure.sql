\set ON_ERROR_STOP on
set role postgres;
begin;

insert into auth.users(id,raw_user_meta_data) values
 ('84000000-0000-0000-0000-000000000001','{"display_name":"S03 closure"}');
insert into core.clubs(id,name,slug) values
 ('84100000-0000-0000-0000-000000000001','S03 Closure Club','s03-closure-club');
insert into core.teams(id,club_id,name) values
 ('84200000-0000-0000-0000-000000000001','84100000-0000-0000-0000-000000000001','Closure Team');
insert into core.club_people(id,club_id,display_name) values
 ('84300000-0000-0000-0000-000000000001','84100000-0000-0000-0000-000000000001','S03 closure');
insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at) values
 ('84100000-0000-0000-0000-000000000001','84300000-0000-0000-0000-000000000001','84000000-0000-0000-0000-000000000001','active',now());
insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at) values
 ('84400000-0000-0000-0000-000000000001','84100000-0000-0000-0000-000000000001','84200000-0000-0000-0000-000000000001','84300000-0000-0000-0000-000000000001','leader','active',now()-interval '1 day');
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at) values
 ('84100000-0000-0000-0000-000000000001','84400000-0000-0000-0000-000000000001','event.manage','team','84200000-0000-0000-0000-000000000001',now()-interval '1 day');

set local role authenticated;
select set_config('request.jwt.claim.sub','84000000-0000-0000-0000-000000000001',true);

select api.create_event(
 '84100000-0000-0000-0000-000000000001','84200000-0000-0000-0000-000000000001',
 'All day DST',null,'activity','scheduled',
 '2026-10-24 00:00 Europe/Stockholm','2026-10-26 00:00 Europe/Stockholm',true,'Europe/Stockholm',
 array['club'],null,null,null,null,'84500000-0000-0000-0000-000000000001');
select api.create_event(
 '84100000-0000-0000-0000-000000000001','84200000-0000-0000-0000-000000000001',
 'Cursor 1',null,'training','scheduled','2026-11-01 18:00 Europe/Stockholm','2026-11-01 19:00 Europe/Stockholm',false,'Europe/Stockholm',array['leaders'],null,null,null,null,'84500000-0000-0000-0000-000000000002');
select api.create_event(
 '84100000-0000-0000-0000-000000000001','84200000-0000-0000-0000-000000000001',
 'Cursor 2',null,'training','scheduled','2026-11-02 18:00 Europe/Stockholm','2026-11-02 19:00 Europe/Stockholm',false,'Europe/Stockholm',array['leaders'],null,null,null,null,'84500000-0000-0000-0000-000000000003');

do $$ begin
 begin
  perform api.create_event(
   '84100000-0000-0000-0000-000000000001','84200000-0000-0000-0000-000000000001',
   'Invalid all day',null,'activity','scheduled','2026-11-03 10:00 Europe/Stockholm','2026-11-04 10:00 Europe/Stockholm',true,'Europe/Stockholm',array['club'],null,null,null,null,'84500000-0000-0000-0000-000000000004');
  raise exception 'invalid all-day boundaries accepted';
 exception when check_violation then null; end;
end $$;

do $$
declare first_cursor text; first_id uuid; second_ids uuid[];
begin
 select page.event_id,page.event_cursor into first_id,first_cursor
 from api.list_calendar_page(array['84400000-0000-0000-0000-000000000001']::uuid[],'2026-10-01','2026-12-01',null,1) page;
 if first_cursor is null then raise exception 'opaque cursor missing'; end if;
 select array_agg(page.event_id) into second_ids
 from api.list_calendar_page(array['84400000-0000-0000-0000-000000000001']::uuid[],'2026-10-01','2026-12-01',first_cursor,200) page;
 if first_id = any(second_ids) then raise exception 'cursor repeated prior event'; end if;
 if cardinality(second_ids) <> 2 then raise exception 'cursor omitted remaining events'; end if;
 begin
  perform api.list_calendar_page(array['84400000-0000-0000-0000-000000000001']::uuid[],'2026-10-01','2026-12-01','not-a-cursor',200);
  raise exception 'invalid cursor accepted';
 exception when invalid_parameter_value then null; end;
end $$;

set local role postgres;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages' and policyname='teamzone_calendar_broadcast_select') then raise exception 'private realtime policy missing'; end if;
 if not exists(select 1 from pg_trigger where tgname='events_private_calendar_invalidation' and not tgisinternal) then raise exception 'calendar invalidation trigger missing'; end if;
 if (select count(*) from core.events where title='Invalid all day')<>0 then raise exception 'invalid all-day event leaked'; end if;
end $$;

rollback;
