-- Team statistics (Laget → Statistik): attendance over a period for the
-- people who manage the team. Same rules as everywhere else:
--  * attended = present, late or partial;
--  * an absence only counts when the person was expected
--    (internal.attendance_is_expected: called, or the event had no callups);
--  * unknown / unregistered attendance is not counted at all.
-- Only events that have started, are not cancelled, and belong to the team
-- (primary or shared) are included.

create function internal.get_team_statistics_for_actor(target_team_id uuid, from_at timestamptz, to_at timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare club uuid; tz text; result jsonb;
begin
 select team.club_id, club_row.default_timezone into club, tz
 from core.teams team join core.clubs club_row on club_row.id = team.club_id
 where team.id = target_team_id;
 if auth.uid() is null or club is null or not (
   internal.actor_has_capability(club, target_team_id, 'event.attendance.manage')
   or internal.actor_has_capability(club, target_team_id, 'event.manage')
   or internal.actor_has_capability(club, target_team_id, 'team.roster.manage')) then
  raise insufficient_privilege using message = 'not_found';
 end if;
 if from_at is null or to_at is null or to_at <= from_at or to_at - from_at > interval '400 days' then
  raise invalid_parameter_value using message = 'invalid_period';
 end if;

 with events as (
  select event_row.id,
   case when event_row.event_type in ('training', 'match') then event_row.event_type else 'other' end as kind,
   event_row.starts_at
  from core.events event_row
  join core.event_teams relation on relation.event_id = event_row.id and relation.club_id = event_row.club_id
   and relation.team_id = target_team_id
  where event_row.club_id = club and event_row.state in ('scheduled', 'completed')
   and event_row.starts_at >= from_at and event_row.starts_at < least(to_at, now())
 ), roster as (
  select assignment.club_person_id as person_id, person.display_name as name,
   case when bool_or(assignment.role_package = 'player') then 'player' else 'leader' end as role
  from core.assignments assignment
  join core.club_people person on person.id = assignment.club_person_id and person.club_id = assignment.club_id
  where assignment.club_id = club and assignment.team_id = target_team_id and assignment.state = 'active'
   and assignment.role_package in ('player', 'leader') and person.status = 'active'
  group by assignment.club_person_id, person.display_name
 ), facts as (
  select fact.club_person_id as person_id, ev.kind, ev.starts_at, fact.status,
   fact.status in ('present', 'late', 'partial') as attended,
   fact.status in ('present', 'late', 'partial')
    or (fact.status = 'absent' and internal.attendance_is_expected(fact.event_id, fact.club_person_id)) as counted
  from core.attendance_facts fact
  join events ev on ev.id = fact.event_id
  join roster on roster.person_id = fact.club_person_id
  where fact.club_id = club
 ), calls as (
  select callup.club_person_id as person_id, callup.state
  from core.callups callup
  join events ev on ev.id = callup.event_id
  join roster on roster.person_id = callup.club_person_id
  where callup.club_id = club and callup.state in ('pending', 'accepted', 'declined')
 ), player_facts as (
  select facts.* from facts join roster on roster.person_id = facts.person_id and roster.role = 'player'
 )
 select jsonb_build_object(
  'team_id', target_team_id, 'from', from_at, 'to', to_at, 'timezone', tz,
  'events', jsonb_build_object(
   'total', (select count(*) from events),
   'training', (select count(*) from events where kind = 'training'),
   'match', (select count(*) from events where kind = 'match'),
   'other', (select count(*) from events where kind = 'other')),
  -- Team rates are about the players; leaders are listed separately.
  'attendance_rate', (select round(100.0 * count(*) filter (where attended) / nullif(count(*) filter (where counted), 0), 1) from player_facts),
  'training_rate', (select round(100.0 * count(*) filter (where attended) / nullif(count(*) filter (where counted), 0), 1) from player_facts where kind = 'training'),
  'match_rate', (select round(100.0 * count(*) filter (where attended) / nullif(count(*) filter (where counted), 0), 1) from player_facts where kind = 'match'),
  'response_rate', (select round(100.0 * count(*) filter (where state in ('accepted', 'declined')) / nullif(count(*), 0), 1)
   from calls join roster on roster.person_id = calls.person_id and roster.role = 'player'),
  'late', (select count(*) from player_facts where status = 'late'),
  'months', coalesce((select jsonb_agg(month_row order by month_row->>'month') from (
   select jsonb_build_object(
    'month', to_char(date_trunc('month', starts_at at time zone tz), 'YYYY-MM'),
    'attendance_rate', round(100.0 * count(*) filter (where attended) / nullif(count(*) filter (where counted), 0), 1),
    'training_rate', round(100.0 * count(*) filter (where attended and kind = 'training')
      / nullif(count(*) filter (where counted and kind = 'training'), 0), 1),
    'match_rate', round(100.0 * count(*) filter (where attended and kind = 'match')
      / nullif(count(*) filter (where counted and kind = 'match'), 0), 1)) as month_row
   from player_facts
   group by date_trunc('month', starts_at at time zone tz)) months), '[]'::jsonb),
  'people', coalesce((select jsonb_agg(jsonb_build_object(
    'person_id', roster.person_id, 'name', roster.name, 'role', roster.role,
    'attended', coalesce(agg.attended, 0), 'counted', coalesce(agg.counted, 0),
    'trainings_attended', coalesce(agg.trainings_attended, 0), 'trainings_counted', coalesce(agg.trainings_counted, 0),
    'matches_attended', coalesce(agg.matches_attended, 0), 'matches_counted', coalesce(agg.matches_counted, 0),
    'late', coalesce(agg.late, 0),
    'callups', coalesce(call_agg.received, 0), 'answered', coalesce(call_agg.answered, 0))
    order by roster.role desc, roster.name)
   from roster
   left join (
    select person_id,
     count(*) filter (where attended) as attended, count(*) filter (where counted) as counted,
     count(*) filter (where attended and kind = 'training') as trainings_attended,
     count(*) filter (where counted and kind = 'training') as trainings_counted,
     count(*) filter (where attended and kind = 'match') as matches_attended,
     count(*) filter (where counted and kind = 'match') as matches_counted,
     count(*) filter (where status = 'late') as late
    from facts group by person_id) agg on agg.person_id = roster.person_id
   left join (
    select person_id, count(*) as received, count(*) filter (where state in ('accepted', 'declined')) as answered
    from calls group by person_id) call_agg on call_agg.person_id = roster.person_id), '[]'::jsonb)
 ) into result;
 return result;
end$$;

create function api.get_team_statistics(team_id uuid, from_at timestamptz, to_at timestamptz)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_team_statistics_for_actor(team_id, from_at, to_at)$$;

revoke all on function internal.get_team_statistics_for_actor(uuid, timestamptz, timestamptz),
 api.get_team_statistics(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function internal.get_team_statistics_for_actor(uuid, timestamptz, timestamptz),
 api.get_team_statistics(uuid, timestamptz, timestamptz) to authenticated;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values ('20261016090000_team_statistics', 'greenfield',
 'Laget → Statistik: team attendance over a period for team managers');
notify pgrst, 'reload schema';
