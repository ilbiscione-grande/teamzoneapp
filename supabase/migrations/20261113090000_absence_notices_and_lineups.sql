-- UX review 2026-10-19, the player's view:
-- 1. Absence notices. An activity can do without callups ("Kallelse behövs
--    inte", events.callups_required = false): everyone in the team is then
--    expected, and players (or guardians) report when they cannot come.
--    Leaders are told; the notice prefills the attendance; the follow-up
--    counts reported absences. A team chooses the default for its new and
--    coming activities.
-- 2. The starting line-up of a match, set under Förberedelser and shown to
--    the players when the leader chooses to; match mode stays with leaders.

create table if not exists core.team_event_settings (
  team_id uuid primary key references core.teams(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  callups_required boolean not null,
  updated_by uuid references core.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table core.team_event_settings enable row level security;
revoke all on core.team_event_settings from public, anon, authenticated;

create table if not exists core.event_absence_notices (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  club_person_id uuid not null references core.club_people(id) on delete cascade,
  reason_code text not null check (reason_code in ('illness', 'injury', 'unavailable', 'transport', 'other')),
  reason_text text check (length(reason_text) <= 500),
  reported_by uuid references core.profiles(id) on delete set null,
  reported_at timestamptz not null default now(),
  withdrawn_at timestamptz
);
create unique index if not exists event_absence_notices_active
  on core.event_absence_notices(event_id, club_person_id) where withdrawn_at is null;
alter table core.event_absence_notices enable row level security;
revoke all on core.event_absence_notices from public, anon, authenticated;

create table if not exists core.event_lineups (
  event_id uuid primary key references core.events(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  formation text check (length(formation) <= 20),
  starters jsonb not null default '[]'::jsonb check (jsonb_typeof(starters) = 'array'),
  substitutes jsonb not null default '[]'::jsonb check (jsonb_typeof(substitutes) = 'array'),
  published boolean not null default false,
  revision bigint not null default 1,
  updated_by uuid references core.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table core.event_lineups enable row level security;
revoke all on core.event_lineups from public, anon, authenticated;

create or replace function internal.actor_changes_team_events(target_team_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from core.teams team where team.id = target_team_id
    and (internal.actor_has_capability(team.club_id, team.id, 'event.squad.manage')
      or internal.actor_has_capability(team.club_id, team.id, 'event.manage')
      or internal.actor_manages_club(team.club_id)))
$$;

-- New activities follow the team's choice.
create or replace function internal.apply_team_event_settings()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.callups_required and exists (select 1 from core.team_event_settings setting
      where setting.team_id = new.owning_team_id and not setting.callups_required) then
    new.callups_required := false;
  end if;
  return new;
end;$$;
drop trigger if exists events_apply_team_event_settings on core.events;
create trigger events_apply_team_event_settings before insert on core.events
for each row execute function internal.apply_team_event_settings();

create or replace function internal.get_team_event_settings_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare team_row core.teams%rowtype;
begin
  select * into team_row from core.teams where id = target_team_id;
  if team_row.id is null or not exists (select 1 from core.person_account_links link
      where link.club_id = team_row.club_id and link.profile_id = auth.uid() and link.state = 'active') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'callups_required', coalesce((select setting.callups_required from core.team_event_settings setting
      where setting.team_id = team_row.id), true),
    'can_change', internal.actor_changes_team_events(team_row.id));
end;$$;

-- The team's choice; coming activities without sent callups follow it.
create or replace function internal.set_team_event_settings_for_actor(target_team_id uuid, callups_required boolean)
returns integer language plpgsql security definer set search_path = '' as $$
declare team_row core.teams%rowtype; changed integer;
begin
  select * into team_row from core.teams where id = target_team_id;
  if team_row.id is null or not internal.actor_changes_team_events(team_row.id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if callups_required is null then raise invalid_parameter_value using message = 'invalid_input'; end if;
  insert into core.team_event_settings(team_id, club_id, callups_required, updated_by)
  values (team_row.id, team_row.club_id, set_team_event_settings_for_actor.callups_required, auth.uid())
  on conflict (team_id) do update set callups_required = excluded.callups_required,
    updated_by = excluded.updated_by, updated_at = now();
  update core.events event_row
  set callups_required = set_team_event_settings_for_actor.callups_required, revision = event_row.revision + 1
  where event_row.owning_team_id = team_row.id and event_row.starts_at > now()
    and event_row.state in ('draft', 'scheduled')
    and event_row.callups_required is distinct from set_team_event_settings_for_actor.callups_required
    and not exists (select 1 from core.squad_revisions squad where squad.event_id = event_row.id
      and squad.state = 'sent');
  get diagnostics changed = row_count;
  return changed;
end;$$;

-- Someone in one of the event's teams, as player or leader.
create or replace function internal.event_expects_person(target_event_id uuid, target_person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from core.events event_row
    join core.event_teams relation on relation.event_id = event_row.id
    join core.assignments assignment on assignment.team_id = relation.team_id
      and assignment.club_id = event_row.club_id and assignment.club_person_id = target_person_id
      and assignment.state = 'active' and assignment.role_package in ('player', 'leader')
      and assignment.starts_at <= event_row.starts_at
      and (assignment.ends_at is null or assignment.ends_at > event_row.starts_at)
    where event_row.id = target_event_id)
$$;

create or replace function internal.report_event_absence_for_actor(target_event_id uuid, target_person_id uuid,
  reason_code text, reason_text text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype; clean text := nullif(btrim(coalesce(reason_text, '')), ''); new_id uuid;
  person_name text;
begin
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or target_person_id is null
    or not internal.actor_represents_club_person(event_row.club_id, target_person_id)
    or not internal.event_expects_person(event_row.id, target_person_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if event_row.callups_required or event_row.state not in ('draft', 'scheduled') or event_row.ends_at <= now() then
    raise invalid_parameter_value using message = 'not_open';
  end if;
  if reason_code is null or reason_code not in ('illness', 'injury', 'unavailable', 'transport', 'other')
    or (reason_code = 'other' and (clean is null or length(clean) not between 2 and 500))
    or length(clean) > 500 then
    raise invalid_parameter_value using message = 'invalid_decline_reason';
  end if;
  update core.event_absence_notices set withdrawn_at = now()
  where event_id = event_row.id and club_person_id = target_person_id and withdrawn_at is null;
  insert into core.event_absence_notices(event_id, club_id, club_person_id, reason_code, reason_text, reported_by)
  values (event_row.id, event_row.club_id, target_person_id, reason_code, clean, auth.uid())
  returning id into new_id;
  -- The team's leaders hear of it; the reason stays on the event page.
  insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select event_row.club_id, gen_random_uuid(), 'absence.reported.v1', 'event', event_row.id,
    recipient.profile_id, recipient.club_person_id,
    jsonb_build_object('event_id', event_row.id, 'notice_id', new_id)
  from internal.match_pool_recipients(event_row.club_id, event_row.owning_team_id) recipient
  where recipient.profile_id is distinct from auth.uid()
  on conflict do nothing;
  return new_id;
end;$$;

create or replace function internal.withdraw_event_absence_for_actor(target_event_id uuid, target_person_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype;
begin
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or not internal.actor_represents_club_person(event_row.club_id, target_person_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if event_row.ends_at <= now() then raise invalid_parameter_value using message = 'not_open'; end if;
  update core.event_absence_notices set withdrawn_at = now()
  where event_id = event_row.id and club_person_id = target_person_id and withdrawn_at is null;
end;$$;

-- Notices for those who manage the squad or attendance; others their own.
create or replace function internal.get_event_absence_notices_for_actor(target_event_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('person_id', notice.club_person_id, 'name', person.display_name,
      'reason_code', notice.reason_code, 'reason_text', notice.reason_text, 'reported_at', notice.reported_at)
      order by person.display_name), '[]'::jsonb)
  from core.event_absence_notices notice
  join core.club_people person on person.id = notice.club_person_id
  where notice.event_id = target_event_id and notice.withdrawn_at is null
    and (internal.actor_can_manage_squad(target_event_id) or internal.actor_can_manage_attendance(target_event_id)
      or internal.actor_represents_club_person(notice.club_id, notice.club_person_id))
$$;

-- The people in the event's teams the signed-in person answers for: self,
-- and children for a guardian.
create or replace function internal.event_represented_people(target_event_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(distinct jsonb_build_object('person_id', person.id, 'name', person.display_name)), '[]'::jsonb)
  from core.events event_row
  join core.event_teams relation on relation.event_id = event_row.id
  join core.assignments assignment on assignment.team_id = relation.team_id and assignment.club_id = event_row.club_id
    and assignment.state = 'active' and assignment.role_package in ('player', 'leader')
    and assignment.starts_at <= event_row.starts_at
    and (assignment.ends_at is null or assignment.ends_at > event_row.starts_at)
  join core.club_people person on person.id = assignment.club_person_id
  where event_row.id = target_event_id
    and internal.actor_represents_club_person(event_row.club_id, person.id)
$$;

-- As in 20260928104134, with the absence notices.
create or replace function api.get_event_squad(target_event_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select internal.get_event_squad_for_actor(target_event_id)||jsonb_build_object(
  'decline_reasons',internal.get_visible_decline_reasons_for_actor(target_event_id),
  'attendance',internal.get_event_attendance_for_actor(target_event_id),
  'absence_notices',internal.get_event_absence_notices_for_actor(target_event_id),
  'represented_people',internal.event_represented_people(target_event_id)
 )
$$;

-- As in 20261017090000, with reported absences.
create or replace function internal.event_attendance_summary(target_event_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 with called as(
  select c.club_person_id,c.state from core.callups c where c.event_id=target_event_id and c.state<>'cancelled'
 ),facts as(
  select a.club_person_id,a.status,a.minutes,
   (not exists(select 1 from called) or exists(select 1 from called c where c.club_person_id=a.club_person_id)) as expected
  from core.attendance_facts a where a.event_id=target_event_id
 ),counts as(
  select
   (select count(*) from called) called,
   (select count(*) from called where state='accepted') accepted,
   (select count(*) from called where state='declined') declined,
   (select count(*) from called where state='pending') pending,
   (select count(*) from facts where expected and status='present') present,
   (select count(*) from facts where expected and status='late') late,
   (select count(*) from facts where expected and status='partial') partial,
   (select count(*) from facts where expected and status='absent') absent,
   (select count(*) from facts where expected and status<>'unknown') registered,
   (select count(*) from facts where not expected and status in('present','late','partial')) extra,
   (select round(avg(minutes)) from facts where expected and status='late') late_minutes,
   (select count(*) from called c where not exists(select 1 from facts f where f.club_person_id=c.club_person_id and f.status<>'unknown')) unregistered,
   (select count(*) from core.event_absence_notices n where n.event_id=target_event_id and n.withdrawn_at is null) notices,
   (select count(*) from facts f where f.expected and f.status='absent' and exists(select 1 from core.event_absence_notices n
     where n.event_id=target_event_id and n.club_person_id=f.club_person_id and n.withdrawn_at is null)) absent_reported
 )
 select jsonb_build_object('called',called,'accepted',accepted,'declined',declined,'pending',pending,
  'present',present,'late',late,'partial',partial,'absent',absent,'registered',registered,
  'extra',extra,'unregistered',unregistered,'late_minutes_avg',late_minutes,
  'absence_notices',notices,'absent_reported',absent_reported,
  'attendance_rate',case when registered=0 then null
   else round(100.0*(present+late+partial)/registered,1) end,
  'response_rate',case when called=0 then null else round(100.0*(accepted+declined)/called,1) end)
 from counts
$$;

create or replace function internal.lineup_json(target_event_id uuid, can_edit boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('event_id', target_event_id, 'can_edit', can_edit,
    'formation', lineup.formation, 'published', coalesce(lineup.published, false),
    'revision', coalesce(lineup.revision, 0),
    'starters', coalesce((select jsonb_agg(jsonb_build_object('person_id', item.value->>'person_id',
        'position', item.value->>'position', 'name', person.display_name) order by item.ordinality)
      from jsonb_array_elements(lineup.starters) with ordinality as item(value, ordinality)
      left join core.club_people person on person.id::text = item.value->>'person_id'), '[]'::jsonb),
    'substitutes', coalesce((select jsonb_agg(jsonb_build_object('person_id', item.value->>'person_id',
        'name', person.display_name) order by item.ordinality)
      from jsonb_array_elements(lineup.substitutes) with ordinality as item(value, ordinality)
      left join core.club_people person on person.id::text = item.value->>'person_id'), '[]'::jsonb))
  from (select 1) one left join core.event_lineups lineup on lineup.event_id = target_event_id
$$;

-- The line-up: always for those who call up; for others once shown.
create or replace function internal.get_event_lineup_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare can_edit boolean;
begin
  if auth.uid() is null or not internal.actor_can_read_event(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  can_edit := internal.actor_can_manage_squad(target_event_id);
  if not can_edit and not exists (select 1 from core.event_lineups lineup
      where lineup.event_id = target_event_id and lineup.published) then
    return null;
  end if;
  return internal.lineup_json(target_event_id, can_edit);
end;$$;

create or replace function internal.save_event_lineup_for_actor(target_event_id uuid, formation text,
  starters jsonb, substitutes jsonb, published boolean, expected_revision bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare event_row core.events%rowtype; current_revision bigint; new_revision bigint;
begin
  select * into event_row from core.events where id = target_event_id for update;
  if event_row.id is null or not internal.actor_can_manage_squad(target_event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if event_row.event_type <> 'match' or jsonb_typeof(coalesce(starters, '[]')) <> 'array'
    or jsonb_typeof(coalesce(substitutes, '[]')) <> 'array'
    or jsonb_array_length(coalesce(starters, '[]')) > 30 or jsonb_array_length(coalesce(substitutes, '[]')) > 30
    or length(formation) > 20 or published is null then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if exists (select 1 from (select value->>'person_id' person_id from jsonb_array_elements(coalesce(starters, '[]'))
        union all select value->>'person_id' from jsonb_array_elements(coalesce(substitutes, '[]'))) chosen
      where chosen.person_id is null or chosen.person_id !~ '^[0-9a-fA-F-]{36}$'
        or not exists (select 1 from core.club_people person where person.id = chosen.person_id::uuid
          and person.club_id = event_row.club_id)) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if (select count(*) from (select value->>'person_id' from jsonb_array_elements(coalesce(starters, '[]'))
        union all select value->>'person_id' from jsonb_array_elements(coalesce(substitutes, '[]'))) chosen(id))
     <> (select count(distinct id) from (select value->>'person_id' from jsonb_array_elements(coalesce(starters, '[]'))
        union all select value->>'person_id' from jsonb_array_elements(coalesce(substitutes, '[]'))) chosen(id)) then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  select revision into current_revision from core.event_lineups where event_id = event_row.id;
  if coalesce(current_revision, 0) <> coalesce(expected_revision, 0) then
    raise serialization_failure using message = 'stale_revision';
  end if;
  insert into core.event_lineups(event_id, club_id, formation, starters, substitutes, published, updated_by)
  values (event_row.id, event_row.club_id, nullif(btrim(coalesce(formation, '')), ''), coalesce(starters, '[]'),
    coalesce(substitutes, '[]'), published, auth.uid())
  on conflict (event_id) do update set formation = excluded.formation, starters = excluded.starters,
    substitutes = excluded.substitutes, published = excluded.published,
    revision = core.event_lineups.revision + 1, updated_by = excluded.updated_by, updated_at = now()
  returning revision into new_revision;
  return new_revision;
end;$$;

-- As in 20261110090000, with absence notices.
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

-- As in 20261110090000, with absence notices.
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
  when event_type = 'absence.reported.v1' then 'Frånvaroanmälan'
  when event_type like 'event.%' then 'Kalendern har uppdaterats'
  else 'Ny aktivitet i TeamZone' end
$$;

-- As in 20261110090000, with absence notices.
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
  when event_type = 'absence.reported.v1' then 'Öppna aktiviteten för att se vem som inte kan komma.'
  when event_type like 'event.%' then 'Öppna kalendern för aktuell information.'
  else 'Öppna TeamZone för mer information.' end
$$;

create or replace function api.get_team_event_settings(target_team_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_team_event_settings_for_actor(target_team_id)$$;
create or replace function api.set_team_event_settings(target_team_id uuid, callups_required boolean)
returns integer language sql security invoker set search_path = '' as
$$select internal.set_team_event_settings_for_actor(target_team_id, callups_required)$$;
create or replace function api.report_event_absence(target_event_id uuid, target_person_id uuid,
  reason_code text, reason_text text default null)
returns uuid language sql security invoker set search_path = '' as
$$select internal.report_event_absence_for_actor(target_event_id, target_person_id, reason_code, reason_text)$$;
create or replace function api.withdraw_event_absence(target_event_id uuid, target_person_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.withdraw_event_absence_for_actor(target_event_id, target_person_id)$$;
create or replace function api.get_event_lineup(target_event_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_event_lineup_for_actor(target_event_id)$$;
create or replace function api.save_event_lineup(target_event_id uuid, formation text, starters jsonb,
  substitutes jsonb, published boolean, expected_revision bigint)
returns bigint language sql security invoker set search_path = '' as
$$select internal.save_event_lineup_for_actor(target_event_id, formation, starters, substitutes, published,
  expected_revision)$$;

revoke all on function internal.actor_changes_team_events(uuid), internal.apply_team_event_settings(),
  internal.event_represented_people(uuid),
  internal.event_expects_person(uuid, uuid), internal.get_event_absence_notices_for_actor(uuid),
  internal.lineup_json(uuid, boolean),
  internal.get_team_event_settings_for_actor(uuid), internal.set_team_event_settings_for_actor(uuid, boolean),
  internal.report_event_absence_for_actor(uuid, uuid, text, text),
  internal.withdraw_event_absence_for_actor(uuid, uuid), internal.get_event_lineup_for_actor(uuid),
  internal.save_event_lineup_for_actor(uuid, text, jsonb, jsonb, boolean, bigint),
  api.get_team_event_settings(uuid), api.set_team_event_settings(uuid, boolean),
  api.report_event_absence(uuid, uuid, text, text), api.withdraw_event_absence(uuid, uuid),
  api.get_event_lineup(uuid), api.save_event_lineup(uuid, text, jsonb, jsonb, boolean, bigint)
  from public, anon, authenticated;
grant execute on function internal.get_event_absence_notices_for_actor(uuid), internal.event_represented_people(uuid),
  internal.get_team_event_settings_for_actor(uuid), internal.set_team_event_settings_for_actor(uuid, boolean),
  internal.report_event_absence_for_actor(uuid, uuid, text, text),
  internal.withdraw_event_absence_for_actor(uuid, uuid), internal.get_event_lineup_for_actor(uuid),
  internal.save_event_lineup_for_actor(uuid, text, jsonb, jsonb, boolean, bigint),
  api.get_team_event_settings(uuid), api.set_team_event_settings(uuid, boolean),
  api.report_event_absence(uuid, uuid, text, text), api.withdraw_event_absence(uuid, uuid),
  api.get_event_lineup(uuid), api.save_event_lineup(uuid, text, jsonb, jsonb, boolean, bigint)
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261113090000_absence_notices_and_lineups', 'greenfield', 'UX: absence notices without callups, and the starting line-up'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261113090000_absence_notices_and_lineups');
notify pgrst, 'reload schema';
