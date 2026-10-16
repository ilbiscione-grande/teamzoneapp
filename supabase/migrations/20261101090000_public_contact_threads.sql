-- PUB-14 (decided 2026-10-16): messages from the club site reach the club
-- and its teams, as two-way threads.
--
-- * A message to a club goes to its administrators (club.memberships.manage);
--   to a team, to the team's roster managers (team.roster.manage), or the
--   club's administrators when the team has none. Club administrators can
--   read their teams' threads too.
-- * Recipients see the thread in the app, answer there and mark it handled.
--   Answers are sent by contact-email-worker from a TeamZone address with
--   the club's name, so no leader's own address is ever shown. The sender's
--   e-mail replies come back through contact-inbound (signed by Resend,
--   reply address bound to the thread with an HMAC, sender address and
--   DMARC checked) and are added with internal.receive_contact_email.
-- * Recipients get a notification with only type and club or team.
-- * Content is erased 30 days after the thread's last activity; the
--   retention job now runs daily (it never ran before).
-- * Published team pages get the contact form unless the team switches it
--   off (team_publication_settings.contact_enabled).

alter table internal.public_contact_submissions
  add column if not exists team_id uuid references core.teams(id) on delete set null,
  add column if not exists handled_at timestamptz,
  add column if not exists handled_by uuid references core.profiles(id),
  add column if not exists last_activity_at timestamptz;
update internal.public_contact_submissions set last_activity_at = created_at where last_activity_at is null;
alter table internal.public_contact_submissions
  alter column last_activity_at set default now(),
  alter column last_activity_at set not null;

-- Retention now counts from the last activity, so the fixed 30 days from
-- creation no longer holds.
do $migration$
declare constraint_name text;
begin
  select con.conname into constraint_name from pg_constraint con
  where con.conrelid = 'internal.public_contact_submissions'::regclass and con.contype = 'c'
    and pg_get_constraintdef(con.oid) like '%expires_at <= (created_at%';
  if constraint_name is not null then
    execute format('alter table internal.public_contact_submissions drop constraint %I', constraint_name);
  end if;
end;
$migration$;

create index if not exists public_contact_submissions_team_idx
  on internal.public_contact_submissions(team_id, last_activity_at desc) where team_id is not null;

alter table core.team_publication_settings
  add column if not exists contact_enabled boolean not null default true;

create table if not exists internal.public_contact_messages (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references internal.public_contact_submissions(id) on delete cascade,
  direction text not null check (direction in ('in', 'out')),
  author_profile_id uuid references core.profiles(id),
  body text not null check (length(btrim(body)) between 1 and 5000),
  email_state text check (email_state in ('pending', 'processing', 'sent', 'failed')),
  email_attempts integer not null default 0 check (email_attempts between 0 and 10),
  email_error text,
  provider_email_id text unique,
  idempotency_key uuid,
  -- Statement time, so read and new message never share a timestamp.
  created_at timestamptz not null default clock_timestamp(),
  unique (submission_id, idempotency_key),
  check ((direction = 'out' and author_profile_id is not null and email_state is not null)
    or (direction = 'in' and author_profile_id is null and email_state is null))
);
create index if not exists public_contact_messages_thread_idx
  on internal.public_contact_messages(submission_id, created_at);
create index if not exists public_contact_messages_outbox_idx
  on internal.public_contact_messages(email_state, created_at) where email_state in ('pending', 'failed');

