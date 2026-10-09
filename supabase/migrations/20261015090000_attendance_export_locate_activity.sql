-- Attendance export: let the sync agent find the laget.se activity itself.
--
-- TEMPORARY FEATURE (schema attendance_export, removed by
-- supabase/removal/attendance_export_remove.sql). A sync may now be requested
-- without an activity link: the agent searches the team's laget.se calendar
-- for the same date and start time. Exactly one match -> the link is saved
-- and the sync continues to the preview. Otherwise -> 'needs_activity' with
-- the day's activities as candidates for the administrator to choose from.

alter table attendance_export.sync_jobs alter column external_activity_id drop not null;
alter table attendance_export.sync_jobs
 add column event_starts_at timestamptz,
 add column event_ends_at timestamptz,
 add column event_type text,
 add column event_timezone text,
 add column candidates jsonb check (candidates is null or jsonb_typeof(candidates) = 'array');
alter table attendance_export.sync_jobs drop constraint sync_jobs_state_check;
alter table attendance_export.sync_jobs add constraint sync_jobs_state_check check (state in
 ('queued', 'locating', 'previewing', 'awaiting_approval', 'approved', 'applying',
  'verified', 'failed', 'needs_activity', 'cancelled'));

drop index attendance_export.sync_jobs_one_active_idx;
create unique index sync_jobs_one_active_idx on attendance_export.sync_jobs(event_id, team_id, provider)
 where state in ('queued', 'locating', 'previewing', 'awaiting_approval', 'approved', 'applying');
drop index attendance_export.sync_jobs_pending_idx;
create index sync_jobs_pending_idx on attendance_export.sync_jobs(state, requested_at)
 where state in ('queued', 'locating', 'previewing', 'approved', 'applying');

create or replace function attendance_export.sync_job_json(job attendance_export.sync_jobs)
returns jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('id', job.id, 'state', job.state, 'external_activity_id', job.external_activity_id,
  'summary', job.summary, 'preview', job.preview, 'preview_sha256', job.preview_sha256,
  'result', job.result, 'message', job.message, 'candidates', job.candidates,
  'requested_at', job.requested_at, 'approved_at', job.approved_at,
  'finished_at', job.finished_at, 'updated_at', job.updated_at)
$$;

