-- Ledargrupper: a club's own groups of leaders across teams, e.g. a
-- herrsektion with the men's teams' leaders, the oldest junior team and a
-- few board members. A group is made of teams (their leaders belong while
-- they lead the team) and single people. Each group has a chat of its own,
-- kept up to date like a team's leader chat. Groups are made and changed by
-- whoever holds members and teams or leads the board (board.manage).

create table core.leader_groups (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  name text not null check (length(btrim(name)) between 1 and 80),
  state text not null default 'active' check (state in ('active', 'archived')),
  thread_id uuid references core.message_threads(id),
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id)
);
create unique index leader_groups_active_name_idx
  on core.leader_groups (club_id, lower(btrim(name))) where state = 'active';

create table core.leader_group_teams (
  group_id uuid not null,
  club_id uuid not null,
  team_id uuid not null,
  primary key (group_id, team_id),
  foreign key (group_id, club_id) references core.leader_groups(id, club_id) on delete cascade,
  foreign key (team_id, club_id) references core.teams(id, club_id)
);
create index leader_group_teams_team_idx on core.leader_group_teams (team_id);

create table core.leader_group_people (
  group_id uuid not null,
  club_id uuid not null,
  club_person_id uuid not null,
  primary key (group_id, club_person_id),
  foreign key (group_id, club_id) references core.leader_groups(id, club_id) on delete cascade,
  foreign key (club_person_id, club_id) references core.club_people(id, club_id)
);
create index leader_group_people_person_idx on core.leader_group_people (club_person_id);

alter table core.leader_groups enable row level security;
alter table core.leader_group_teams enable row level security;
alter table core.leader_group_people enable row level security;
revoke all on core.leader_groups, core.leader_group_teams, core.leader_group_people
  from public, anon, authenticated;

-- The club people in a group right now: the leaders of its teams and the
-- single people who are still active in the club.
create or replace function internal.leader_group_member_people(target_group_id uuid)
returns table (club_person_id uuid) language sql stable security definer set search_path = '' as $$
  select assignment.club_person_id
  from core.leader_group_teams group_team
  join core.assignments assignment on assignment.club_id = group_team.club_id
    and assignment.team_id = group_team.team_id and assignment.role_package = 'leader'
    and assignment.state = 'active' and assignment.starts_at <= now()
    and (assignment.ends_at is null or assignment.ends_at > now())
  join core.teams team on team.id = group_team.team_id and team.status = 'active'
  where group_team.group_id = target_group_id
  union
  select person.club_person_id
  from core.leader_group_people person
  where person.group_id = target_group_id
    and exists (select 1 from core.assignments assignment
      where assignment.club_id = person.club_id and assignment.club_person_id = person.club_person_id
        and assignment.state = 'active' and assignment.starts_at <= now()
        and (assignment.ends_at is null or assignment.ends_at > now()))
$$;

