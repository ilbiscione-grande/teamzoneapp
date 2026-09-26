\set ON_ERROR_STOP on
set role postgres;
begin;

insert into auth.users(id,raw_user_meta_data) values
 ('93000000-0000-0000-0000-000000000001','{"display_name":"CAL02 admin"}');
insert into core.clubs(id,name,slug) values
 ('93100000-0000-0000-0000-000000000001','CAL02 Klubb','cal02-typed-klubb');
insert into core.teams(id,club_id,name,created_by) values
 ('93200000-0000-0000-0000-000000000001','93100000-0000-0000-0000-000000000001','CAL02 laget','93000000-0000-0000-0000-000000000001');
insert into core.club_people(id,club_id,display_name) values
 ('93300000-0000-0000-0000-000000000001','93100000-0000-0000-0000-000000000001','CAL02 admin');
insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at) values
 ('93100000-0000-0000-0000-000000000001','93300000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','active',now());
insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at) values
 ('93400000-0000-0000-0000-000000000001','93100000-0000-0000-0000-000000000001','93200000-0000-0000-0000-000000000001','93300000-0000-0000-0000-000000000001','leader','active',now()-interval '1 day');
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at) values
 ('93100000-0000-0000-0000-000000000001','93400000-0000-0000-0000-000000000001','event.manage','team','93200000-0000-0000-0000-000000000001',now()-interval '1 day');

set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-0000-0000-000000000001',true);
select api.create_event_v2(
 '93100000-0000-0000-0000-000000000001','93200000-0000-0000-0000-000000000001',
 'CAL02 träning','Test','training','scheduled',
 now()+interval '1 day',now()+interval '1 day 2 hours',false,'Europe/Stockholm',
 array['players','leaders'],'Plan A',null,null,null,
 '{"assembly_minutes_before":15,"training_theme":"Passningar","training_focus":"Tempo","training_plan":"Tre block","opponent_name":null,"home_away":null,"match_notes":null,"meeting_purpose":null,"meeting_agenda":null}',
 '93500000-0000-0000-0000-000000000001') as created_event_id \gset

select api.revise_event_v3(
 :'created_event_id','one',
 '{"assembly_minutes_before":20,"training_theme":"Avslut","training_focus":"Precision","training_plan":"Fyra block","opponent_name":null,"home_away":null,"match_notes":null,"meeting_purpose":null,"meeting_agenda":null}',
 1,'93500000-0000-0000-0000-000000000002');

set local role postgres;
do $$ begin
 if not exists(select 1 from core.events where title='CAL02 träning' and revision=2 and assembly_minutes_before=20 and training_theme='Avslut')
 then raise exception 'typed event fields were not persisted'; end if;
end $$;

rollback;
