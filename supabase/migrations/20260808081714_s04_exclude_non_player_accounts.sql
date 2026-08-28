create or replace function internal.person_eligibility_at_event(target_event_id uuid,target_person_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select case
    when exists(select 1 from core.person_account_links link where link.club_person_id=target_person_id and link.state='active')
      and not exists(
        select 1 from core.events event_row
        join core.assignments assignment on assignment.club_id=event_row.club_id and assignment.club_person_id=target_person_id
        where event_row.id=target_event_id and assignment.role_package in ('player','guest')
          and assignment.state='active' and assignment.starts_at<=event_row.starts_at
          and (assignment.ends_at is null or assignment.ends_at>event_row.starts_at)
          and (assignment.team_id is null or assignment.team_id=event_row.owning_team_id)
      ) then null
    else coalesce(
      (select jsonb_build_object('kind','team_assignment','id',assignment.id,'team_id',assignment.team_id,'starts_at',assignment.starts_at,'ends_at',assignment.ends_at)
       from core.events event_row join core.team_assignments assignment on assignment.club_id=event_row.club_id and assignment.team_id=event_row.owning_team_id
       where event_row.id=target_event_id and assignment.club_person_id=target_person_id and assignment.state='active'
         and assignment.starts_at<=event_row.starts_at and (assignment.ends_at is null or assignment.ends_at>event_row.starts_at) limit 1),
      (select jsonb_build_object('kind',eligibility.kind,'id',eligibility.id,'team_id',eligibility.team_id,'starts_at',eligibility.starts_at,'ends_at',eligibility.ends_at)
       from core.events event_row join core.play_eligibilities eligibility on eligibility.club_id=event_row.club_id and eligibility.team_id=event_row.owning_team_id
       where event_row.id=target_event_id and eligibility.club_person_id=target_person_id and eligibility.state='active'
         and eligibility.starts_at<=event_row.starts_at and eligibility.ends_at>event_row.starts_at limit 1)
    ) end;
$$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)values('20260808081714_s04_exclude_non_player_accounts','greenfield',null);
