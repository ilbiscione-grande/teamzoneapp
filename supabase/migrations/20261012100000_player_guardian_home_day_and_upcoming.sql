-- Hem for players and guardians gets the same day card as leaders: the
-- projection now carries the team's events today and the coming days. The
-- callups already in the projection (own_callups / child_callups) are
-- matched to these events in the app, so a callup shows in the card.

create or replace function internal.home_with_team_events(base jsonb)
returns jsonb language sql stable security definer set search_path='' as $$
 with team as (select nullif(base->'team'->>'team_id','')::uuid team_id),
 events as (
  select event_row.id event_id,event_row.title,event_row.event_type,event_row.state,event_row.starts_at,event_row.ends_at,
   internal.event_place_label(location.name,location.pitch) location_name,location.address,event_row.timezone
  from team
  join core.event_teams relation on relation.team_id=team.team_id
  join core.events event_row on event_row.id=relation.event_id and event_row.club_id=relation.club_id
  left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
  where event_row.archived_at is null and event_row.state<>'cancelled'
   and event_row.starts_at<statement_timestamp()+interval '14 days'
   and event_row.ends_at>=statement_timestamp()-interval '1 day'
   and internal.actor_can_read_event(event_row.id)
 )
 select base||jsonb_build_object(
  'today_events',coalesce((select jsonb_agg(to_jsonb(e)-'timezone' order by e.starts_at,e.event_id) from events e
   where (e.starts_at at time zone e.timezone)::date=(statement_timestamp() at time zone e.timezone)::date),'[]'::jsonb),
  'upcoming_events',coalesce((select jsonb_agg(to_jsonb(u)-'timezone' order by u.starts_at,u.event_id) from (
   select * from events e where e.state='scheduled'
    and (e.starts_at at time zone e.timezone)::date>(statement_timestamp() at time zone e.timezone)::date
   order by e.starts_at,e.event_id limit 6) u),'[]'::jsonb))
$$;

create or replace function api.get_player_home(context_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.home_with_team_events(internal.get_player_home_with_reasons_for_actor(context_id))$$;

create or replace function api.get_guardian_home(context_id uuid,child_person_id uuid default null)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.home_with_team_events(internal.get_guardian_home_with_reasons_for_actor(context_id,child_person_id))$$;

revoke all on function internal.home_with_team_events(jsonb) from public,anon,authenticated;
grant execute on function internal.home_with_team_events(jsonb) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261012100000_player_guardian_home_day_and_upcoming','greenfield',
  'Player and guardian home: team events today and upcoming');
notify pgrst,'reload schema';
