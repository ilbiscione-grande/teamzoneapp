-- Team Development Plan: a new season can start from an earlier one
-- (2026-11-02). The leader picks what follows along: the game model's
-- principles and the key figures (their target, direction and source, not
-- their values). The vision is filled in by the app, so the leader can edit
-- it before the season is created. Both seasons must be the same team's,
-- and the limits stay (40 principles, 12 key figures); what is already in
-- the new season is kept.

create or replace function internal.copy_team_development_season_for_actor(
  target_plan_id uuid, expected_revision bigint, source_plan_id uuid, copy_principles boolean, copy_kpis boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans; source core.development_plans;
begin
  source := internal.tdp_plan(source_plan_id);
  plan := internal.tdp_change(target_plan_id, expected_revision);
  if source.id = plan.id or source.team_id <> plan.team_id or source.club_id <> plan.club_id then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if coalesce(copy_principles, false) then
    insert into core.team_development_principles (club_id, plan_id, area, title, description, position, updated_by)
    select plan.club_id, plan.id, principle.area, principle.title, principle.description,
      principle.position, auth.uid()
    from core.team_development_principles principle
    where principle.plan_id = source.id
      and not exists (select 1 from core.team_development_principles kept
        where kept.plan_id = plan.id and kept.area = principle.area and lower(kept.title) = lower(principle.title))
    order by principle.position, principle.updated_at
    limit greatest(0, 40 - (select count(*) from core.team_development_principles where plan_id = plan.id));
  end if;
  if coalesce(copy_kpis, false) then
    insert into core.team_development_kpis (club_id, plan_id, title, unit, target, higher_is_better, source, position, updated_by)
    select plan.club_id, plan.id, kpi.title, kpi.unit, kpi.target, kpi.higher_is_better, kpi.source,
      kpi.position, auth.uid()
    from core.team_development_kpis kpi
    where kpi.plan_id = source.id
      and not exists (select 1 from core.team_development_kpis kept
        where kept.plan_id = plan.id and lower(kept.title) = lower(kpi.title))
    order by kpi.position, kpi.updated_at
    limit greatest(0, 12 - (select count(*) from core.team_development_kpis where plan_id = plan.id));
  end if;
  return internal.tdp_plan_json(plan);
end;
$$;

create or replace function api.copy_team_development_season(target_plan_id uuid, expected_revision bigint,
  source_plan_id uuid, copy_principles boolean, copy_kpis boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.copy_team_development_season_for_actor(target_plan_id, expected_revision, source_plan_id,
    copy_principles, copy_kpis) $$;

revoke all on function
  internal.copy_team_development_season_for_actor(uuid, bigint, uuid, boolean, boolean),
  api.copy_team_development_season(uuid, bigint, uuid, boolean, boolean)
from public, anon, authenticated;
grant execute on function
  internal.copy_team_development_season_for_actor(uuid, bigint, uuid, boolean, boolean),
  api.copy_team_development_season(uuid, bigint, uuid, boolean, boolean)
to authenticated;
notify pgrst, 'reload schema';