create table if not exists internal.public_contact_reads (
  profile_id uuid not null references core.profiles(id) on delete cascade,
  submission_id uuid not null references internal.public_contact_submissions(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (profile_id, submission_id)
);
alter table internal.public_contact_messages enable row level security;
alter table internal.public_contact_reads enable row level security;
revoke all on internal.public_contact_messages, internal.public_contact_reads from public, anon, authenticated;

-- Who may read and answer a thread.
create or replace function internal.actor_handles_contact(target_club_id uuid, target_team_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.actor_manages_club(target_club_id)
    or (target_team_id is not null
      and internal.actor_has_capability(target_club_id, target_team_id, 'team.roster.manage'))
$$;

-- Who is notified: the team's roster managers, or the club's administrators
-- for club messages (and for teams without roster managers).
create or replace function internal.contact_recipients(target_club_id uuid, target_team_id uuid)
returns table(profile_id uuid, club_person_id uuid) language sql stable security definer set search_path = '' as $$
  with holders as (
    select distinct link.profile_id, link.club_person_id, grant_row.capability, grant_row.scope_type
    from core.person_account_links link
    join core.assignments assignment on assignment.club_person_id = link.club_person_id
      and assignment.club_id = link.club_id
    join core.capability_grants grant_row on grant_row.assignment_id = assignment.id
      and grant_row.club_id = assignment.club_id
    where link.club_id = target_club_id and link.state = 'active'
      and assignment.state = 'active' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
      and ((grant_row.capability = 'club.memberships.manage' and grant_row.scope_type = 'club'
          and grant_row.scope_id = target_club_id)
        or (target_team_id is not null and grant_row.capability = 'team.roster.manage'
          and grant_row.scope_type = 'team' and grant_row.scope_id = target_team_id))
  ), team_managers as (
    select distinct on (h.profile_id) h.profile_id, h.club_person_id from holders h
    where h.capability = 'team.roster.manage' order by h.profile_id, h.club_person_id
  ), club_admins as (
    select distinct on (h.profile_id) h.profile_id, h.club_person_id from holders h
    where h.capability = 'club.memberships.manage' order by h.profile_id, h.club_person_id
  )
  select profile_id, club_person_id from team_managers where target_team_id is not null
  union all
  select profile_id, club_person_id from club_admins
  where target_team_id is null or not exists (select 1 from team_managers)
$$;

create or replace function internal.notify_contact_recipients(target_submission_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare submission internal.public_contact_submissions%rowtype; event_id uuid := gen_random_uuid(); added integer;
begin
  select * into submission from internal.public_contact_submissions where id = target_submission_id;
  if submission.id is null or submission.state = 'erased' then return 0; end if;
  insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select submission.club_id, event_id, 'contact.message.received.v1', 'contact', submission.id,
    recipient.profile_id, recipient.club_person_id, jsonb_build_object('submission_id', submission.id)
  from internal.contact_recipients(submission.club_id, submission.team_id) recipient
  on conflict do nothing;
  get diagnostics added = row_count;
  return added;
end;$$;

-- The contact form, now also for a team. The old entry point (club only)
-- keeps working for pages that are already open.
create or replace function internal.public_submit_contact_v2(target_club_public_id uuid, target_team_public_id uuid,
  new_sender_name text, new_sender_email text, new_subject text, new_message_body text, ip_sha256_hex text,
  captcha_verified boolean, captcha_assertion_sha256_hex text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare rate jsonb; target_club_id uuid; target_team_id uuid; new_id uuid; submission_id uuid;
begin
  if not internal.public_runtime_enabled() then return jsonb_build_object('accepted', false, 'code', 'unavailable'); end if;
  if captcha_verified is not true or captcha_assertion_sha256_hex !~ '^[0-9a-fA-F]{64}$'
    or length(btrim(coalesce(new_sender_name, ''))) not between 2 and 120
    or length(coalesce(new_sender_email, '')) not between 3 and 254
    or new_sender_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or length(btrim(coalesce(new_subject, ''))) not between 2 and 160
    or length(btrim(coalesce(new_message_body, ''))) not between 2 and 2000
  then raise invalid_parameter_value using message = 'invalid_request'; end if;
  select setting.club_id into target_club_id from core.club_publication_settings setting
    join core.publication_confirmations confirmation on confirmation.id = setting.confirmation_id
    join public_api.club_projections projection on projection.public_id = setting.public_id
    where setting.public_id = target_club_public_id and setting.mode = 'published'
      and confirmation.state = 'active' and confirmation.expires_at > now();
  if target_club_id is not null and target_team_public_id is not null then
    select setting.team_id into target_team_id from core.team_publication_settings setting
      join public_api.team_projections projection on projection.public_id = setting.public_id
      where setting.public_id = target_team_public_id and setting.club_id = target_club_id
        and setting.contact_enabled;
    if target_team_id is null then target_club_id := null; end if;
  end if;
  -- Unknown, unpublished, expired and closed recipients get the same answer.
  if target_club_id is null then return jsonb_build_object('accepted', true); end if;
  rate := internal.consume_public_rate_limit(ip_sha256_hex, 'contact', target_club_public_id);
  if not (rate->>'allowed')::boolean then raise program_limit_exceeded using message = 'rate_limited'; end if;
  insert into internal.public_contact_submissions(club_id, team_id, sender_name, sender_email, subject,
    message_body, captcha_assertion_hash)
  values (target_club_id, target_team_id, btrim(new_sender_name), lower(btrim(new_sender_email)), btrim(new_subject),
    btrim(new_message_body), decode(lower(captcha_assertion_sha256_hex), 'hex'))
  returning id, public_id into new_id, submission_id;
  perform internal.notify_contact_recipients(new_id);
  return jsonb_build_object('accepted', true, 'reference', submission_id);
end;$$;

create or replace function internal.public_submit_contact(target_club_public_id uuid, new_sender_name text,
  new_sender_email text, new_subject text, new_message_body text, ip_sha256_hex text, captcha_verified boolean,
  captcha_assertion_sha256_hex text)
returns jsonb language sql security definer set search_path = '' as $$
  select internal.public_submit_contact_v2(target_club_public_id, null, new_sender_name, new_sender_email,
    new_subject, new_message_body, ip_sha256_hex, captcha_verified, captcha_assertion_sha256_hex)
$$;

-- As in 20260925105653, plus whether the team page shows the contact form.
create or replace function internal.public_get_team(
  target_club_slug text,target_team_slug text,ip_sha256_hex text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb;result jsonb;
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false);end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 select jsonb_build_object('id',team.public_id,'club_slug',team.club_slug,
  'slug',team.slug,'name',team.name,'age_class',team.age_class,
  'contact_enabled',coalesce(setting.contact_enabled,false))
 into result from public_api.team_projections team
 join public_api.club_projections club on club.public_id=team.club_public_id
 left join core.team_publication_settings setting on setting.public_id=team.public_id
 where team.club_slug=lower(btrim(target_club_slug))
  and team.slug=lower(btrim(target_team_slug))
  and team.visibility='published' and club.visibility='published';
 return coalesce(result,jsonb_build_object('not_found',true));
end;$$;

-- The team page's contact form, switched by the team's leaders or the club.
do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('internal.get_publication_self_service_for_actor(uuid)'::regprocedure);
  patched := replace(definition, $old$'can_request',internal.actor_has_capability(target_club_id,t.id,'team.roster.manage'),$old$,
    $new$'can_request',internal.actor_has_capability(target_club_id,t.id,'team.roster.manage'),
    'contact_enabled',coalesce(ts.contact_enabled,true),
    'can_set_contact',internal.actor_handles_contact(target_club_id,t.id),$new$);
  if patched = definition then raise exception 'publication self-service changed'; end if;
  execute patched;
end;
$migration$;

create or replace function internal.set_team_contact_enabled_for_actor(target_team_id uuid, enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare team_row core.teams%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into team_row from core.teams where id = target_team_id;
  if team_row.id is null or enabled is null or not internal.actor_handles_contact(team_row.club_id, team_row.id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  update core.team_publication_settings set contact_enabled = enabled where team_id = team_row.id;
  if not found then raise invalid_parameter_value using message = 'team_page_missing'; end if;
end;$$;

-- Threads the actor handles, newest activity first.
create or replace function internal.list_contact_threads_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', submission.id, 'club_id', submission.club_id, 'club_name', club.name,
      'team_id', submission.team_id, 'team_name', team.name,
      'sender_name', submission.sender_name, 'sender_email', submission.sender_email,
      'subject', submission.subject,
      'preview', left(coalesce(latest.body, submission.message_body), 160),
      'latest_direction', coalesce(latest.direction, 'in'),
      'created_at', submission.created_at, 'last_activity_at', submission.last_activity_at,
      'expires_at', submission.expires_at, 'handled', submission.handled_at is not null,
      'unread', submission.handled_at is null and (read.read_at is null or read.read_at < coalesce(
        (select max(m.created_at) from internal.public_contact_messages m
          where m.submission_id = submission.id and m.direction = 'in'), submission.created_at)))
      order by submission.last_activity_at desc)
    from internal.public_contact_submissions submission
    join core.clubs club on club.id = submission.club_id
    left join core.teams team on team.id = submission.team_id
    left join internal.public_contact_reads read on read.submission_id = submission.id and read.profile_id = actor
    left join lateral (select m.body, m.direction from internal.public_contact_messages m
      where m.submission_id = submission.id order by m.created_at desc limit 1) latest on true
    where submission.state <> 'erased'
      and internal.actor_handles_contact(submission.club_id, submission.team_id)), '[]'::jsonb);
end;$$;

-- One thread with its messages; reading it marks it read for the actor.
create or replace function internal.get_contact_thread_for_actor(target_submission_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); submission internal.public_contact_submissions%rowtype; result jsonb;
begin
  if actor is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into submission from internal.public_contact_submissions where id = target_submission_id;
  if submission.id is null or submission.state = 'erased'
    or not internal.actor_handles_contact(submission.club_id, submission.team_id)
  then raise insufficient_privilege using message = 'not_found'; end if;
  insert into internal.public_contact_reads(profile_id, submission_id, read_at) values (actor, submission.id, clock_timestamp())
  on conflict (profile_id, submission_id) do update set read_at = excluded.read_at;
  select jsonb_build_object(
    'id', submission.id, 'club_name', club.name, 'team_name', team.name,
    'sender_name', submission.sender_name, 'sender_email', submission.sender_email,
    'subject', submission.subject, 'created_at', submission.created_at,
    'expires_at', submission.expires_at, 'handled', submission.handled_at is not null,
    'messages', jsonb_build_array(jsonb_build_object('id', submission.id, 'direction', 'in',
        'body', submission.message_body, 'created_at', submission.created_at)) || coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'direction', m.direction, 'body', m.body,
        'created_at', m.created_at, 'email_state', m.email_state,
        'author_name', coalesce(nullif(btrim(profile.display_name), ''), 'Ledare')) order by m.created_at)
      from internal.public_contact_messages m left join core.profiles profile on profile.id = m.author_profile_id
      where m.submission_id = submission.id), '[]'::jsonb))
  into result
  from core.clubs club left join core.teams team on team.id = submission.team_id
  where club.id = submission.club_id;
  return result;
