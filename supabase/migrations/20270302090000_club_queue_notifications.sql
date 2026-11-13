-- Club functionaries hear what waits in Att hantera. A new membership
-- application or a request for a new team tells those who hold members and
-- teams club-wide (push and the notification list), as team page requests
-- already tell the publication managers. Messages from the public pages,
-- already pushed, now open the inbox on its Klubbsajt tab. The notifications
-- name the team or club and the role, never who applied. The notification
-- functions are their live versions with these additions.

-- Those who hold a capability club-wide: an active club-scoped grant.
create or replace function internal.club_capability_profiles(target_club_id uuid, target_capability text)
returns table(profile_id uuid, club_person_id uuid) language sql stable security definer set search_path = '' as $$
  select distinct on (link.profile_id) link.profile_id, link.club_person_id
  from core.capability_grants grant_row
  join core.assignments assignment on assignment.id = grant_row.assignment_id and assignment.state = 'active'
    and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
  join core.person_account_links link on link.club_id = assignment.club_id
    and link.club_person_id = assignment.club_person_id and link.state = 'active'
  where grant_row.club_id = target_club_id and grant_row.capability = target_capability
    and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
    and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
  order by link.profile_id, link.club_person_id
$$;

-- A new pending application: one notification to each members-and-teams
-- holder but the applicant.
create or replace function internal.notify_membership_application_received()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status <> 'pending' then return new; end if;
  insert into internal.notification_outbox (club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select new.club_id, new.id, 'club.application.received.v1', 'club', new.club_id,
    recipient.profile_id, recipient.club_person_id,
    jsonb_build_object('application_id', new.id, 'team_id', new.team_id)
  from internal.club_capability_profiles(new.club_id, 'club.memberships.manage') recipient
  where recipient.profile_id is distinct from new.applicant_profile_id
  on conflict do nothing;
  return new;
end;
$$;

-- A new pending team request: the same, but the one who asked.
create or replace function internal.notify_team_creation_request_received()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.state <> 'pending' then return new; end if;
  insert into internal.notification_outbox (club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select new.club_id, new.id, 'club.team_request.received.v1', 'club', new.club_id,
    recipient.profile_id, recipient.club_person_id,
    jsonb_build_object('request_id', new.id)
  from internal.club_capability_profiles(new.club_id, 'club.memberships.manage') recipient
  where recipient.profile_id is distinct from new.requester_profile_id
  on conflict do nothing;
  return new;
end;
$$;

revoke all on function internal.club_capability_profiles(uuid, text),
  internal.notify_membership_application_received(),
  internal.notify_team_creation_request_received()
  from public, anon, authenticated;

drop trigger if exists membership_application_received_notify on core.membership_applications;
create trigger membership_application_received_notify
  after insert on core.membership_applications
  for each row execute function internal.notify_membership_application_received();

drop trigger if exists team_creation_request_received_notify on core.team_creation_requests;
create trigger team_creation_request_received_notify
  after insert on core.team_creation_requests
  for each row execute function internal.notify_team_creation_request_received();

-- As live, with the two new notifications.
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
  when event_type = 'club.fee.reminder.v1' then 'Påminnelse om avgift'
  when event_type = 'club.application.received.v1' then 'Ny medlemsansökan'
  when event_type = 'club.team_request.received.v1' then 'Förfrågan om nytt lag'
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
  when event_type = 'club.fee.reminder.v1' then 'Du har en obetald avgift. Öppna Mina avgifter för att se belopp och hur du betalar.'
  when event_type = 'club.application.received.v1' then 'Någon vill gå med i klubben. Öppna Medlemsansökningar för att besluta.'
  when event_type = 'club.team_request.received.v1' then 'En ledare vill starta ett nytt lag. Öppna Förfrågningar om nya lag för att besluta.'
  else 'Öppna TeamZone för mer information.' end
$function$;

-- As live, with the two new notifications and Klubbsajt for site messages.
CREATE OR REPLACE FUNCTION internal.notification_deep_link(outbox internal.notification_outbox)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select case
    when outbox.event_type = 'club.fee.reminder.v1' then '/fees'
    when outbox.event_type like 'publication.team_page.%' then '/publication'
    when outbox.event_type = 'club.application.received.v1' then '/team?action=applications'
    when outbox.event_type = 'club.team_request.received.v1' then '/team?action=team-requests'
    -- Messages from the public pages open the inbox on its Klubbsajt tab.
    when outbox.event_type = 'contact.message.received.v1' then '/inbox?action=site'
    when outbox.event_type='message.message.sent.v1'
      and outbox.payload_ref->>'thread_id'~'^[0-9a-fA-F-]{36}$'
      then '/inbox?thread='||(outbox.payload_ref->>'thread_id')
    when outbox.event_type='matchpool.watch.matched.v1'
      and outbox.payload_ref->>'listing_id'~'^[0-9a-fA-F-]{36}$'
      then '/inbox?poolad='||(outbox.payload_ref->>'listing_id')
    when outbox.event_type like 'matchpool.%'
      and outbox.payload_ref->>'interest_id'~'^[0-9a-fA-F-]{36}$'
      then '/inbox?pool='||(outbox.payload_ref->>'interest_id')
    -- REF-01: the team side opens the match; the referee side the home page
    -- with the referee assignments.
    when outbox.event_type like 'referee.%' and outbox.payload_ref->>'side' = 'referee'
      then '/home'
    -- REF-02: answers to control questions go to the domaransvarig's home.
    when outbox.event_type = 'referee.control_answered.v1'
      then '/home'
    when outbox.event_type like 'referee.%'
      and outbox.payload_ref->>'event_id'~'^[0-9a-fA-F-]{36}$'
      then '/calendar/event/'||(outbox.payload_ref->>'event_id')
    when outbox.event_type like 'callup.%'
      and outbox.payload_ref->>'event_id'~'^[0-9a-fA-F-]{36}$'
      then '/calendar/event/'||(outbox.payload_ref->>'event_id')
    when outbox.aggregate_type='event'
      then '/calendar/event/'||outbox.aggregate_id::text
    else '/inbox'
  end;
$function$;

-- As live, with the two new notifications.
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
  elsif outbox.event_type = 'club.fee.reminder.v1' then
    -- A fee reminder: the round and the amount, nothing about the person.
    -- Not sent once every fee it names is paid or waived.
    if not exists (select 1 from core.club_fees fee
        where fee.id in (select value::uuid from jsonb_array_elements_text(outbox.payload_ref->'fee_ids'))
          and fee.state = 'open') then
      return null;
    end if;
    select fee_round.title into team_name from core.club_fee_rounds fee_round
    where outbox.payload_ref->>'round_id' ~ '^[0-9a-fA-F-]{36}$'
      and fee_round.id = (outbox.payload_ref->>'round_id')::uuid;
    title := case when swedish then 'Påminnelse om avgift' else 'Fee reminder' end;
    body := concat_ws(' · ', team_name,
      ((coalesce((outbox.payload_ref->>'amount')::bigint, 0) / 100)::text || ' kr'));
  elsif outbox.event_type = 'club.application.received.v1' then
    -- An application to decide: the team (or the club) and the role asked
    -- for, never who applied. Not sent once it is decided or withdrawn.
    select coalesce(team.name, club.name),
      case application.requested_role
        when 'player' then case when swedish then 'spelare' else 'player' end
        when 'leader' then case when swedish then 'ledare' else 'leader' end
        when 'guardian' then case when swedish then 'vårdnadshavare' else 'guardian' end
        when 'club_functionary' then case when swedish then 'klubbfunktionär' else 'club functionary' end
        else case when swedish then 'medlem' else 'member' end end
    into team_name, kind
    from core.membership_applications application
    join core.clubs club on club.id = application.club_id
    left join core.teams team on team.id = application.team_id
    where outbox.payload_ref->>'application_id' ~ '^[0-9a-fA-F-]{36}$'
      and application.id = (outbox.payload_ref->>'application_id')::uuid
      and application.status = 'pending';
    if team_name is null then return null; end if;
    title := case when swedish then 'Ny medlemsansökan' else 'New membership application' end;
    body := concat_ws(' · ', team_name, kind);
  elsif outbox.event_type = 'club.team_request.received.v1' then
    -- A new team to decide: the team name asked for. Not sent once decided.
    select request.team_name into team_name
    from core.team_creation_requests request
    where outbox.payload_ref->>'request_id' ~ '^[0-9a-fA-F-]{36}$'
      and request.id = (outbox.payload_ref->>'request_id')::uuid
      and request.state = 'pending';
    if team_name is null then return null; end if;
    title := case when swedish then 'Förfrågan om nytt lag' else 'New team requested' end;
    body := team_name;
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

notify pgrst, 'reload schema';
