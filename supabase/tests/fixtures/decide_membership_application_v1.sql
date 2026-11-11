-- Live internal.decide_membership_application_for_actor (2026-11-11), for club_applications.local.mjs.
CREATE OR REPLACE FUNCTION internal.decide_membership_application_for_actor(application_id uuid, decision text, idempotency_key uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor_id uuid:=auth.uid(); row_value core.membership_applications%rowtype;
 existing_result jsonb; person_id uuid; club_person_id uuid; role_assignment_id uuid;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if decision not in ('approved','rejected') then raise invalid_parameter_value using message='invalid_decision'; end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='membership.application.decide.v1'
    and internal.command_deduplication.idempotency_key=decide_membership_application_for_actor.idempotency_key;
  if existing_result is not null then return existing_result->>'status'; end if;
  select * into row_value from core.membership_applications where id=application_id for update;
  if row_value.id is null or row_value.status<>'pending'
     or not (
       internal.actor_has_capability(
         row_value.club_id,row_value.team_id,'club.memberships.manage'
       )
       or internal.actor_has_capability(
         row_value.club_id,row_value.team_id,'team.roster.manage'
       )
     ) then
    raise insufficient_privilege using message='not_found';
  end if;
  if decision='approved' then
    if exists(select 1 from core.person_account_links where profile_id=row_value.applicant_profile_id
        and club_id=row_value.club_id and state='active') then
      raise invalid_parameter_value using message='relation_exists';
    end if;
    insert into core.persons(created_by) values(actor_id) returning id into person_id;
    insert into core.club_people(club_id,person_id,display_name,created_by)
    select row_value.club_id,person_id,coalesce(nullif(profile.display_name,''),'Ny medlem'),actor_id
    from core.profiles profile where profile.id=row_value.applicant_profile_id
    returning id into club_person_id;
    insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at,created_by)
    values(row_value.club_id,club_person_id,row_value.applicant_profile_id,'active',now(),actor_id);
    insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
    values(row_value.club_id,row_value.team_id,club_person_id,row_value.requested_role,'active',now(),actor_id)
    returning id into role_assignment_id;
    if row_value.requested_role='player' then
      insert into core.team_assignments(club_id,team_id,club_person_id,starts_at,created_by)
      values(row_value.club_id,row_value.team_id,club_person_id,now(),actor_id);
    end if;
  end if;
  update core.membership_applications set status=decision,decided_at=now(),decided_by=actor_id,revision=revision+1
  where id=row_value.id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'membership.application.decide.v1',jsonb_build_object('status',decision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
  values(row_value.club_id,actor_id,'membership.application.decide.v1','membership_application',row_value.id,row_value.revision+1);
  return decision;
end
$function$
;