end;$$;

create or replace function internal.reply_contact_thread_for_actor(target_submission_id uuid, reply_body text,
  idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); submission internal.public_contact_submissions%rowtype; existing uuid; new_id uuid;
begin
  if actor is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if idempotency_key is null or reply_body is null or length(btrim(reply_body)) not between 1 and 5000 then
    raise invalid_parameter_value using message = 'invalid_reply';
  end if;
  select * into submission from internal.public_contact_submissions where id = target_submission_id for update;
  if submission.id is null or submission.state = 'erased'
    or not internal.actor_handles_contact(submission.club_id, submission.team_id)
  then raise insufficient_privilege using message = 'not_found'; end if;
  select id into existing from internal.public_contact_messages
  where submission_id = submission.id and public_contact_messages.idempotency_key = reply_contact_thread_for_actor.idempotency_key;
  if existing is not null then return jsonb_build_object('id', existing, 'repeated', true); end if;
  -- At most 20 answers per thread and day: TeamZone is not a mass mailer.
  if (select count(*) from internal.public_contact_messages where submission_id = submission.id
      and direction = 'out' and created_at > now() - interval '1 day') >= 20 then
    raise program_limit_exceeded using message = 'rate_limited';
  end if;
  insert into internal.public_contact_messages(submission_id, direction, author_profile_id, body, email_state, idempotency_key)
  values (submission.id, 'out', actor, btrim(reply_body), 'pending', idempotency_key) returning id into new_id;
  update internal.public_contact_submissions set last_activity_at = now(), expires_at = now() + interval '30 days',
    revision = revision + 1 where id = submission.id;
  return jsonb_build_object('id', new_id);
