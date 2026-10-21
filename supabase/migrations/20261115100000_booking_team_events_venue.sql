-- Bokningshanterare: a match in the activity list says whether it is home or
-- away, and against whom: a minibus is for away matches. As in
-- 20261115090000, with home_away and opponent_name.
create or replace function internal.list_booking_team_events_for_actor(target_organization_id uuid, target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from internal.booking_actor_teams(target_organization_id) t where t.team_id = target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'event_id', event_row.id, 'title', event_row.title, 'event_type', event_row.event_type,
      'starts_at', event_row.starts_at, 'ends_at', event_row.ends_at,
      'home_away', event_row.home_away, 'opponent_name', event_row.opponent_name
    ) order by event_row.starts_at)
    from core.events event_row
    join core.event_teams relation on relation.event_id = event_row.id and relation.team_id = target_team_id
    where event_row.state in ('draft', 'scheduled') and event_row.archived_at is null
      and event_row.ends_at > now() and event_row.starts_at < now() + interval '60 days'), '[]'::jsonb);
end;
$$;

revoke all on function internal.list_booking_team_events_for_actor(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.list_booking_team_events_for_actor(uuid, uuid) to authenticated;
