-- Failed-sign-in limits for the auth-password-sign-in Edge Function.
--
-- The function calls Supabase Auth from its own address, so Auth's per-IP
-- limits see one shared client. The function therefore counts failed
-- attempts itself, in 15-minute windows, per e-mail address (the main
-- protection; it cannot be spoofed) and per client address (secondary; the
-- address comes from a proxy header). Only HMAC hashes are stored, never the
-- address or e-mail. A successful sign-in clears that e-mail's count.
-- Service role only: no grants to anon or authenticated.

create table if not exists internal.sign_in_failures (
  key_hash bytea not null check (octet_length(key_hash) = 32),
  key_kind text not null check (key_kind in ('email', 'ip')),
  window_started_at timestamptz not null,
  failures integer not null default 1 check (failures between 1 and 1000000),
  primary key (key_hash, key_kind, window_started_at)
);
create index if not exists sign_in_failures_window_idx
  on internal.sign_in_failures (window_started_at);
alter table internal.sign_in_failures enable row level security;
revoke all on internal.sign_in_failures from public, anon, authenticated;

create or replace function internal.sign_in_window()
returns timestamptz language sql stable set search_path = '' as $$
  select pg_catalog.date_bin('15 minutes', pg_catalog.now(), timestamptz '2000-01-01 00:00:00+00')
$$;

-- Limits per 15-minute window: 10 failures per e-mail, 50 per address.
create or replace function internal.sign_in_attempt_allowed(email_hash bytea, ip_hash bytea)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select failure.failures from internal.sign_in_failures failure
      where failure.key_hash = email_hash and failure.key_kind = 'email'
        and failure.window_started_at = internal.sign_in_window()), 0) < 10
    and coalesce((select failure.failures from internal.sign_in_failures failure
      where failure.key_hash = ip_hash and failure.key_kind = 'ip'
        and failure.window_started_at = internal.sign_in_window()), 0) < 50
$$;

create or replace function internal.record_sign_in_result(email_hash bytea, ip_hash bytea, succeeded boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare current_window timestamptz := internal.sign_in_window();
begin
  if octet_length(email_hash) <> 32 or octet_length(ip_hash) <> 32 then
    raise invalid_parameter_value using message = 'invalid_hash';
  end if;
  if succeeded then
    delete from internal.sign_in_failures where key_hash = email_hash and key_kind = 'email';
  else
    insert into internal.sign_in_failures (key_hash, key_kind, window_started_at)
    values (email_hash, 'email', current_window), (ip_hash, 'ip', current_window)
    on conflict (key_hash, key_kind, window_started_at)
    do update set failures = internal.sign_in_failures.failures + 1;
  end if;
  -- Old windows are of no use; keep the table small.
  delete from internal.sign_in_failures where window_started_at < pg_catalog.now() - interval '1 day';
end;$$;

create or replace function api.sign_in_attempt_allowed(email_hash text, ip_hash text)
returns boolean language sql stable security invoker set search_path = '' as $$
  select internal.sign_in_attempt_allowed(pg_catalog.decode(email_hash, 'hex'), pg_catalog.decode(ip_hash, 'hex'))
$$;

create or replace function api.record_sign_in_result(email_hash text, ip_hash text, succeeded boolean)
returns void language sql security invoker set search_path = '' as $$
  select internal.record_sign_in_result(pg_catalog.decode(email_hash, 'hex'), pg_catalog.decode(ip_hash, 'hex'), succeeded)
$$;

revoke all on function internal.sign_in_window(), internal.sign_in_attempt_allowed(bytea, bytea),
  internal.record_sign_in_result(bytea, bytea, boolean), api.sign_in_attempt_allowed(text, text),
  api.record_sign_in_result(text, text, boolean) from public, anon, authenticated;
grant usage on schema internal to service_role;
grant execute on function internal.sign_in_window(), internal.sign_in_attempt_allowed(bytea, bytea),
  internal.record_sign_in_result(bytea, bytea, boolean), api.sign_in_attempt_allowed(text, text),
  api.record_sign_in_result(text, text, boolean) to service_role;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261022090000_sign_in_attempt_limits', 'greenfield',
  'Failed-sign-in limits per e-mail and address for auth-password-sign-in'
where not exists (select 1 from internal.migration_provenance
  where migration_name = '20261022090000_sign_in_attempt_limits');
notify pgrst, 'reload schema';
