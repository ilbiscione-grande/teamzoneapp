-- Product clarification: leaders with a valid team roster relation are valid
-- callup subjects alongside players. Role package does not narrow eligibility.
create or replace function internal.person_eligibility_at_event(target_event_id uuid,target_person_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(
    (select jsonb_build_object('kind','team_assignment','id',assignment.id,'team_id',assignment.team_id,'starts_at',assignment.starts_at,'ends_at',assignment.ends_at)
     from core.events event_row join core.team_assignments assignment on assignment.club_id=event_row.club_id and assignment.team_id=event_row.owning_team_id
     where event_row.id=target_event_id and assignment.club_person_id=target_person_id and assignment.state='active'
       and assignment.starts_at<=event_row.starts_at and (assignment.ends_at is null or assignment.ends_at>event_row.starts_at) limit 1),
    (select jsonb_build_object('kind',eligibility.kind,'id',eligibility.id,'team_id',eligibility.team_id,'starts_at',eligibility.starts_at,'ends_at',eligibility.ends_at)
     from core.events event_row join core.play_eligibilities eligibility on eligibility.club_id=event_row.club_id and eligibility.team_id=event_row.owning_team_id
     where event_row.id=target_event_id and eligibility.club_person_id=target_person_id and eligibility.state='active'
       and eligibility.starts_at<=event_row.starts_at and eligibility.ends_at>event_row.starts_at limit 1)
  );
$$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)values('20260808081822_s04_allow_eligible_leaders','greenfield',null);
