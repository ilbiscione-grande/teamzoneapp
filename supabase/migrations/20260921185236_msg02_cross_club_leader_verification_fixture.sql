-- MSG-02 hosted physical-test fixture. Only the two exact test accounts may
-- be verified, and only while they are active leaders in separate clubs.
do $$
declare
  requester_id uuid;
  target_id uuid;
begin
  select profile.id
  into requester_id
  from auth.users account
  join core.profiles profile on profile.id = account.id
  where lower(account.email) = 'coach.emilson+tzleader@gmail.com';

  select profile.id
  into target_id
  from auth.users account
  join core.profiles profile on profile.id = account.id
  where lower(account.email) = 'coach.emilson+tzexternal@gmail.com';

  if requester_id is null or target_id is null or requester_id = target_id then
    raise exception 'msg02_cross_club_fixture_accounts_missing';
  end if;

  if not exists (
    select 1
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_id = link.club_id
     and assignment.club_person_id = link.club_person_id
    join core.clubs club on club.id = assignment.club_id
    where link.profile_id = requester_id
      and link.state = 'active'
      and assignment.role_package = 'leader'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and lower(club.name) = lower('Thomas klubb')
  ) then
    raise exception 'msg02_requester_is_not_thomas_club_leader';
  end if;

  if not exists (
    select 1
    from core.person_account_links link
    join core.assignments assignment
      on assignment.club_id = link.club_id
     and assignment.club_person_id = link.club_person_id
    join core.clubs club on club.id = assignment.club_id
    where link.profile_id = target_id
      and link.state = 'active'
      and assignment.role_package = 'leader'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and lower(club.name) = lower('Genomfångsklubben')
  ) then
    raise exception 'msg02_target_is_not_genomfangsklubben_leader';
  end if;

  if internal.actors_share_active_club(requester_id, target_id) then
    raise exception 'msg02_cross_club_fixture_actors_share_active_club';
  end if;

  insert into core.leader_verifications (
    profile_id,
    adult_verified,
    verification_method,
    state,
    verified_at,
    verified_by,
    revision
  )
  values
    (requester_id, true, 'manual_club_admin', 'active', now(), requester_id, 1),
    (target_id, true, 'manual_club_admin', 'active', now(), requester_id, 1)
  on conflict (profile_id) do update
  set adult_verified = true,
      verification_method = 'manual_club_admin',
      state = 'active',
      verified_at = now(),
      verified_by = requester_id,
      revision = core.leader_verifications.revision + 1;
end
$$;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260921185236_msg02_cross_club_leader_verification_fixture',
  'greenfield',
  'MSG-02 approved hosted verification fixture for exact adult leaders in separate clubs'
);
