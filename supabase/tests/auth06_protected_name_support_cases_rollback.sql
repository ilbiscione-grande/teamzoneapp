\set ON_ERROR_STOP on
begin;

set local role postgres;

select set_config('test.requester_id',(select id::text from auth.users
  where lower(email)='coach.emilson+tzprotected@gmail.com'),true);
select set_config('test.admin_id',(select id::text from auth.users
  where lower(email)='coach.emilson@gmail.com'),true);

insert into internal.support_admins(profile_id,created_by)
values(current_setting('test.admin_id')::uuid,current_setting('test.admin_id')::uuid);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.requester_id'),true);

select set_config('test.case_id',api.submit_protected_name_support_case(
  'Team-Zone','AUTH06 testlag',
  'Jag vill få klubbnamnet Team-Zone granskat och kan lämna underlag som styrker min koppling.',
  '86060000-0000-4000-8000-000000000001'::uuid
)::text,true);

do $$
declare replay_id uuid; mine_count integer;
begin
  if api.is_support_admin() then raise exception 'ordinary requester reported as support admin'; end if;
  replay_id:=api.submit_protected_name_support_case(
    'Team-Zone','AUTH06 testlag',
    'Jag vill få klubbnamnet Team-Zone granskat och kan lämna underlag som styrker min koppling.',
    '86060000-0000-4000-8000-000000000001'::uuid
  );
  if replay_id<>current_setting('test.case_id')::uuid then raise exception 'submit replay changed case id'; end if;
  select count(*) into mine_count from api.list_my_protected_name_support_cases()
  where case_id=current_setting('test.case_id')::uuid and status='pending';
  if mine_count<>1 then raise exception 'requester cannot read own pending case'; end if;
  begin
    perform * from api.list_protected_name_support_cases('pending');
    raise exception 'ordinary requester read the support queue';
  exception when insufficient_privilege then null;
  end;
  begin
    perform api.update_protected_name_support_case(
      current_setting('test.case_id')::uuid,'resolved','Otillåtet beslut.',1,
      '86060000-0000-4000-8000-000000000002'::uuid
    );
    raise exception 'ordinary requester updated a support case';
  exception when insufficient_privilege then null;
  end;
end
$$;

select set_config('request.jwt.claim.sub',current_setting('test.admin_id'),true);

do $$
declare queue_count integer; new_revision bigint;
begin
  if not api.is_support_admin() then raise exception 'support admin probe returned false'; end if;
  select count(*) into queue_count from api.list_protected_name_support_cases('pending')
  where case_id=current_setting('test.case_id')::uuid
    and requester_profile_id=current_setting('test.requester_id')::uuid;
  if queue_count<>1 then raise exception 'support admin cannot read pending case'; end if;
  new_revision:=api.update_protected_name_support_case(
    current_setting('test.case_id')::uuid,'resolved','Kopplingen har granskats i rollback-testet.',1,
    '86060000-0000-4000-8000-000000000003'::uuid
  );
  if new_revision<>2 then raise exception 'unexpected support case revision'; end if;
  if api.update_protected_name_support_case(
    current_setting('test.case_id')::uuid,'resolved','Kopplingen har granskats i rollback-testet.',1,
    '86060000-0000-4000-8000-000000000003'::uuid
  )<>2 then raise exception 'admin replay changed revision'; end if;
end
$$;

set local role postgres;
do $$
begin
  if not exists(
    select 1 from internal.protected_name_support_cases
    where id=current_setting('test.case_id')::uuid and status='resolved' and revision=2
      and handled_by=current_setting('test.admin_id')::uuid and resolved_at is not null
  ) then raise exception 'resolved case state is incorrect'; end if;
  if (select count(*) from audit.command_events
      where aggregate_id=current_setting('test.case_id')::uuid
        and command_type in ('support.protected_name.request.v1','support.protected_name.update.v1'))<>2
  then raise exception 'support case audit trail is incomplete'; end if;
end
$$;

rollback;
\echo AUTH06_SUPPORT_CASES_ROLLBACK_OK
