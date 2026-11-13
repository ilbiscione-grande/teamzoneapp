-- Ledargruppers möten on Hem, and one row per person in Styrelse.
--
-- A group meeting is held by one team, so a member who leads another team
-- did not see it on that team's home page. The leader home now shows a
-- member's group meetings in every team context (today, next and coming),
-- and the club home (a board member or functionary without a team) gets
-- "Dina möten": the coming meetings of the groups one is in.
--
-- Styrelse listed one row per assignment, so whoever has several roles
-- (functionary in two teams, leader in two teams …) showed up several
-- times when registering a mandate. It now lists each person once, with
-- the assignment a mandate is best kept on: the club-wide one, a
-- functionary's first.

-- Is the viewer in the group whose meeting this is?
create or replace function internal.actor_in_leader_group_meeting(target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from core.leader_group_events group_event
    cross join lateral internal.leader_group_member_people(group_event.group_id) member
    join core.person_account_links link on link.club_person_id = member.club_person_id
      and link.club_id = group_event.club_id and link.profile_id = auth.uid() and link.state = 'active'
    where group_event.event_id = target_event_id)
$$;

-- The viewer's coming group meetings in a club, soonest first.
create or replace function internal.my_leader_group_meetings(target_club_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item.value order by item.starts_at, item.event_id), '[]'::jsonb)
  from (
    select event_row.id as event_id, event_row.starts_at, jsonb_build_object(
      'event_id', event_row.id, 'title', event_row.title, 'event_type', event_row.event_type,
      'starts_at', event_row.starts_at, 'ends_at', event_row.ends_at, 'all_day', event_row.all_day,
      'location_name', internal.event_place_label(location.name, location.pitch),
      'group_name', group_row.name) as value
    from core.leader_group_events group_event
    join core.leader_groups group_row on group_row.id = group_event.group_id
    join core.events event_row on event_row.id = group_event.event_id
    left join core.event_locations location on location.id = event_row.location_id
    where group_event.club_id = target_club_id and event_row.state = 'scheduled'
      and event_row.archived_at is null and event_row.ends_at > now()
      and internal.actor_in_leader_group_meeting(event_row.id)
    order by event_row.starts_at, event_row.id
    limit 5
  ) item
$$;

revoke all on function
  internal.actor_in_leader_group_meeting(uuid),
  internal.my_leader_group_meetings(uuid)
from public, anon, authenticated;

do $patch$
declare
  fn text;
  def text;
  patched text;
  hits integer;
begin
  -- Leader home: today, next and coming include the member's group
  -- meetings held by another team (one row: the holding team's).
  foreach fn in array array[
    'internal.get_leader_home_base_for_actor(uuid)',
    'internal.get_leader_home_for_actor(uuid)'
  ] loop
    def := pg_get_functiondef(fn::regprocedure);
    hits := (length(def) - length(replace(def, 'relation.team_id=context_row.team_id', '')))
      / length('relation.team_id=context_row.team_id');
    if hits = 0 then raise exception '% not patched', fn; end if;
    patched := replace(def, 'relation.team_id=context_row.team_id',
      '(relation.team_id=context_row.team_id or (relation.relation=''primary'' and relation.team_id<>context_row.team_id and internal.actor_in_leader_group_meeting(event_row.id)))');
    execute patched;
  end loop;

  -- Club home: Dina möten.
  def := pg_get_functiondef('internal.get_club_home_for_actor(uuid)'::regprocedure);
  patched := replace(def,
    '''can_announce'', internal.actor_has_capability(actor_context.club_id, null, ''club.messaging.manage''),',
    '''can_announce'', internal.actor_has_capability(actor_context.club_id, null, ''club.messaging.manage''),
    ''my_meetings'', internal.my_leader_group_meetings(actor_context.club_id),');
  if patched = def then raise exception 'get_club_home_for_actor not patched'; end if;
  execute patched;

  -- Styrelse: each person once.
  def := pg_get_functiondef('internal.get_board_for_actor(uuid)'::regprocedure);
  patched := regexp_replace(def,
    'from core\.assignments assignment join core\.club_people person on person\.id=assignment\.club_person_id\s+where assignment\.club_id=target_club_id and assignment\.state=''active''\s+and assignment\.starts_at<=now\(\) and \(assignment\.ends_at is null or assignment\.ends_at>now\(\)\)\),',
    'from (select distinct on (candidate.club_person_id) candidate.* from core.assignments candidate
     where candidate.club_id=target_club_id and candidate.state=''active''
       and candidate.starts_at<=now() and (candidate.ends_at is null or candidate.ends_at>now())
     order by candidate.club_person_id,(candidate.team_id is null) desc,
       (candidate.role_package=''club_functionary'') desc,candidate.starts_at,candidate.id) assignment
   join core.club_people person on person.id=assignment.club_person_id),');
  if patched = def then raise exception 'get_board_for_actor not patched'; end if;
  execute patched;
end
$patch$;

notify pgrst, 'reload schema';