-- Same rules as before; without an activity link the payload carries
-- activityId '' and the agent locates the activity first.
create or replace function attendance_export.request_sync(target_event_id uuid, target_team_id uuid, target_provider text,
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
 if jsonb_typeof(new_payload) <> 'object'
  or (select array_agg(key order by key) from jsonb_object_keys(new_payload) key) <> array['activityId', 'participants']
  or new_payload->>'activityId' is distinct from coalesce(activity, '')
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
  and state in ('queued', 'locating', 'previewing', 'awaiting_approval', 'approved', 'applying');
 if active.id is not null then
  if active.state in ('locating', 'previewing', 'approved', 'applying') then
   raise invalid_parameter_value using message = 'sync_in_progress';
  end if;
  update attendance_export.sync_jobs set state = 'cancelled', payload = '{}'::jsonb,
   message = 'Ersatt av en ny synk.', finished_at = now(), updated_at = now()
  where id = active.id;
 end if;
 insert into attendance_export.sync_jobs(club_id, team_id, event_id, provider, external_activity_id, team_ref,
  payload, payload_sha256, summary, requested_by, event_starts_at, event_ends_at, event_type, event_timezone)
 values (club, target_team_id, target_event_id, target_provider, activity, setting.external_team_ref,
  new_payload, encode(sha256(convert_to(new_payload::text, 'UTF8')), 'hex'),
  coalesce(new_summary, '{}'::jsonb), auth.uid(), event_row.starts_at, event_row.ends_at,
  event_row.event_type, event_row.timezone)
 returning * into job;
 insert into audit.command_events(club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
 values (club, auth.uid(), 'attendance_export.sync.request', 'event', target_event_id, 1,
  jsonb_build_object('provider', target_provider, 'team_id', target_team_id, 'job_id', job.id,
   'locate', activity is null));
 return attendance_export.sync_job_json(job);
end$$;

create or replace function attendance_export.agent_claim_job()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
 select * into job from attendance_export.sync_jobs candidate
 where (candidate.state in ('queued', 'approved')
   or (candidate.state in ('locating', 'previewing', 'applying') and candidate.claimed_at < now() - interval '10 minutes'))
  and internal.actor_can_manage_attendance(candidate.event_id)
 order by candidate.requested_at
 limit 1 for update skip locked;
 if job.id is null then return null; end if;
 update attendance_export.sync_jobs set
  state = case
   when job.state in ('approved', 'applying') then 'applying'
   when job.external_activity_id is null then 'locating'
   else 'previewing' end,
  claimed_by = auth.uid(), claimed_at = now(), updated_at = now()
 where id = job.id returning * into job;
 return jsonb_build_object('id', job.id,
  'phase', case job.state when 'locating' then 'locate' when 'previewing' then 'preview' else 'apply' end,
  'team_ref', job.team_ref, 'external_activity_id', job.external_activity_id, 'payload', job.payload,
  'approved_preview_sha256', case when job.state = 'applying' then job.preview_sha256 end,
  'event', jsonb_build_object('starts_at', job.event_starts_at, 'ends_at', job.event_ends_at,
   'type', job.event_type, 'timezone', coalesce(job.event_timezone, 'Europe/Stockholm')));
end$$;

create or replace function attendance_export.lock_job_for_agent(target_job_id uuid)
returns attendance_export.sync_jobs language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 select * into job from attendance_export.sync_jobs where id = target_job_id for update;
 if job.id is null or auth.uid() is null or job.claimed_by is distinct from auth.uid()
  or job.state not in ('locating', 'previewing', 'applying') then
  raise insufficient_privilege using message = 'not_claimed';
 end if;
 return job;
end$$;

create or replace function attendance_export.agent_release_job(target_job_id uuid, new_message text)
returns void language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 job := attendance_export.lock_job_for_agent(target_job_id);
 update attendance_export.sync_jobs set state = case when job.state in ('locating', 'previewing') then 'queued' else 'approved' end,
  claimed_by = null, claimed_at = null, message = left(new_message, 2000), updated_at = now()
 where id = target_job_id;
end$$;

-- Agent: exactly one matching activity was found. Saves the activity link
-- (reused by later exports) and continues the same job to the preview.
create function attendance_export.agent_report_located(target_job_id uuid, found_activity_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype; existing text; new_payload jsonb;
begin
 job := attendance_export.lock_job_for_agent(target_job_id);
 if job.state <> 'locating' then raise invalid_parameter_value using message = 'not_locating'; end if;
 if found_activity_id is null or found_activity_id !~ '^[0-9]{1,20}$' then
  raise invalid_parameter_value using message = 'invalid_external_activity_id';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('attendance-export-team:' || job.team_id::text, 0));
 select external_activity_id into existing from attendance_export.activity_links
 where event_id = job.event_id and team_id = job.team_id and provider = job.provider;
 if existing is not null and existing <> found_activity_id then
  raise invalid_parameter_value using message = 'activity_link_changed';
 end if;
 if exists (select 1 from attendance_export.activity_links where team_id = job.team_id
   and provider = job.provider and external_activity_id = found_activity_id and event_id <> job.event_id) then
  raise unique_violation using message = 'external_activity_taken';
 end if;
 if existing is null then
  insert into attendance_export.activity_links(club_id, event_id, team_id, provider, external_activity_id, changed_by)
  values (job.club_id, job.event_id, job.team_id, job.provider, found_activity_id, auth.uid());
 end if;
 new_payload := jsonb_set(job.payload, '{activityId}', to_jsonb(found_activity_id));
 update attendance_export.sync_jobs set external_activity_id = found_activity_id, payload = new_payload,
  payload_sha256 = encode(sha256(convert_to(new_payload::text, 'UTF8')), 'hex'),
  state = 'previewing', message = null, updated_at = now()
 where id = target_job_id;
end$$;

-- Agent: no single match. The administrator chooses among the candidates
-- (activities on the same day) or pastes the link.
create function attendance_export.agent_report_not_found(target_job_id uuid, new_message text, new_candidates jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare job attendance_export.sync_jobs%rowtype;
begin
 job := attendance_export.lock_job_for_agent(target_job_id);
 if job.state <> 'locating' then raise invalid_parameter_value using message = 'not_locating'; end if;
 if new_candidates is not null and (jsonb_typeof(new_candidates) <> 'array' or jsonb_array_length(new_candidates) > 30) then
  raise invalid_parameter_value using message = 'invalid_candidates';
 end if;
 update attendance_export.sync_jobs set state = 'needs_activity', message = left(new_message, 2000),
  candidates = coalesce(new_candidates, '[]'::jsonb), payload = '{}'::jsonb,
  finished_at = now(), updated_at = now()
 where id = target_job_id;
end$$;

create function api.attendance_export_agent_report_located(job_id uuid, external_activity_id text)
returns void language sql security invoker set search_path = '' as
$$select attendance_export.agent_report_located(job_id, external_activity_id)$$;
create function api.attendance_export_agent_report_not_found(job_id uuid, message text, candidates jsonb)
returns void language sql security invoker set search_path = '' as
$$select attendance_export.agent_report_not_found(job_id, message, candidates)$$;

revoke all on function attendance_export.agent_report_located(uuid, text),
 attendance_export.agent_report_not_found(uuid, text, jsonb),
 api.attendance_export_agent_report_located(uuid, text),
 api.attendance_export_agent_report_not_found(uuid, text, jsonb)
 from public, anon;
revoke all on function attendance_export.sync_job_json(attendance_export.sync_jobs),
 attendance_export.lock_job_for_agent(uuid) from public, anon, authenticated;
grant execute on function attendance_export.agent_report_located(uuid, text),
 attendance_export.agent_report_not_found(uuid, text, jsonb),
 api.attendance_export_agent_report_located(uuid, text),
 api.attendance_export_agent_report_not_found(uuid, text, jsonb)
 to authenticated;

insert into internal.migration_provenance(migration_name, source_kind, source_reference)
values ('20261015090000_attendance_export_locate_activity', 'greenfield',
 'Temporary laget.se sync: agent locates the laget.se activity in the team calendar');
notify pgrst, 'reload schema';
