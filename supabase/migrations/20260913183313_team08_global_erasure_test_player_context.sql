-- TEAM-08 hosted-test fixture: give the explicitly approved disposable Auth
-- account a minimal player context so it can request global account erasure.

do $$
declare
  target_profile uuid;
  operator_profile uuid;
  target_club uuid;
  target_team uuid;
  target_person uuid;
  target_club_person uuid;
begin
  select users.id into strict target_profile
  from auth.users users
  where lower(users.email) = lower('coach.emilson+tzprotected@gmail.com')
    and users.email_confirmed_at is not null;

  select users.id into strict operator_profile
  from auth.users users
  where lower(users.email) = lower('coach.emilson@gmail.com')
    and users.email_confirmed_at is not null;

  select club.id into strict target_club
  from core.clubs club
  where lower(btrim(club.name)) = lower('Thomas klubb')
    and club.status = 'active';

  select team.id into strict target_team
  from core.teams team
  where team.club_id = target_club
    and lower(btrim(team.name)) = lower('Thomas lag')
    and team.status = 'active';

  select link.club_person_id into target_club_person
  from core.person_account_links link
  where link.club_id = target_club
    and link.profile_id = target_profile
    and link.state = 'active'
  order by link.created_at desc
  limit 1;

  if target_club_person is null then
    insert into core.persons(created_by)
    values(operator_profile)
    returning id into target_person;

    insert into core.club_people(
      club_id,person_id,display_name,provenance,created_by
    )
    select
      target_club,target_person,
      coalesce(nullif(btrim(profile.display_name),''),'TEAM-08 testspelare'),
      'team08_global_erasure_test',operator_profile
    from core.profiles profile
    where profile.id = target_profile
    returning id into target_club_person;

    insert into core.person_account_links(
      club_id,club_person_id,profile_id,state,verified_at,created_by
    ) values(
      target_club,target_club_person,target_profile,'active',now(),operator_profile
    );
  end if;

  if not exists(
    select 1 from core.assignments assignment
    where assignment.club_id = target_club
      and assignment.team_id = target_team
      and assignment.club_person_id = target_club_person
      and assignment.role_package = 'player'
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
  ) then
    insert into core.assignments(
      club_id,team_id,club_person_id,role_package,state,starts_at,created_by
    ) values(
      target_club,target_team,target_club_person,'player','active',now(),operator_profile
    );
  end if;

  if not exists(
    select 1 from core.team_assignments assignment
    where assignment.club_id = target_club
      and assignment.team_id = target_team
      and assignment.club_person_id = target_club_person
      and assignment.state = 'active'
  ) then
    insert into core.team_assignments(
      club_id,team_id,club_person_id,kind,state,starts_at,created_by
    ) values(
      target_club,target_team,target_club_person,'home','active',now(),operator_profile
    );
  end if;

  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,
    metadata
  ) values(
    target_club,operator_profile,'roster.test_global_erasure_context.activated.v1',
    'club_person',target_club_person,
    'Explicitly approved disposable TEAM-08 global erasure test account',
    jsonb_build_object(
      'profile_id',target_profile,
      'team_id',target_team,
      'role_package','player'
    )
  );
end
$$;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
)
values(
  '20260913183313_team08_global_erasure_test_player_context',
  'greenfield',
  'Explicit user approval for disposable TEAM-08 global erasure account test'
)
on conflict do nothing;
