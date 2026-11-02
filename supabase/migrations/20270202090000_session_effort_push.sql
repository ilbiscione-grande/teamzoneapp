-- The effort question as a notification (2026-11-02): when a training
-- ends, the players who were there get "Hur kändes träningen?" with the
-- answers 1–10 in the notification itself (Android draws them; elsewhere
-- the notification opens the activity). Same rules as the question in the
-- app (20270201090000, PAR-PRIV-04): from 13, the team's active players,
-- not opted out, not yet answered.
--
-- The notification is off until the team's leaders turn it on (in the
-- Team Development Plan, beside the load's thresholds). The question, in
-- the app and in the notification, exists only when the club has the Team
-- Development Plan or the Individual Development Plan.
--
-- Who was there: attendance taken says so (present, late, partial: yes;
-- absent: no). Without attendance, an accepted callup when the activity
-- has callups, else no absence reported (an activity without callups
-- expects everyone).
--
-- The answer from the notification has no user session: a token from the
-- push is the credential, for one training and player, valid while the
-- question is open (at most two days). The last answer counts.

create table internal.push_effort_tokens (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events(id) on delete cascade,
  club_person_id uuid not null,
  recipient_profile_id uuid not null references core.profiles(id) on delete cascade,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index push_effort_tokens_event on internal.push_effort_tokens (event_id);
create index push_effort_tokens_profile on internal.push_effort_tokens (recipient_profile_id);
alter table internal.push_effort_tokens enable row level security;
revoke all on internal.push_effort_tokens from public, anon, authenticated;

-- Whether the team's leaders have turned the notification on.
alter table core.team_development_load_settings add column if not exists effort_push boolean not null default false;

-- Whether the club has a module the question belongs to: the Team or the
-- Individual Development Plan.
create or replace function internal.effort_module_on(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.module_allows_read(target_club_id, 'module.team_development')
    or internal.module_allows_read(target_club_id, 'module.player_development')
$$;

-- As in 20270131090000, with whether the effort notification is on.
create or replace function internal.tdp_load_settings(target_team_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'load_increase_percent', coalesce(setting.load_increase_percent, case when setting.team_id is null then 130 end),
    'attendance_min_percent', coalesce(setting.attendance_min_percent, case when setting.team_id is null then 50 end),
    'match_minutes_max', coalesce(setting.match_minutes_max, case when setting.team_id is null then 180 end),
    'effort_push', coalesce(setting.effort_push, false))
  from (select 1) one left join core.team_development_load_settings setting on setting.team_id = target_team_id
$$;

-- The leaders turn the effort notification on or off for the team.
create or replace function internal.set_team_development_effort_push_for_actor(target_plan_id uuid, turn_on boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan core.development_plans;
begin
  plan := internal.tdp_checkin_plan(target_plan_id);
  if turn_on is null then raise invalid_parameter_value using message = 'invalid_input'; end if;
  insert into core.team_development_load_settings (team_id, club_id, effort_push, updated_by)
  values (plan.team_id, plan.club_id, turn_on, auth.uid())
  on conflict (team_id) do update set effort_push = excluded.effort_push,
    updated_by = excluded.updated_by, updated_at = now();
  return internal.tdp_load(plan, (now() at time zone 'Europe/Stockholm')::date);
end;
$$;

create or replace function api.set_team_development_effort_push(target_plan_id uuid, turn_on boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.set_team_development_effort_push_for_actor(target_plan_id, turn_on) $$;

-- As in 20270201090000, for the clubs with either development module.
create or replace function internal.get_session_effort_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events; day date; open boolean;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or event_row.event_type <> 'training' or event_row.owning_team_id is null
    or event_row.archived_at is not null or event_row.state = 'cancelled' or event_row.ends_at > now()
    or not internal.effort_module_on(event_row.club_id) then
    return jsonb_build_object('people', '[]'::jsonb);
  end if;
  day := (event_row.starts_at at time zone event_row.timezone)::date;
  open := event_row.ends_at > now() - interval '7 days';
  return jsonb_build_object('open', open, 'people', coalesce((
    select jsonb_agg(jsonb_build_object(
        'person_id', person.id, 'name', person.display_name, 'self', mine.own,
        'rating', rating.rating, 'opted_out', opt_out.club_person_id is not null,
        'can_answer', mine.own and open and opt_out.club_person_id is null)
      order by not mine.own, person.display_name)
    from core.club_people person
    cross join lateral (select internal.actor_owns_club_person(event_row.club_id, person.id) own) mine
    left join core.session_effort_ratings rating on rating.event_id = event_row.id and rating.club_person_id = person.id
    left join core.session_effort_opt_outs opt_out on opt_out.club_person_id = person.id
    where person.club_id = event_row.club_id and person.status = 'active'
      and internal.effort_age_reached(person, day)
      and internal.actor_represents_club_person(event_row.club_id, person.id)
      and exists (select 1 from core.assignments assignment
        where assignment.team_id = event_row.owning_team_id and assignment.club_person_id = person.id
          and assignment.role_package = 'player' and assignment.state = 'active')), '[]'::jsonb));
end;
$$;

-- Whether the player was at the training, by what is known.
create or replace function internal.effort_attended(event_row core.events, target_person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select fact.status in ('present', 'late', 'partial') from core.attendance_facts fact
     where fact.event_id = event_row.id and fact.club_person_id = target_person_id and fact.status <> 'unknown'),
    case when event_row.callups_required or exists (select 1 from core.callups callup
        where callup.event_id = event_row.id and callup.state <> 'cancelled')
      then exists (select 1 from core.callups callup where callup.event_id = event_row.id
        and callup.club_person_id = target_person_id and callup.state = 'accepted')
      else not exists (select 1 from core.event_absence_notices notice where notice.event_id = event_row.id
        and notice.club_person_id = target_person_id and notice.withdrawn_at is null) end)
$$;

-- Whether the effort question is open for the player at the training: as
-- the question in the app.
create or replace function internal.effort_question_open(event_row core.events, person core.club_people)
returns boolean language sql stable security definer set search_path = '' as $$
  select event_row.event_type = 'training' and event_row.owning_team_id is not null
    and event_row.archived_at is null and event_row.state <> 'cancelled'
    and event_row.ends_at <= now() and event_row.ends_at > now() - interval '7 days'
    and person.club_id = event_row.club_id and person.status = 'active'
    and internal.effort_age_reached(person, (event_row.starts_at at time zone event_row.timezone)::date)
    and internal.effort_module_on(event_row.club_id)
    and exists (select 1 from core.assignments assignment
      where assignment.team_id = event_row.owning_team_id and assignment.club_person_id = person.id
        and assignment.role_package = 'player' and assignment.state = 'active')
    and not exists (select 1 from core.session_effort_opt_outs opt_out where opt_out.club_person_id = person.id)
$$;

-- Queues the question for the trainings that ended in the last two hours,
-- once per player (to the player's own account), who was there and has
-- not answered. Run every minute.
create or replace function internal.enqueue_session_effort_pushes()
returns integer language plpgsql security definer set search_path = '' as $$
declare queued integer;
begin
  insert into internal.notification_outbox (club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select event_row.club_id, md5('effort:' || event_row.id::text)::uuid, 'effort.asked.v1', 'event', event_row.id,
    link.profile_id, person.id, jsonb_build_object('event_id', event_row.id)
  from core.events event_row
  join core.assignments assignment on assignment.team_id = event_row.owning_team_id
    and assignment.role_package = 'player' and assignment.state = 'active'
  join core.club_people person on person.id = assignment.club_person_id
  cross join lateral (
    select min(link.profile_id::text)::uuid profile_id from core.person_account_links link
    where link.club_id = event_row.club_id and link.club_person_id = person.id and link.state = 'active'
  ) link
  join core.team_development_load_settings setting on setting.team_id = event_row.owning_team_id
    and setting.effort_push
  where event_row.event_type = 'training'
    and event_row.ends_at <= now() and event_row.ends_at > now() - interval '2 hours'
    and link.profile_id is not null
    and internal.effort_question_open(event_row, person)
    and internal.effort_attended(event_row, person.id)
    and not exists (select 1 from core.session_effort_ratings rating
      where rating.event_id = event_row.id and rating.club_person_id = person.id)
  on conflict (domain_event_id, recipient_person_id) do nothing;
  get diagnostics queued = row_count;
  return queued;
end;
$$;

do $$
declare existing_job_id bigint;
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    for existing_job_id in select jobid from cron.job where jobname = 'session-effort-push' loop
      perform cron.unschedule(existing_job_id);
    end loop;
    perform cron.schedule('session-effort-push', '* * * * *', 'select internal.enqueue_session_effort_pushes();');
  end if;
end $$;

-- The answer from the notification (push-effort-response): the token is
-- the credential; the question must still be open.
create or replace function internal.respond_effort_from_push(raw_token text, new_rating integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare stored internal.push_effort_tokens; event_row core.events; person core.club_people;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  if raw_token !~ '^[0-9a-f]{64}$' or new_rating is null or new_rating not between 1 and 10 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select * into stored from internal.push_effort_tokens
  where token_hash = extensions.digest(raw_token, 'sha256') and expires_at > now();
  if stored.id is null then raise insufficient_privilege using message = 'invalid_or_expired_token'; end if;
  select * into event_row from core.events where id = stored.event_id;
  select * into person from core.club_people where id = stored.club_person_id;
  if event_row.id is null or person.id is null or not internal.effort_question_open(event_row, person) then
    raise insufficient_privilege using message = 'invalid_state';
  end if;
  insert into core.session_effort_ratings (club_id, event_id, club_person_id, rating, recorded_by)
  values (event_row.club_id, event_row.id, person.id, new_rating, stored.recipient_profile_id)
  on conflict (event_id, club_person_id) do update
    set rating = excluded.rating, recorded_by = excluded.recorded_by, recorded_at = now();
  return jsonb_build_object('rating', new_rating);
end;
$$;

create or replace function api.respond_effort_from_push(raw_token text, new_rating integer) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.respond_effort_from_push(raw_token, new_rating) $$;

revoke all on function
  internal.effort_module_on(uuid),
  internal.tdp_load_settings(uuid),
  internal.set_team_development_effort_push_for_actor(uuid, boolean),
  api.set_team_development_effort_push(uuid, boolean),
  internal.get_session_effort_for_actor(uuid),
  internal.effort_attended(core.events, uuid),
  internal.effort_question_open(core.events, core.club_people),
  internal.enqueue_session_effort_pushes(),
  internal.respond_effort_from_push(text, integer),
  api.respond_effort_from_push(text, integer)
from public, anon, authenticated;
grant execute on function internal.respond_effort_from_push(text, integer), api.respond_effort_from_push(text, integer)
  to service_role;
grant execute on function
  internal.set_team_development_effort_push_for_actor(uuid, boolean),
  api.set_team_development_effort_push(uuid, boolean),
  internal.get_session_effort_for_actor(uuid)
to authenticated;

-- The notification's text and, for someone with a device, the token for
-- the answers in it. Otherwise as in the live definition (2026-11-02).
CREATE OR REPLACE FUNCTION internal.push_message_for_outbox(target_outbox_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare outbox internal.notification_outbox%rowtype; profile core.profiles%rowtype;
  swedish boolean; event_row core.events%rowtype; team_name text; kind text;
  title text; body text; callup_row core.callups%rowtype; raw_token text;
  response jsonb; thread_row core.message_threads%rowtype; reply jsonb; targets jsonb;
  effort jsonb; person core.club_people%rowtype;
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
  elsif outbox.event_type like 'referee.%' then
    -- A referee assignment: what happened and the match's time, no names.
    select concat_ws(' · ', team.name, internal.push_local_time(event_row.starts_at,
        coalesce(profile.timezone, event_row.timezone), swedish))
      into body
    from core.events event_row join core.teams team on team.id = event_row.owning_team_id
    where outbox.payload_ref->>'event_id' ~ '^[0-9a-fA-F-]{36}$'
      and event_row.id = (outbox.payload_ref->>'event_id')::uuid;
    title := case outbox.event_type
      when 'referee.proposed.v1' then case when swedish then 'Förfrågan om att döma' else 'Asked to referee' end
      when 'referee.requested.v1' then case when swedish then 'En domare vill döma er match' else 'A referee offers to referee your match' end
      when 'referee.confirmed.v1' then case when swedish then 'Domaren är bekräftad' else 'Referee confirmed' end
      when 'referee.declined.v1' then case when swedish then 'Domarförfrågan nekad' else 'Referee request declined' end
      when 'referee.club_requested.v1' then case when swedish then 'En föreningsdomare vill döma' else 'A club referee offers to referee' end
      when 'referee.control_question.v1' then case when swedish then 'Dömde domaren matchen?' else 'Did the referee referee the match?' end
      when 'referee.control_answered.v1' then case when swedish then 'Svar på kontrollfrågan om domaren' else 'Answer about the referee' end
      when 'referee.report_rejected.v1' then case when swedish then 'Domaruppdraget godkändes inte' else 'Referee report not approved' end
      when 'referee.payout_paid.v1' then case when swedish then 'Domarersättningen är utbetald' else 'Referee pay is paid out' end
      else case when swedish then 'Domaruppdraget är ändrat' else 'Referee assignment changed' end end;
    body := coalesce(body, case when swedish then 'Öppna TeamZone.' else 'Open TeamZone.' end);
  elsif outbox.event_type like 'booking.%' then
    -- Bokningshanterare: the resource and its time.
    select concat_ws(' · ', resource.name, internal.push_local_time(booking.starts_at,
        coalesce(profile.timezone, 'Europe/Stockholm'), swedish))
      into body
    from core.booking_bookings booking join core.booking_resources resource on resource.id = booking.resource_id
    where outbox.payload_ref->>'booking_id' ~ '^[0-9a-fA-F-]{36}$'
      and booking.id = (outbox.payload_ref->>'booking_id')::uuid;
    title := case outbox.event_type
      when 'booking.rescheduled.v1' then case when swedish then U&'Bokningen har f\00e5tt ny tid' else 'Booking rescheduled' end
      when 'booking.resource_changed.v1' then case when swedish then U&'Bokningen har bytt resurs' else 'Booking resource changed' end
      when 'booking.resources_updated.v1' then case when swedish then U&'Bokningens resurser har \00e4ndrats' else 'Booking resources updated' end
   when 'booking.requested.v1' then case when swedish then 'Bokning att godkänna' else 'Booking to approve' end
      when 'booking.approved.v1' then case when swedish then 'Bokningen är godkänd' else 'Booking approved' end
      when 'booking.declined.v1' then case when swedish then 'Bokningen nekades' else 'Booking declined' end
      else case when swedish then 'Bokningen är avbokad' else 'Booking cancelled' end end;
    body := coalesce(body, case when swedish then 'Öppna Bokningshanteraren i Webtools.' else 'Open the booking manager in Webtools.' end);
  elsif outbox.event_type = 'absence.reported.v1' then
    -- Someone cannot come: the team and the time, never who or why.
    select concat_ws(' · ', team.name, internal.push_local_time(event_row.starts_at,
        coalesce(profile.timezone, event_row.timezone), swedish))
      into body
    from core.events event_row join core.teams team on team.id = event_row.owning_team_id
    where outbox.payload_ref->>'event_id' ~ '^[0-9a-fA-F-]{36}$'
      and event_row.id = (outbox.payload_ref->>'event_id')::uuid;
    title := case when swedish then 'Frånvaroanmälan' else 'Absence reported' end;
    body := coalesce(body, case when swedish then 'Öppna aktiviteten.' else 'Open the activity.' end);
  elsif outbox.event_type = 'matchpool.watch.matched.v1' then
    -- A new listing that fits a watch: age class, format and place, never names.
    select listing.age_class || ' · ' || replace(listing.match_format, 'v', case when swedish then ' mot ' else ' v ' end)
        || ' · ' || listing.place_label
      into body
    from internal.match_pool_listings listing
    where outbox.payload_ref->>'listing_id' ~ '^[0-9a-fA-F-]{36}$'
      and listing.id = (outbox.payload_ref->>'listing_id')::uuid;
    title := case when swedish then 'Ny annons som matchar er bevakning' else 'A new listing matches your watch' end;
    body := coalesce(body, case when swedish then 'Öppna matchpoolen.' else 'Open the match pool.' end);
  elsif outbox.event_type like 'matchpool.%' then
    -- The pool: what happened and the leader's own team, never the text.
    select team.name into team_name from core.teams team
    where outbox.payload_ref->>'team_id' ~ '^[0-9a-fA-F-]{36}$'
      and team.id = (outbox.payload_ref->>'team_id')::uuid;
    title := case outbox.event_type
      when 'matchpool.interest.received.v1' then case when swedish then 'Intresse för er annons i matchpoolen' else 'Interest in your match pool listing' end
      when 'matchpool.interest.accepted.v1' then case when swedish then 'Träningsmatchen är bokad' else 'The friendly is booked' end
      when 'matchpool.message.sent.v1' then case when swedish then 'Nytt meddelande i matchpoolen' else 'New message in the match pool' end
      when 'matchpool.cancellation.requested.v1' then case when swedish then 'Begäran om avbokning' else 'Cancellation requested' end
      when 'matchpool.cancellation.accepted.v1' then case when swedish then 'Träningsmatchen är avbokad' else 'The friendly is cancelled' end
      when 'matchpool.cancellation.declined.v1' then case when swedish then 'Träningsmatchen gäller' else 'The friendly is still on' end
      when 'matchpool.cancellation.withdrawn.v1' then case when swedish then 'Träningsmatchen gäller' else 'The friendly is still on' end
      else case when swedish then 'Besked från matchpoolen' else 'News from the match pool' end end;
    body := coalesce(team_name, case when swedish then 'Öppna matchpoolen på teamzoneapp.se.' else 'Open the match pool on teamzoneapp.se.' end);
  elsif outbox.event_type like 'publication.team_page.%' then
    -- A team page to decide, or the decision: the team, never the message.
    select team.name into team_name from core.teams team
    where outbox.payload_ref->>'team_id' ~ '^[0-9a-fA-F-]{36}$'
      and team.id = (outbox.payload_ref->>'team_id')::uuid;
    title := case outbox.event_type
      when 'publication.team_page.requested.v1' then case when swedish then 'Ansökan om lagsida' else 'Team page requested' end
      when 'publication.team_page.approved.v1' then case when swedish then 'Lagsidan är godkänd' else 'Team page approved' end
      else case when swedish then 'Ansökan om lagsida avslogs' else 'Team page request declined' end end;
    body := coalesce(team_name, case when swedish then 'Öppna Publika sidor.' else 'Open Public pages.' end);
  elsif outbox.event_type = 'effort.asked.v1' and outbox.payload_ref->>'event_id' ~ '^[0-9a-fA-F-]{36}$' then
    -- The effort question after a training: the type, team and time, and
    -- the answers 1–10 for someone with a device. Not sent once answered,
    -- opted out or closed.
    select * into event_row from core.events where id = (outbox.payload_ref->>'event_id')::uuid;
    select * into person from core.club_people where id = outbox.recipient_person_id;
    if event_row.id is null or person.id is null or not internal.effort_question_open(event_row, person)
      or exists (select 1 from core.session_effort_ratings rating
        where rating.event_id = event_row.id and rating.club_person_id = person.id) then
      return null;
    end if;
    select name into team_name from core.teams where id = event_row.owning_team_id;
    title := case when swedish then 'Hur kändes träningen?' else 'How was training?' end;
    body := concat_ws(' · ', case when swedish then 'Träning' else 'Training' end, team_name,
      internal.push_local_time(event_row.starts_at, coalesce(profile.timezone, event_row.timezone), swedish));
    if jsonb_array_length(targets) > 0 then
      delete from internal.push_effort_tokens where expires_at <= now();
      raw_token := encode(extensions.gen_random_bytes(32), 'hex');
      insert into internal.push_effort_tokens (event_id, club_person_id, recipient_profile_id, token_hash, expires_at)
      values (event_row.id, person.id, outbox.recipient_profile_id, extensions.digest(raw_token, 'sha256'),
        least(event_row.ends_at + interval '7 days', now() + interval '2 days'));
      effort := jsonb_build_object('event_id', event_row.id, 'token', raw_token);
    end if;
  else
    return null;
  end if;
  return jsonb_build_object(
    'title', title,
    'body', body,
    'route', internal.notification_deep_link(outbox),
    'response', response,
    'reply', reply,
    'effort', effort,
    'language', case when swedish then 'sv' else 'en' end,
    'targets', targets);
end;$function$;

CREATE OR REPLACE FUNCTION internal.notification_title(event_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case
  when event_type = 'message.message.sent.v1' then 'Nytt meddelande'
  when event_type = 'contact.message.received.v1' then 'Nytt meddelande via klubbsajten'
  when event_type = 'matchpool.interest.received.v1' then 'Intresse för er annons i matchpoolen'
  when event_type = 'matchpool.interest.accepted.v1' then 'Träningsmatchen är bokad'
  when event_type in ('matchpool.interest.declined.v1', 'matchpool.interest.closed.v1') then 'Besked från matchpoolen'
  when event_type = 'matchpool.message.sent.v1' then 'Nytt meddelande i matchpoolen'
  when event_type = 'matchpool.cancellation.requested.v1' then 'Begäran om avbokning'
  when event_type = 'matchpool.cancellation.accepted.v1' then 'Träningsmatchen är avbokad'
  when event_type in ('matchpool.cancellation.declined.v1', 'matchpool.cancellation.withdrawn.v1') then 'Träningsmatchen gäller'
  when event_type = 'matchpool.watch.matched.v1' then 'Ny annons som matchar er bevakning'
  when event_type = 'referee.proposed.v1' then 'Förfrågan om att döma'
  when event_type = 'referee.requested.v1' then 'En domare vill döma er match'
  when event_type = 'referee.confirmed.v1' then 'Domaren är bekräftad'
  when event_type = 'referee.declined.v1' then 'Domarförfrågan nekad'
  when event_type = 'referee.club_requested.v1' then 'En föreningsdomare vill döma'
  when event_type = 'referee.control_question.v1' then 'Dömde domaren matchen?'
  when event_type = 'referee.control_answered.v1' then 'Svar på kontrollfrågan om domaren'
  when event_type = 'referee.report_rejected.v1' then 'Domaruppdraget godkändes inte'
  when event_type = 'referee.payout_paid.v1' then 'Domarersättningen är utbetald'
  when event_type like 'referee.%' then 'Domaruppdraget är ändrat'
  when event_type like 'callup.%.cancelled.%' then 'Kallelse återkallad'
  when event_type like 'callup.%.reminded.%' then 'Påminnelse om kallelse'
  when event_type like 'callup.%' then 'Ny kallelse'
  when event_type = 'booking.rescheduled.v1' then U&'Bokningen har f\00e5tt ny tid'
  when event_type = 'booking.resource_changed.v1' then 'Bokningen har bytt resurs'
  when event_type = 'booking.resources_updated.v1' then U&'Bokningens resurser har \00e4ndrats'
   when event_type = 'booking.requested.v1' then 'Bokning att godkänna'
  when event_type = 'booking.approved.v1' then 'Bokningen är godkänd'
  when event_type = 'booking.declined.v1' then 'Bokningen nekades'
  when event_type = 'booking.cancelled.v1' then 'Bokningen är avbokad'
  when event_type = 'absence.reported.v1' then 'Frånvaroanmälan'
  when event_type like 'event.%' then 'Kalendern har uppdaterats'
  when event_type = 'publication.team_page.requested.v1' then 'Ansökan om lagsida'
  when event_type = 'publication.team_page.approved.v1' then 'Lagsidan är godkänd'
  when event_type = 'publication.team_page.rejected.v1' then 'Ansökan om lagsida avslogs'
  when event_type = 'effort.asked.v1' then 'Hur kändes träningen?'
  else 'Ny aktivitet i TeamZone' end
$function$;

CREATE OR REPLACE FUNCTION internal.notification_preview(event_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case
  when event_type = 'message.message.sent.v1' then 'Öppna inkorgen för att läsa meddelandet.'
  when event_type = 'contact.message.received.v1' then 'Öppna inkorgen för att läsa och svara.'
  when event_type like 'matchpool.%' then 'Öppna matchpoolen på teamzoneapp.se.'
  when event_type = 'referee.control_question.v1' then 'Öppna matchen för att svara.'
  when event_type in ('referee.report_rejected.v1', 'referee.payout_paid.v1') then 'Öppna Mina domaruppdrag.'
  when event_type = 'referee.control_answered.v1' then 'Öppna Domartillsättning.'
  when event_type like 'referee.%' then 'Öppna matchen för att se domarna.'
  when event_type like 'callup.%.cancelled.%' then 'En kallelse har återkallats.'
  when event_type like 'callup.%.reminded.%' then 'Du har en kallelse som behöver besvaras.'
  when event_type like 'callup.%' then 'Du har fått en kallelse.'
  when event_type = 'booking.rescheduled.v1' then U&'Aktiviteten och dess resursbokning har flyttats. Se de nya tiderna i Bokningshanteraren.'
  when event_type = 'booking.resource_changed.v1' then U&'Se den nya resursen i Bokningshanteraren. Bokningens tider och aktivitetskoppling \00e4r kvar.'
  when event_type = 'booking.resources_updated.v1' then U&'Resurser har lagts till eller tagits bort. Se bokningen i Bokningshanteraren.'
   when event_type = 'booking.requested.v1' then 'En bokning väntar på ditt godkännande i Bokningshanteraren.'
  when event_type like 'booking.%' then 'Se bokningen i Bokningshanteraren.'
  when event_type = 'absence.reported.v1' then 'Öppna aktiviteten för att se vem som inte kan komma.'
  when event_type like 'event.%' then 'Öppna kalendern för aktuell information.'
  when event_type = 'publication.team_page.requested.v1' then 'Ett lag vill ha en publik sida. Öppna Publika sidor för att besluta.'
  when event_type = 'publication.team_page.approved.v1' then 'Klubben har godkänt lagsidan. Den blir synlig när klubben publicerar den.'
  when event_type = 'publication.team_page.rejected.v1' then 'Klubben har avslagit ansökan om lagsida.'
  when event_type = 'effort.asked.v1' then 'Svara på hur ansträngande passet var, 1–10.'
  else 'Öppna TeamZone för mer information.' end
$function$;

notify pgrst, 'reload schema';
