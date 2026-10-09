-- Attendance export: sync queue for the local laget.se sync agent.
--
-- TEMPORARY FEATURE (see 20261013090000_attendance_export_laget_se.sql and
-- supabase/removal/attendance_export_remove.sql). Teamzone still never holds
-- laget.se credentials: the agent runs on the administrator's own computer
-- with its own laget.se session and works through these RPCs as that
-- Teamzone user. Flow: request (app) -> preview (agent) -> approve (app)
-- -> apply + verify (agent) -> verified/failed.

create table attendance_export.sync_jobs (
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 team_id uuid not null,
 event_id uuid not null,
 provider text not null check (provider in ('laget_se')),
 external_activity_id text not null check (external_activity_id ~ '^[0-9]{1,20}$'),
 -- The team's path segment on admin.laget.se, e.g. EksjoFotbollJ18.
 team_ref text not null check (team_ref ~ '^[A-Za-z0-9_-]{1,100}$'),
 -- The laget.se file contract; cleared ('{}') when the job ends.
 payload jsonb not null check (jsonb_typeof(payload) = 'object'),
 payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
 summary jsonb not null default '{}'::jsonb check (jsonb_typeof(summary) = 'object'),
 state text not null default 'queued' check (state in
  ('queued', 'previewing', 'awaiting_approval', 'approved', 'applying', 'verified', 'failed', 'cancelled')),
 -- What the agent read on laget.se and plans to change (shown for approval).
 preview jsonb check (preview is null or jsonb_typeof(preview) = 'object'),
 preview_sha256 text check (preview_sha256 is null or preview_sha256 ~ '^[0-9a-f]{64}$'),
 result jsonb check (result is null or jsonb_typeof(result) = 'object'),
 message text check (message is null or length(message) <= 2000),
 requested_by uuid not null references core.profiles(id),
 requested_at timestamptz not null default now(),
 approved_by uuid references core.profiles(id),
 approved_at timestamptz,
 claimed_by uuid references core.profiles(id),
 claimed_at timestamptz,
 finished_at timestamptz,
 updated_at timestamptz not null default now(),
 foreign key (event_id, club_id) references core.events(id, club_id) on delete cascade,
 foreign key (team_id, club_id) references core.teams(id, club_id) on delete cascade
);
create unique index sync_jobs_one_active_idx on attendance_export.sync_jobs(event_id, team_id, provider)
 where state in ('queued', 'previewing', 'awaiting_approval', 'approved', 'applying');
create index sync_jobs_pending_idx on attendance_export.sync_jobs(state, requested_at)
 where state in ('queued', 'previewing', 'approved', 'applying');
create index sync_jobs_event_idx on attendance_export.sync_jobs(event_id, team_id, provider, requested_at desc);

-- Liveness of each user's agent, so the app can say whether it is running.
create table attendance_export.agents (
 profile_id uuid primary key references core.profiles(id) on delete cascade,
 last_seen_at timestamptz not null default now(),
 laget_session_ok boolean,
 agent_version text check (agent_version is null or length(agent_version) <= 40)
);

alter table attendance_export.sync_jobs enable row level security;
alter table attendance_export.agents enable row level security;
revoke all on attendance_export.sync_jobs, attendance_export.agents from public, anon, authenticated;

create function attendance_export.sync_job_json(job attendance_export.sync_jobs)
returns jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('id', job.id, 'state', job.state, 'external_activity_id', job.external_activity_id,
  'summary', job.summary, 'preview', job.preview, 'preview_sha256', job.preview_sha256,
  'result', job.result, 'message', job.message, 'requested_at', job.requested_at,
  'approved_at', job.approved_at, 'finished_at', job.finished_at, 'updated_at', job.updated_at)
$$;

