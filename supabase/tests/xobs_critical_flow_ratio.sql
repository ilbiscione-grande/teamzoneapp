begin;

select set_config('request.jwt.claim.role', 'service_role', true);

select internal.record_critical_flow_outcome('checkout', 'succeeded', '2026-08-22 18:00:10+00');
select internal.record_critical_flow_outcome('checkout', 'succeeded', '2026-08-22 18:01:10+00');
select internal.record_critical_flow_outcome('checkout', 'succeeded', '2026-08-22 18:02:10+00');
select internal.record_critical_flow_outcome('checkout', 'succeeded', '2026-08-22 18:03:10+00');
select internal.record_critical_flow_outcome('checkout', 'succeeded', '2026-08-22 18:04:10+00');
select internal.record_critical_flow_outcome('checkout', 'failed', '2026-08-22 18:04:20+00');

do $$
declare ratio record;
begin
  select * into ratio
  from internal.get_critical_flow_ratios('2026-08-22 18:04:59+00')
  where flow = 'checkout';
  if ratio.attempts <> 6 or ratio.failed <> 1 or ratio.failure_rate_percent <> 16.67 or not ratio.breached then
    raise exception 'unexpected breached ratio: %', row_to_json(ratio);
  end if;

  select * into ratio
  from internal.get_critical_flow_ratios('2026-08-22 18:10:00+00')
  where flow = 'checkout';
  if ratio.attempts <> 0 or ratio.failure_rate_percent <> 0 or ratio.breached then
    raise exception 'expired bucket leaked into window: %', row_to_json(ratio);
  end if;
end;
$$;

do $$
begin
  begin
    perform internal.record_critical_flow_outcome('unknown', 'failed', now());
    raise exception 'invalid flow was accepted';
  exception when check_violation then null;
  end;
end;
$$;

do $$
begin
  if has_function_privilege(
    'authenticated',
    'api.record_critical_flow_outcome(text,text,timestamptz)',
    'execute'
  ) then
    raise exception 'authenticated role can execute observability counter';
  end if;
  if not has_function_privilege(
    'service_role',
    'api.record_critical_flow_outcome(text,text,timestamptz)',
    'execute'
  ) then
    raise exception 'service_role cannot execute observability counter';
  end if;
end;
$$;

rollback;