-- Creates the group's chat on first use and keeps its participants and
-- scopes (so each member's own context lists it) in step with the group.
create or replace function internal.sync_leader_group_thread(target_group_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare group_row core.leader_groups%rowtype; thread_id_value uuid;
begin
  select * into group_row from core.leader_groups where id = target_group_id for update;
  if group_row.id is null then return; end if;
  thread_id_value := group_row.thread_id;
  if group_row.state <> 'active' then
    update core.message_threads set state = 'closed', closed_at = coalesce(closed_at, now()), revision = revision + 1
    where id = thread_id_value and state = 'active';
    return;
  end if;
  if thread_id_value is null then
    insert into core.message_threads (club_id, thread_type, subject, created_by)
    values (group_row.club_id, 'leader', group_row.name, group_row.created_by)
    returning id into thread_id_value;
    update core.leader_groups set thread_id = thread_id_value where id = group_row.id;
  end if;
  update core.message_threads set subject = group_row.name, revision = revision + 1
  where id = thread_id_value and subject is distinct from group_row.name;
  update core.message_threads set state = 'active', closed_at = null, revision = revision + 1
  where id = thread_id_value and state = 'closed';

  with eligible as (
    select distinct on (link.profile_id) link.profile_id, link.club_id, link.club_person_id
    from internal.leader_group_member_people(group_row.id) member
    join core.person_account_links link on link.club_id = group_row.club_id
      and link.club_person_id = member.club_person_id and link.state = 'active'
    order by link.profile_id, link.club_person_id
  )
  insert into core.thread_participants (thread_id, profile_id, club_id, club_person_id, participant_role, state, left_at)
  select thread_id_value, eligible.profile_id, eligible.club_id, eligible.club_person_id, 'member', 'active', null
  from eligible
  on conflict (thread_id, profile_id) do update set club_id = excluded.club_id,
    club_person_id = excluded.club_person_id, state = 'active', left_at = null,
    revision = core.thread_participants.revision + 1
  where core.thread_participants.state <> 'active'
    or core.thread_participants.club_person_id <> excluded.club_person_id;

  update core.thread_participants participant set state = 'removed', left_at = now(), revision = revision + 1
  where participant.thread_id = thread_id_value and participant.state = 'active'
    and not exists (
      select 1 from internal.leader_group_member_people(group_row.id) member
      join core.person_account_links link on link.club_id = group_row.club_id
        and link.club_person_id = member.club_person_id and link.state = 'active'
      where link.profile_id = participant.profile_id);

  -- Scopes: the club, the group's teams and the members' own teams.
  if not exists (select 1 from core.thread_scopes where thread_id = thread_id_value and team_id is null) then
    insert into core.thread_scopes (thread_id, club_id, team_id, scope_role)
    values (thread_id_value, group_row.club_id, null, 'owner');
  end if;
  with wanted as (
    select group_team.team_id from core.leader_group_teams group_team where group_team.group_id = group_row.id
    union
    select assignment.team_id
    from internal.leader_group_member_people(group_row.id) member
    join core.assignments assignment on assignment.club_id = group_row.club_id
      and assignment.club_person_id = member.club_person_id and assignment.team_id is not null
      and assignment.state = 'active' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
  )
  insert into core.thread_scopes (thread_id, club_id, team_id, scope_role)
  select thread_id_value, group_row.club_id, wanted.team_id, 'member' from wanted
  on conflict (thread_id, club_id, team_id) do nothing;
  delete from core.thread_scopes scope
  where scope.thread_id = thread_id_value and scope.team_id is not null
    and scope.team_id not in (
      select group_team.team_id from core.leader_group_teams group_team where group_team.group_id = group_row.id
      union
      select assignment.team_id
      from internal.leader_group_member_people(group_row.id) member
      join core.assignments assignment on assignment.club_id = group_row.club_id
        and assignment.club_person_id = member.club_person_id and assignment.team_id is not null
        and assignment.state = 'active' and assignment.starts_at <= now()
        and (assignment.ends_at is null or assignment.ends_at > now()));
end
$$;

-- Keep the groups' chats in step when someone starts or stops leading a
-- team, leaves the club or links their account.
create or replace function internal.sync_leader_groups_for_person(target_club_id uuid, target_person_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare group_id_value uuid;
begin
  for group_id_value in
    select person.group_id from core.leader_group_people person
    where person.club_id = target_club_id and person.club_person_id = target_person_id
    union
    select group_team.group_id from core.leader_group_teams group_team
    join core.assignments assignment on assignment.club_id = group_team.club_id
      and assignment.team_id = group_team.team_id and assignment.club_person_id = target_person_id
    where group_team.club_id = target_club_id
    union
    select group_row.id from core.leader_groups group_row
    join core.thread_participants participant on participant.thread_id = group_row.thread_id
      and participant.club_person_id = target_person_id
    where group_row.club_id = target_club_id
  loop
    perform internal.sync_leader_group_thread(group_id_value);
  end loop;
end
$$;

create or replace function internal.sync_leader_groups_from_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op <> 'DELETE' then perform internal.sync_leader_groups_for_person(new.club_id, new.club_person_id); end if;
  if tg_op <> 'INSERT' and (tg_op = 'DELETE' or old.club_person_id is distinct from new.club_person_id) then
    perform internal.sync_leader_groups_for_person(old.club_id, old.club_person_id);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;
create trigger assignments_sync_leader_groups after insert or update or delete on core.assignments
  for each row execute function internal.sync_leader_groups_from_assignment();

create or replace function internal.sync_leader_groups_from_link()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op <> 'DELETE' then perform internal.sync_leader_groups_for_person(new.club_id, new.club_person_id); end if;
  if tg_op <> 'INSERT' and (tg_op = 'DELETE' or old.club_person_id is distinct from new.club_person_id) then
    perform internal.sync_leader_groups_for_person(old.club_id, old.club_person_id);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;
create trigger person_links_sync_leader_groups after insert or update or delete on core.person_account_links
  for each row execute function internal.sync_leader_groups_from_link();

create or replace function internal.actor_manages_leader_groups(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.actor_has_capability(target_club_id, null, 'club.memberships.manage')
    or internal.actor_has_capability(target_club_id, null, 'board.manage')
$$;

-- The club's groups with their teams and people, and what can be chosen.
create or replace function internal.list_leader_groups_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_manages_leader_groups(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'schema_version', 1,
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', group_row.id, 'name', group_row.name, 'revision', group_row.revision,
        'thread_id', group_row.thread_id,
        'teams', coalesce((select jsonb_agg(jsonb_build_object('id', team.id, 'name', team.name) order by team.name)
          from core.leader_group_teams group_team join core.teams team on team.id = group_team.team_id
          where group_team.group_id = group_row.id), '[]'),
        'people', coalesce((select jsonb_agg(jsonb_build_object('id', person.id, 'name', person.display_name)
            order by person.display_name)
          from core.leader_group_people group_person join core.club_people person on person.id = group_person.club_person_id
          where group_person.group_id = group_row.id), '[]'),
        'member_count', (select count(*) from internal.leader_group_member_people(group_row.id))
      ) order by lower(group_row.name))
      from core.leader_groups group_row
      where group_row.club_id = target_club_id and group_row.state = 'active'), '[]'),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object('id', team.id, 'name', team.name) order by team.name)
      from core.teams team where team.club_id = target_club_id and team.status = 'active'), '[]'),
    'people', coalesce((
      select jsonb_agg(candidate.value order by candidate.name)
      from (
        select person.display_name as name, jsonb_build_object(
          'id', person.id, 'name', person.display_name,
          'teams', coalesce((select jsonb_agg(distinct team.name)
            from core.assignments assignment join core.teams team on team.id = assignment.team_id
            where assignment.club_id = person.club_id and assignment.club_person_id = person.id
              and assignment.role_package = 'leader' and assignment.state = 'active'
              and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())), '[]'),
          'offices', coalesce((select jsonb_agg(distinct mandate.office)
            from core.board_mandates mandate join core.assignments assignment on assignment.id = mandate.assignment_id
            where assignment.club_person_id = person.id and mandate.club_id = person.club_id
              and mandate.state = 'active' and mandate.starts_at <= now() and mandate.ends_at > now()), '[]'),
          'functionary', exists (select 1 from core.assignments assignment
            where assignment.club_id = person.club_id and assignment.club_person_id = person.id
              and assignment.role_package = 'club_functionary' and assignment.state = 'active'
              and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now()))
        ) as value
        from core.club_people person
        where person.club_id = target_club_id and person.status = 'active'
          and exists (select 1 from core.assignments assignment
            where assignment.club_id = person.club_id and assignment.club_person_id = person.id
              and assignment.role_package in ('leader', 'club_functionary') and assignment.state = 'active'
              and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now()))
      ) candidate), '[]')
  );
