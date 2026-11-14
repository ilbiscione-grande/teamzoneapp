-- Ledargrupper of single people can book meetings too.
--
-- An activity still belongs to a team. A group without teams has its
-- meeting held by a team one of its members leads (the first by name), or
-- else by the club's first team. Those of that team's leaders who are not
-- in the group must not see it, so a team's rights reach a group meeting
-- only for members of the group (and, for reading, those called to it).
-- That is no change for a group of teams, whose holding team's leaders are
-- all members.

-- Does a team's own view reach this activity? Every activity but a group
-- meeting; a group meeting for its members and those called to it.
create or replace function internal.visible_as_team_event(target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from core.leader_group_events group_event
      where group_event.event_id = target_event_id)
    or internal.actor_in_leader_group_meeting(target_event_id)
    or exists (
      select 1 from core.callups callup
      join core.person_account_links link on link.club_person_id = callup.club_person_id
        and link.club_id = callup.club_id and link.profile_id = auth.uid() and link.state = 'active'
      where callup.event_id = target_event_id and callup.state <> 'cancelled')
$$;

-- Do a team's rights (manage, squad, attendance) reach this activity?
-- Every activity but a group meeting; a group meeting for its members.
create or replace function internal.team_rights_reach_event(target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from core.leader_group_events group_event
      where group_event.event_id = target_event_id)
    or internal.actor_in_leader_group_meeting(target_event_id)
$$;

revoke all on function
  internal.visible_as_team_event(uuid),
  internal.team_rights_reach_event(uuid)
from public, anon, authenticated;

do $patch$
declare
  fn text;
  def text;
  patched text;
begin
  -- The meeting's holding team: one of the group's teams, else a team a
  -- member leads, else the club's first team.
  def := pg_get_functiondef('internal.create_leader_group_meeting_for_actor(uuid,text,timestamptz,timestamptz,text,text,text,uuid)'::regprocedure);
  patched := replace(def, '  if host_team_id is null then raise invalid_parameter_value using message = ''no_team''; end if;',
    '  if host_team_id is null then
    select team.id into host_team_id
    from internal.leader_group_member_people(group_row.id) member
    join core.assignments assignment on assignment.club_person_id = member.club_person_id
      and assignment.club_id = group_row.club_id and assignment.role_package = ''leader''
      and assignment.state = ''active'' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
    join core.teams team on team.id = assignment.team_id and team.status = ''active''
    order by lower(team.name), team.id limit 1;
  end if;
  if host_team_id is null then
    select team.id into host_team_id from core.teams team
    where team.club_id = group_row.club_id and team.status = ''active''
    order by lower(team.name), team.id limit 1;
  end if;
  if host_team_id is null then raise invalid_parameter_value using message = ''no_team''; end if;');
  if patched = def then raise exception 'create_leader_group_meeting_for_actor not patched'; end if;
  execute patched;

  -- Reading through a team: not a group meeting one is outside of.
  def := pg_get_functiondef('internal.actor_can_read_event(uuid)'::regprocedure);
  patched := regexp_replace(def, ' or exists\s*\(',
    ' or internal.visible_as_team_event(target_event_id) and exists (');
  if patched = def then raise exception 'actor_can_read_event not patched'; end if;
  execute patched;

  -- Managing through a team: only a member of the group.
  foreach fn in array array[
    'internal.actor_can_manage_event(uuid)',
    'internal.actor_has_event_capability(uuid,text)',
    'internal.actor_can_manage_event_sharing(uuid)'
  ] loop
    def := pg_get_functiondef(fn::regprocedure);
    patched := regexp_replace(def, ' or exists\s*\(',
      ' or internal.team_rights_reach_event(target_event_id) and exists (');
    if patched = def then raise exception '% not patched', fn; end if;
    execute patched;
  end loop;

  -- Hem in a team context: lists and tasks leave out a group meeting one
  -- is outside of.
  foreach fn in array array[
    'internal.get_leader_home_base_for_actor(uuid)',
    'internal.get_leader_home_for_actor(uuid)'
  ] loop
    def := pg_get_functiondef(fn::regprocedure);
    patched := replace(def, 'relation.team_id=context_row.team_id or (',
      'relation.team_id=context_row.team_id and internal.visible_as_team_event(event_row.id) or (');
    patched := replace(patched, 'event_row.owning_team_id=context_row.team_id',
      '(event_row.owning_team_id=context_row.team_id and internal.visible_as_team_event(event_row.id))');
    if patched = def then raise exception '% not patched', fn; end if;
    execute patched;
  end loop;
end
$patch$;

notify pgrst, 'reload schema';
