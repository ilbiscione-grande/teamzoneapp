-- TEAM-06 candidate discovery is scoped to the team being administered. It
-- exposes only the minimal roster projection needed by the create dialog.
create function internal.list_play_eligibility_candidates_for_actor(
  target_club_id uuid,
  target_team_id uuid
)
returns table(
  club_person_id uuid,
  display_name text,
  age_class text,
  safeguarding_required boolean,
  team_id uuid,
  team_name text,
  assignment_state text
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  if not internal.actor_has_capability(
    target_club_id,target_team_id,'club.memberships.manage'
  ) then
    raise insufficient_privilege using message='not_found';
  end if;
  if not exists(
    select 1 from core.teams team
    where team.id=target_team_id and team.club_id=target_club_id
      and team.status='active'
  ) then
    raise insufficient_privilege using message='not_found';
  end if;

  return query
  select person.id,person.display_name,
    coalesce(person.birth_year::text,person.age_class),
    person.safeguarding_required,assignment.team_id,team.name,assignment.state
  from core.team_assignments assignment
  join core.club_people person
    on person.id=assignment.club_person_id and person.club_id=assignment.club_id
  join core.teams team
    on team.id=assignment.team_id and team.club_id=assignment.club_id
  where assignment.club_id=target_club_id
    and assignment.team_id<>target_team_id
    and assignment.state='active'
    and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and person.status='active'
    and team.status='active'
  order by person.display_name,team.name,person.id;
end
$$;

create function api.list_play_eligibility_candidates(
  target_club_id uuid,
  target_team_id uuid
)
returns table(
  club_person_id uuid,
  display_name text,
  age_class text,
  safeguarding_required boolean,
  team_id uuid,
  team_name text,
  assignment_state text
)
language sql stable security invoker set search_path=''
as $$
  select * from internal.list_play_eligibility_candidates_for_actor(
    target_club_id,target_team_id
  )
$$;

revoke all on function internal.list_play_eligibility_candidates_for_actor(uuid,uuid)
  from public,anon,authenticated;
revoke all on function api.list_play_eligibility_candidates(uuid,uuid)
  from public,anon,authenticated;
grant execute on function internal.list_play_eligibility_candidates_for_actor(uuid,uuid)
  to authenticated;
grant execute on function api.list_play_eligibility_candidates(uuid,uuid)
  to authenticated;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values(
  '20260913084540_team06_representation_candidates',
  'greenfield',
  'TEAM-06 scoped candidate discovery'
);

notify pgrst,'reload schema';