end
$$;

create or replace function internal.save_leader_group_for_actor(
  target_club_id uuid, target_group_id uuid, group_name text, team_ids uuid[], person_ids uuid[],
  expected_revision bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); group_row core.leader_groups%rowtype; clean_name text := btrim(group_name);
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_manages_leader_groups(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if clean_name is null or length(clean_name) not between 1 and 80 then
    raise invalid_parameter_value using message = 'invalid_name';
  end if;
  team_ids := coalesce(team_ids, '{}'); person_ids := coalesce(person_ids, '{}');
  if cardinality(team_ids) + cardinality(person_ids) = 0 then
    raise invalid_parameter_value using message = 'empty_group';
  end if;
  if cardinality(team_ids) > 100 or cardinality(person_ids) > 200 then
    raise invalid_parameter_value using message = 'too_many';
  end if;
  if exists (select 1 from unnest(team_ids) wanted where not exists (
      select 1 from core.teams team where team.id = wanted and team.club_id = target_club_id and team.status = 'active'))
    or exists (select 1 from unnest(person_ids) wanted where not exists (
      select 1 from core.club_people person where person.id = wanted and person.club_id = target_club_id
        and person.status = 'active')) then
    raise invalid_parameter_value using message = 'invalid_member';
  end if;
  if exists (select 1 from core.leader_groups other where other.club_id = target_club_id and other.state = 'active'
      and lower(btrim(other.name)) = lower(clean_name) and other.id is distinct from target_group_id) then
    raise sqlstate 'PT409' using message = 'name_taken';
  end if;

  if target_group_id is null then
    insert into core.leader_groups (club_id, name, created_by) values (target_club_id, clean_name, actor_id)
    returning * into group_row;
  else
    select * into group_row from core.leader_groups
    where id = target_group_id and club_id = target_club_id and state = 'active' for update;
    if group_row.id is null then raise insufficient_privilege using message = 'not_found'; end if;
    if expected_revision is null or group_row.revision <> expected_revision then
      raise sqlstate 'PT409' using message = 'stale_revision';
    end if;
    update core.leader_groups set name = clean_name, updated_at = now(), revision = revision + 1
    where id = group_row.id returning * into group_row;
  end if;

  delete from core.leader_group_teams where group_id = group_row.id and team_id <> all (team_ids);
  insert into core.leader_group_teams (group_id, club_id, team_id)
  select distinct group_row.id, target_club_id, wanted from unnest(team_ids) wanted
  on conflict do nothing;
  delete from core.leader_group_people where group_id = group_row.id and club_person_id <> all (person_ids);
  insert into core.leader_group_people (group_id, club_id, club_person_id)
  select distinct group_row.id, target_club_id, wanted from unnest(person_ids) wanted
  on conflict do nothing;

  perform internal.sync_leader_group_thread(group_row.id);
  return jsonb_build_object('id', group_row.id, 'revision', group_row.revision);
end
$$;

create or replace function internal.archive_leader_group_for_actor(target_group_id uuid, expected_revision bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare group_row core.leader_groups%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into group_row from core.leader_groups where id = target_group_id and state = 'active' for update;
  if group_row.id is null or not internal.actor_manages_leader_groups(group_row.club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if group_row.revision <> expected_revision then raise sqlstate 'PT409' using message = 'stale_revision'; end if;
  update core.leader_groups set state = 'archived', updated_at = now(), revision = revision + 1
  where id = group_row.id;
  perform internal.sync_leader_group_thread(group_row.id);
  return jsonb_build_object('id', group_row.id);
end
$$;

create function api.list_leader_groups(target_club_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select internal.list_leader_groups_for_actor(target_club_id)
$$;
create function api.save_leader_group(target_club_id uuid, target_group_id uuid, group_name text,
  team_ids uuid[], person_ids uuid[], expected_revision bigint)
returns jsonb language sql security definer set search_path = '' as $$
  select internal.save_leader_group_for_actor(target_club_id, target_group_id, group_name, team_ids, person_ids,
    expected_revision)
$$;
create function api.archive_leader_group(target_group_id uuid, expected_revision bigint)
returns jsonb language sql security definer set search_path = '' as $$
  select internal.archive_leader_group_for_actor(target_group_id, expected_revision)
$$;

revoke all on function
  internal.leader_group_member_people(uuid),
  internal.sync_leader_group_thread(uuid),
  internal.sync_leader_groups_for_person(uuid, uuid),
  internal.sync_leader_groups_from_assignment(),
  internal.sync_leader_groups_from_link(),
  internal.actor_manages_leader_groups(uuid),
  internal.list_leader_groups_for_actor(uuid),
  internal.save_leader_group_for_actor(uuid, uuid, text, uuid[], uuid[], bigint),
  internal.archive_leader_group_for_actor(uuid, bigint)
from public, anon, authenticated;
revoke all on function
  api.list_leader_groups(uuid),
  api.save_leader_group(uuid, uuid, text, uuid[], uuid[], bigint),
  api.archive_leader_group(uuid, bigint)
from public, anon;
grant execute on function
  api.list_leader_groups(uuid),
  api.save_leader_group(uuid, uuid, text, uuid[], uuid[], bigint),
  api.archive_leader_group(uuid, bigint)
to authenticated;

notify pgrst, 'reload schema';
