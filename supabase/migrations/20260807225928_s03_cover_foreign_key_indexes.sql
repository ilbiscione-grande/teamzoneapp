create index recurrence_rules_club_idx on core.recurrence_rules(club_id);
create index recurrence_rules_created_by_idx on core.recurrence_rules(created_by);
create index event_locations_club_idx on core.event_locations(club_id);
create index event_locations_created_by_idx on core.event_locations(created_by);
create index events_owning_team_club_idx on core.events(owning_team_id,club_id);
create index events_recurrence_club_idx on core.events(recurrence_id,club_id);
create index events_location_club_idx on core.events(location_id,club_id);
create index events_created_by_idx on core.events(created_by);
create index event_teams_club_idx on core.event_teams(club_id);
create index event_teams_event_club_idx on core.event_teams(event_id,club_id);
create index event_teams_team_club_idx on core.event_teams(team_id,club_id);
create index event_teams_created_by_idx on core.event_teams(created_by);
create index event_audiences_club_idx on core.event_audiences(club_id);
create index event_audiences_event_club_idx on core.event_audiences(event_id,club_id);
create index event_audiences_team_club_idx on core.event_audiences(team_id,club_id);
create index event_audiences_created_by_idx on core.event_audiences(created_by);
create index event_revisions_club_idx on core.event_revisions(club_id);
create index event_revisions_event_club_idx on core.event_revisions(event_id,club_id);
create index event_revisions_actor_idx on core.event_revisions(actor_profile_id);
create index domain_outbox_club_idx on internal.domain_outbox(club_id);

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260807225928_s03_cover_foreign_key_indexes','greenfield',null);
