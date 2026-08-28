alter table audit.command_events add column acting_as_person_id uuid;
alter table audit.command_events add constraint command_events_acting_as_club_fkey foreign key(acting_as_person_id,club_id) references core.club_people(id,club_id);
create index command_events_acting_as_idx on audit.command_events(acting_as_person_id) where acting_as_person_id is not null;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808075405_s04_audit_acting_as','greenfield',null);
