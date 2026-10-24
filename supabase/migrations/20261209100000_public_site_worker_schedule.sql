-- The public site's publication worker, run from the database every minute
-- (decided 2026-10-24), like the support e-mail and notification workers.
-- The worker (public-site/app/api/internal/cache-invalidation) projects
-- published clubs and teams and refreshes the pages they change; until now
-- it ran only when started by hand, so a published club stayed unseen.
-- Where the site is and the worker's token are read from Vault
-- (public_site_worker_url, public_site_worker_token); the same token is the
-- site's CACHE_INVALIDATION_SECRET. A project without them, as production
-- until it is provisioned, calls nothing. The site is only woken when a job
-- waits for it, by the same conditions the worker claims jobs by.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- A club or team to project (internal.process_publication_projection_batch)
-- or pages to refresh (internal.claim_publication_delivery).
create or replace function internal.public_site_worker_has_work()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from internal.publication_projection_jobs job
    where (job.action in ('rebuild', 'remove') and job.aggregate_type in ('club', 'team')
        and job.state in ('pending', 'failed') and job.available_at <= now() and job.attempts < 20)
      or (job.state = 'awaiting_invalidation'
        and (job.invalidation_claimed_at is null or job.invalidation_claimed_at < now() - interval '10 minutes'))
      or (job.action = 'invalidate' and job.state in ('pending', 'failed') and job.available_at <= now() and job.attempts < 20)
  )
$$;

create or replace function internal.invoke_public_site_worker()
returns bigint language plpgsql security definer set search_path = '' as $$
declare site_url text; worker_token text; request_id bigint;
begin
  select decrypted_secret into site_url from vault.decrypted_secrets where name = 'public_site_worker_url' limit 1;
  select decrypted_secret into worker_token from vault.decrypted_secrets where name = 'public_site_worker_token' limit 1;
  if nullif(site_url, '') is null or nullif(worker_token, '') is null then
    raise warning 'Public site worker skipped: Vault secrets public_site_worker_url/public_site_worker_token are not configured';
    return null;
  end if;
  if not internal.public_site_worker_has_work() then return null; end if;
  select net.http_post(
    url := rtrim(site_url, '/') || '/api/internal/cache-invalidation',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || worker_token),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000)
  into request_id;
  return request_id;
end;$$;

revoke all on function internal.public_site_worker_has_work(), internal.invoke_public_site_worker()
  from public, anon, authenticated;

do $$
declare existing_job_id bigint;
begin
  select jobid into existing_job_id from cron.job where jobname = 'public-site-worker' limit 1;
  if existing_job_id is not null then perform cron.unschedule(existing_job_id); end if;
end $$;
select cron.schedule('public-site-worker', '* * * * *',
  $cron$ select internal.invoke_public_site_worker(); $cron$);

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261209100000_public_site_worker_schedule', 'greenfield',
  'Minute schedule for the public site publication worker, token shared through Vault and App Hosting'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261209100000_public_site_worker_schedule');
