begin;
set local role postgres;

insert into auth.users(id,raw_user_meta_data) values
 ('89000000-0000-0000-0000-000000000001','{"display_name":"S09 Admin"}'),
 ('89000000-0000-0000-0000-000000000002','{"display_name":"S09 Barn"}'),
 ('89000000-0000-0000-0000-000000000003','{"display_name":"S09 Guardian"}'),
 ('89000000-0000-0000-0000-000000000004','{"display_name":"S09 16plus"}'),
 ('89000000-0000-0000-0000-000000000005','{"display_name":"S09 Outsider"}');
insert into core.clubs(id,name,slug) values
 ('89100000-0000-0000-0000-000000000001','S09 Klubb','s09-klubb');
insert into core.teams(id,club_id,name) values
 ('89200000-0000-0000-0000-000000000001','89100000-0000-0000-0000-000000000001','S09 Lag');
insert into core.club_people(id,club_id,display_name) values
 ('89300000-0000-0000-0000-000000000001','89100000-0000-0000-0000-000000000001','S09 Admin'),
 ('89300000-0000-0000-0000-000000000002','89100000-0000-0000-0000-000000000001','S09 Barn'),
 ('89300000-0000-0000-0000-000000000003','89100000-0000-0000-0000-000000000001','S09 Guardian'),
 ('89300000-0000-0000-0000-000000000004','89100000-0000-0000-0000-000000000001','S09 16plus');
insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at) values
 ('89100000-0000-0000-0000-000000000001','89300000-0000-0000-0000-000000000001','89000000-0000-0000-0000-000000000001','active',now()),
 ('89100000-0000-0000-0000-000000000001','89300000-0000-0000-0000-000000000002','89000000-0000-0000-0000-000000000002','active',now()),
 ('89100000-0000-0000-0000-000000000001','89300000-0000-0000-0000-000000000003','89000000-0000-0000-0000-000000000003','active',now()),
 ('89100000-0000-0000-0000-000000000001','89300000-0000-0000-0000-000000000004','89000000-0000-0000-0000-000000000004','active',now());
insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at) values
 ('89400000-0000-0000-0000-000000000001','89100000-0000-0000-0000-000000000001',null,'89300000-0000-0000-0000-000000000001','club_functionary','active',now()-interval '1 day');
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at) values
 ('89100000-0000-0000-0000-000000000001','89400000-0000-0000-0000-000000000001','club.memberships.manage','club','89100000-0000-0000-0000-000000000001',now()-interval '1 day');
insert into core.guardian_relations(
  club_id,guardian_person_id,child_person_id,kind,state,starts_at,created_by
) values (
  '89100000-0000-0000-0000-000000000001','89300000-0000-0000-0000-000000000003',
  '89300000-0000-0000-0000-000000000002','guardian','active',now()-interval '1 day',
  '89000000-0000-0000-0000-000000000001'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000001',true);
select api.verify_publication_age_band(
  '89100000-0000-0000-0000-000000000001','89300000-0000-0000-0000-000000000002',
  'through_15',current_date + 365,repeat('a',64),'89500000-0000-0000-0000-000000000001'
);
select api.verify_publication_age_band(
  '89100000-0000-0000-0000-000000000001','89300000-0000-0000-0000-000000000004',
  '16_plus',current_date + 365,repeat('b',64),'89500000-0000-0000-0000-000000000002'
);

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000002',true);
select api.give_publication_consent(
  '89100000-0000-0000-0000-000000000001','89300000-0000-0000-0000-000000000002',
  'name',current_date + 365,now() + interval '364 days','89500000-0000-0000-0000-000000000003'
);

set local role postgres;
do $$ begin
 if (select state from core.publication_consents where subject_club_person_id='89300000-0000-0000-0000-000000000002') <> 'pending_guardian'
 then raise exception 'minor consent activated without guardian'; end if;
end $$;
select id as minor_consent_id
from core.publication_consents
where subject_club_person_id='89300000-0000-0000-0000-000000000002'
\gset
select set_config('test.minor_consent_id', :'minor_consent_id', true);

set local role authenticated;
select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000005',true);
do $$ begin
 begin
  perform api.approve_guardian_publication_consent(
    current_setting('test.minor_consent_id')::uuid,
    '89300000-0000-0000-0000-000000000003',1,'89500000-0000-0000-0000-000000000004');
  raise exception 'outsider approved guardian consent';
 exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000003',true);
select api.approve_guardian_publication_consent(
  :'minor_consent_id',
  '89300000-0000-0000-0000-000000000003',1,'89500000-0000-0000-0000-000000000005');
select api.approve_guardian_publication_consent(
  :'minor_consent_id',
  '89300000-0000-0000-0000-000000000003',1,'89500000-0000-0000-0000-000000000005');

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000004',true);
select api.give_publication_consent(
  '89100000-0000-0000-0000-000000000001','89300000-0000-0000-0000-000000000004',
  'position',current_date + 365,now() + interval '364 days','89500000-0000-0000-0000-000000000006'
);

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000002',true);
select api.withdraw_publication_consent(
  :'minor_consent_id',
  'Återkallat i test',2,'89500000-0000-0000-0000-000000000007'
);
select api.withdraw_publication_consent(
  :'minor_consent_id',
  'Återkallat i test',2,'89500000-0000-0000-0000-000000000007'
);

set local role postgres;
do $$ begin
 if (select state from core.publication_consents where subject_club_person_id='89300000-0000-0000-0000-000000000002') <> 'withdrawn'
 then raise exception 'withdrawal missing'; end if;
 if (select state from core.publication_consents where subject_club_person_id='89300000-0000-0000-0000-000000000004') <> 'active'
 then raise exception '16+ self-consent not active'; end if;
 if (select count(*) from internal.publication_projection_jobs where aggregate_type='person' and action='remove') <> 1
 then raise exception 'withdrawal projection removal missing or duplicated'; end if;
 if (select count(*) from audit.command_events where command_type like 'publication.%') <> 6
 then raise exception 'publication audit count mismatch'; end if;
 if (select enabled from internal.publication_runtime_state where singleton)
 then raise exception 'publication runtime unexpectedly enabled'; end if;
end $$;

rollback;
