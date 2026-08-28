\set ON_ERROR_STOP on

set role postgres;
begin;

insert into auth.users (id, raw_user_meta_data, raw_app_meta_data) values
  ('91000000-0000-0000-0000-000000000001', '{"display_name":"Player"}', '{}'),
  ('91000000-0000-0000-0000-000000000002', '{"display_name":"Guardian"}', '{}'),
  ('91000000-0000-0000-0000-000000000003', '{"display_name":"Leader"}', '{}'),
  ('91000000-0000-0000-0000-000000000004', '{"display_name":"Functionary"}', '{}'),
  ('91000000-0000-0000-0000-000000000005', '{"display_name":"Guest"}', '{}'),
  ('91000000-0000-0000-0000-000000000006', '{"display_name":"Unknown"}', '{}'),
  ('91000000-0000-0000-0000-000000000007', '{"display_name":"Super claim"}', '{"super_admin":true}'),
  ('91000000-0000-0000-0000-000000000008', '{"display_name":"Suspended"}', '{}'),
  ('91000000-0000-0000-0000-000000000009', '{"display_name":"Ended"}', '{}'),
  ('91000000-0000-0000-0000-000000000010', '{"display_name":"Other club"}', '{}');

insert into core.clubs (id, name, slug) values
  ('92000000-0000-0000-0000-000000000001', 'Matrix Club A', 'matrix-club-a'),
  ('92000000-0000-0000-0000-000000000002', 'Matrix Club B', 'matrix-club-b');

insert into core.teams (id, club_id, name) values
  ('93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', 'Matrix Team A'),
  ('93000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000002', 'Matrix Team B');

insert into core.club_people (id, club_id, display_name)
select
  ('94000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  case when n = 10
    then '92000000-0000-0000-0000-000000000002'::uuid
    else '92000000-0000-0000-0000-000000000001'::uuid
  end,
  'Matrix person ' || n
from generate_series(1, 10) as n;

insert into core.person_account_links (
  id, club_id, club_person_id, profile_id, state, verified_at
)
select
  ('95000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  case when n = 10
    then '92000000-0000-0000-0000-000000000002'::uuid
    else '92000000-0000-0000-0000-000000000001'::uuid
  end,
  ('94000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('91000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'active',
  now()
from generate_series(1, 10) as n;

insert into core.assignments (
  id, club_id, team_id, club_person_id, role_package, state, starts_at, ends_at
) values
  ('96000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000001', 'player', 'active', now() - interval '1 day', null),
  ('96000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000001', null, '94000000-0000-0000-0000-000000000002', 'guardian', 'active', now() - interval '1 day', null),
  ('96000000-0000-0000-0000-000000000003', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000003', 'leader', 'active', now() - interval '1 day', null),
  ('96000000-0000-0000-0000-000000000004', '92000000-0000-0000-0000-000000000001', null, '94000000-0000-0000-0000-000000000004', 'club_functionary', 'active', now() - interval '1 day', null),
  ('96000000-0000-0000-0000-000000000005', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000005', 'guest', 'active', now() - interval '1 day', null),
  ('96000000-0000-0000-0000-000000000008', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000008', 'player', 'suspended', now() - interval '1 day', null),
  ('96000000-0000-0000-0000-000000000009', '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000009', 'player', 'ended', now() - interval '2 days', now() - interval '1 day'),
  ('96000000-0000-0000-0000-000000000010', '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000002', '94000000-0000-0000-0000-000000000010', 'leader', 'active', now() - interval '1 day', null);

insert into core.capability_grants (
  club_id, assignment_id, capability, scope_type, scope_id, starts_at
)
select
  assignment.club_id,
  assignment.id,
  'team.read',
  case when assignment.team_id is null then 'club' else 'team' end,
  coalesce(assignment.team_id, assignment.club_id),
  now() - interval '1 day'
from core.assignments as assignment
where assignment.id between
  '96000000-0000-0000-0000-000000000001'::uuid and
  '96000000-0000-0000-0000-000000000010'::uuid;

do $$
begin
  begin
    insert into core.assignments (
      club_id, team_id, club_person_id, role_package, state, starts_at
    ) values (
      '92000000-0000-0000-0000-000000000001',
      '93000000-0000-0000-0000-000000000001',
      '94000000-0000-0000-0000-000000000006',
      'unknown',
      'active',
      now()
    );
    raise exception 'unknown role unexpectedly accepted';
  exception
    when check_violation then null;
  end;
end;
$$;

create temporary table expected_contexts (
  profile_id uuid primary key,
  expected_count integer not null,
  expected_role text,
  expected_club_id uuid
) on commit drop;

insert into expected_contexts values
  ('91000000-0000-0000-0000-000000000001', 1, 'player', '92000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-000000000002', 1, 'guardian', '92000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-000000000003', 1, 'leader', '92000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-000000000004', 1, 'club_functionary', '92000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-000000000005', 1, 'guest', '92000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-000000000006', 0, null, null),
  ('91000000-0000-0000-0000-000000000007', 0, null, null),
  ('91000000-0000-0000-0000-000000000008', 0, null, null),
  ('91000000-0000-0000-0000-000000000009', 0, null, null),
  ('91000000-0000-0000-0000-000000000010', 1, 'leader', '92000000-0000-0000-0000-000000000002');

grant select on expected_contexts to authenticated;

set local role authenticated;

do $$
declare
  expectation record;
  actual_count integer;
  actual_role text;
  actual_club_id uuid;
begin
  for expectation in select * from expected_contexts order by profile_id loop
    perform set_config('request.jwt.claim.sub', expectation.profile_id::text, true);

    select count(*), min(role_package), min(club_id::text)::uuid
    into actual_count, actual_role, actual_club_id
    from api.get_my_contexts();

    if actual_count <> expectation.expected_count then
      raise exception 'context count mismatch for %: expected %, got %',
        expectation.profile_id, expectation.expected_count, actual_count;
    end if;
    if expectation.expected_count = 1 and (
      actual_role is distinct from expectation.expected_role or
      actual_club_id is distinct from expectation.expected_club_id
    ) then
      raise exception 'scope mismatch for %', expectation.profile_id;
    end if;
  end loop;
end;
$$;

set local role anon;
do $$
begin
  begin
    perform * from api.get_my_contexts();
    raise exception 'anon unexpectedly executed api.get_my_contexts';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

set local role postgres;
rollback;
reset role;
