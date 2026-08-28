begin;
set local role postgres;

insert into auth.users(id,raw_user_meta_data) values
 ('89600000-0000-0000-0000-000000000001','{"display_name":"S09 Publisher"}');
insert into core.clubs(id,name,slug) values
 ('89610000-0000-0000-0000-000000000001','S09 Public Club','s09-internal-club');
insert into core.teams(id,club_id,name) values
 ('89620000-0000-0000-0000-000000000001','89610000-0000-0000-0000-000000000001','S09 Public Team');
insert into core.club_people(id,club_id,display_name) values
 ('89630000-0000-0000-0000-000000000001','89610000-0000-0000-0000-000000000001','S09 Publisher');
insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at) values
 ('89610000-0000-0000-0000-000000000001','89630000-0000-0000-0000-000000000001','89600000-0000-0000-0000-000000000001','active',now());
insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at) values
 ('89640000-0000-0000-0000-000000000001','89610000-0000-0000-0000-000000000001',null,'89630000-0000-0000-0000-000000000001','club_functionary','active',now()-interval '1 day');
insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at) values
 ('89610000-0000-0000-0000-000000000001','89640000-0000-0000-0000-000000000001','club.memberships.manage','club','89610000-0000-0000-0000-000000000001',now()-interval '1 day');

set local role authenticated;
select set_config('request.jwt.claim.sub','89600000-0000-0000-0000-000000000001',true);
select api.configure_club_publication(
 '89610000-0000-0000-0000-000000000001','draft','s09-klubb','Stockholm','Beskrivning',
 0,'89650000-0000-0000-0000-000000000001');
select api.configure_team_publication(
 '89610000-0000-0000-0000-000000000001','89620000-0000-0000-0000-000000000001',
 'draft','s09-lag','F2010',0,'89650000-0000-0000-0000-000000000002');

set local role service_role;
select api.claim_publication_projection_jobs(20);
set local role postgres;
select id as club_job_id from internal.publication_projection_jobs
 where aggregate_type='club' and action='rebuild' \gset
select id as team_job_id from internal.publication_projection_jobs
 where aggregate_type='team' and action='rebuild' \gset
set local role service_role;
select api.apply_publication_projection_job(:'club_job_id');
select api.apply_publication_projection_job(:'team_job_id');
select api.finish_publication_invalidation(:'club_job_id',true,null);
select api.finish_publication_invalidation(:'team_job_id',false,'cdn_unavailable');
set local role postgres;
update internal.publication_projection_jobs set available_at=now()
 where id=:'team_job_id' and state='failed';
set local role service_role;
select api.claim_publication_projection_jobs(20);
select api.apply_publication_projection_job(:'team_job_id');
select api.finish_publication_invalidation(:'team_job_id',true,null);

set local role postgres;
do $$ begin
 if (select count(*) from public_api.club_projections)<>1 then raise exception 'club projection missing'; end if;
 if (select count(*) from public_api.team_projections)<>1 then raise exception 'team projection missing'; end if;
 if exists(select 1 from internal.publication_projection_jobs where state<>'completed') then
  raise exception 'rebuild jobs not completed'; end if;
 if has_schema_privilege('anon','public_api','usage')
    or has_table_privilege('anon','public_api.club_projections','select') then
  raise exception 'anonymous projection access opened'; end if;
 if (select enabled from internal.publication_runtime_state where singleton) then
  raise exception 'runtime unexpectedly enabled'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','89600000-0000-0000-0000-000000000001',true);
select api.configure_team_publication(
 '89610000-0000-0000-0000-000000000001','89620000-0000-0000-0000-000000000001',
 'private','s09-lag','F2010',1,'89650000-0000-0000-0000-000000000003');

set local role service_role;
select api.claim_publication_projection_jobs(20);
set local role postgres;
select id as remove_job_id from internal.publication_projection_jobs
 where aggregate_type='team' and action='remove' \gset
set local role service_role;
select api.apply_publication_projection_job(:'remove_job_id');
select api.finish_publication_invalidation(:'remove_job_id',false,'cdn_unavailable');

set local role postgres;
do $$ begin
 if exists(select 1 from public_api.team_projections) then
  raise exception 'private transition left projection during CDN failure'; end if;
 if (select state from internal.publication_projection_jobs where action='remove')<>'failed' then
  raise exception 'failed invalidation not retryable'; end if;
end $$;

rollback;
