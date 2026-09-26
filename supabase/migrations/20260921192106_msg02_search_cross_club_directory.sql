create or replace function internal.list_cross_club_leaders_for_actor(
  search_text text
)
returns table(
  profile_id uuid,
  display_name text,
  club_name text,
  team_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_search text := left(btrim(coalesce(search_text, '')), 80);
begin
  if not internal.actor_is_verified_adult_leader(auth.uid()) then
    return;
  end if;

  return query
  select distinct
    profile.id,
    coalesce(
      nullif(btrim(profile.display_name), ''),
      nullif(btrim(club_person.display_name), ''),
      'Ledare'
    ),
    club.name,
    team.name
  from core.profiles profile
  join core.leader_verifications verification
    on verification.profile_id = profile.id
   and verification.adult_verified
   and verification.state = 'active'
  join core.person_account_links link
    on link.profile_id = profile.id
   and link.state = 'active'
  join core.club_people club_person
    on club_person.id = link.club_person_id
   and club_person.club_id = link.club_id
  join core.assignments assignment
    on assignment.club_id = link.club_id
   and assignment.club_person_id = link.club_person_id
   and assignment.role_package = 'leader'
   and assignment.state = 'active'
   and assignment.starts_at <= now()
   and (assignment.ends_at is null or assignment.ends_at > now())
  join core.clubs club on club.id = assignment.club_id
  join core.teams team
    on team.id = assignment.team_id
   and team.club_id = assignment.club_id
  where profile.id <> auth.uid()
    and not internal.actors_share_active_club(auth.uid(), profile.id)
    and (
      normalized_search = ''
      or coalesce(
        nullif(btrim(profile.display_name), ''),
        nullif(btrim(club_person.display_name), ''),
        'Ledare'
      ) ilike '%' || normalized_search || '%'
      or club.name ilike '%' || normalized_search || '%'
      or team.name ilike '%' || normalized_search || '%'
    )
    and not exists (
      select 1
      from core.contact_controls block
      where block.control_type = 'block'
        and block.state = 'active'
        and (
          (block.requester_profile_id = auth.uid()
           and block.target_profile_id = profile.id)
          or
          (block.target_profile_id = auth.uid()
           and block.requester_profile_id = profile.id)
        )
    )
  order by club.name, team.name, coalesce(
    nullif(btrim(profile.display_name), ''),
    nullif(btrim(club_person.display_name), ''),
    'Ledare'
  )
  limit 50;
end
$$;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260921192106_msg02_search_cross_club_directory',
  'greenfield',
  'MSG-02 external leader directory searchable by club, team or leader'
);

notify pgrst, 'reload schema';
