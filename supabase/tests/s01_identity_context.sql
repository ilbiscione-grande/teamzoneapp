\set ON_ERROR_STOP on

set role postgres;
begin;

insert into auth.users (id, raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000001', '{"display_name":"Ledaren","locale":"sv"}'),
  ('10000000-0000-0000-0000-000000000002', '{"display_name":"Outsider","locale":"en"}');

do $$
begin
  if (select count(*) from core.profiles) <> 2 then
    raise exception 'auth profile trigger did not create exactly two profiles';
  end if;
end;
$$;

insert into core.clubs (id, name, slug) values
  ('20000000-0000-0000-0000-000000000001', 'Klubb A', 'klubb-a'),
  ('20000000-0000-0000-0000-000000000002', 'Klubb B', 'klubb-b');

insert into core.teams (id, club_id, name) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Lag A'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'Lag B');

insert into core.club_people (id, club_id, display_name) values
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Ledaren'),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'Outsider');

insert into core.person_account_links (
  id, club_id, club_person_id, profile_id, state, verified_at
) values
  (
    '50000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'active',
    now()
  ),
  (
    '50000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000002',
    '40000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000002',
    'active',
    now()
  );

insert into core.assignments (
  id, club_id, team_id, club_person_id, role_package, state, starts_at
) values
  (
    '60000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    'leader',
    'active',
    now() - interval '1 day'
  ),
  (
    '60000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000002',
    '40000000-0000-0000-0000-000000000002',
    'player',
    'active',
    now() - interval '1 day'
  );

insert into core.capability_grants (
  club_id, assignment_id, capability, scope_type, scope_id, starts_at
) values (
  '20000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000001',
  'team.read',
  'team',
  '30000000-0000-0000-0000-000000000001',
  now() - interval '1 day'
);

do $$
begin
  begin
    insert into core.assignments (
      club_id, team_id, club_person_id, role_package, state, starts_at
    ) values (
      '20000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000001',
      'unknown_role',
      'active',
      now()
    );
    raise exception 'unknown role unexpectedly accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into core.capability_grants (
      club_id, assignment_id, capability, scope_type, scope_id, starts_at
    ) values (
      '20000000-0000-0000-0000-000000000002',
      '60000000-0000-0000-0000-000000000001',
      'team.read',
      'team',
      '30000000-0000-0000-0000-000000000002',
      now()
    );
    raise exception 'cross-tenant capability unexpectedly accepted';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into core.capability_grants (
      club_id, assignment_id, capability, scope_type, scope_id, starts_at
    ) values (
      '20000000-0000-0000-0000-000000000001',
      '60000000-0000-0000-0000-000000000001',
      'team.manage',
      'team',
      '30000000-0000-0000-0000-000000000002',
      now()
    );
    raise exception 'wrong team scope unexpectedly accepted';
  exception
    when check_violation then null;
  end;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

do $$
declare
  context_count integer;
  returned_club uuid;
  returned_capabilities text[];
begin
  select count(*) into context_count from api.get_my_contexts();
  select club_id, capabilities
  into returned_club, returned_capabilities
  from api.get_my_contexts()
  limit 1;

  if context_count <> 1 then
    raise exception 'expected exactly one context, got %', context_count;
  end if;
  if returned_club <> '20000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'cross-tenant context leaked';
  end if;
  if returned_capabilities <> array['team.read']::text[] then
    raise exception 'capability projection mismatch';
  end if;
end;
$$;

select * from api.set_profile_preferences(
  'en',
  'Europe/Stockholm',
  '70000000-0000-0000-0000-000000000001'
);
select * from api.set_profile_preferences(
  'en',
  'Europe/Stockholm',
  '70000000-0000-0000-0000-000000000001'
);

set local role postgres;

do $$
begin
  if (
    select revision
    from core.profiles
    where id = '10000000-0000-0000-0000-000000000001'
  ) <> 2 then
    raise exception 'idempotent retry changed profile revision more than once';
  end if;
  if (
    select count(*)
    from audit.command_events
    where actor_profile_id = '10000000-0000-0000-0000-000000000001'
  ) <> 1 then
    raise exception 'idempotent retry produced duplicate audit event';
  end if;
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
