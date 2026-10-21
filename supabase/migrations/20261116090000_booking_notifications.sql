-- Bokningshanterare: notifications. Admins hear of a request to approve; the
-- one who booked hears it was approved, declined, or cancelled by an admin.
-- Everyone gets them in Webtools; those in the linked TeamZone club also as
-- a push and in the app's inbox (or on the activity the booking is for).

create table core.booking_notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references core.profiles(id),
  organization_id uuid not null references core.booking_organizations(id) on delete cascade,
  booking_id uuid not null references core.booking_bookings(id) on delete cascade,
  kind text not null check (kind in ('requested', 'approved', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index booking_notifications_profile on core.booking_notifications (profile_id, created_at desc);
alter table core.booking_notifications enable row level security;
revoke all on core.booking_notifications from public, anon, authenticated;

-- The organisation's admins: members with the admin role and, through the
-- club link, the club's admins.
create or replace function internal.booking_admin_profiles(target_organization_id uuid)
returns table(profile_id uuid) language sql stable security definer set search_path = '' as $$
  select member.profile_id from core.booking_members member
  where member.organization_id = target_organization_id and member.role = 'admin'
  union
  select link.profile_id
  from core.booking_organizations org
  join core.capability_grants grant_row on grant_row.club_id = org.teamzone_club_id
    and grant_row.capability = 'club.memberships.manage' and grant_row.scope_type = 'club'
    and grant_row.scope_id = org.teamzone_club_id
    and grant_row.starts_at <= now() and (grant_row.ends_at is null or grant_row.ends_at > now())
  join core.assignments assignment on assignment.id = grant_row.assignment_id and assignment.state = 'active'
    and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
  join core.person_account_links link on link.club_id = assignment.club_id
    and link.club_person_id = assignment.club_person_id and link.state = 'active'
  where org.id = target_organization_id
$$;

-- One notification to each recipient but the actor: in Webtools, and as a
-- TeamZone push for those in the linked club.
create or replace function internal.booking_notify(target_booking_id uuid, notify_kind text, recipients uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare booking core.booking_bookings; club uuid;
begin
  select * into booking from core.booking_bookings where id = target_booking_id;
  if booking.id is null then return; end if;
  insert into core.booking_notifications (profile_id, organization_id, booking_id, kind)
  select distinct recipient, booking.organization_id, booking.id, notify_kind
  from unnest(recipients) recipient
  where recipient is not null and recipient is distinct from auth.uid();
  select teamzone_club_id into club from core.booking_organizations where id = booking.organization_id;
  if club is null then return; end if;
  insert into internal.notification_outbox (club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select club, gen_random_uuid(), 'booking.' || notify_kind || '.v1',
    case when booking.event_id is null then 'booking' else 'event' end,
    coalesce(booking.event_id, booking.id),
    person.profile_id, person.club_person_id,
    jsonb_build_object('booking_id', booking.id, 'event_id', booking.event_id)
  from (
    select distinct on (link.profile_id) link.profile_id, link.club_person_id
    from core.person_account_links link
    where link.club_id = club and link.state = 'active'
      and link.profile_id = any(recipients) and link.profile_id is distinct from auth.uid()
    order by link.profile_id, link.club_person_id
  ) person
  on conflict do nothing;
end;
$$;

-- As in 20261115090000, telling the admins of a request to approve.
create or replace function internal.create_booking_for_actor(
  target_resource_id uuid, booking_starts_at timestamptz, booking_ends_at timestamptz,
  booking_title text, booking_notes text, target_team_id uuid, target_event_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  resource core.booking_resources;
  actor_role text;
  created core.booking_bookings;
  event_row core.events;
begin
  select * into resource from core.booking_resources where id = target_resource_id;
  actor_role := internal.booking_actor_role(resource.organization_id);
  if resource.id is null or actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  if not resource.active then raise invalid_parameter_value using message = 'resource_inactive'; end if;
  if booking_ends_at <= booking_starts_at or booking_ends_at - booking_starts_at > interval '31 days' then
    raise invalid_parameter_value using message = 'invalid_time';
  end if;
  if booking_ends_at <= now() then raise invalid_parameter_value using message = 'in_the_past'; end if;
  if target_team_id is not null and not exists (
    select 1 from internal.booking_actor_teams(resource.organization_id) t where t.team_id = target_team_id) then
    raise insufficient_privilege using message = 'not_team_leader';
  end if;
  if target_event_id is not null then
    if target_team_id is null then raise invalid_parameter_value using message = 'event_needs_team'; end if;
    select * into event_row from core.events where id = target_event_id;
    if event_row.id is null or not internal.actor_can_read_event(target_event_id)
      or not exists (select 1 from core.event_teams relation where relation.event_id = target_event_id and relation.team_id = target_team_id) then
      raise insufficient_privilege using message = 'event_not_found';
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_resource_id::text, 0));
  if exists (select 1 from core.booking_bookings other
    where other.resource_id = target_resource_id and other.status in ('pending', 'confirmed')
      and other.starts_at < booking_ends_at and other.ends_at > booking_starts_at) then
    raise exclusion_violation using message = 'resource_busy';
  end if;
  insert into core.booking_bookings (organization_id, resource_id, starts_at, ends_at, title, notes, status, booked_by, team_id, event_id,
    decided_by, decided_at)
  values (resource.organization_id, resource.id, booking_starts_at, booking_ends_at, nullif(btrim(booking_title), ''),
    nullif(btrim(booking_notes), ''),
    case when resource.requires_approval and actor_role <> 'admin' then 'pending' else 'confirmed' end,
    auth.uid(), target_team_id, target_event_id,
    case when resource.requires_approval and actor_role <> 'admin' then null else auth.uid() end,
    case when resource.requires_approval and actor_role <> 'admin' then null else now() end)
  returning * into created;
  if created.status = 'pending' then
    perform internal.booking_notify(created.id, 'requested',
      array(select profile_id from internal.booking_admin_profiles(resource.organization_id)));
  end if;
  return internal.booking_json(created, actor_role);
end;
$$;

-- As in 20261115090000, telling the one who booked when an admin cancels.
create or replace function internal.cancel_booking_for_actor(target_booking_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare booking core.booking_bookings;
begin
  select * into booking from core.booking_bookings where id = target_booking_id;
  if booking.id is null or internal.booking_actor_role(booking.organization_id) is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if booking.booked_by <> auth.uid() and internal.booking_actor_role(booking.organization_id) <> 'admin' then
    raise insufficient_privilege using message = 'not_allowed';
  end if;
  if booking.status not in ('pending', 'confirmed') then raise invalid_parameter_value using message = 'not_active'; end if;
  update core.booking_bookings set status = 'cancelled', revision = revision + 1 where id = target_booking_id;
  if booking.booked_by <> auth.uid() then
    perform internal.booking_notify(booking.id, 'cancelled', array[booking.booked_by]);
  end if;
end;
$$;

-- As in 20261115090000, telling the one who booked of the decision.
create or replace function internal.decide_booking_for_actor(target_booking_id uuid, approve boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare booking core.booking_bookings;
begin
  select * into booking from core.booking_bookings where id = target_booking_id;
  if booking.id is null or internal.booking_actor_role(booking.organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message = 'not_admin';
  end if;
  if booking.status <> 'pending' then raise invalid_parameter_value using message = 'not_pending'; end if;
  update core.booking_bookings set status = case when approve then 'confirmed' else 'declined' end,
    decided_by = auth.uid(), decided_at = now(), revision = revision + 1
  where id = target_booking_id;
  perform internal.booking_notify(booking.id, case when approve then 'approved' else 'declined' end, array[booking.booked_by]);
end;
$$;

-- Your notifications in Webtools, newest first, with the unread count.
create or replace function internal.list_booking_notifications_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'unread', (select count(*) from core.booking_notifications n where n.profile_id = auth.uid() and n.read_at is null),
    'items', coalesce((select jsonb_agg(item order by item->>'created_at' desc) from (
      select jsonb_build_object(
        'id', n.id, 'kind', n.kind, 'created_at', n.created_at, 'read', n.read_at is not null,
        'organization_id', n.organization_id, 'organization_name', org.name,
        'booking_id', booking.id, 'resource_name', resource.name, 'title', booking.title,
        'starts_at', booking.starts_at, 'ends_at', booking.ends_at, 'status', booking.status,
        'booked_by_name', internal.booking_person_name(booking.booked_by)
      ) item
      from core.booking_notifications n
      join core.booking_organizations org on org.id = n.organization_id
      join core.booking_bookings booking on booking.id = n.booking_id
      join core.booking_resources resource on resource.id = booking.resource_id
      where n.profile_id = auth.uid()
      order by n.created_at desc
      limit 50) items), '[]'::jsonb)
  )
$$;

create or replace function internal.mark_booking_notifications_read_for_actor(notification_ids uuid[])
returns void language sql security definer set search_path = '' as $$
  update core.booking_notifications set read_at = now()
  where profile_id = auth.uid() and read_at is null
    and (notification_ids is null or id = any(notification_ids))
$$;

create or replace function api.list_booking_notifications() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_booking_notifications_for_actor() $$;
create or replace function api.mark_booking_notifications_read(notification_ids uuid[] default null) returns void language sql security invoker set search_path = '' as
$$ select internal.mark_booking_notifications_read_for_actor(notification_ids) $$;

revoke all on function internal.booking_admin_profiles(uuid), internal.booking_notify(uuid, text, uuid[]),
  internal.list_booking_notifications_for_actor(), internal.mark_booking_notifications_read_for_actor(uuid[]),
  api.list_booking_notifications(), api.mark_booking_notifications_read(uuid[])
from public, anon, authenticated;
grant execute on function internal.list_booking_notifications_for_actor(), internal.mark_booking_notifications_read_for_actor(uuid[]),
  api.list_booking_notifications(), api.mark_booking_notifications_read(uuid[])
to authenticated;

-- As in 20261113090000, with booking notifications.
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

-- As in 20261113090000, with booking notifications.
create or replace function internal.notification_title(event_type text)
returns text language sql immutable set search_path = '' as $$
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
  else 'Ny aktivitet i TeamZone' end
$$;

-- As in 20261113090000, with booking notifications.
create or replace function internal.notification_preview(event_type text)
returns text language sql immutable set search_path = '' as $$
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
  else 'Öppna TeamZone för mer information.' end
$$;