-- Export context now also carries the sync jobs and the caller's agent.
create or replace function attendance_export.get_export_context(target_event_id uuid, target_team_id uuid, target_provider text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare club uuid; event_row core.events%rowtype; setting attendance_export.team_integrations%rowtype;
begin
 club := attendance_export.assert_event_exporter(target_event_id, target_team_id);
 select * into event_row from core.events where id = target_event_id;
 select * into setting from attendance_export.team_integrations
 where team_id = target_team_id and provider = target_provider;
 return jsonb_build_object(
  'event_id', event_row.id, 'team_id', target_team_id,
  'team_name', (select name from core.teams where id = target_team_id),
  'provider', target_provider,
  'enabled', coalesce(setting.enabled, false),
  'external_team_ref', setting.external_team_ref,
  'activity_link', (select jsonb_build_object('external_activity_id', link.external_activity_id,
    'team_id', link.team_id, 'revision', link.revision)
   from attendance_export.activity_links link
   where link.event_id = target_event_id and link.team_id = target_team_id and link.provider = target_provider),
  'team_roster', coalesce((select jsonb_agg(jsonb_build_object(
    'person_id', assignment.club_person_id, 'role_package', assignment.role_package))
   from core.assignments assignment
   where assignment.club_id = club and assignment.team_id = target_team_id
    and assignment.state = 'active' and assignment.role_package in ('player', 'leader')
    and assignment.starts_at <= event_row.starts_at
    and (assignment.ends_at is null or assignment.ends_at > event_row.starts_at)), '[]'::jsonb),
  'links', attendance_export.links_json(target_team_id, target_provider),
  'exports', coalesce((select jsonb_agg(jsonb_build_object('id', export_row.id, 'state', export_row.state,
    'external_activity_id', export_row.external_activity_id, 'summary', export_row.summary,
    'payload_sha256', export_row.payload_sha256, 'error_code', export_row.error_code,
    'created_at', export_row.created_at, 'verified_at', export_row.verified_at)
    order by export_row.created_at desc)
   from (select * from attendance_export.exports
    where event_id = target_event_id and team_id = target_team_id and provider = target_provider
    order by created_at desc limit 10) export_row), '[]'::jsonb),
  'sync_jobs', coalesce((select jsonb_agg(attendance_export.sync_job_json(job) order by job.requested_at desc)
   from (select * from attendance_export.sync_jobs
    where event_id = target_event_id and team_id = target_team_id and provider = target_provider
    order by requested_at desc limit 5) job), '[]'::jsonb),
  'agent', (select jsonb_build_object('last_seen_at', agent.last_seen_at,
    'laget_session_ok', agent.laget_session_ok, 'agent_version', agent.agent_version)
   from attendance_export.agents agent where agent.profile_id = auth.uid()));
end$$;

-- App: queue a sync. Same rules as creating a file, plus the payload must
-- only contain people linked in this team.
create function attendance_export.request_sync(target_event_id uuid, target_team_id uuid, target_provider text,
 new_payload jsonb, new_summary jsonb, new_confirmed_complete boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare club uuid; event_row core.events%rowtype; setting attendance_export.team_integrations%rowtype;
 activity text; active attendance_export.sync_jobs%rowtype; job attendance_export.sync_jobs%rowtype;
begin
 club := attendance_export.assert_event_exporter(target_event_id, target_team_id);
 perform pg_advisory_xact_lock(hashtextextended('attendance-export-sync:' || target_event_id::text || target_team_id::text, 0));
 select * into event_row from core.events where id = target_event_id;
 select * into setting from attendance_export.team_integrations
 where team_id = target_team_id and provider = target_provider;
 if not coalesce(setting.enabled, false) then raise invalid_parameter_value using message = 'integration_disabled'; end if;
 if setting.external_team_ref is null or setting.external_team_ref !~ '^[A-Za-z0-9_-]{1,100}$' then
  raise invalid_parameter_value using message = 'missing_team_ref';
 end if;
 if event_row.state not in ('scheduled', 'completed') or event_row.ends_at > now() then
  raise invalid_parameter_value using message = 'event_not_ended';
 end if;
 if not coalesce(new_confirmed_complete, false) then raise invalid_parameter_value using message = 'not_confirmed'; end if;
 select external_activity_id into activity from attendance_export.activity_links
 where event_id = target_event_id and team_id = target_team_id and provider = target_provider;
 if activity is null then raise invalid_parameter_value using message = 'missing_activity_id'; end if;
 if jsonb_typeof(new_payload) <> 'object'
  or (select array_agg(key order by key) from jsonb_object_keys(new_payload) key) <> array['activityId', 'participants']
  or new_payload->>'activityId' is distinct from activity
  or jsonb_typeof(new_payload->'participants') <> 'array' then
  raise invalid_parameter_value using message = 'invalid_payload';
 end if;
 if exists (select 1 from jsonb_array_elements(new_payload->'participants') p
   where jsonb_typeof(p) <> 'object'
    or (select count(*) from jsonb_object_keys(p)) <> 4
    or jsonb_typeof(p->'name') <> 'string' or length(btrim(p->>'name')) = 0
    or coalesce(p->>'role', '') not in ('player', 'leader')
    or jsonb_typeof(p->'present') <> 'boolean'
    or jsonb_typeof(p->'id') <> 'string' or p->>'id' !~ '^[0-9]{1,20}$') then
  raise invalid_parameter_value using message = 'invalid_payload';
 end if;
 if exists (select 1 from jsonb_array_elements(new_payload->'participants') p
   where not exists (select 1 from attendance_export.member_links link
    where link.team_id = target_team_id and link.provider = target_provider
     and link.external_id = p->>'id' and link.external_role = p->>'role')) then
  raise invalid_parameter_value using message = 'unknown_member';
 end if;
 select * into active from attendance_export.sync_jobs
 where event_id = target_event_id and team_id = target_team_id and provider = target_provider
  and state in ('queued', 'previewing', 'awaiting_approval', 'approved', 'applying');
 if active.id is not null then
  if active.state in ('previewing', 'approved', 'applying') then
   raise invalid_parameter_value using message = 'sync_in_progress';
  end if;
  update attendance_export.sync_jobs set state = 'cancelled', payload = '{}'::jsonb,
   message = 'Ersatt av en ny synk.', finished_at = now(), updated_at = now()
  where id = active.id;
 end if;
 insert into attendance_export.sync_jobs(club_id, team_id, event_id, provider, external_activity_id, team_ref,
  payload, payload_sha256, summary, requested_by)
 values (club, target_team_id, target_event_id, target_provider, activity, setting.external_team_ref,
  new_payload, encode(sha256(convert_to(new_payload::text, 'UTF8')), 'hex'),
  coalesce(new_summary, '{}'::jsonb), auth.uid())
 returning * into job;
 insert into audit.command_events(club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
 values (club, auth.uid(), 'attendance_export.sync.request', 'event', target_event_id, 1,
  jsonb_build_object('provider', target_provider, 'team_id', target_team_id, 'job_id', job.id));
 return attendance_export.sync_job_json(job);
end$$;

create function attendance_export.lock_job_for_exporter(target_job_id uuid)
returns attendance_export.sync_jobs language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 select * into job from attendance_export.sync_jobs where id = target_job_id for update;
 if job.id is null then raise insufficient_privilege using message = 'not_found'; end if;
 perform attendance_export.assert_event_exporter(job.event_id, job.team_id);
 return job;
end$$;

-- App: approve exactly the preview that was shown.
create function attendance_export.approve_sync(target_job_id uuid, shown_preview_sha256 text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 job := attendance_export.lock_job_for_exporter(target_job_id);
 if job.state <> 'awaiting_approval' or job.preview_sha256 is distinct from shown_preview_sha256 then
  raise serialization_failure using message = 'preview_changed';
 end if;
 update attendance_export.sync_jobs set state = 'approved', approved_by = auth.uid(), approved_at = now(),
  claimed_by = null, claimed_at = null, updated_at = now()
 where id = target_job_id returning * into job;
 insert into audit.command_events(club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
 values (job.club_id, auth.uid(), 'attendance_export.sync.approve', 'event', job.event_id, 1,
  jsonb_build_object('job_id', job.id, 'preview_sha256', job.preview_sha256));
 return attendance_export.sync_job_json(job);
end$$;

create function attendance_export.cancel_sync(target_job_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 job := attendance_export.lock_job_for_exporter(target_job_id);
 if job.state not in ('queued', 'awaiting_approval') then
  raise invalid_parameter_value using message = 'sync_in_progress';
 end if;
 update attendance_export.sync_jobs set state = 'cancelled', payload = '{}'::jsonb, finished_at = now(),
  updated_at = now(), message = 'Avbruten i Teamzone.'
 where id = target_job_id returning * into job;
 return attendance_export.sync_job_json(job);
end$$;

-- Agent: liveness.
create function attendance_export.agent_heartbeat(new_laget_session_ok boolean, new_agent_version text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
 insert into attendance_export.agents(profile_id, last_seen_at, laget_session_ok, agent_version)
 values (auth.uid(), now(), new_laget_session_ok, left(new_agent_version, 40))
 on conflict (profile_id) do update set last_seen_at = now(), laget_session_ok = excluded.laget_session_ok,
  agent_version = excluded.agent_version;
end$$;

-- Agent: take the next job the user may handle. Claims older than ten
-- minutes are considered abandoned (agent closed mid-job) and are retaken;
-- re-planning against the live page makes that safe.
create function attendance_export.agent_claim_job()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
 select * into job from attendance_export.sync_jobs candidate
 where (candidate.state in ('queued', 'approved')
   or (candidate.state in ('previewing', 'applying') and candidate.claimed_at < now() - interval '10 minutes'))
  and internal.actor_can_manage_attendance(candidate.event_id)
 order by candidate.requested_at
 limit 1 for update skip locked;
 if job.id is null then return null; end if;
 update attendance_export.sync_jobs set
  state = case when job.state in ('queued', 'previewing') then 'previewing' else 'applying' end,
  claimed_by = auth.uid(), claimed_at = now(), updated_at = now()
 where id = job.id returning * into job;
 return jsonb_build_object('id', job.id, 'phase', case when job.state = 'previewing' then 'preview' else 'apply' end,
  'team_ref', job.team_ref, 'external_activity_id', job.external_activity_id, 'payload', job.payload,
  'approved_preview_sha256', case when job.state = 'applying' then job.preview_sha256 end);
end$$;

create function attendance_export.lock_job_for_agent(target_job_id uuid)
returns attendance_export.sync_jobs language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 select * into job from attendance_export.sync_jobs where id = target_job_id for update;
 if job.id is null or auth.uid() is null or job.claimed_by is distinct from auth.uid()
  or job.state not in ('previewing', 'applying') then
  raise insufficient_privilege using message = 'not_claimed';
 end if;
 return job;
end$$;

-- Agent: a plan to approve (also used when the page changed after approval).
create function attendance_export.agent_report_preview(target_job_id uuid, new_preview jsonb, new_preview_sha256 text)
returns void language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 job := attendance_export.lock_job_for_agent(target_job_id);
 if jsonb_typeof(new_preview) <> 'object' or new_preview_sha256 !~ '^[0-9a-f]{64}$' then
  raise invalid_parameter_value using message = 'invalid_preview';
 end if;
 update attendance_export.sync_jobs set state = 'awaiting_approval', preview = new_preview,
  preview_sha256 = new_preview_sha256, approved_by = null, approved_at = null,
  claimed_by = null, claimed_at = null, updated_at = now(),
  message = case when job.state = 'applying' then 'laget.se har ändrats sedan förhandsgranskningen. Godkänn igen.' end
 where id = target_job_id;
end$$;

-- Agent: give the job back (e.g. the laget.se session expired).
create function attendance_export.agent_release_job(target_job_id uuid, new_message text)
returns void language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 job := attendance_export.lock_job_for_agent(target_job_id);
 update attendance_export.sync_jobs set state = case when job.state = 'previewing' then 'queued' else 'approved' end,
  claimed_by = null, claimed_at = null, message = left(new_message, 2000), updated_at = now()
 where id = target_job_id;
end$$;

-- Agent: final outcome after read-back verification.
create function attendance_export.agent_report_result(target_job_id uuid, new_ok boolean, new_message text,
 new_result jsonb, new_preview jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 job := attendance_export.lock_job_for_agent(target_job_id);
 update attendance_export.sync_jobs set state = case when new_ok then 'verified' else 'failed' end,
  message = left(new_message, 2000), result = coalesce(new_result, '{}'::jsonb),
  preview = coalesce(new_preview, preview), payload = '{}'::jsonb,
  finished_at = now(), updated_at = now()
 where id = target_job_id;
 if new_ok then
  insert into attendance_export.exports(club_id, team_id, event_id, provider, state, external_activity_id,
   summary, confirmed_complete, payload_sha256, created_by, verified_at, verification_note)
  values (job.club_id, job.team_id, job.event_id, job.provider, 'verified', job.external_activity_id,
   job.summary, true, job.payload_sha256, job.requested_by, now(), left(new_message, 500));
 end if;
end$$;

create function api.attendance_export_request_sync(event_id uuid, team_id uuid, provider text, payload jsonb,
 summary jsonb, confirmed_complete boolean)
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.request_sync(event_id, team_id, provider, payload, summary, confirmed_complete)$$;
create function api.attendance_export_approve_sync(job_id uuid, preview_sha256 text)
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.approve_sync(job_id, preview_sha256)$$;
create function api.attendance_export_cancel_sync(job_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.cancel_sync(job_id)$$;
create function api.attendance_export_agent_heartbeat(laget_session_ok boolean, agent_version text)
returns void language sql security invoker set search_path = '' as
$$select attendance_export.agent_heartbeat(laget_session_ok, agent_version)$$;
create function api.attendance_export_agent_claim_job()
returns jsonb language sql security invoker set search_path = '' as
$$select attendance_export.agent_claim_job()$$;
create function api.attendance_export_agent_report_preview(job_id uuid, preview jsonb, preview_sha256 text)
returns void language sql security invoker set search_path = '' as
$$select attendance_export.agent_report_preview(job_id, preview, preview_sha256)$$;
create function api.attendance_export_agent_release_job(job_id uuid, message text)
returns void language sql security invoker set search_path = '' as
$$select attendance_export.agent_release_job(job_id, message)$$;
create function api.attendance_export_agent_report_result(job_id uuid, ok boolean, message text, result jsonb, preview jsonb)
returns void language sql security invoker set search_path = '' as
$$select attendance_export.agent_report_result(job_id, ok, message, result, preview)$$;

revoke all on all functions in schema attendance_export from public, anon, authenticated;
grant execute on function attendance_export.get_team_integration(uuid, text),
 attendance_export.set_team_integration(uuid, text, boolean, text, bigint),
 attendance_export.save_member_link(uuid, text, uuid, text, text, text, bigint),
 attendance_export.delete_member_link(uuid, text, uuid, bigint),
 attendance_export.get_export_context(uuid, uuid, text),
 attendance_export.set_activity_link(uuid, uuid, text, text, bigint),
 attendance_export.record_export(uuid, uuid, text, text, text, jsonb, boolean, text, text),
 attendance_export.request_sync(uuid, uuid, text, jsonb, jsonb, boolean),
 attendance_export.approve_sync(uuid, text),
 attendance_export.cancel_sync(uuid),
 attendance_export.agent_heartbeat(boolean, text),
 attendance_export.agent_claim_job(),
 attendance_export.agent_report_preview(uuid, jsonb, text),
 attendance_export.agent_release_job(uuid, text),
 attendance_export.agent_report_result(uuid, boolean, text, jsonb, jsonb)
 to authenticated;
revoke all on function api.attendance_export_request_sync(uuid, uuid, text, jsonb, jsonb, boolean),
 api.attendance_export_approve_sync(uuid, text),
 api.attendance_export_cancel_sync(uuid),
 api.attendance_export_agent_heartbeat(boolean, text),
 api.attendance_export_agent_claim_job(),
 api.attendance_export_agent_report_preview(uuid, jsonb, text),
 api.attendance_export_agent_release_job(uuid, text),
 api.attendance_export_agent_report_result(uuid, boolean, text, jsonb, jsonb)
 from public, anon;
grant execute on function api.attendance_export_request_sync(uuid, uuid, text, jsonb, jsonb, boolean),
 api.attendance_export_approve_sync(uuid, text),
 api.attendance_export_cancel_sync(uuid),
 api.attendance_export_agent_heartbeat(boolean, text),
 api.attendance_export_agent_claim_job(),
 api.attendance_export_agent_report_preview(uuid, jsonb, text),
 api.attendance_export_agent_release_job(uuid, text),
 api.attendance_export_agent_report_result(uuid, boolean, text, jsonb, jsonb)
 to authenticated;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values ('20261014090000_attendance_export_sync_agent', 'greenfield',
 'Temporary laget.se sync queue for the local sync agent (schema attendance_export)');
notify pgrst, 'reload schema';