end;$$;

create or replace function internal.set_contact_thread_handled_for_actor(target_submission_id uuid, handled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); submission internal.public_contact_submissions%rowtype;
begin
  if actor is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into submission from internal.public_contact_submissions where id = target_submission_id for update;
  if submission.id is null or submission.state = 'erased'
    or not internal.actor_handles_contact(submission.club_id, submission.team_id)
  then raise insufficient_privilege using message = 'not_found'; end if;
  update internal.public_contact_submissions set
    handled_at = case when handled then now() end, handled_by = case when handled then actor end,
    revision = revision + 1
  where id = submission.id;
end;$$;

-- contact-email-worker: answers waiting to be sent (failed ones are retried
-- up to five times). Service role only.
create or replace function internal.claim_contact_emails(batch_size integer default 20)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  with picked as (
    select m.id from internal.public_contact_messages m
    join internal.public_contact_submissions s on s.id = m.submission_id and s.state <> 'erased'
    where m.direction = 'out' and (m.email_state = 'pending'
      or (m.email_state = 'failed' and m.email_attempts < 5))
    order by m.created_at limit least(greatest(batch_size, 1), 50)
    for update of m skip locked
  ), claimed as (
    update internal.public_contact_messages m set email_state = 'processing', email_attempts = m.email_attempts + 1
    from picked where m.id = picked.id returning m.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'message_id', c.id, 'submission_public_id', s.public_id, 'to', s.sender_email, 'to_name', s.sender_name,
    'subject', s.subject, 'body', c.body, 'club_name', club.name, 'team_name', team.name,
    'original_body', s.message_body, 'original_at', s.created_at)), '[]'::jsonb)
  into result
  from claimed c join internal.public_contact_submissions s on s.id = c.submission_id
  join core.clubs club on club.id = s.club_id left join core.teams team on team.id = s.team_id;
  return result;
