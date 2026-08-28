create table internal.critical_flow_outcome_buckets (
  bucket_start timestamptz not null,
  flow text not null check (flow in ('auth', 'checkout', 'messaging', 'critical_commands')),
  succeeded bigint not null default 0 check (succeeded >= 0),
  failed bigint not null default 0 check (failed >= 0),
  updated_at timestamptz not null default now(),
  primary key (bucket_start, flow),
  check (bucket_start = date_trunc('minute', bucket_start))
);

comment on table internal.critical_flow_outcome_buckets is
  'Data-minimized technical counters only; never stores actor, tenant, payload, token or free text.';

alter table internal.critical_flow_outcome_buckets enable row level security;
revoke all on internal.critical_flow_outcome_buckets from public, anon, authenticated;
grant select, insert, update, delete on internal.critical_flow_outcome_buckets to service_role;

create function internal.require_observability_service_role()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise insufficient_privilege using message = 'service_role_required';
  end if;
end;
$$;

create function internal.record_critical_flow_outcome(
  target_flow text,
  target_result text,
  occurred_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform internal.require_observability_service_role();
  if target_flow not in ('auth', 'checkout', 'messaging', 'critical_commands') then
    raise check_violation using message = 'invalid_observability_flow';
  end if;
  if target_result not in ('succeeded', 'failed') then
    raise check_violation using message = 'invalid_observability_result';
  end if;

  insert into internal.critical_flow_outcome_buckets(
    bucket_start, flow, succeeded, failed
  ) values (
    date_trunc('minute', occurred_at),
    target_flow,
    case when target_result = 'succeeded' then 1 else 0 end,
    case when target_result = 'failed' then 1 else 0 end
  )
  on conflict (bucket_start, flow) do update
    set succeeded = internal.critical_flow_outcome_buckets.succeeded + excluded.succeeded,
        failed = internal.critical_flow_outcome_buckets.failed + excluded.failed,
        updated_at = now();
end;
$$;

create function internal.get_critical_flow_ratios(window_end timestamptz default now())
returns table(
  flow text,
  succeeded bigint,
  failed bigint,
  attempts bigint,
  failure_rate_percent numeric,
  breached boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with allowed(flow) as (
    values ('auth'::text), ('checkout'), ('messaging'), ('critical_commands')
  ), totals as (
    select b.flow, sum(b.succeeded)::bigint as succeeded, sum(b.failed)::bigint as failed
    from internal.critical_flow_outcome_buckets b
    where b.bucket_start >= date_trunc('minute', window_end) - interval '4 minutes'
      and b.bucket_start <= date_trunc('minute', window_end)
    group by b.flow
  )
  select a.flow,
         coalesce(t.succeeded, 0),
         coalesce(t.failed, 0),
         coalesce(t.succeeded, 0) + coalesce(t.failed, 0),
         case when coalesce(t.succeeded, 0) + coalesce(t.failed, 0) = 0 then 0
              else round(100 * coalesce(t.failed, 0)::numeric /
                (coalesce(t.succeeded, 0) + coalesce(t.failed, 0)), 2)
         end,
         coalesce(t.failed, 0) > 0 and
           100 * coalesce(t.failed, 0)::numeric /
             nullif(coalesce(t.succeeded, 0) + coalesce(t.failed, 0), 0) >= 5
  from allowed a
  left join totals t using (flow)
  order by a.flow;
$$;

create function internal.purge_critical_flow_outcomes(retain_after timestamptz default now() - interval '30 days')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare removed bigint;
begin
  perform internal.require_observability_service_role();
  delete from internal.critical_flow_outcome_buckets where bucket_start < retain_after;
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function internal.require_observability_service_role() from public, anon, authenticated;
revoke all on function internal.record_critical_flow_outcome(text, text, timestamptz) from public, anon, authenticated;
revoke all on function internal.get_critical_flow_ratios(timestamptz) from public, anon, authenticated;
revoke all on function internal.purge_critical_flow_outcomes(timestamptz) from public, anon, authenticated;
grant execute on function internal.record_critical_flow_outcome(text, text, timestamptz) to service_role;
grant execute on function internal.get_critical_flow_ratios(timestamptz) to service_role;
grant execute on function internal.purge_critical_flow_outcomes(timestamptz) to service_role;

create function api.record_critical_flow_outcome(
  target_flow text,
  target_result text,
  occurred_at timestamptz default now()
)
returns void
language sql
security definer
set search_path = ''
as $$
  select internal.record_critical_flow_outcome(target_flow, target_result, occurred_at);
$$;

create function api.get_critical_flow_ratios(window_end timestamptz default now())
returns table(
  flow text,
  succeeded bigint,
  failed bigint,
  attempts bigint,
  failure_rate_percent numeric,
  breached boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select * from internal.get_critical_flow_ratios(window_end);
$$;

revoke all on function api.record_critical_flow_outcome(text, text, timestamptz) from public, anon, authenticated;
revoke all on function api.get_critical_flow_ratios(timestamptz) from public, anon, authenticated;
grant execute on function api.record_critical_flow_outcome(text, text, timestamptz) to service_role;
grant execute on function api.get_critical_flow_ratios(timestamptz) to service_role;
