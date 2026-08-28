alter function internal.issue_roster_invite_for_actor(uuid, text, timestamptz, uuid)
  set search_path = '', extensions;

alter function internal.claim_club_person_for_actor(text, uuid)
  set search_path = '', extensions;

insert into internal.migration_provenance (migration_name)
values ('20260807220513_s02_qualify_token_hash');