end;$$;

create or replace function internal.finish_contact_email(target_message_id uuid, sent boolean, provider_id text,
  error_code text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  update internal.public_contact_messages set
    email_state = case when sent then 'sent' else 'failed' end,
    provider_email_id = case when sent then left(provider_id, 200) else provider_email_id end,
    email_error = case when sent then null else left(error_code, 80) end
  where id = target_message_id and direction = 'out';
end;$$;

-- contact-inbound: an e-mail reply from the sender. The Edge Function has
-- already verified Resend's signature, the HMAC of the reply address and
-- DMARC; here the sender address must match and the thread must be open.
create or replace function internal.receive_contact_email(target_submission_public_id uuid, from_email text,
  reply_body text, provider_email_id text)
returns text language plpgsql security definer set search_path = '' as $$
declare submission internal.public_contact_submissions%rowtype;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  if reply_body is null or length(btrim(reply_body)) = 0 then return 'empty'; end if;
  if provider_email_id is null or exists (select 1 from internal.public_contact_messages m
      where m.provider_email_id = receive_contact_email.provider_email_id) then return 'duplicate'; end if;
  select * into submission from internal.public_contact_submissions
  where public_id = target_submission_public_id for update;
  if submission.id is null or submission.state = 'erased' or submission.expires_at <= now() then return 'closed'; end if;
  if lower(btrim(coalesce(from_email, ''))) <> submission.sender_email then return 'wrong_sender'; end if;
  -- At most 20 e-mails per thread and day (auto-replies, loops, floods).
  if (select count(*) from internal.public_contact_messages where submission_id = submission.id
      and direction = 'in' and created_at > now() - interval '1 day') >= 20 then return 'rate_limited'; end if;
  insert into internal.public_contact_messages(submission_id, direction, body, provider_email_id)
  values (submission.id, 'in', left(btrim(reply_body), 5000), left(provider_email_id, 200));
  update internal.public_contact_submissions set last_activity_at = now(), expires_at = now() + interval '30 days',
    handled_at = null, handled_by = null, revision = revision + 1 where id = submission.id;
  perform internal.notify_contact_recipients(submission.id);
  return 'accepted';
end;$$;

-- Retention: thread messages and reads go with the erased submission.
create or replace function internal.apply_public_contact_retention(batch_size integer default 100)
returns integer language plpgsql security definer set search_path = '' as $$
declare changed integer;
begin
  if batch_size not between 1 and 500 then raise invalid_parameter_value using message = 'invalid_batch'; end if;
  with targets as (select id from internal.public_contact_submissions
    where state <> 'erased' and expires_at <= now() order by expires_at, id for update skip locked limit batch_size),
  gone_messages as (delete from internal.public_contact_messages m using targets where m.submission_id = targets.id),
  gone_reads as (delete from internal.public_contact_reads r using targets where r.submission_id = targets.id)
  update internal.public_contact_submissions submission set
    sender_name = '', sender_email = '', subject = '', message_body = '', state = 'erased', erased_at = now(),
    captcha_assertion_hash = extensions.digest(gen_random_uuid()::text, 'sha256'), revision = revision + 1
  from targets where submission.id = targets.id;
  get diagnostics changed = row_count;
  delete from internal.public_rate_limit_buckets where expires_at <= now();
  return changed;
end;$$;

-- The notification centre shows contact messages with a neutral text.
create or replace function internal.notification_title(event_type text)
returns text language sql immutable set search_path = '' as $$
 select case
  when event_type = 'message.message.sent.v1' then 'Nytt meddelande'
  when event_type = 'contact.message.received.v1' then 'Nytt meddelande via klubbsajten'
  when event_type like 'callup.%.cancelled.%' then 'Kallelse återkallad'
  when event_type like 'callup.%.reminded.%' then 'Påminnelse om kallelse'
  when event_type like 'callup.%' then 'Ny kallelse'
  when event_type like 'event.%' then 'Kalendern har uppdaterats'
  else 'Ny aktivitet i TeamZone' end
$$;
create or replace function internal.notification_preview(event_type text)
returns text language sql immutable set search_path = '' as $$
 select case
  when event_type = 'message.message.sent.v1' then 'Öppna inkorgen för att läsa meddelandet.'
  when event_type = 'contact.message.received.v1' then 'Öppna inkorgen för att läsa och svara.'
  when event_type like 'callup.%.cancelled.%' then 'En kallelse har återkallats.'
  when event_type like 'callup.%.reminded.%' then 'Du har en kallelse som behöver besvaras.'
  when event_type like 'callup.%' then 'Du har fått en kallelse.'
  when event_type like 'event.%' then 'Öppna kalendern för aktuell information.'
  else 'Öppna TeamZone för mer information.' end
$$;

-- As in 20261029090000, with contact messages.
create or replace function internal.push_message_for_outbox(target_outbox_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare outbox internal.notification_outbox%rowtype; profile core.profiles%rowtype;
  swedish boolean; event_row core.events%rowtype; team_name text; kind text;
  title text; body text; callup_row core.callups%rowtype; raw_token text;
  response jsonb; thread_row core.message_threads%rowtype; reply jsonb; targets jsonb;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  select * into outbox from internal.notification_outbox where id = target_outbox_id;
  if outbox.id is null or outbox.recipient_profile_id is null then return null; end if;
  select * into profile from core.profiles where id = outbox.recipient_profile_id;
  swedish := coalesce(profile.locale, 'sv') not like 'en%';
  targets := coalesce((
    select jsonb_agg(jsonb_build_object('endpoint_id', endpoint.id, 'platform', stored.platform,
      'token', extensions.pgp_sym_decrypt(stored.token_ciphertext, internal.push_token_key())))
    from core.notification_endpoints endpoint
    join internal.push_endpoint_tokens stored on stored.endpoint_id = endpoint.id
    where endpoint.profile_id = outbox.recipient_profile_id and endpoint.channel = 'push'
      and endpoint.state = 'active'), '[]'::jsonb);
  if outbox.event_type like 'callup.%' and outbox.payload_ref->>'event_id' ~ '^[0-9a-fA-F-]{36}$' then
    select * into event_row from core.events where id = (outbox.payload_ref->>'event_id')::uuid;
    if event_row.id is null then return null; end if;
    select name into team_name from core.teams where id = event_row.owning_team_id;
    kind := case event_row.event_type
      when 'training' then case when swedish then 'Träning' else 'Training' end
      when 'match' then 'Match'
      when 'meeting' then case when swedish then 'Möte' else 'Meeting' end
      else case when swedish then 'Aktivitet' else 'Activity' end end;
    title := case
      when outbox.event_type like 'callup.callup.cancelled.%' then case when swedish then 'Kallelsen är inställd' else 'Callup cancelled' end
      when outbox.event_type like 'callup.callup.reminded.%' then case when swedish then 'Påminnelse: svara på kallelsen' else 'Reminder: answer the callup' end
      else case when swedish then 'Ny kallelse' else 'New callup' end end;
    body := concat_ws(' · ', kind, team_name,
      internal.push_local_time(event_row.starts_at, coalesce(profile.timezone, event_row.timezone), swedish));
    -- Tokens only for someone with a device to answer from.
    if jsonb_array_length(targets) > 0
      and outbox.event_type ~ '^callup\.callup\.(sent|late_sent|reminded)\.'
      and outbox.payload_ref->>'callup_id' ~ '^[0-9a-fA-F-]{36}$' then
      select * into callup_row from core.callups where id = (outbox.payload_ref->>'callup_id')::uuid;
      if callup_row.id is not null and callup_row.event_id = event_row.id and callup_row.state = 'pending'
        and (callup_row.expires_at is null or callup_row.expires_at > now()) then
        delete from internal.push_response_tokens
        where expires_at <= now() or consumed_at < now() - interval '1 day';
        raw_token := encode(extensions.gen_random_bytes(32), 'hex');
        insert into internal.push_response_tokens(callup_id, recipient_profile_id, acting_as_person_id,
          token_hash, expires_at)
        values (callup_row.id, outbox.recipient_profile_id,
          -- Someone other than the called person (a guardian) answers for
          -- them; decided by the recipient's own link, not recipient_person_id
          -- (which can be null).
          case when exists (select 1 from core.person_account_links link
              where link.profile_id = outbox.recipient_profile_id and link.club_id = callup_row.club_id
                and link.club_person_id = callup_row.club_person_id and link.state = 'active')
            then null else callup_row.club_person_id end,
          extensions.digest(raw_token, 'sha256'),
          least(callup_row.expires_at, now() + interval '2 days'));
        response := jsonb_build_object('callup_id', callup_row.id, 'token', raw_token);
      end if;
    end if;
  elsif outbox.event_type = 'message.message.sent.v1' then
    select team.name into team_name from core.thread_scopes scope join core.teams team on team.id = scope.team_id
    where outbox.payload_ref->>'thread_id' ~ '^[0-9a-fA-F-]{36}$'
      and scope.thread_id = (outbox.payload_ref->>'thread_id')::uuid
    order by team.name limit 1;
    title := case when swedish then 'Nytt meddelande' else 'New message' end;
    body := coalesce(team_name, case when swedish then 'Öppna TeamZone för att läsa.' else 'Open TeamZone to read it.' end);
    if jsonb_array_length(targets) > 0 and outbox.payload_ref->>'thread_id' ~ '^[0-9a-fA-F-]{36}$' then
      select * into thread_row from core.message_threads where id = (outbox.payload_ref->>'thread_id')::uuid;
      -- Announcements are written by their creator only: no reply button.
      if thread_row.id is not null and thread_row.state = 'active' and thread_row.thread_type <> 'announcement' then
        delete from internal.push_reply_tokens
        where expires_at <= now() or consumed_at < now() - interval '1 day';
        raw_token := encode(extensions.gen_random_bytes(32), 'hex');
        insert into internal.push_reply_tokens(thread_id, recipient_profile_id, token_hash, expires_at)
        values (thread_row.id, outbox.recipient_profile_id, extensions.digest(raw_token, 'sha256'),
          now() + interval '2 days');
        reply := jsonb_build_object('thread_id', thread_row.id, 'token', raw_token);
      end if;
    end if;
  elsif outbox.event_type = 'contact.message.received.v1' then
    -- A message via the club site: type and club or team, never the text.
    select coalesce(team.name, club.name) into team_name
    from internal.public_contact_submissions submission
    join core.clubs club on club.id = submission.club_id
    left join core.teams team on team.id = submission.team_id
    where outbox.payload_ref->>'submission_id' ~ '^[0-9a-fA-F-]{36}$'
      and submission.id = (outbox.payload_ref->>'submission_id')::uuid;
    title := case when swedish then 'Nytt meddelande via klubbsajten' else 'New message via the club site' end;
    body := coalesce(team_name, case when swedish then 'Öppna TeamZone för att läsa.' else 'Open TeamZone to read it.' end);
  else
    return null;
  end if;
  return jsonb_build_object(
    'title', title,
    'body', body,
    'route', internal.notification_deep_link(outbox),
    'response', response,
    'reply', reply,
    'language', case when swedish then 'sv' else 'en' end,
    'targets', targets);
end;$$;

-- Workers: answers every minute (the support worker's token), retention daily.
create or replace function internal.invoke_contact_email_worker()
returns bigint language plpgsql security definer set search_path = '' as $$
declare project_url text; worker_token text; request_id bigint;
begin
  if not exists (select 1 from internal.public_contact_messages where direction = 'out'
      and (email_state = 'pending' or (email_state = 'failed' and email_attempts < 5))) then
    return null;
  end if;
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into worker_token from vault.decrypted_secrets where name = 'support_email_worker_token' limit 1;
  if nullif(project_url, '') is null or nullif(worker_token, '') is null then return null; end if;
  select net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/contact-email-worker',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-teamzone-worker-token', worker_token),
    body := '{}'::jsonb, timeout_milliseconds := 15000) into request_id;
  return request_id;
end;$$;

do $$
declare existing_job_id bigint;
begin
  for existing_job_id in select jobid from cron.job where jobname in ('contact-email-worker', 'public-contact-retention') loop
    perform cron.unschedule(existing_job_id);
  end loop;
  perform cron.schedule('contact-email-worker', '* * * * *', 'select internal.invoke_contact_email_worker();');
  perform cron.schedule('public-contact-retention', '17 3 * * *', 'select internal.apply_public_contact_retention(500);');
end $$;

create or replace function api.public_submit_contact_v2(club_id uuid, team_id uuid, sender_name text, sender_email text,
  subject text, message_body text, ip_hash text, captcha_verified boolean, captcha_assertion_hash text)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.public_submit_contact_v2(club_id, team_id, sender_name, sender_email, subject, message_body, ip_hash,
  captcha_verified, captcha_assertion_hash)$$;
create or replace function api.set_team_contact_enabled(target_team_id uuid, enabled boolean)
returns void language sql security invoker set search_path = '' as
$$select internal.set_team_contact_enabled_for_actor(target_team_id, enabled)$$;
create or replace function api.list_contact_threads()
returns jsonb language sql stable security invoker set search_path = '' as
$$select internal.list_contact_threads_for_actor()$$;
create or replace function api.get_contact_thread(target_submission_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_contact_thread_for_actor(target_submission_id)$$;
create or replace function api.reply_contact_thread(target_submission_id uuid, reply_body text, idempotency_key uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.reply_contact_thread_for_actor(target_submission_id, reply_body, idempotency_key)$$;
create or replace function api.set_contact_thread_handled(target_submission_id uuid, handled boolean)
returns void language sql security invoker set search_path = '' as
$$select internal.set_contact_thread_handled_for_actor(target_submission_id, handled)$$;
create or replace function api.claim_contact_emails(batch_size integer default 20)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.claim_contact_emails(batch_size)$$;
create or replace function api.finish_contact_email(target_message_id uuid, sent boolean, provider_id text, error_code text)
returns void language sql security invoker set search_path = '' as
$$select internal.finish_contact_email(target_message_id, sent, provider_id, error_code)$$;
create or replace function api.receive_contact_email(target_submission_public_id uuid, from_email text, reply_body text,
  provider_email_id text)
returns text language sql security invoker set search_path = '' as
$$select internal.receive_contact_email(target_submission_public_id, from_email, reply_body, provider_email_id)$$;

revoke all on function internal.set_team_contact_enabled_for_actor(uuid, boolean), api.set_team_contact_enabled(uuid, boolean),
  internal.actor_handles_contact(uuid, uuid), internal.contact_recipients(uuid, uuid),
  internal.notify_contact_recipients(uuid),
  internal.public_submit_contact_v2(uuid, uuid, text, text, text, text, text, boolean, text),
  internal.list_contact_threads_for_actor(), internal.get_contact_thread_for_actor(uuid),
  internal.reply_contact_thread_for_actor(uuid, text, uuid), internal.set_contact_thread_handled_for_actor(uuid, boolean),
  internal.claim_contact_emails(integer), internal.finish_contact_email(uuid, boolean, text, text),
  internal.receive_contact_email(uuid, text, text, text), internal.invoke_contact_email_worker(),
  api.public_submit_contact_v2(uuid, uuid, text, text, text, text, text, boolean, text),
  api.list_contact_threads(), api.get_contact_thread(uuid), api.reply_contact_thread(uuid, text, uuid),
  api.set_contact_thread_handled(uuid, boolean), api.claim_contact_emails(integer),
  api.finish_contact_email(uuid, boolean, text, text), api.receive_contact_email(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function internal.set_team_contact_enabled_for_actor(uuid, boolean), api.set_team_contact_enabled(uuid, boolean),
  internal.list_contact_threads_for_actor(), internal.get_contact_thread_for_actor(uuid),
  internal.reply_contact_thread_for_actor(uuid, text, uuid), internal.set_contact_thread_handled_for_actor(uuid, boolean),
  api.list_contact_threads(), api.get_contact_thread(uuid), api.reply_contact_thread(uuid, text, uuid),
  api.set_contact_thread_handled(uuid, boolean)
  to authenticated;
grant execute on function internal.public_submit_contact_v2(uuid, uuid, text, text, text, text, text, boolean, text),
  internal.claim_contact_emails(integer), internal.finish_contact_email(uuid, boolean, text, text),
  internal.receive_contact_email(uuid, text, text, text),
  api.public_submit_contact_v2(uuid, uuid, text, text, text, text, text, boolean, text),
  api.claim_contact_emails(integer), api.finish_contact_email(uuid, boolean, text, text),
  api.receive_contact_email(uuid, text, text, text)
  to service_role;

-- Messages already waiting are delivered: their recipients are notified.
do $$
declare waiting uuid;
begin
  for waiting in select id from internal.public_contact_submissions where state <> 'erased'
    and not exists (select 1 from internal.notification_outbox o where o.event_type = 'contact.message.received.v1'
      and o.aggregate_id = public_contact_submissions.id) loop
    perform internal.notify_contact_recipients(waiting);
  end loop;
end $$;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261101090000_public_contact_threads', 'greenfield',
  'PUB-14: club-site messages reach clubs and teams as two-way threads'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261101090000_public_contact_threads');
notify pgrst, 'reload schema';
