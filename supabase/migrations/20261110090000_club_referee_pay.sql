-- REF-02, phase 2: reports, approval and pay for föreningsdomare.
--
-- Arvoden: the club sets a fee for the main referee and for assistants,
-- for the whole club and per team (the team's wins).
-- A report is made for every confirmed club referee once the match has
-- ended: pending with the fee filled in. The referee (or a guardian) can
-- leave a note, e.g. that the match did not take place. The domaransvarig
-- can send a control question to the team's leaders ("Dömde X matchen?"),
-- adjusts amounts and approves or rejects, many at once.
-- Domarersättning is the capability club.referees.pay (club administrators
-- always have it): it makes payout lists of approved reports, one line per
-- referee, exports them and marks them paid. Lines carry a method, state and
-- provider reference so that a direct payment (Swish) can take over later.
-- Year totals are compared with half a prisbasbelopp as a guide; the club
-- decides what applies.

create table if not exists core.club_referee_fees (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  team_id uuid references core.teams(id) on delete cascade,
  fee_main integer not null check (fee_main between 0 and 100000),
  fee_assistant integer not null check (fee_assistant between 0 and 100000),
  updated_by uuid references core.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
create unique index if not exists club_referee_fees_club on core.club_referee_fees(club_id) where team_id is null;
create unique index if not exists club_referee_fees_team on core.club_referee_fees(team_id) where team_id is not null;
alter table core.club_referee_fees enable row level security;
revoke all on core.club_referee_fees from public, anon, authenticated;

create table if not exists core.club_referee_payouts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  through_date date not null,
  -- export: the club pays from the list; direct: paid by TeamZone later.
  method text not null default 'export' check (method in ('export', 'direct')),
  state text not null default 'draft' check (state in ('draft', 'paid')),
  total integer not null default 0,
  created_by uuid references core.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  paid_by uuid references core.profiles(id) on delete set null,
  paid_at timestamptz
);
create index if not exists club_referee_payouts_club on core.club_referee_payouts(club_id, created_at desc);
alter table core.club_referee_payouts enable row level security;
revoke all on core.club_referee_payouts from public, anon, authenticated;

create table if not exists core.club_referee_payout_lines (
  id uuid primary key default gen_random_uuid(),
  payout_id uuid not null references core.club_referee_payouts(id) on delete cascade,
  club_id uuid not null references core.clubs(id),
  referee_person_id uuid references core.club_people(id) on delete set null,
  payee_name text not null,
  report_count integer not null,
  amount integer not null,
  state text not null default 'pending' check (state in ('pending', 'paid', 'failed')),
  provider_reference text,
  paid_at timestamptz
);
create index if not exists club_referee_payout_lines_payout on core.club_referee_payout_lines(payout_id);
alter table core.club_referee_payout_lines enable row level security;
revoke all on core.club_referee_payout_lines from public, anon, authenticated;

create table if not exists core.club_referee_reports (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  event_referee_id uuid not null unique references core.event_referees(id) on delete cascade,
  event_id uuid not null references core.events(id) on delete cascade,
  referee_person_id uuid references core.club_people(id) on delete set null,
  slot text not null,
  amount integer not null default 0 check (amount between 0 and 100000),
  amount_by_hand boolean not null default false,
  state text not null default 'pending' check (state in ('pending', 'approved', 'rejected', 'paid')),
  referee_note text check (length(referee_note) <= 500),
  referee_noted_at timestamptz,
  control_state text check (control_state in ('asked', 'confirmed', 'denied')),
  control_asked_by uuid references core.profiles(id) on delete set null,
  control_asked_at timestamptz,
  control_answered_by uuid references core.profiles(id) on delete set null,
  control_answered_at timestamptz,
  control_note text check (length(control_note) <= 500),
  decided_by uuid references core.profiles(id) on delete set null,
  decided_at timestamptz,
  reject_reason text check (length(reject_reason) <= 500),
  payout_id uuid references core.club_referee_payouts(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists club_referee_reports_club on core.club_referee_reports(club_id, state);
create index if not exists club_referee_reports_person on core.club_referee_reports(referee_person_id);
create index if not exists club_referee_reports_payout on core.club_referee_reports(payout_id);
alter table core.club_referee_reports enable row level security;
revoke all on core.club_referee_reports from public, anon, authenticated;

create or replace function internal.actor_pays_club_referees(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.actor_has_capability(target_club_id, null, 'club.referees.pay')
    or internal.actor_manages_club(target_club_id)
$$;

-- The referee's own pay: who answers for them, and guardians while under 18.
create or replace function internal.actor_sees_referee_pay(target_person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.actor_acts_for_referee(target_person_id) or (
    coalesce(internal.person_age_years(target_person_id), 0) < 18
    and exists (select 1 from core.guardian_relations relation
      join core.person_account_links link on link.club_person_id = relation.guardian_person_id
        and link.club_id = relation.club_id and link.state = 'active'
      where relation.child_person_id = target_person_id and relation.state = 'active'
        and relation.starts_at <= now() and (relation.ends_at is null or relation.ends_at > now())
        and link.profile_id = auth.uid()))
$$;

-- The fee for a place on a match: the team's, else the club's, else 0.
create or replace function internal.club_referee_fee(target_event_id uuid, target_slot text)
returns integer language sql stable security definer set search_path = '' as $$
  select coalesce((select case when target_slot = 'main' then fee.fee_main else fee.fee_assistant end
      from core.events event_row
      join core.club_referee_fees fee on fee.club_id = event_row.club_id
        and (fee.team_id = event_row.owning_team_id or fee.team_id is null)
      where event_row.id = target_event_id
      order by fee.team_id is null limit 1), 0)
$$;

-- Half a prisbasbelopp, as a guide for the year's total.
create or replace function internal.referee_tax_free_limit(target_year integer)
returns integer language sql immutable set search_path = '' as $$
  select case target_year when 2025 then 29400 else 29600 end
$$;

-- Approved and paid pay for matches in the year.
create or replace function internal.club_referee_year_total(target_person_id uuid, target_year integer)
returns integer language sql stable security definer set search_path = '' as $$
  select coalesce(sum(report.amount), 0)::integer from core.club_referee_reports report
  join core.events event_row on event_row.id = report.event_id
  where report.referee_person_id = target_person_id and report.state in ('approved', 'paid')
    and extract(year from event_row.starts_at at time zone 'Europe/Stockholm')::integer = target_year
$$;

-- Reports for confirmed club referees whose match has ended (not for
-- cancelled matches, and not further back than half a year).
create or replace function internal.create_due_club_referee_reports(target_club_id uuid default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare added integer;
begin
  insert into core.club_referee_reports(club_id, event_referee_id, event_id, referee_person_id, slot, amount)
  select referee.club_id, referee.id, referee.event_id, referee.referee_person_id, referee.slot,
    internal.club_referee_fee(event_row.id, referee.slot)
  from core.event_referees referee
  join core.events event_row on event_row.id = referee.event_id
  where referee.kind = 'club' and referee.state = 'confirmed' and referee.referee_person_id is not null
    and event_row.state in ('scheduled', 'completed') and event_row.ends_at <= now()
    and event_row.ends_at > now() - interval '180 days'
    and (target_club_id is null or referee.club_id = target_club_id)
  on conflict (event_referee_id) do nothing;
  get diagnostics added = row_count;
  return added;
end;$$;

create or replace function internal.club_referee_report_json(target_report_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', report.id, 'event_referee_id', report.event_referee_id, 'slot', report.slot,
    'person_id', report.referee_person_id, 'name', coalesce(person.display_name, 'Borttagen person'),
    'amount', report.amount, 'state', report.state,
    'referee_note', report.referee_note, 'control_state', report.control_state,
    'control_note', report.control_note, 'control_answered_at', report.control_answered_at,
    'reject_reason', report.reject_reason, 'decided_at', report.decided_at,
    'payout_id', report.payout_id, 'created_at', report.created_at,
    'match', internal.referee_event_json(report.event_id))
  from core.club_referee_reports report
  left join core.club_people person on person.id = report.referee_person_id
  where report.id = target_report_id
$$;

-- To the referee (or who answers for them) about their pay.
create or replace function internal.notify_club_referee_pay(target_person_id uuid, target_club_id uuid,
  new_event_type text, aggregate uuid, payload jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare added integer;
begin
  if target_person_id is null then return 0; end if;
  insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select target_club_id, gen_random_uuid(), new_event_type, 'referee_report', aggregate,
    confirmer.profile_id, confirmer.club_person_id, payload || jsonb_build_object('side', 'referee')
  from internal.referee_confirmers(target_person_id) confirmer
  where confirmer.club_id = target_club_id and confirmer.profile_id is distinct from auth.uid()
  on conflict do nothing;
  get diagnostics added = row_count;
  return added;
end;$$;

-- Fees: the club's and every team's.
create or replace function internal.get_club_referee_fees_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (internal.actor_manages_club_referees(target_club_id) or internal.actor_pays_club_referees(target_club_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'club', (select jsonb_build_object('fee_main', fee.fee_main, 'fee_assistant', fee.fee_assistant)
      from core.club_referee_fees fee where fee.club_id = target_club_id and fee.team_id is null),
    'teams', coalesce((select jsonb_agg(jsonb_build_object('team_id', team.id, 'team_name', team.name,
        'fee_main', fee.fee_main, 'fee_assistant', fee.fee_assistant) order by team.name)
      from core.teams team left join core.club_referee_fees fee on fee.team_id = team.id
      where team.club_id = target_club_id and team.status = 'active'), '[]'::jsonb));
end;$$;

-- Saves (or with both null removes) the club's or a team's fee; pending
-- reports that were not changed by hand get the new amount.
create or replace function internal.save_club_referee_fee_for_actor(target_club_id uuid, target_team_id uuid,
  fee_main integer, fee_assistant integer)
returns integer language plpgsql security definer set search_path = '' as $$
declare changed integer;
begin
  if not internal.actor_manages_club_referees(target_club_id)
    or (target_team_id is not null and not exists (select 1 from core.teams team
      where team.id = target_team_id and team.club_id = target_club_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if (fee_main is null) <> (fee_assistant is null) or fee_main not between 0 and 100000
    or fee_assistant not between 0 and 100000 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if fee_main is null then
    delete from core.club_referee_fees fee where fee.club_id = target_club_id
      and fee.team_id is not distinct from target_team_id;
  elsif target_team_id is null then
    insert into core.club_referee_fees(club_id, team_id, fee_main, fee_assistant, updated_by)
    values (target_club_id, null, fee_main, fee_assistant, auth.uid())
    on conflict (club_id) where team_id is null do update set fee_main = excluded.fee_main,
      fee_assistant = excluded.fee_assistant, updated_by = excluded.updated_by, updated_at = now();
  else
    insert into core.club_referee_fees(club_id, team_id, fee_main, fee_assistant, updated_by)
    values (target_club_id, target_team_id, fee_main, fee_assistant, auth.uid())
    on conflict (team_id) where team_id is not null do update set fee_main = excluded.fee_main,
      fee_assistant = excluded.fee_assistant, updated_by = excluded.updated_by, updated_at = now();
  end if;
  update core.club_referee_reports report set amount = internal.club_referee_fee(report.event_id, report.slot)
  where report.club_id = target_club_id and report.state = 'pending' and not report.amount_by_hand
    and report.payout_id is null
    and (target_team_id is null or report.event_id in (select event_row.id from core.events event_row
      where event_row.owning_team_id = target_team_id));
  get diagnostics changed = row_count;
  return changed;
end;$$;

-- The domaransvarig's and the payer's list: everything not paid, or one state.
create or replace function internal.list_club_referee_reports_for_actor(target_club_id uuid, target_state text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not (internal.actor_manages_club_referees(target_club_id) or internal.actor_pays_club_referees(target_club_id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if target_state is not null and target_state not in ('pending', 'approved', 'rejected', 'paid') then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  perform internal.create_due_club_referee_reports(target_club_id);
  return jsonb_build_object(
    'reports', coalesce((select jsonb_agg(internal.club_referee_report_json(picked.id) order by picked.starts_at desc)
      from (select report.id, event_row.starts_at from core.club_referee_reports report
        join core.events event_row on event_row.id = report.event_id
        where report.club_id = target_club_id
          and case when target_state is null then report.state <> 'paid' else report.state = target_state end
        order by event_row.starts_at desc limit 300) picked), '[]'::jsonb),
    'counts', coalesce((select jsonb_object_agg(counted.state, counted.n)
      from (select report.state, count(*) n from core.club_referee_reports report
        where report.club_id = target_club_id group by report.state) counted), '{}'::jsonb),
    'can_manage', internal.actor_manages_club_referees(target_club_id),
    'can_pay', internal.actor_pays_club_referees(target_club_id));
end;$$;

create or replace function internal.ask_club_referee_control_for_actor(target_report_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare report core.club_referee_reports%rowtype; event_row core.events%rowtype;
begin
  select * into report from core.club_referee_reports where id = target_report_id for update;
  if report.id is null or not internal.actor_manages_club_referees(report.club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if report.state <> 'pending' then raise invalid_parameter_value using message = 'not_pending'; end if;
  select * into event_row from core.events where id = report.event_id;
  update core.club_referee_reports set control_state = 'asked', control_asked_by = auth.uid(), control_asked_at = now(),
    control_answered_by = null, control_answered_at = null, control_note = null
  where id = report.id;
  insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select event_row.club_id, gen_random_uuid(), 'referee.control_question.v1', 'referee_report', report.id,
    recipient.profile_id, recipient.club_person_id,
    jsonb_build_object('event_id', event_row.id, 'report_id', report.id, 'side', 'team')
  from internal.match_pool_recipients(event_row.club_id, event_row.owning_team_id) recipient
  where recipient.profile_id is distinct from auth.uid()
  on conflict do nothing;
end;$$;

-- The team's leader answers: did the referee referee the match?
create or replace function internal.answer_club_referee_control_for_actor(target_report_id uuid, confirmed boolean,
  note text)
returns void language plpgsql security definer set search_path = '' as $$
declare report core.club_referee_reports%rowtype; clean text := nullif(btrim(coalesce(note, '')), '');
begin
  select * into report from core.club_referee_reports where id = target_report_id for update;
  if report.id is null or not internal.actor_can_manage_event(report.event_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if report.control_state is distinct from 'asked' then raise invalid_parameter_value using message = 'not_pending'; end if;
  if confirmed is null or length(clean) > 500 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  update core.club_referee_reports set control_state = case when confirmed then 'confirmed' else 'denied' end,
    control_answered_by = auth.uid(), control_answered_at = now(), control_note = clean
  where id = report.id;
  insert into internal.notification_outbox(club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select report.club_id, gen_random_uuid(), 'referee.control_answered.v1', 'referee_report', report.id,
    recipient.profile_id, recipient.club_person_id,
    jsonb_build_object('event_id', report.event_id, 'report_id', report.id, 'side', 'coordinator')
  from internal.club_referee_coordinators(report.club_id) recipient
  where recipient.profile_id is distinct from auth.uid()
  on conflict do nothing;
end;$$;

-- Approves or rejects reports not yet in a payout list; rejected ones are
-- told to the referee side.
create or replace function internal.decide_club_referee_reports_for_actor(target_club_id uuid, report_ids uuid[],
  approve boolean, reason text)
returns integer language plpgsql security definer set search_path = '' as $$
declare clean text := nullif(btrim(coalesce(reason, '')), ''); changed uuid[]; item record;
begin
  if not internal.actor_manages_club_referees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if approve is null or report_ids is null or cardinality(report_ids) = 0 or cardinality(report_ids) > 300
    or length(clean) > 500 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  with updated as (
    update core.club_referee_reports report set state = case when approve then 'approved' else 'rejected' end,
      decided_by = auth.uid(), decided_at = now(), reject_reason = case when approve then null else clean end
    where report.id = any(report_ids) and report.club_id = target_club_id
      and report.state in ('pending', 'approved', 'rejected') and report.payout_id is null
      and report.state is distinct from case when approve then 'approved' else 'rejected' end
    returning report.id)
  select coalesce(array_agg(id), '{}') into changed from updated;
  if not approve then
    for item in select report.id, report.referee_person_id, report.event_id from core.club_referee_reports report
        where report.id = any(changed) loop
      perform internal.notify_club_referee_pay(item.referee_person_id, target_club_id, 'referee.report_rejected.v1',
        item.id, jsonb_build_object('event_id', item.event_id, 'report_id', item.id));
    end loop;
  end if;
  return cardinality(changed);
end;$$;

create or replace function internal.set_club_referee_report_amount_for_actor(target_report_id uuid, amount integer)
returns void language plpgsql security definer set search_path = '' as $$
declare report core.club_referee_reports%rowtype;
begin
  select * into report from core.club_referee_reports where id = target_report_id for update;
  if report.id is null or not internal.actor_manages_club_referees(report.club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if report.payout_id is not null or report.state = 'paid' then raise invalid_parameter_value using message = 'in_payout'; end if;
  if amount is null or amount not between 0 and 100000 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  update core.club_referee_reports set amount = set_club_referee_report_amount_for_actor.amount, amount_by_hand = true
  where id = report.id;
end;$$;

-- The referee (or a guardian) leaves a note on a pending report.
create or replace function internal.note_club_referee_report_for_actor(target_report_id uuid, note text)
returns void language plpgsql security definer set search_path = '' as $$
declare report core.club_referee_reports%rowtype; clean text := nullif(btrim(coalesce(note, '')), '');
begin
  select * into report from core.club_referee_reports where id = target_report_id for update;
  if report.id is null or report.referee_person_id is null
    or not internal.actor_acts_for_referee(report.referee_person_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if report.state <> 'pending' then raise invalid_parameter_value using message = 'not_pending'; end if;
  if length(clean) > 500 then raise invalid_parameter_value using message = 'invalid_input'; end if;
  update core.club_referee_reports set referee_note = clean, referee_noted_at = now() where id = report.id;
end;$$;

-- The referee's (and a guardian's) own pay: per person the year's total
-- and the latest reports.
create or replace function internal.list_my_referee_reports_for_actor()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare this_year integer := extract(year from now() at time zone 'Europe/Stockholm')::integer; club uuid;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  for club in select distinct referee.club_id from core.club_referees referee
      where internal.actor_sees_referee_pay(referee.club_person_id) loop
    perform internal.create_due_club_referee_reports(club);
  end loop;
  return coalesce((select jsonb_agg(jsonb_build_object('person_id', person.id, 'name', person.display_name,
      'year', this_year, 'year_total', internal.club_referee_year_total(person.id, this_year),
      'limit', internal.referee_tax_free_limit(this_year),
      'can_note', internal.actor_acts_for_referee(person.id),
      'reports', coalesce((select jsonb_agg(internal.club_referee_report_json(picked.id) order by picked.starts_at desc)
        from (select report.id, event_row.starts_at from core.club_referee_reports report
          join core.events event_row on event_row.id = report.event_id
          where report.referee_person_id = person.id order by event_row.starts_at desc limit 50) picked), '[]'::jsonb))
      order by person.display_name)
    from core.club_people person
    where person.id in (select referee.club_person_id from core.club_referees referee)
      and internal.actor_sees_referee_pay(person.id)), '[]'::jsonb);
end;$$;

-- Makes a payout list of the approved reports for matches up to a date.
create or replace function internal.create_club_referee_payout_for_actor(target_club_id uuid, through_date date)
returns uuid language plpgsql security definer set search_path = '' as $$
declare last_day date := coalesce(through_date, (now() at time zone 'Europe/Stockholm')::date); new_id uuid;
begin
  if not internal.actor_pays_club_referees(target_club_id) then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.create_due_club_referee_reports(target_club_id);
  insert into core.club_referee_payouts(club_id, through_date, created_by)
  values (target_club_id, last_day, auth.uid()) returning id into new_id;
  update core.club_referee_reports report set payout_id = new_id
  from core.events event_row
  where event_row.id = report.event_id and report.club_id = target_club_id and report.state = 'approved'
    and report.payout_id is null and (event_row.starts_at at time zone 'Europe/Stockholm')::date <= last_day;
  if not found then raise invalid_parameter_value using message = 'nothing_to_pay'; end if;
  insert into core.club_referee_payout_lines(payout_id, club_id, referee_person_id, payee_name, report_count, amount)
  select new_id, target_club_id, report.referee_person_id, coalesce(max(person.display_name), 'Borttagen person'),
    count(*), sum(report.amount)
  from core.club_referee_reports report left join core.club_people person on person.id = report.referee_person_id
  where report.payout_id = new_id
  group by report.referee_person_id;
  update core.club_referee_payouts set total = (select coalesce(sum(line.amount), 0)
    from core.club_referee_payout_lines line where line.payout_id = new_id)
  where id = new_id;
  return new_id;
end;$$;

create or replace function internal.club_referee_payout_json(target_payout_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', payout.id, 'through_date', payout.through_date, 'state', payout.state,
    'method', payout.method, 'total', payout.total, 'created_at', payout.created_at, 'paid_at', payout.paid_at,
    'line_count', (select count(*) from core.club_referee_payout_lines line where line.payout_id = payout.id))
  from core.club_referee_payouts payout where payout.id = target_payout_id
$$;

-- One list: per referee the amount, the year's total against the guide
-- and, under 18, the guardians; and every report for the export.
create or replace function internal.get_club_referee_payout_for_actor(target_payout_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare payout core.club_referee_payouts%rowtype; pay_year integer;
begin
  select * into payout from core.club_referee_payouts where id = target_payout_id;
  if payout.id is null or not internal.actor_pays_club_referees(payout.club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  pay_year := extract(year from payout.through_date)::integer;
  return internal.club_referee_payout_json(payout.id) || jsonb_build_object(
    'limit', internal.referee_tax_free_limit(pay_year),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('id', line.id, 'person_id', line.referee_person_id,
        'name', line.payee_name, 'report_count', line.report_count, 'amount', line.amount, 'state', line.state,
        'age', internal.person_age_years(line.referee_person_id),
        'year_total', internal.club_referee_year_total(line.referee_person_id, pay_year),
        'guardians', case when coalesce(internal.person_age_years(line.referee_person_id), 99) < 18 then
          (select string_agg(guardian.display_name, ', ' order by guardian.display_name)
            from core.guardian_relations relation
            join core.club_people guardian on guardian.id = relation.guardian_person_id
            where relation.child_person_id = line.referee_person_id and relation.state = 'active'
              and (relation.ends_at is null or relation.ends_at > now())) end)
        order by line.payee_name)
      from core.club_referee_payout_lines line where line.payout_id = payout.id), '[]'::jsonb),
    'reports', coalesce((select jsonb_agg(jsonb_build_object('person_id', report.referee_person_id,
        'name', coalesce(person.display_name, 'Borttagen person'), 'slot', report.slot, 'amount', report.amount,
        'starts_at', event_row.starts_at, 'team_name', team.name, 'opponent_name', event_row.opponent_name)
        order by person.display_name, event_row.starts_at)
      from core.club_referee_reports report
      join core.events event_row on event_row.id = report.event_id
      join core.teams team on team.id = event_row.owning_team_id
      left join core.club_people person on person.id = report.referee_person_id
      where report.payout_id = payout.id), '[]'::jsonb));
end;$$;

-- The payer's page: lists, what is ready to pay, and who pays.
create or replace function internal.list_club_referee_payouts_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_pays_club_referees(target_club_id) then raise insufficient_privilege using message = 'not_found'; end if;
  return jsonb_build_object(
    'payouts', coalesce((select jsonb_agg(internal.club_referee_payout_json(payout.id) order by payout.created_at desc)
      from (select id, created_at from core.club_referee_payouts where club_id = target_club_id
        order by created_at desc limit 50) payout), '[]'::jsonb),
    'ready_count', (select count(*) from core.club_referee_reports report where report.club_id = target_club_id
      and report.state = 'approved' and report.payout_id is null),
    'ready_total', (select coalesce(sum(report.amount), 0) from core.club_referee_reports report
      where report.club_id = target_club_id and report.state = 'approved' and report.payout_id is null),
    'payers', coalesce((select jsonb_agg(distinct jsonb_build_object('person_id', person.id, 'name', person.display_name))
      from core.capability_grants grant_row
      join core.assignments assignment on assignment.id = grant_row.assignment_id and assignment.state = 'active'
      join core.club_people person on person.id = assignment.club_person_id and person.status = 'active'
      where grant_row.capability = 'club.referees.pay' and grant_row.scope_type = 'club'
        and grant_row.scope_id = target_club_id and grant_row.starts_at <= now()
        and (grant_row.ends_at is null or grant_row.ends_at > now())), '[]'::jsonb),
    'can_appoint_payers', internal.actor_manages_club(target_club_id));
end;$$;

create or replace function internal.mark_club_referee_payout_paid_for_actor(target_payout_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare payout core.club_referee_payouts%rowtype; line record;
begin
  select * into payout from core.club_referee_payouts where id = target_payout_id for update;
  if payout.id is null or not internal.actor_pays_club_referees(payout.club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if payout.state <> 'draft' then raise invalid_parameter_value using message = 'not_pending'; end if;
  update core.club_referee_payouts set state = 'paid', paid_by = auth.uid(), paid_at = now() where id = payout.id;
  update core.club_referee_payout_lines set state = 'paid', paid_at = now() where payout_id = payout.id;
  update core.club_referee_reports set state = 'paid' where payout_id = payout.id;
  for line in select * from core.club_referee_payout_lines where payout_id = payout.id loop
    perform internal.notify_club_referee_pay(line.referee_person_id, payout.club_id, 'referee.payout_paid.v1',
      line.id, jsonb_build_object('payout_id', payout.id));
  end loop;
end;$$;

-- A list not yet paid can be removed; its reports are free again.
create or replace function internal.cancel_club_referee_payout_for_actor(target_payout_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare payout core.club_referee_payouts%rowtype;
begin
  select * into payout from core.club_referee_payouts where id = target_payout_id for update;
  if payout.id is null or not internal.actor_pays_club_referees(payout.club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if payout.state <> 'draft' then raise invalid_parameter_value using message = 'not_pending'; end if;
  delete from core.club_referee_payouts where id = payout.id;
end;$$;

-- Domarersättning: given and taken back by the club's administrators, as
-- domaransvarig in 20261109090000.
create or replace function internal.set_club_referee_payer_for_actor(target_club_id uuid,
  target_person_id uuid, enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare assignment_id uuid;
begin
  if not internal.actor_manages_club(target_club_id) then raise insufficient_privilege using message = 'not_found'; end if;
  if coalesce(enabled, false) then
    select assignment.id into assignment_id from core.assignments assignment
    where assignment.club_id = target_club_id and assignment.club_person_id = target_person_id
      and assignment.state = 'active' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
    order by assignment.starts_at limit 1;
    if assignment_id is null then raise invalid_parameter_value using message = 'no_assignment'; end if;
    if not exists (select 1 from core.capability_grants grant_row
        join core.assignments assignment on assignment.id = grant_row.assignment_id
        where assignment.club_person_id = target_person_id and grant_row.capability = 'club.referees.pay'
          and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
          and (grant_row.ends_at is null or grant_row.ends_at > now())) then
      insert into core.capability_grants(club_id, assignment_id, capability, scope_type, scope_id, starts_at, created_by)
      values (target_club_id, assignment_id, 'club.referees.pay', 'club', target_club_id, now(), auth.uid());
    end if;
  else
    update core.capability_grants grant_row
    set ends_at = greatest(now(), grant_row.starts_at + interval '1 microsecond')
    from core.assignments assignment
    where assignment.id = grant_row.assignment_id and assignment.club_person_id = target_person_id
      and grant_row.capability = 'club.referees.pay' and grant_row.scope_type = 'club'
      and grant_row.scope_id = target_club_id and (grant_row.ends_at is null or grant_row.ends_at > now());
  end if;
end;$$;

-- As in 20261109090000, with the control questions the team's leaders answer.
create or replace function internal.get_event_referees_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or not (internal.actor_can_read_event(event_row.id)
      or internal.actor_manages_club_referees(event_row.club_id)
      or exists (select 1 from core.event_referees referee where referee.event_id = event_row.id
        and referee.referee_person_id is not null and internal.actor_acts_for_referee(referee.referee_person_id))) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'event_id', event_row.id,
    'slots', event_row.referee_slots,
    'referee_kind', event_row.referee_kind,
    'can_manage', internal.actor_can_manage_event(event_row.id),
    'can_manage_club_referees', internal.actor_manages_club_referees(event_row.club_id),
    'referees', coalesce((select jsonb_agg(internal.event_referee_json(referee.id)
        order by internal.referee_slot_index(referee.slot), referee.created_at)
      from core.event_referees referee
      where referee.event_id = event_row.id
        and referee.state in ('awaiting_referee', 'awaiting_team', 'awaiting_coordinator', 'confirmed')),
      '[]'::jsonb),
    'control_questions', case when internal.actor_can_manage_event(event_row.id) then
      coalesce((select jsonb_agg(jsonb_build_object('id', report.id, 'slot', report.slot,
          'name', coalesce(person.display_name, 'Borttagen person')) order by internal.referee_slot_index(report.slot))
        from core.club_referee_reports report left join core.club_people person on person.id = report.referee_person_id
        where report.event_id = event_row.id and report.control_state = 'asked'), '[]'::jsonb)
      else '[]'::jsonb end);
end;$$;

-- As in 20261109090000, with payers and the reports waiting per club.
create or replace function internal.get_my_referee_summary_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'club_referee', exists (select 1 from core.club_referees referee where referee.ends_at is null
      and internal.actor_acts_for_referee(referee.club_person_id)),
    'coordinator_clubs', coalesce((select jsonb_agg(jsonb_build_object('club_id', club.id, 'club_name', club.name,
        'can_manage', internal.actor_manages_club_referees(club.id),
        'can_pay', internal.actor_pays_club_referees(club.id),
        'pending_reports', (select count(*) from core.club_referee_reports report
          where report.club_id = club.id and report.state = 'pending'))
        order by club.name)
      from core.clubs club where club.status = 'active'
        and club.id in (select link.club_id from core.person_account_links link
          where link.profile_id = auth.uid() and link.state = 'active')
        and (internal.actor_manages_club_referees(club.id) or internal.actor_pays_club_referees(club.id))), '[]'::jsonb),
    'open_count', (select jsonb_array_length(internal.list_open_club_matches_for_actor())))
$$;

-- As in 20261109090000, with reports and pay.
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

-- As in 20261109090000, with reports and pay.
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
  when event_type like 'event.%' then 'Kalendern har uppdaterats'
  else 'Ny aktivitet i TeamZone' end
$$;

-- As in 20261108090000, with reports and pay.
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
  when event_type like 'event.%' then 'Öppna kalendern för aktuell information.'
  else 'Öppna TeamZone för mer information.' end
$$;

-- As in 20261108090000, with answers to the domaransvarig.
create or replace function internal.notification_deep_link(
  outbox internal.notification_outbox)
returns text
language sql
stable
set search_path=''
as $$
  select case
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
$$;

create or replace function api.get_club_referee_fees(target_club_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_club_referee_fees_for_actor(target_club_id)$$;
create or replace function api.save_club_referee_fee(target_club_id uuid, target_team_id uuid, fee_main integer,
  fee_assistant integer)
returns integer language sql security invoker set search_path = '' as
$$select internal.save_club_referee_fee_for_actor(target_club_id, target_team_id, fee_main, fee_assistant)$$;
create or replace function api.list_club_referee_reports(target_club_id uuid, target_state text default null)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_club_referee_reports_for_actor(target_club_id, target_state)$$;
create or replace function api.ask_club_referee_control(target_report_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.ask_club_referee_control_for_actor(target_report_id)$$;
create or replace function api.answer_club_referee_control(target_report_id uuid, confirmed boolean,
  note text default null)
returns void language sql security invoker set search_path = '' as
$$select internal.answer_club_referee_control_for_actor(target_report_id, confirmed, note)$$;
create or replace function api.decide_club_referee_reports(target_club_id uuid, report_ids uuid[], approve boolean,
  reason text default null)
returns integer language sql security invoker set search_path = '' as
$$select internal.decide_club_referee_reports_for_actor(target_club_id, report_ids, approve, reason)$$;
create or replace function api.set_club_referee_report_amount(target_report_id uuid, amount integer)
returns void language sql security invoker set search_path = '' as
$$select internal.set_club_referee_report_amount_for_actor(target_report_id, amount)$$;
create or replace function api.note_club_referee_report(target_report_id uuid, note text)
returns void language sql security invoker set search_path = '' as
$$select internal.note_club_referee_report_for_actor(target_report_id, note)$$;
create or replace function api.list_my_referee_reports()
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_my_referee_reports_for_actor()$$;
create or replace function api.create_club_referee_payout(target_club_id uuid, through_date date default null)
returns uuid language sql security invoker set search_path = '' as
$$select internal.create_club_referee_payout_for_actor(target_club_id, through_date)$$;
create or replace function api.get_club_referee_payout(target_payout_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_club_referee_payout_for_actor(target_payout_id)$$;
create or replace function api.list_club_referee_payouts(target_club_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_club_referee_payouts_for_actor(target_club_id)$$;
create or replace function api.mark_club_referee_payout_paid(target_payout_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.mark_club_referee_payout_paid_for_actor(target_payout_id)$$;
create or replace function api.cancel_club_referee_payout(target_payout_id uuid)
returns void language sql security invoker set search_path = '' as
$$select internal.cancel_club_referee_payout_for_actor(target_payout_id)$$;
create or replace function api.set_club_referee_payer(target_club_id uuid, target_person_id uuid, enabled boolean)
returns void language sql security invoker set search_path = '' as
$$select internal.set_club_referee_payer_for_actor(target_club_id, target_person_id, enabled)$$;

revoke all on function internal.actor_pays_club_referees(uuid), internal.actor_sees_referee_pay(uuid),
  internal.club_referee_fee(uuid, text), internal.referee_tax_free_limit(integer),
  internal.club_referee_year_total(uuid, integer), internal.create_due_club_referee_reports(uuid),
  internal.club_referee_report_json(uuid), internal.notify_club_referee_pay(uuid, uuid, text, uuid, jsonb),
  internal.club_referee_payout_json(uuid),
  internal.get_club_referee_fees_for_actor(uuid), internal.save_club_referee_fee_for_actor(uuid, uuid, integer, integer),
  internal.list_club_referee_reports_for_actor(uuid, text), internal.ask_club_referee_control_for_actor(uuid),
  internal.answer_club_referee_control_for_actor(uuid, boolean, text),
  internal.decide_club_referee_reports_for_actor(uuid, uuid[], boolean, text),
  internal.set_club_referee_report_amount_for_actor(uuid, integer), internal.note_club_referee_report_for_actor(uuid, text),
  internal.list_my_referee_reports_for_actor(), internal.create_club_referee_payout_for_actor(uuid, date),
  internal.get_club_referee_payout_for_actor(uuid), internal.list_club_referee_payouts_for_actor(uuid),
  internal.mark_club_referee_payout_paid_for_actor(uuid), internal.cancel_club_referee_payout_for_actor(uuid),
  internal.set_club_referee_payer_for_actor(uuid, uuid, boolean),
  api.get_club_referee_fees(uuid), api.save_club_referee_fee(uuid, uuid, integer, integer),
  api.list_club_referee_reports(uuid, text), api.ask_club_referee_control(uuid),
  api.answer_club_referee_control(uuid, boolean, text), api.decide_club_referee_reports(uuid, uuid[], boolean, text),
  api.set_club_referee_report_amount(uuid, integer), api.note_club_referee_report(uuid, text),
  api.list_my_referee_reports(), api.create_club_referee_payout(uuid, date), api.get_club_referee_payout(uuid),
  api.list_club_referee_payouts(uuid), api.mark_club_referee_payout_paid(uuid), api.cancel_club_referee_payout(uuid),
  api.set_club_referee_payer(uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function
  internal.get_club_referee_fees_for_actor(uuid), internal.save_club_referee_fee_for_actor(uuid, uuid, integer, integer),
  internal.list_club_referee_reports_for_actor(uuid, text), internal.ask_club_referee_control_for_actor(uuid),
  internal.answer_club_referee_control_for_actor(uuid, boolean, text),
  internal.decide_club_referee_reports_for_actor(uuid, uuid[], boolean, text),
  internal.set_club_referee_report_amount_for_actor(uuid, integer), internal.note_club_referee_report_for_actor(uuid, text),
  internal.list_my_referee_reports_for_actor(), internal.create_club_referee_payout_for_actor(uuid, date),
  internal.get_club_referee_payout_for_actor(uuid), internal.list_club_referee_payouts_for_actor(uuid),
  internal.mark_club_referee_payout_paid_for_actor(uuid), internal.cancel_club_referee_payout_for_actor(uuid),
  internal.set_club_referee_payer_for_actor(uuid, uuid, boolean),
  api.get_club_referee_fees(uuid), api.save_club_referee_fee(uuid, uuid, integer, integer),
  api.list_club_referee_reports(uuid, text), api.ask_club_referee_control(uuid),
  api.answer_club_referee_control(uuid, boolean, text), api.decide_club_referee_reports(uuid, uuid[], boolean, text),
  api.set_club_referee_report_amount(uuid, integer), api.note_club_referee_report(uuid, text),
  api.list_my_referee_reports(), api.create_club_referee_payout(uuid, date), api.get_club_referee_payout(uuid),
  api.list_club_referee_payouts(uuid), api.mark_club_referee_payout_paid(uuid), api.cancel_club_referee_payout(uuid),
  api.set_club_referee_payer(uuid, uuid, boolean)
  to authenticated;

-- Reports also come without anyone opening the app.
do $$
declare existing_job_id bigint;
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    for existing_job_id in select jobid from cron.job where jobname = 'club-referee-reports' loop
      perform cron.unschedule(existing_job_id);
    end loop;
    perform cron.schedule('club-referee-reports', '*/15 * * * *', 'select internal.create_due_club_referee_reports();');
  end if;
end $$;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261110090000_club_referee_pay', 'greenfield', 'REF-02: club referee reports, approval and payout lists'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261110090000_club_referee_pay');
notify pgrst, 'reload schema';
