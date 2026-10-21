-- Bokningshanterare from the app: where you can book for an activity. The
-- organisations linked to the activity's club that you may book in, and the
-- activity's team you lead there (null when you lead none of its teams).
create or replace function internal.list_event_booking_targets_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_can_read_event(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'organization_id', org.id, 'name', org.name,
      'team_id', (select lead.team_id from internal.booking_actor_teams(org.id) lead
        join core.event_teams relation on relation.team_id = lead.team_id and relation.event_id = target_event_id
        order by lead.team_name limit 1)
    ) order by org.name)
    from core.booking_organizations org
    join core.events event_row on event_row.id = target_event_id and event_row.club_id = org.teamzone_club_id
    where internal.booking_actor_role(org.id) is not null), '[]'::jsonb);
end;
$$;

create or replace function api.list_event_booking_targets(target_event_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_event_booking_targets_for_actor(target_event_id) $$;

revoke all on function internal.list_event_booking_targets_for_actor(uuid), api.list_event_booking_targets(uuid) from public, anon, authenticated;
grant execute on function internal.list_event_booking_targets_for_actor(uuid), api.list_event_booking_targets(uuid) to authenticated;
