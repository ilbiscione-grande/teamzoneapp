-- TEAM-16: details sent through a contact page can update an existing person
-- instead of creating a new one. Phone, email and address are replaced; the
-- birth date is only filled in when the person has none (and the birth year,
-- if known, matches); the name is kept. The submission is then deleted.

create or replace function internal.update_person_from_intake_for_actor(target_submission_id uuid,
 target_team_id uuid,target_person_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare submission core.intake_submissions%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into submission from core.intake_submissions where id=target_submission_id for update;
 if submission.id is null or not internal.actor_handles_intake(submission.club_id,submission.team_id)
  or not exists(select 1 from core.teams team where team.id=target_team_id and team.club_id=submission.club_id
   and team.status='active')
  or not internal.actor_handles_intake(submission.club_id,target_team_id)
  or not internal.person_in_team(submission.club_id,target_team_id,target_person_id) then
  raise insufficient_privilege using message='not_found'; end if;
 perform internal.set_person_contact_for_actor(submission.club_id,target_team_id,target_person_id,
  submission.email,submission.phone);
 perform internal.set_person_address_for_actor(submission.club_id,target_team_id,target_person_id,
  submission.street_address,submission.postal_code,submission.city);
 update core.club_people set birth_date=submission.birth_date,
  birth_year=extract(year from submission.birth_date)::integer
 where id=target_person_id and club_id=submission.club_id and birth_date is null
  and (birth_year is null or birth_year=extract(year from submission.birth_date)::integer);
 delete from core.intake_submissions where id=submission.id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(submission.club_id,auth.uid(),'club.intake.merged.v1','club_person',target_person_id,1,
  jsonb_build_object('team_id',target_team_id));
end$$;

create or replace function api.update_person_from_intake(target_submission_id uuid,target_team_id uuid,
 target_person_id uuid) returns void language sql security invoker set search_path='' as
 $$select internal.update_person_from_intake_for_actor(target_submission_id,target_team_id,target_person_id)$$;

revoke all on function internal.update_person_from_intake_for_actor(uuid,uuid,uuid),
 api.update_person_from_intake(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function internal.update_person_from_intake_for_actor(uuid,uuid,uuid),
 api.update_person_from_intake(uuid,uuid,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261002120000_intake_update_existing','greenfield','TEAM-16 contact page details update an existing person'
where not exists(select 1 from internal.migration_provenance where migration_name='20261002120000_intake_update_existing');
notify pgrst,'reload schema';
