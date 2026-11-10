-- Medlemsregister (club-members-and-fees.md, step 1): everyone active in the
-- club with teams, roles and guardians, and who is a member in which
-- category. Players, leaders and club functionaries are members unless the
-- club says otherwise; a guardian only when the club says so. The category
-- follows the birth year (youth through the year one turns 20) unless set.
-- Read and set by whoever holds members and teams (club.memberships.manage);
-- the permissions review decides whether it gets its own capability. No
-- contact details here: they keep their own rules (get_person_contact).

create table core.club_memberships (
  club_person_id uuid primary key,
  club_id uuid not null references core.clubs(id),
  is_member boolean not null,
  category text check (category in ('youth', 'adult', 'supporter')),
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  foreign key (club_person_id, club_id) references core.club_people(id, club_id)
);
create index club_memberships_club_idx on core.club_memberships(club_id);
alter table core.club_memberships enable row level security;
revoke all on core.club_memberships from public, anon, authenticated;

-- Member unless the club says otherwise: plays in a team, leads one or
-- holds a club assignment.
create or replace function internal.club_person_is_default_member(target_club_id uuid, target_person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from core.team_assignments ta
      where ta.club_id = target_club_id and ta.club_person_id = target_person_id and ta.state = 'active')
    or exists (select 1 from core.assignments a
      where a.club_id = target_club_id and a.club_person_id = target_person_id and a.state = 'active'
        and a.role_package in ('player', 'leader', 'club_functionary')
        and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now()))
$$;

create or replace function internal.club_member_default_category(birth_year smallint)
returns text language sql stable set search_path = '' as $$
  select case when birth_year is null then null
    when extract(year from now())::int - birth_year <= 20 then 'youth' else 'adult' end
$$;

create or replace function internal.get_club_member_register_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object('people', coalesce((select jsonb_agg(entry order by entry->>'name', entry->>'person_id') from (
    select jsonb_build_object(
      'person_id', person.id,
      'name', person.display_name,
      'birth_year', person.birth_year,
      'has_account', exists (select 1 from core.person_account_links link
        where link.club_person_id = person.id and link.club_id = target_club_id and link.state = 'active'),
      'club_role', exists (select 1 from core.assignments a
        where a.club_id = target_club_id and a.club_person_id = person.id and a.team_id is null
          and a.role_package = 'club_functionary' and a.state = 'active'
          and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())),
      'teams', coalesce((select jsonb_agg(distinct jsonb_build_object('team_id', team.id, 'name', team.name, 'role', role_row.role))
        from (
          select ta.team_id, 'player'::text as role from core.team_assignments ta
          where ta.club_id = target_club_id and ta.club_person_id = person.id and ta.state = 'active'
          union
          select a.team_id, a.role_package from core.assignments a
          where a.club_id = target_club_id and a.club_person_id = person.id and a.team_id is not null
            and a.state = 'active' and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())
        ) role_row
        join core.teams team on team.id = role_row.team_id and team.club_id = target_club_id), '[]'::jsonb),
      'guardians', coalesce((select jsonb_agg(distinct guardian.display_name)
        from core.guardian_relations relation
        join core.club_people guardian on guardian.id = relation.guardian_person_id and guardian.status = 'active'
        where relation.club_id = target_club_id and relation.child_person_id = person.id and relation.state = 'active'
          and (relation.ends_at is null or relation.ends_at > now())), '[]'::jsonb),
      'children', coalesce((select jsonb_agg(distinct child.display_name)
        from core.guardian_relations relation
        join core.club_people child on child.id = relation.child_person_id and child.status = 'active'
        where relation.club_id = target_club_id and relation.guardian_person_id = person.id and relation.state = 'active'
          and (relation.ends_at is null or relation.ends_at > now())), '[]'::jsonb),
      'is_member', coalesce(membership.is_member, internal.club_person_is_default_member(target_club_id, person.id)),
      'member_set', membership.club_person_id is not null,
      'category', coalesce(membership.category, internal.club_member_default_category(person.birth_year)),
      'category_set', membership.category is not null,
      'revision', coalesce(membership.revision, 0)) as entry
    from core.club_people person
    left join core.club_memberships membership on membership.club_person_id = person.id
    where person.club_id = target_club_id and person.status = 'active') register_rows), '[]'::jsonb));
end;
$$;

-- new_category null: follow the birth year again.
create or replace function internal.set_club_membership_for_actor(target_club_id uuid, target_person_id uuid,
  new_is_member boolean, new_category text, expected_revision bigint, idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); cached jsonb; current_row core.club_memberships%rowtype; result jsonb;
begin
  if actor_id is null or not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if idempotency_key is null or new_is_member is null or expected_revision is null
    or (new_category is not null and new_category not in ('youth', 'adult', 'supporter')) then
    raise invalid_parameter_value using message = 'invalid_membership';
  end if;
  select d.result into cached from internal.command_deduplication d where d.actor_profile_id = actor_id
    and d.command_type = 'club.membership.updated.v1' and d.idempotency_key = set_club_membership_for_actor.idempotency_key;
  if cached is not null then return cached; end if;
  if not exists (select 1 from core.club_people person
      where person.id = target_person_id and person.club_id = target_club_id and person.status = 'active') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('club-membership:' || target_person_id::text, 0));
  select * into current_row from core.club_memberships where club_person_id = target_person_id;
  if coalesce(current_row.revision, 0) <> expected_revision then
    raise sqlstate 'PT409' using message = 'stale_revision';
  end if;
  insert into core.club_memberships (club_person_id, club_id, is_member, category, updated_by)
  values (target_person_id, target_club_id, new_is_member, new_category, actor_id)
  on conflict (club_person_id) do update
  set is_member = excluded.is_member, category = excluded.category, updated_at = now(),
    updated_by = excluded.updated_by, revision = core.club_memberships.revision + 1
  returning jsonb_build_object('is_member', is_member, 'category', category, 'revision', revision) into result;
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'club.membership.updated.v1', result);
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  values (target_club_id, actor_id, 'club.membership.updated.v1', 'club_person', target_person_id, (result->>'revision')::bigint,
    jsonb_build_object('from', case when current_row.club_person_id is null then null
      else jsonb_build_object('is_member', current_row.is_member, 'category', current_row.category) end,
      'to', jsonb_build_object('is_member', new_is_member, 'category', new_category)));
  return result;
end;
$$;

create or replace function api.get_club_member_register(target_club_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_club_member_register_for_actor(target_club_id) $$;
create or replace function api.set_club_membership(target_club_id uuid, target_person_id uuid,
  new_is_member boolean, new_category text, expected_revision bigint, idempotency_key uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_club_membership_for_actor(target_club_id, target_person_id, new_is_member, new_category,
    expected_revision, idempotency_key) $$;

revoke all on function
  internal.club_person_is_default_member(uuid, uuid), internal.club_member_default_category(smallint),
  internal.get_club_member_register_for_actor(uuid),
  internal.set_club_membership_for_actor(uuid, uuid, boolean, text, bigint, uuid),
  api.get_club_member_register(uuid), api.set_club_membership(uuid, uuid, boolean, text, bigint, uuid)
from public, anon, authenticated;
grant execute on function
  internal.get_club_member_register_for_actor(uuid),
  internal.set_club_membership_for_actor(uuid, uuid, boolean, text, bigint, uuid),
  api.get_club_member_register(uuid), api.set_club_membership(uuid, uuid, boolean, text, bigint, uuid)
to authenticated;
notify pgrst, 'reload schema';
