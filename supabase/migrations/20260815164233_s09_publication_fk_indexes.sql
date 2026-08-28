-- Cover composite S09 foreign keys in their declared column order.

create index person_age_assertions_person_club_fk_idx
  on core.person_age_assertions(club_person_id, club_id);

create index publication_consents_subject_club_fk_idx
  on core.publication_consents(subject_club_person_id, club_id);

create index publication_consents_guardian_club_fk_idx
  on core.publication_consents(guardian_club_person_id, club_id)
  where guardian_club_person_id is not null;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values (
  '20260815164233_s09_publication_fk_indexes',
  'greenfield',
  'Cover S09 composite foreign keys in advisor-recognized order'
);
