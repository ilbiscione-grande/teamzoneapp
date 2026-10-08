-- Events are shown to their audience. Until now every member of the owning
-- team could read every team event, so players saw "Ledarmöte". The rule
-- below is used by the calendar, event details and Hem alike:
--   * leaders and club functionaries in the team see all team events;
--   * players (and guests) see events for players;
--   * guardians see events for guardians or players (their child plays);
--   * a club-wide audience is seen by everyone in the club;
--   * someone with a callup always sees the event, and a guardian sees
--     the events their child is called to;
--   * a team without any audience on the event (e.g. a shared team) keeps
--     seeing it, as before.

create or replace function internal.actor_can_read_event(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1
    from core.events event_row
    join core.event_teams event_team on event_team.event_id = event_row.id and event_team.club_id = event_row.club_id
    join core.person_account_links link on link.profile_id = auth.uid() and link.club_id = event_row.club_id and link.state = 'active'
    join core.assignments assignment on assignment.club_person_id = link.club_person_id and assignment.club_id = link.club_id
    where event_row.id = target_event_id
      and assignment.state = 'active' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and (
        (
          assignment.team_id = event_team.team_id
          and (
            assignment.role_package in ('leader', 'club_functionary')
            or not exists (
              select 1 from core.event_audiences audience
              where audience.event_id = event_row.id and audience.club_id = event_row.club_id
                and (audience.team_id = assignment.team_id or audience.audience_type = 'club')
            )
          )
        )
        or exists (
          select 1 from core.event_audiences audience
          where audience.event_id = event_row.id and audience.club_id = event_row.club_id
            and (audience.team_id = assignment.team_id or audience.audience_type = 'club')
            and (
              audience.audience_type = 'club'
              or audience.audience_type = 'players' and assignment.role_package in ('player', 'guest', 'guardian')
              or audience.audience_type = 'leaders' and assignment.role_package in ('leader', 'club_functionary')
              or audience.audience_type = 'guardians' and assignment.role_package = 'guardian'
            )
        )
        or exists (
          select 1 from core.callups callup
          where callup.event_id = event_row.id and callup.club_id = event_row.club_id
            and callup.state <> 'cancelled'
            and (
              callup.club_person_id = link.club_person_id
              or exists (
                select 1 from core.guardian_relations relation
                where relation.club_id = link.club_id and relation.guardian_person_id = link.club_person_id
                  and relation.child_person_id = callup.club_person_id and relation.state = 'active'
              )
            )
        )
      )
  );
$$;

-- Hem's "next event" fallback comes from the team list; keep it within
-- what the viewer may see.
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
  'next_event',case when base->'next_event' is not null and base->>'next_event'<>'null'
   and internal.actor_can_read_event((base->'next_event'->>'event_id')::uuid) then base->'next_event' end,
  'today_events',coalesce((select jsonb_agg(to_jsonb(e)-'timezone' order by e.starts_at,e.event_id) from events e
   where (e.starts_at at time zone e.timezone)::date=(statement_timestamp() at time zone e.timezone)::date),'[]'::jsonb),
  'upcoming_events',coalesce((select jsonb_agg(to_jsonb(u)-'timezone' order by u.starts_at,u.event_id) from (
   select * from events e where e.state='scheduled'
    and (e.starts_at at time zone e.timezone)::date>(statement_timestamp() at time zone e.timezone)::date
   order by e.starts_at,e.event_id limit 6) u),'[]'::jsonb))
$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261012110000_event_visibility_by_audience','greenfield',
  'Events are visible to their audience; leaders see all team events; callups always visible');
notify pgrst,'reload schema';
