begin;

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- The worker is deliberately not reachable with a user session. A dedicated
-- random token is stored independently in Edge Function secrets and Vault.
-- The migration only contains the lookup names, never the token itself.
create or replace function internal.invoke_support_email_worker()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  project_url text;
  worker_token text;
  request_id bigint;
begin
  select decrypted_secret
    into project_url
  from vault.decrypted_secrets
  where name = 'project_url'
  limit 1;

  select decrypted_secret
    into worker_token
  from vault.decrypted_secrets
  where name = 'support_email_worker_token'
  limit 1;

  if nullif(project_url, '') is null or nullif(worker_token, '') is null then
    raise warning
      'Support email worker skipped: Vault secrets project_url/support_email_worker_token are not configured';
    return null;
  end if;

  select net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/support-email-worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-teamzone-worker-token', worker_token
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 15000
  )
  into request_id;

  return request_id;
end
$$;

revoke all on function internal.invoke_support_email_worker()
  from public, anon, authenticated;

do $$
declare
  existing_job_id bigint;
begin
  select jobid
    into existing_job_id
  from cron.job
  where jobname = 'support-email-worker'
  limit 1;

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;
end
$$;

select cron.schedule(
  'support-email-worker',
  '* * * * *',
  $cron$
    select internal.invoke_support_email_worker();
  $cron$
);

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
)
values (
  '20261003134430_schedule_support_email_worker',
  'greenfield',
  'Minute worker schedule with a dedicated secret shared through Supabase Vault'
);

commit;
