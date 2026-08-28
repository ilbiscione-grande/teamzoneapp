-- Opaque sb_secret_* keys are mapped to the service_role database role by the
-- Data API, but they do not carry the legacy request.jwt.claim.role setting.
-- EXECUTE remains revoked from PUBLIC, anon and authenticated and granted only
-- to service_role, so the explicit JWT-claim check was both redundant and
-- incompatible with the current server-key model.

create or replace function internal.record_critical_flow_outcome(
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

create or replace function internal.purge_critical_flow_outcomes(
  retain_after timestamptz default now() - interval '30 days'
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare removed bigint;
begin
  delete from internal.critical_flow_outcome_buckets
  where bucket_start < retain_after;
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function internal.record_critical_flow_outcome(text, text, timestamptz)
  from public, anon, authenticated;
revoke all on function internal.purge_critical_flow_outcomes(timestamptz)
  from public, anon, authenticated;
grant execute on function internal.record_critical_flow_outcome(text, text, timestamptz)
  to service_role;
grant execute on function internal.purge_critical_flow_outcomes(timestamptz)
  to service_role;
