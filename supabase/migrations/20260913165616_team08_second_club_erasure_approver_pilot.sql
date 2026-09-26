-- TEAM-08 hosted-test pilot: a separate club-level reviewer for the pending
-- Thomas klubb erasure request. This is deliberately email- and club-bound,
-- idempotent, and grants only the capability required by the dual-control flow.

do $$
declare
  target_profile uuid;
  target_club uuid;
  target_person uuid;
  target_assignment uuid;
  operator_profile uuid;
begin
  select users.id into strict target_profile
  from auth.users users
  where lower(users.email) = lower('coach.emilson@gmail.com')
    and users.email_confirmed_at is not null;

  select club.id into strict target_club
  from core.clubs club
  where lower(btrim(club.name)) = lower('Thomas klubb')
    and club.status = 'active';

  select request.initiated_by into operator_profile
  from core.club_person_erasure_requests request
  where request.club_id = target_club
    and request.state = 'requested'
  order by request.created_at desc
  limit 1;

  if operator_profile is null or operator_profile = target_profile then
    raise exception 'separate_test_approver_precondition_failed';
  end if;

  select link.club_person_id into target_person
  from core.person_account_links link
  where link.club_id = target_club
    and link.profile_id = target_profile
    and link.state = 'active'
  order by link.created_at desc
  limit 1;

  if target_person is null then
    insert into core.persons(created_by)
    values(operator_profile)
    returning id into target_person;

    insert into core.club_people(
      id,club_id,person_id,display_name,provenance,created_by
    )
    select
      gen_random_uuid(),target_club,target_person,
      coalesce(nullif(btrim(profile.display_name),''),'Thomas Emilson'),
      'team08_test_approver',operator_profile
    from core.profiles profile
    where profile.id = target_profile
    returning id into target_person;

    insert into core.person_account_links(
      club_id,club_person_id,profile_id,state,verified_at,created_by
    ) values(
      target_club,target_person,target_profile,'active',now(),operator_profile
    );
  end if;

  select assignment.id into target_assignment
  from core.assignments assignment
  where assignment.club_id = target_club
    and assignment.club_person_id = target_person
    and assignment.team_id is null
    and assignment.role_package = 'club_functionary'
    and assignment.state = 'active'
    and assignment.starts_at <= now()
    and (assignment.ends_at is null or assignment.ends_at > now())
  order by assignment.created_at desc
  limit 1;

  if target_assignment is null then
    insert into core.assignments(
      club_id,team_id,club_person_id,role_package,state,starts_at,created_by
    ) values(
      target_club,null,target_person,'club_functionary','active',now(),operator_profile
    )
    returning id into target_assignment;
  end if;

  insert into core.capability_grants(
    club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by
  ) values(
    target_club,target_assignment,'club.memberships.manage','club',target_club,
    now(),operator_profile
  )
  on conflict(assignment_id,capability,scope_type,scope_id) do update
  set starts_at = least(core.capability_grants.starts_at,excluded.starts_at),
      ends_at = null,
      revision = core.capability_grants.revision + 1;

  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,
    metadata
  ) values(
    target_club,operator_profile,'roster.test_erasure_approver.activated.v1',
    'assignment',target_assignment,
    'Explicitly approved TEAM-08 hosted dual-control verification',
    jsonb_build_object(
      'reviewer_profile_id',target_profile,
      'capability','club.memberships.manage'
    )
  );
end
$$;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
)
values(
  '20260913165616_team08_second_club_erasure_approver_pilot',
  'greenfield',
  'Explicit user approval for TEAM-08 hosted dual-control verification'
)
on conflict do nothing;
