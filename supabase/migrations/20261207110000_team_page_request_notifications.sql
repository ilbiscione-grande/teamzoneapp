-- Team page requests are heard. A request tells the club's publication
-- managers (push and inbox), the decision tells the one who asked; the club
-- home counts the requests waiting, which the assistant shows as a club duty.
-- The notifications name the team, never the request's message. The
-- functions are their current versions with these additions.

-- Those who manage the club's publication: an active club-wide grant.
create or replace function internal.publication_manager_profiles(target_club_id uuid)
returns table(profile_id uuid) language sql stable security definer set search_path = '' as $$
  select distinct link.profile_id
  from core.capability_grants grant_row
  join core.assignments assignment on assignment.id = grant_row.assignment_id and assignment.state = 'active'
    and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
  join core.person_account_links link on link.club_id = assignment.club_id
    and link.club_person_id = assignment.club_person_id and link.state = 'active'
  where grant_row.club_id = target_club_id and grant_row.capability = 'publication.manage'
    and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
    and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
$$;

-- One notification to each recipient but the actor, in the club's outbox.
create or replace function internal.notify_team_page_request(target_request_id uuid, notify_kind text, recipients uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare request_row core.team_publication_requests;
begin
  select * into request_row from core.team_publication_requests where id = target_request_id;
  if request_row.id is null then return; end if;
  insert into internal.notification_outbox (club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select request_row.club_id, gen_random_uuid(), 'publication.team_page.' || notify_kind || '.v1',
    'team', request_row.team_id, person.profile_id, person.club_person_id,
    jsonb_build_object('request_id', request_row.id, 'team_id', request_row.team_id)
  from (
    select distinct on (link.profile_id) link.profile_id, link.club_person_id
    from core.person_account_links link
    where link.club_id = request_row.club_id and link.state = 'active'
      and link.profile_id = any(recipients) and link.profile_id is distinct from auth.uid()
    order by link.profile_id, link.club_person_id
  ) person
  on conflict do nothing;
end;
$$;

revoke all on function internal.publication_manager_profiles(uuid), internal.notify_team_page_request(uuid, text, uuid[])
  from public, anon, authenticated;

-- As before, telling the club's publication managers.
CREATE OR REPLACE FUNCTION internal.request_team_publication_for_actor(target_club_id uuid, target_team_id uuid, request_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare existing_id uuid;new_id uuid;
begin
 if auth.uid() is null or not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.manage')
  or not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active')
 then raise insufficient_privilege using message='not_found';end if;
 if length(coalesce(request_message,''))>1000 then raise invalid_parameter_value using message='invalid_message';end if;
 perform pg_advisory_xact_lock(hashtextextended('team-publication-request:'||target_team_id::text,0));
 select id into existing_id from core.team_publication_requests where team_id=target_team_id and status='pending';
 if existing_id is not null then return jsonb_build_object('id',existing_id,'status','pending');end if;
 insert into core.team_publication_requests(club_id,team_id,requested_by,message)
 values(target_club_id,target_team_id,auth.uid(),btrim(coalesce(request_message,''))) returning id into new_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,
  aggregate_id,aggregate_revision,metadata)
 values(target_club_id,auth.uid(),'publication.team.requested','team',target_team_id,1,
  jsonb_build_object('request_id',new_id));
 perform internal.notify_team_page_request(new_id,'requested',
  array(select profile_id from internal.publication_manager_profiles(target_club_id)));
 return jsonb_build_object('id',new_id,'status','pending');
end;$function$;

-- As before, telling the one who asked.
CREATE OR REPLACE FUNCTION internal.decide_team_publication_for_actor(request_id uuid, approve boolean, note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare request_row core.team_publication_requests%rowtype;
begin
 select * into request_row from core.team_publication_requests where id=request_id for update;
 if request_row.id is null or auth.uid() is null or
   not internal.actor_has_capability(request_row.club_id,null,'publication.manage')
 then raise insufficient_privilege using message='not_found';end if;
 if length(coalesce(note,''))>1000 then raise invalid_parameter_value using message='invalid_note';end if;
 if request_row.status<>'pending' then
  return jsonb_build_object('id',request_row.id,'status',request_row.status);
 end if;
 update core.team_publication_requests set status=case when approve then 'approved' else 'rejected' end,
  decided_by=auth.uid(),decided_at=now(),decision_note=nullif(btrim(coalesce(note,'')),'')
 where id=request_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,
  aggregate_id,aggregate_revision,metadata)
 values(request_row.club_id,auth.uid(),'publication.team.decided','team',request_row.team_id,1,
  jsonb_build_object('request_id',request_id,'approved',approve));
 perform internal.notify_team_page_request(request_id,case when approve then 'approved' else 'rejected' end,
  array[request_row.requested_by]);
 return jsonb_build_object('id',request_id,'status',case when approve then 'approved' else 'rejected' end);
end;$function$;

-- As before, with team page notifications.
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
  when event_type = 'booking.requested.v1' then 'Bokning att godkänna'
  when event_type = 'booking.approved.v1' then 'Bokningen är godkänd'
  when event_type = 'booking.declined.v1' then 'Bokningen nekades'
  when event_type = 'booking.cancelled.v1' then 'Bokningen är avbokad'
  when event_type = 'absence.reported.v1' then 'Frånvaroanmälan'
  when event_type like 'event.%' then 'Kalendern har uppdaterats'
  when event_type = 'publication.team_page.requested.v1' then 'Ansökan om lagsida'
  when event_type = 'publication.team_page.approved.v1' then 'Lagsidan är godkänd'
  when event_type = 'publication.team_page.rejected.v1' then 'Ansökan om lagsida avslogs'
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
  when event_type = 'booking.requested.v1' then 'En bokning väntar på ditt godkännande i Bokningshanteraren.'
  when event_type like 'booking.%' then 'Se bokningen i Bokningshanteraren.'
  when event_type = 'absence.reported.v1' then 'Öppna aktiviteten för att se vem som inte kan komma.'
  when event_type like 'event.%' then 'Öppna kalendern för aktuell information.'
  when event_type = 'publication.team_page.requested.v1' then 'Ett lag vill ha en publik sida. Öppna Publika sidor för att besluta.'
  when event_type = 'publication.team_page.approved.v1' then 'Klubben har godkänt lagsidan. Den blir synlig när klubben publicerar den.'
  when event_type = 'publication.team_page.rejected.v1' then 'Klubben har avslagit ansökan om lagsida.'
  else 'Öppna TeamZone för mer information.' end
$function$;

-- Team page notifications open Public pages.
create or replace function internal.notification_deep_link(outbox internal.notification_outbox)
 returns text language sql stable set search_path to '' as $function$
  select case
    when outbox.event_type like 'publication.team_page.%' then '/publication'
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

-- As before, with the team page requests waiting for those who decide them.
CREATE OR REPLACE FUNCTION internal.get_club_home_for_actor(target_context_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_context record;
  own_person_ids uuid[];
  own_name text;
  can_board boolean;
  can_economy boolean;
  can_members boolean;
  can_publication boolean;
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  select * into actor_context from internal.get_my_contexts_for_actor()
  where context_id = target_context_id;
  if actor_context.context_id is null or actor_context.team_id is not null then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select array_agg(link.club_person_id), min(person.display_name)
  into own_person_ids, own_name
  from core.person_account_links link
  join core.club_people person on person.id = link.club_person_id and person.club_id = link.club_id
  where link.profile_id = auth.uid() and link.club_id = actor_context.club_id and link.state = 'active';

  can_board := internal.actor_has_capability(actor_context.club_id, null, 'board.read');
  can_economy := internal.actor_has_capability(actor_context.club_id, null, 'economy.read');
  can_members := internal.actor_has_capability(actor_context.club_id, null, 'club.memberships.manage');
  can_publication := internal.actor_has_capability(actor_context.club_id, null, 'publication.manage');

  return jsonb_build_object(
    'club_id', actor_context.club_id,
    'own_name', own_name,
    'own_offices', coalesce((
      select jsonb_agg(distinct mandate.office)
      from core.board_mandates mandate
      join core.assignments assignment on assignment.id = mandate.assignment_id and assignment.club_id = mandate.club_id
      where mandate.club_id = actor_context.club_id and mandate.state = 'active'
        and mandate.starts_at <= now() and mandate.ends_at > now()
        and assignment.club_person_id = any(own_person_ids)
    ), '[]'::jsonb),
    'board', case when can_board then jsonb_build_object(
      'active_mandates', (select count(*) from core.board_mandates mandate
        where mandate.club_id = actor_context.club_id and mandate.state = 'active'
          and mandate.starts_at <= now() and mandate.ends_at > now()),
      'pending_changes', (select count(*) from core.board_mandate_changes change
        where change.club_id = actor_context.club_id and change.state = 'pending')
    ) end,
    'economy', case when can_economy then jsonb_build_object(
      'accounts', (select count(*) from core.economy_accounts account
        where account.club_id = actor_context.club_id and account.state = 'active'),
      'pending_entries', (select count(*) from core.economy_ledger_entries entry
        where entry.club_id = actor_context.club_id and entry.state = 'pending')
    ) end,
    'members', case when can_members then jsonb_build_object(
      'pending_applications', (select count(*) from core.membership_applications application
        where application.club_id = actor_context.club_id and application.status = 'pending'),
      'pending_team_requests', (select count(*) from core.team_creation_requests request
        where request.club_id = actor_context.club_id and request.state = 'pending')
    ) end,
    'publication', case when can_publication then jsonb_build_object(
      'pending_team_pages', (select count(*) from core.team_publication_requests request
        where request.club_id = actor_context.club_id and request.status = 'pending')
    ) end,
    'can_announce', internal.actor_has_capability(actor_context.club_id, null, 'club.messaging.manage'),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'team_id', team.id,
        'name', team.name,
        'member_count', (select count(*) from core.assignments assignment
          where assignment.club_id = team.club_id and assignment.team_id = team.id
            and assignment.state = 'active' and assignment.starts_at <= now()
            and (assignment.ends_at is null or assignment.ends_at > now())),
        'upcoming', coalesce((
          select jsonb_agg(jsonb_build_object(
            'title', upcoming.title, 'event_type', upcoming.event_type,
            'starts_at', upcoming.starts_at, 'ends_at', upcoming.ends_at,
            'all_day', upcoming.all_day, 'location_name', upcoming.location_name
          ) order by upcoming.starts_at)
          from (
            select event_row.title, event_row.event_type, event_row.starts_at,
              event_row.ends_at, event_row.all_day, location.name location_name
            from core.events event_row
            join core.event_teams relation on relation.event_id = event_row.id
              and relation.club_id = event_row.club_id and relation.team_id = team.id
            left join core.event_locations location on location.id = event_row.location_id
            where event_row.club_id = team.club_id and event_row.state = 'scheduled'
              and event_row.archived_at is null and event_row.ends_at > now()
            order by event_row.starts_at
            limit 5
          ) upcoming
        ), '[]'::jsonb)
      ) order by team.name)
      from core.teams team
      where team.club_id = actor_context.club_id and team.status = 'active'
    ), '[]'::jsonb)
  );
end;
$function$;

-- Requests already waiting were asked before anyone heard: tell the
-- managers of each once now.
do $$ declare request_row record;
begin
  for request_row in select id, club_id from core.team_publication_requests where status = 'pending' loop
    perform internal.notify_team_page_request(request_row.id, 'requested',
      array(select profile_id from internal.publication_manager_profiles(request_row.club_id)));
  end loop;
end $$;
