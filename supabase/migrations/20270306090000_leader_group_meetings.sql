-- Möten för ledargrupper: whoever manages a club's leader groups books a
-- meeting for a group, and it shows in every member's calendar.
--
-- An activity still belongs to a team, so a group meeting is held by the
-- group's first team (by name). It is shown to that team's leaders (who
-- are all in the group) and not to its players. The other members see it
-- through core.leader_group_events, and those who manage leader groups may
-- change and cancel it from the activity page like a team's own activity.
-- A group of single people only has no team, so it cannot book a meeting
-- yet ('no_team').

create table core.leader_group_events (
  event_id uuid primary key,
  club_id uuid not null,
  group_id uuid not null references core.leader_groups(id),
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  foreign key (event_id, club_id) references core.events(id, club_id) on delete cascade
);
create index leader_group_events_group_idx on core.leader_group_events (group_id);
alter table core.leader_group_events enable row level security;
revoke all on core.leader_group_events from public, anon, authenticated;

-- A group meeting is readable by the group's members and by whoever
-- manages the club's leader groups.
create or replace function internal.actor_can_read_leader_group_meeting(target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from core.leader_group_events group_event
    where group_event.event_id = target_event_id
      and (
        internal.actor_manages_leader_groups(group_event.club_id)
        or exists (
          select 1
          from internal.leader_group_member_people(group_event.group_id) member
          join core.person_account_links link on link.club_person_id = member.club_person_id
            and link.club_id = group_event.club_id and link.profile_id = auth.uid() and link.state = 'active'
        )
      )
  )
$$;

create or replace function internal.actor_can_manage_leader_group_meeting(target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from core.leader_group_events group_event
    where group_event.event_id = target_event_id
      and internal.actor_manages_leader_groups(group_event.club_id)
  )
$$;

-- Read, manage and the calendars take group meetings into account.
do $patch$
declare
  fn text;
  def text;
  patched text;
