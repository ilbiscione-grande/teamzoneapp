\set ON_ERROR_STOP on
begin;
set local role postgres;

select set_config(
  'test.actor_id',
  (select id::text from auth.users where lower(email)='coach.emilson@gmail.com'),
  true
);

do $$
begin
  if nullif(current_setting('test.actor_id',true),'') is null then
    raise exception 'TEAM-02 fixture actor is missing';
  end if;
end
$$;

insert into core.clubs(id,name,slug,created_by)
values(
  '72020000-0000-4000-8000-000000000001','TEAM-02 räknarfixture',
  'team02-counter-fixture',current_setting('test.actor_id')::uuid
);
insert into core.teams(id,club_id,name,created_by)
values(
  '72020000-0000-4000-8000-000000000002',
  '72020000-0000-4000-8000-000000000001','Räknarlaget',
  current_setting('test.actor_id')::uuid
);
insert into core.club_people(id,club_id,display_name,created_by)
values
  ('72020000-0000-4000-8000-000000000003','72020000-0000-4000-8000-000000000001','Fixtureledare',current_setting('test.actor_id')::uuid),
  ('72020000-0000-4000-8000-000000000004','72020000-0000-4000-8000-000000000001','Aktiv invite',current_setting('test.actor_id')::uuid),
  ('72020000-0000-4000-8000-000000000005','72020000-0000-4000-8000-000000000001','Utgången invite',current_setting('test.actor_id')::uuid),
  ('72020000-0000-4000-8000-000000000006','72020000-0000-4000-8000-000000000001','Återkallad invite',current_setting('test.actor_id')::uuid);
insert into core.person_account_links(
  club_id,club_person_id,profile_id,state,verified_at,created_by
) values(
  '72020000-0000-4000-8000-000000000001',
  '72020000-0000-4000-8000-000000000003',
  current_setting('test.actor_id')::uuid,'active',now(),
  current_setting('test.actor_id')::uuid
);
insert into core.assignments(
  id,club_id,team_id,club_person_id,role_package,state,starts_at,created_by
) values
  ('72020000-0000-4000-8000-000000000007','72020000-0000-4000-8000-000000000001','72020000-0000-4000-8000-000000000002','72020000-0000-4000-8000-000000000003','leader','active',now()-interval '1 day',current_setting('test.actor_id')::uuid),
  ('72020000-0000-4000-8000-000000000008','72020000-0000-4000-8000-000000000001','72020000-0000-4000-8000-000000000002','72020000-0000-4000-8000-000000000004','player','pending',now(),current_setting('test.actor_id')::uuid),
  ('72020000-0000-4000-8000-000000000009','72020000-0000-4000-8000-000000000001','72020000-0000-4000-8000-000000000002','72020000-0000-4000-8000-000000000005','player','pending',now(),current_setting('test.actor_id')::uuid),
  ('72020000-0000-4000-8000-000000000010','72020000-0000-4000-8000-000000000001','72020000-0000-4000-8000-000000000002','72020000-0000-4000-8000-000000000006','player','pending',now(),current_setting('test.actor_id')::uuid);
insert into core.capability_grants(
  club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by
) values(
  '72020000-0000-4000-8000-000000000001',
  '72020000-0000-4000-8000-000000000007','team.roster.manage','team',
  '72020000-0000-4000-8000-000000000002',now()-interval '1 day',
  current_setting('test.actor_id')::uuid
);

insert into core.roster_invites(
  id,club_id,club_person_id,token_hash,state,created_at,expires_at,created_by
) values
  ('72020000-0000-4000-8000-000000000011','72020000-0000-4000-8000-000000000001','72020000-0000-4000-8000-000000000004',decode(repeat('11',32),'hex'),'issued',now()-interval '1 hour',now()+interval '1 day',current_setting('test.actor_id')::uuid),
  ('72020000-0000-4000-8000-000000000012','72020000-0000-4000-8000-000000000001','72020000-0000-4000-8000-000000000005',decode(repeat('12',32),'hex'),'issued',now()-interval '2 days',now()-interval '1 day',current_setting('test.actor_id')::uuid),
  ('72020000-0000-4000-8000-000000000013','72020000-0000-4000-8000-000000000001','72020000-0000-4000-8000-000000000006',decode(repeat('13',32),'hex'),'revoked',now()-interval '1 hour',now()+interval '1 day',current_setting('test.actor_id')::uuid);

insert into core.membership_applications(
  id,applicant_profile_id,club_id,team_id,requested_role,status
) values(
  '72020000-0000-4000-8000-000000000014',current_setting('test.actor_id')::uuid,
  '72020000-0000-4000-8000-000000000001','72020000-0000-4000-8000-000000000002','player','pending'
);
insert into core.membership_applications(
  id,applicant_profile_id,club_id,team_id,requested_role,status,decided_at,decided_by
) values(
  '72020000-0000-4000-8000-000000000015',current_setting('test.actor_id')::uuid,
  '72020000-0000-4000-8000-000000000001','72020000-0000-4000-8000-000000000002','guardian','rejected',now(),current_setting('test.actor_id')::uuid
);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.actor_id'),true);

do $$
declare projection jsonb;
begin
  projection:=api.get_team_overview('72020000-0000-4000-8000-000000000002');
  if (projection->>'can_manage')::boolean is not true then
    raise exception 'manager capability was not projected';
  end if;
  if (projection->>'active_invitation_count')::integer<>1 then
    raise exception 'active invite count included expired or revoked rows: %',projection;
  end if;
  if (projection->>'pending_application_count')::integer<>1 then
    raise exception 'pending application count included decided rows: %',projection;
  end if;
end
$$;

set local role postgres;
update core.roster_invites
set state='revoked',revision=revision+1
where id='72020000-0000-4000-8000-000000000011';
update core.membership_applications
set status='withdrawn',withdrawn_at=now(),revision=revision+1
where id='72020000-0000-4000-8000-000000000014';

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.actor_id'),true);
do $$
declare projection jsonb;
begin
  projection:=api.get_team_overview('72020000-0000-4000-8000-000000000002');
  if (projection->>'active_invitation_count')::integer<>0
    or (projection->>'pending_application_count')::integer<>0
  then raise exception 'status changes were not reflected atomically: %',projection; end if;
end
$$;

rollback;
\echo TEAM02_OVERVIEW_COUNTS_ROLLBACK_OK
