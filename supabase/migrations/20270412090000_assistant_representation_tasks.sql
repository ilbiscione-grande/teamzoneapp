-- The assistant tells leaders about representation:
-- (1) the home team: requests from other teams to let its players represent
--     them, waiting for its approval;
-- (2) the other teams: players their own team has recently marked available
--     to represent other teams (the last 14 days), not yet requested here.
-- Only teams where you are a leader, so a club admin is not told about every
-- team in the club.

alter table core.club_people add column if not exists representation_available_at timestamptz;

create or replace function internal.stamp_representation_available_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.representation_available and not coalesce(old.representation_available, false) then
    new.representation_available_at := now();
  elsif not new.representation_available then
    new.representation_available_at := null;
  end if;
  return new;
end $$;

drop trigger if exists club_people_representation_available_at on core.club_people;
create trigger club_people_representation_available_at
  before update of representation_available on core.club_people
  for each row execute function internal.stamp_representation_available_at();

-- Players already available: when they were last marked so.
update core.club_people person
set representation_available_at = coalesce((
    select max(event.occurred_at) from audit.command_events event
    where event.command_type = 'roster.person.representation_available.set.v1'
      and event.aggregate_id = person.id
      and event.metadata ->> 'available' = 'true'
  ), now())
where person.representation_available and person.representation_available_at is null;

create or replace function internal.list_my_representation_tasks_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  return coalesce((
    with my_teams as (
      select distinct team.id team_id, team.club_id
      from core.person_account_links link
      join core.assignments assignment on assignment.club_person_id = link.club_person_id
        and assignment.club_id = link.club_id and assignment.role_package = 'leader'
        and assignment.state = 'active' and assignment.starts_at <= now()
        and (assignment.ends_at is null or assignment.ends_at > now())
      join core.teams team on team.id = assignment.team_id and team.club_id = assignment.club_id
        and team.status = 'active'
      where link.profile_id = auth.uid() and link.state = 'active'
    ), tasks as (
      select mine.club_id, mine.team_id, 'decide' kind, (
        select count(*) from core.play_eligibilities eligibility
        where eligibility.club_id = mine.club_id and eligibility.home_team_id = mine.team_id
          and eligibility.state = 'pending'
          and coalesce(eligibility.ends_at, eligibility.review_due_at) > now()
      ) count
      from my_teams mine
      where internal.actor_has_capability(mine.club_id, mine.team_id, 'club.memberships.manage')
         or internal.actor_has_capability(mine.club_id, mine.team_id, 'team.roster.manage')
      union all
      select mine.club_id, mine.team_id, 'available', (
        select count(distinct person.id) from core.club_people person
        join core.team_assignments home on home.club_person_id = person.id and home.club_id = person.club_id
          and home.state = 'active' and home.starts_at <= now()
          and (home.ends_at is null or home.ends_at > now()) and home.team_id <> mine.team_id
        join core.teams home_team on home_team.id = home.team_id and home_team.status = 'active'
        where person.club_id = mine.club_id and person.status = 'active'
          and person.representation_available
          and person.representation_available_at > now() - interval '14 days'
          and not exists (select 1 from core.team_assignments own
            where own.club_person_id = person.id and own.team_id = mine.team_id and own.state = 'active'
              and own.starts_at <= now() and (own.ends_at is null or own.ends_at > now()))
          and not exists (select 1 from core.play_eligibilities eligibility
            where eligibility.club_id = mine.club_id and eligibility.team_id = mine.team_id
              and eligibility.club_person_id = person.id and eligibility.state in ('pending', 'active')
              and coalesce(eligibility.ends_at, eligibility.review_due_at) > now())
      )
      from my_teams mine
      where internal.actor_has_capability(mine.club_id, mine.team_id, 'club.memberships.manage')
    )
    select jsonb_agg(jsonb_build_object('club_id', club_id, 'team_id', team_id, 'kind', kind,
      'count', count) order by team_id, kind)
    from tasks where count > 0
  ), '[]'::jsonb);
end $$;

create or replace function api.list_my_representation_tasks() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.list_my_representation_tasks_for_actor()
$$;

revoke all on function internal.stamp_representation_available_at() from public, anon, authenticated;
revoke all on function internal.list_my_representation_tasks_for_actor(), api.list_my_representation_tasks()
  from public, anon, authenticated;
grant execute on function internal.list_my_representation_tasks_for_actor(), api.list_my_representation_tasks()
  to authenticated;

-- The new kinds can be hidden in the assistant's settings.
alter table internal.assistant_task_preferences
  drop constraint if exists assistant_task_preferences_hidden_kinds_check;
alter table internal.assistant_task_preferences
  add constraint assistant_task_preferences_hidden_kinds_check check (hidden_kinds <@ array[
    'pending_callups','missing_callups','missing_attendance','missing_match_result',
    'missing_match_report','unfinished_preparation','calendar_conflict','personal_calendar_conflict',
    'team_representation_requests','team_representation_available','inbox_messages','inbox_notices'
  ]::text[]);

create or replace function internal.set_assistant_task_preferences_v3_for_actor(
 hidden_kinds text[],expected_revision bigint,current_team_only boolean,welcome_message_visible boolean
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); current_row internal.assistant_task_preferences; normalized text[];
begin
 if actor is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if current_team_only is null or welcome_message_visible is null or hidden_kinds is null
   or expected_revision is null or expected_revision<0
   or array_position(hidden_kinds,null) is not null
   or not hidden_kinds <@ array['pending_callups','missing_callups','missing_attendance',
     'missing_match_result','missing_match_report','unfinished_preparation','calendar_conflict','personal_calendar_conflict',
     'team_representation_requests','team_representation_available','inbox_messages','inbox_notices']::text[]
 then raise invalid_parameter_value using message='invalid_preferences'; end if;
 select coalesce(array_agg(distinct value order by value),'{}'::text[])
 into normalized from unnest(hidden_kinds) value;
 insert into internal.assistant_task_preferences(profile_id) values(actor) on conflict do nothing;
 select * into current_row from internal.assistant_task_preferences where profile_id=actor for update;
 if current_row.hidden_kinds=normalized
   and current_row.current_team_only=current_team_only
   and current_row.welcome_message_visible=welcome_message_visible
 then return internal.get_assistant_task_preferences_for_actor(); end if;
 if current_row.revision<>expected_revision then
   raise sqlstate 'PT409' using message='revision_conflict';
 end if;
 update internal.assistant_task_preferences p set
   hidden_kinds=normalized,
   current_team_only=set_assistant_task_preferences_v3_for_actor.current_team_only,
   welcome_message_visible=set_assistant_task_preferences_v3_for_actor.welcome_message_visible,
   revision=current_row.revision+1
 where p.profile_id=actor;
 return internal.get_assistant_task_preferences_for_actor();
end $$;

notify pgrst, 'reload schema';
