-- "Bjud in ny spelare" listed every active roster person, including ones
-- who already have a claimed account — inviting them again is meaningless
-- since claiming a roster identity is a one-time link, not something to
-- redo. Expose whether a person already has an active account link so the
-- client can filter them out of that picker, the same way it already
-- filters out archived ("Tidigare spelare") people. Guardian invites are
-- unaffected: an already-claimed guardian legitimately gets invited again
-- for a second child.

drop function if exists api.list_club_people(uuid, uuid);
drop function if exists internal.list_club_people_for_actor(uuid, uuid);

create function internal.list_club_people_for_actor(
  target_club_id uuid,
  target_team_id uuid default null
)
returns table(
  club_person_id uuid,
  display_name text,
  age_class text,
  safeguarding_required boolean,
  team_id uuid,
  team_name text,
  assignment_state text,
  assignment_starts_at timestamptz,
  assignment_ends_at timestamptz,
  account_linked boolean
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if not internal.actor_has_capability(
      target_club_id, target_team_id, 'team.roster.view'
    )
    and not internal.actor_has_capability(
      target_club_id, target_team_id, 'club.memberships.manage'
    )
  then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return query select person.id, person.display_name,
    coalesce(person.birth_year::text, person.age_class),
    person.safeguarding_required,
    home.team_id, team.name, home.state, home.starts_at, home.ends_at,
    exists(
      select 1 from core.person_account_links link
      where link.club_person_id = person.id
        and link.club_id = person.club_id
        and link.state = 'active'
    )
  from core.club_people person
  join lateral (
    select assignment.* from core.team_assignments assignment
    where assignment.club_person_id = person.id
      and assignment.club_id = person.club_id
      and (target_team_id is null or assignment.team_id = target_team_id)
    order by assignment.state = 'active' desc, assignment.starts_at desc,
      assignment.id desc
    limit 1
  ) home on true
  join core.teams team on team.id = home.team_id and team.club_id = home.club_id
  where person.club_id = target_club_id and person.status in ('active', 'ended')
  order by home.state = 'active' desc, person.display_name, person.id;
end
$$;

create function api.list_club_people(
  target_club_id uuid,
  target_team_id uuid default null
)
returns table(
  club_person_id uuid,
  display_name text,
  age_class text,
  safeguarding_required boolean,
  team_id uuid,
  team_name text,
  assignment_state text,
  assignment_starts_at timestamptz,
  assignment_ends_at timestamptz,
  account_linked boolean
)
language sql stable security invoker set search_path = ''
as $$
  select * from internal.list_club_people_for_actor(target_club_id, target_team_id);
$$;

revoke all on function internal.list_club_people_for_actor(uuid, uuid)
  from public, anon, authenticated;
grant execute on function internal.list_club_people_for_actor(uuid, uuid)
  to authenticated;
revoke all on function api.list_club_people(uuid, uuid) from public, anon;
grant execute on function api.list_club_people(uuid, uuid) to authenticated;

insert into internal.migration_provenance(
  migration_name, source_kind, source_reference
) values (
  '20260927120000_team03_roster_account_linked_flag',
  'greenfield',
  'TEAM-03 physical verification: invite picker showed already-claimed people'
);

notify pgrst, 'reload schema';