begin
  def := pg_get_functiondef('internal.actor_can_read_event(uuid)'::regprocedure);
  patched := regexp_replace(def, 'select exists \(',
    'select internal.actor_can_read_leader_group_meeting(target_event_id) or exists (');
  if patched = def then raise exception 'actor_can_read_event not patched'; end if;
  execute patched;

  def := pg_get_functiondef('internal.actor_can_manage_event(uuid)'::regprocedure);
  patched := regexp_replace(def, 'select exists \(',
    'select internal.actor_can_manage_leader_group_meeting(target_event_id) or exists (');
  if patched = def then raise exception 'actor_can_manage_event not patched'; end if;
  execute patched;

  -- A member's own team contexts list the meeting even when the group
  -- meeting is held by another team; actor_can_read_event still decides.
  foreach fn in array array[
    'internal.list_calendar_for_actor(uuid[],timestamptz,timestamptz,integer)',
    'internal.list_calendar_page_for_actor(uuid[],timestamptz,timestamptz,text,integer)'
  ] loop
    def := pg_get_functiondef(fn::regprocedure);
    patched := regexp_replace(def, 'context_row\.team_id is null',
      'context_row.team_id is null or exists (select 1 from core.leader_group_events group_event where group_event.event_id = event_row.id)');
    if patched = def then raise exception '% not patched', fn; end if;
    execute patched;
  end loop;

  -- The activity page names the group a meeting belongs to.
  def := pg_get_functiondef('internal.get_event_details_for_actor(uuid)'::regprocedure);
  patched := replace(def, '''caller_actions'',actions);',
    '''caller_actions'',actions,''leader_group'',(select jsonb_build_object(''id'',group_row.id,''name'',group_row.name) from core.leader_group_events group_event join core.leader_groups group_row on group_row.id=group_event.group_id where group_event.event_id=event_row.id));');
  if patched = def then raise exception 'get_event_details_for_actor not patched'; end if;
  execute patched;

  -- The groups page lists each group's coming meetings.
  def := pg_get_functiondef('internal.list_leader_groups_for_actor(uuid)'::regprocedure);
  patched := replace(def,
    '''member_count'', (select count(*) from internal.leader_group_member_people(group_row.id))',
    '''member_count'', (select count(*) from internal.leader_group_member_people(group_row.id)),
        ''meetings'', coalesce((select jsonb_agg(jsonb_build_object(
            ''id'', event_row.id, ''title'', event_row.title, ''starts_at'', event_row.starts_at,
            ''ends_at'', event_row.ends_at, ''state'', event_row.state,
            ''location'', (select internal.event_place_label(location.name, location.pitch)
              from core.event_locations location where location.id = event_row.location_id)
          ) order by event_row.starts_at)
          from core.leader_group_events group_event
          join core.events event_row on event_row.id = group_event.event_id
          where group_event.group_id = group_row.id and event_row.archived_at is null
            and event_row.state <> ''cancelled'' and event_row.ends_at > now()), ''[]'')');
  if patched = def then raise exception 'list_leader_groups_for_actor not patched'; end if;
  execute patched;
end
$patch$;

create or replace function internal.create_leader_group_meeting_for_actor(
  target_group_id uuid, new_title text, new_starts_at timestamptz, new_ends_at timestamptz,
  new_timezone text, location_name text, new_agenda text, idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid();
  group_row core.leader_groups%rowtype;
  host_team_id uuid;
  place_id uuid;
  new_event_id uuid;
  normalized jsonb;
  existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into group_row from core.leader_groups where id = target_group_id and state = 'active';
  if group_row.id is null or not internal.actor_manages_leader_groups(group_row.club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if idempotency_key is null or new_title is null or length(btrim(new_title)) not between 1 and 160
    or new_starts_at is null or new_ends_at is null or new_ends_at <= new_starts_at
    or new_timezone is null or length(btrim(new_timezone)) not between 1 and 80
  then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select result into existing_result from internal.command_deduplication deduplication
  where deduplication.actor_profile_id = actor_id
    and deduplication.command_type = 'leader_group.meeting.create.v1'
    and deduplication.idempotency_key = create_leader_group_meeting_for_actor.idempotency_key;
  if existing_result is not null then return existing_result; end if;

  select team.id into host_team_id
  from core.leader_group_teams group_team
  join core.teams team on team.id = group_team.team_id and team.status = 'active'
  where group_team.group_id = group_row.id
  order by lower(team.name), team.id limit 1;
  if host_team_id is null then raise invalid_parameter_value using message = 'no_team'; end if;

  normalized := internal.normalized_event_type_fields('meeting',
    jsonb_build_object('meeting_agenda', nullif(btrim(new_agenda), '')));
  if nullif(btrim(location_name), '') is not null then
    place_id := internal.resolve_event_place(group_row.club_id, location_name, null, null, actor_id);
  end if;

  insert into core.events(club_id, owning_team_id, event_type, title, state, starts_at, ends_at,
    all_day, timezone, location_id, created_by, meeting_agenda)
  values (group_row.club_id, host_team_id, 'meeting', btrim(new_title), 'scheduled', new_starts_at,
    new_ends_at, false, btrim(new_timezone), place_id, actor_id, normalized->>'meeting_agenda')
  returning id into new_event_id;
  insert into core.event_teams(club_id, event_id, team_id, relation, capabilities, created_by)
  values (group_row.club_id, new_event_id, host_team_id, 'primary', array['view','co_manage'], actor_id);
  insert into core.event_audiences(club_id, event_id, audience_type, team_id, created_by)
  values (group_row.club_id, new_event_id, 'leaders', host_team_id, actor_id);
  insert into core.leader_group_events(event_id, club_id, group_id, created_by)
  values (new_event_id, group_row.club_id, group_row.id, actor_id);
  insert into core.event_revisions(club_id, event_id, event_revision, action, scope, snapshot, actor_profile_id)
  select group_row.club_id, new_event_id, 1, 'created', 'one', internal.event_snapshot(event_row), actor_id
  from core.events event_row where event_row.id = new_event_id;
  insert into audit.command_events(club_id, actor_profile_id, command_type, aggregate_type, aggregate_id,
    aggregate_revision, metadata)
  values (group_row.club_id, actor_id, 'leader_group.meeting.create.v1', 'event', new_event_id, 1,
    jsonb_build_object('leader_group_id', group_row.id));
  insert into internal.domain_outbox(club_id, event_type, aggregate_type, aggregate_id, aggregate_revision, payload)
  values (group_row.club_id, 'event.event.created.v1', 'event', new_event_id, 1,
    jsonb_build_object('starts_at', new_starts_at));
  existing_result := jsonb_build_object('event_id', new_event_id);
  insert into internal.command_deduplication(actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'leader_group.meeting.create.v1', existing_result);
  return existing_result;
end
$$;

create function api.create_leader_group_meeting(
  target_group_id uuid, new_title text, new_starts_at timestamptz, new_ends_at timestamptz,
  new_timezone text, location_name text, new_agenda text, idempotency_key uuid
)
returns jsonb language sql security definer set search_path = '' as $$
  select internal.create_leader_group_meeting_for_actor(target_group_id, new_title, new_starts_at,
    new_ends_at, new_timezone, location_name, new_agenda, idempotency_key)
$$;

revoke all on function
  internal.actor_can_read_leader_group_meeting(uuid),
  internal.actor_can_manage_leader_group_meeting(uuid),
  internal.create_leader_group_meeting_for_actor(uuid, text, timestamptz, timestamptz, text, text, text, uuid)
from public, anon, authenticated;
revoke all on function
  api.create_leader_group_meeting(uuid, text, timestamptz, timestamptz, text, text, text, uuid)
from public, anon;
grant execute on function
  api.create_leader_group_meeting(uuid, text, timestamptz, timestamptz, text, text, text, uuid)
to authenticated;

notify pgrst, 'reload schema';
