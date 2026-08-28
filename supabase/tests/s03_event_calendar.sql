\set ON_ERROR_STOP on
set role postgres;
begin;

insert into auth.users(id,raw_user_meta_data) values
 ('83000000-0000-0000-0000-000000000001','{"display_name":"Event admin"}'),
 ('83000000-0000-0000-0000-000000000002','{"display_name":"Shared leader"}'),
 ('83000000-0000-0000-0000-000000000003','{"display_name":"Audience only"}');
insert into core.clubs(id,name,slug) values
 ('83100000-0000-0000-0000-000000000001','S03 Klubb','s03-klubb');
insert into core.teams(id,club_id,name) values
 ('83200000-0000-0000-0000-000000000001','83100000-0000-0000-0000-000000000001','Primärlaget'),
 ('83200000-0000-0000-0000-000000000002','83100000-0000-0000-0000-000000000001','Delade laget'),
 ('83200000-0000-0000-0000-000000000003','83100000-0000-0000-0000-000000000001','Audience laget');
insert into core.club_people(id,club_id,display_name) values
 ('83300000-0000-0000-0000-000000000001','83100000-0000-0000-0000-000000000001','Event admin'),
 ('83300000-0000-0000-0000-000000000002','83100000-0000-0000-0000-000000000001','Shared leader'),
 ('83300000-0000-0000-0000-000000000003','83100000-0000-0000-0000-000000000001','Audience only');
insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at) values
 ('83100000-0000-0000-0000-000000000001','83300000-0000-0000-0000-000000000001','83000000-0000-0000-0000-000000000001','active',now()),
 ('83100000-0000-0000-0000-000000000001','83300000-0000-0000-0000-000000000002','83000000-0000-0000-0000-000000000002','active',now()),
 ('83100000-0000-0000-0000-000000000001','83300000-0000-0000-0000-000000000003','83000000-0000-0000-0000-000000000003','active',now());
insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at) values
 ('83400000-0000-0000-0000-000000000001','83100000-0000-0000-0000-000000000001','83200000-0000-0000-0000-000000000001','83300000-0000-0000-0000-000000000001','leader','active',now()-interval '1 day'),
 ('83400000-0000-0000-0000-000000000002','83100000-0000-0000-0000-000000000001','83200000-0000-0000-0000-000000000002','83300000-0000-0000-0000-000000000002','leader','active',now()-interval '1 day'),
 ('83400000-0000-0000-0000-000000000003','83100000-0000-0000-0000-000000000001','83200000-0000-0000-0000-000000000003','83300000-0000-0000-0000-000000000003','leader','active',now()-interval '1 day');
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at) values
 ('83100000-0000-0000-0000-000000000001','83400000-0000-0000-0000-000000000001','event.manage','team','83200000-0000-0000-0000-000000000001',now()-interval '1 day'),
 ('83100000-0000-0000-0000-000000000001','83400000-0000-0000-0000-000000000002','event.manage','team','83200000-0000-0000-0000-000000000002',now()-interval '1 day');

set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000001',true);
select api.create_event(
 '83100000-0000-0000-0000-000000000001','83200000-0000-0000-0000-000000000001',
 'DST-serie','Ska behålla lokal starttid','training','scheduled',
 '2026-03-22 18:00 Europe/Stockholm','2026-03-22 20:00 Europe/Stockholm',false,'Europe/Stockholm',
 array['players','leaders'],'Plan A','weekly',1,3,'83500000-0000-0000-0000-000000000001');
select api.create_event(
 '83100000-0000-0000-0000-000000000001','83200000-0000-0000-0000-000000000001',
 'Nattaktivitet',null,'activity','scheduled',
 '2026-09-01 22:00 Europe/Stockholm','2026-09-02 01:00 Europe/Stockholm',false,'Europe/Stockholm',
 array['club'],null,null,null,null,'83500000-0000-0000-0000-000000000002');

set local role postgres;
do $$
declare first_event uuid; first_revision bigint; before_count bigint;
begin
 if (select count(*) from core.events where title='DST-serie')<>3 then raise exception 'recurrence count mismatch'; end if;
 if exists(select 1 from core.events where title='DST-serie' and extract(hour from starts_at at time zone timezone)<>18) then raise exception 'DST changed wall-clock start'; end if;
 if (select count(*) from core.event_teams relation join core.events event_row on event_row.id=relation.event_id where event_row.title='DST-serie' and relation.relation='primary')<>3 then raise exception 'primary relation missing'; end if;
 if (select count(*) from internal.domain_outbox where event_type='event.event.created.v1')<>4 then raise exception 'outbox not atomic with create'; end if;
 select id,revision into first_event,first_revision from core.events where title='DST-serie' order by occurrence_number limit 1;
 insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
 values('83100000-0000-0000-0000-000000000001',first_event,'83200000-0000-0000-0000-000000000002','shared',array['view','co_manage'],'83000000-0000-0000-0000-000000000001');
 insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
 values('83100000-0000-0000-0000-000000000001',first_event,'leaders','83200000-0000-0000-0000-000000000003','83000000-0000-0000-0000-000000000001');
 select count(*) into before_count from core.event_revisions;
 perform set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000003',true);
 begin
  perform api.transition_event(first_event,'cancelled',first_revision,'audience cannot edit','83500000-0000-0000-0000-000000000003');
  raise exception 'audience gained edit permission';
 exception when insufficient_privilege then null; end;
 if (select count(*) from core.event_revisions)<>before_count then raise exception 'denied transition wrote revision'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000002',true);
do $$ declare event_id uuid; revision_value bigint; begin
 select calendar.event_id,calendar.revision into event_id,revision_value
 from api.list_calendar(array['83400000-0000-0000-0000-000000000002']::uuid[],'2026-01-01','2027-01-01',200) calendar
 where calendar.title='DST-serie' order by calendar.starts_at limit 1;
 perform api.transition_event(event_id,'cancelled',revision_value,'shared co-manager','83500000-0000-0000-0000-000000000004');
end $$;

select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000001',true);
do $$ declare event_id uuid; before_revision bigint; begin
 select calendar.event_id,calendar.revision into event_id,before_revision
 from api.list_calendar(array['83400000-0000-0000-0000-000000000001']::uuid[],'2026-01-01','2027-01-01',200) calendar
 where calendar.title='DST-serie' order by calendar.starts_at offset 1 limit 1;
 begin
  perform api.revise_event(event_id,'forward','{"starts_at":"2026-04-01T10:00:00Z","ends_at":"2026-03-01T10:00:00Z"}',before_revision,'83500000-0000-0000-0000-000000000005');
  raise exception 'invalid series patch committed';
 exception when check_violation then null; end;
 if ((api.get_event_details(event_id)->>'revision')::bigint)<>before_revision then raise exception 'partial series failure changed anchor'; end if;
 begin
  perform api.transition_event(event_id,'cancelled',before_revision+99,'stale','83500000-0000-0000-0000-000000000006');
  raise exception 'stale revision accepted';
 exception when serialization_failure then null; end;
end $$;

rollback;
