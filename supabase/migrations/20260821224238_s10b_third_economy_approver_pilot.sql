-- Explicit sandbox-only third Economy approver for the Thomas club.

do $$
declare
 target_club constant uuid := 'e423cb36-eaf3-44a5-b6d0-0406914a21ae';
 target_profile constant uuid := 'd2ae2b22-6ecd-4009-a512-765f80eff511';
 operator_profile constant uuid := '6379829a-1258-4893-aae7-d063979ef118';
 target_person uuid;
 target_assignment uuid;
begin
 if not exists(
  select 1 from auth.users
  where id=target_profile and lower(email)=lower('eksjoj18@gmail.com')
    and email_confirmed_at is not null
 ) then raise exception 'third_approver_auth_target_mismatch'; end if;

 update core.profiles set display_name='Eksjö J18',revision=revision+1
 where id=target_profile and btrim(display_name)='';

 select link.club_person_id into target_person
 from core.person_account_links link
 where link.club_id=target_club and link.profile_id=target_profile
   and link.state='active';

 if target_person is null then
  insert into core.club_people(club_id,display_name,provenance,created_by)
  values(target_club,'Eksjö J18','sandbox_pilot',operator_profile)
  returning id into target_person;

  insert into core.person_account_links(
   club_id,club_person_id,profile_id,state,verified_at,created_by
  ) values(target_club,target_person,target_profile,'active',now(),operator_profile);
 end if;

 select assignment.id into target_assignment
 from core.assignments assignment
 where assignment.club_id=target_club
   and assignment.club_person_id=target_person
   and assignment.team_id is null
   and assignment.role_package='club_functionary'
   and assignment.state='active'
 limit 1;

 if target_assignment is null then
  insert into core.assignments(
   club_id,team_id,club_person_id,role_package,state,starts_at,created_by
  ) values(
   target_club,null,target_person,'club_functionary','active',now(),operator_profile
  ) returning id into target_assignment;
 end if;

 insert into core.capability_grants(
  club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by
 )
 select target_club,target_assignment,capability,'club',target_club,now(),operator_profile
 from (values('economy.read'),('economy.approve')) value(capability)
 on conflict(assignment_id,capability,scope_type,scope_id) do update set
  ends_at=null,
  starts_at=least(core.capability_grants.starts_at,excluded.starts_at),
  revision=core.capability_grants.revision+1;

 if (select count(*) from core.capability_grants
     where assignment_id=target_assignment and ends_at is null
       and capability in ('economy.read','economy.approve'))<>2 then
  raise exception 'third_approver_capability_mismatch';
 end if;

 insert into audit.command_events(
  club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata
 ) values(
  target_club,operator_profile,'economy.sandbox_approver.activated.v1',
  'assignment',target_assignment,'Explicit S10B third approver pilot',
  jsonb_build_object('profile_id',target_profile,'capabilities',jsonb_build_array('economy.read','economy.approve'))
 );
end$$;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260821224238_s10b_third_economy_approver_pilot','greenfield');
