create index command_events_actor_profile_id_idx
  on audit.command_events (actor_profile_id);

create index assignments_club_id_idx
  on core.assignments (club_id);
create index assignments_created_by_idx
  on core.assignments (created_by);
create index assignments_team_id_club_id_idx
  on core.assignments (team_id, club_id);

create index capability_grants_club_id_idx
  on core.capability_grants (club_id);
create index capability_grants_created_by_idx
  on core.capability_grants (created_by);

create index club_people_club_id_idx
  on core.club_people (club_id);
create index club_people_created_by_idx
  on core.club_people (created_by);

create index clubs_created_by_idx
  on core.clubs (created_by);

create index person_account_links_club_id_idx
  on core.person_account_links (club_id);
create index person_account_links_club_person_id_club_id_idx
  on core.person_account_links (club_person_id, club_id);
create index person_account_links_created_by_idx
  on core.person_account_links (created_by);
create index person_account_links_profile_id_idx
  on core.person_account_links (profile_id);

create index teams_created_by_idx
  on core.teams (created_by);
