-- Approve the exact hosted test account's pending leader application through
-- the same server command used by an authorized in-app reviewer.
do $$
declare
  target_id uuid;
  application_id uuid;
  application_club_id uuid;
  application_team_id uuid;
  reviewer_id uuid;
  matching_applications integer;
  approval_result text;
begin
  select profile.id
  into target_id
  from auth.users account
  join core.profiles profile on profile.id = account.id
  where lower(account.email) = 'coach.emilson+tzexternal@gmail.com';

  if target_id is null then
    raise exception 'msg02_external_fixture_account_missing';
  end if;

  select count(*)
  into matching_applications
  from core.membership_applications application
  join core.clubs club on club.id = application.club_id
  where application.applicant_profile_id = target_id
    and application.status = 'pending'
    and application.requested_role = 'leader'
    and lower(club.name) = lower('Genomfångsklubben');

  if matching_applications <> 1 then
    raise exception 'msg02_expected_one_pending_external_leader_application_found_%',
      matching_applications;
  end if;

  select application.id, application.club_id, application.team_id
  into application_id, application_club_id, application_team_id
  from core.membership_applications application
  join core.clubs club on club.id = application.club_id
  where application.applicant_profile_id = target_id
    and application.status = 'pending'
    and application.requested_role = 'leader'
    and lower(club.name) = lower('Genomfångsklubben');

  select link.profile_id
  into reviewer_id
  from core.person_account_links link
  join core.assignments assignment
    on assignment.club_id = link.club_id
   and assignment.club_person_id = link.club_person_id
  join core.capability_grants grant_row
    on grant_row.assignment_id = assignment.id
   and grant_row.club_id = assignment.club_id
  where link.club_id = application_club_id
    and link.state = 'active'
    and assignment.state = 'active'
    and assignment.starts_at <= now()
    and (assignment.ends_at is null or assignment.ends_at > now())
    and grant_row.capability in ('club.memberships.manage','team.roster.manage')
    and grant_row.starts_at <= now()
    and (grant_row.ends_at is null or grant_row.ends_at > now())
    and (
      (grant_row.capability = 'club.memberships.manage'
       and grant_row.scope_type = 'club'
       and grant_row.scope_id = application_club_id)
      or
      (grant_row.capability = 'team.roster.manage'
       and grant_row.scope_type = 'team'
       and grant_row.scope_id = application_team_id)
    )
  order by
    case when grant_row.capability = 'club.memberships.manage' then 0 else 1 end,
    link.profile_id
  limit 1;

  if reviewer_id is null or reviewer_id = target_id then
    raise exception 'msg02_no_distinct_authorized_application_reviewer';
  end if;

  perform set_config('request.jwt.claim.sub', reviewer_id::text, true);
  approval_result := internal.decide_membership_application_v2(
    application_id,
    'approved',
    'leader',
    gen_random_uuid()
  );

  if approval_result <> 'approved' then
    raise exception 'msg02_application_approval_failed_%', approval_result;
  end if;
end
$$;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260921081500_msg02_cross_club_verification_fixture',
  'greenfield',
  'MSG-02 exact hosted test-account application approval through the normal authorized command'
);
