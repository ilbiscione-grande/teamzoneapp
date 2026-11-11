-- Betalstatus (club-members-and-fees.md, step 3): an issued round's fees are
-- marked paid by hand (day, Swish, bank, cash or other, a note), one or
-- many at a time, or waived; a mistake is undone by opening the fee again.
-- Every change is kept in audit.command_events with what it was before.
-- Fees of 0 kr (covered by the family cap) stay waived. No payment
-- integration: paying in the app is the Economy module's add-on.

alter table core.club_fees
  add column paid_on date,
  add column payment_method text check (payment_method in ('swish', 'bank', 'cash', 'other')),
  add column note text check (length(note) <= 200),
  add column marked_at timestamptz,
  add column marked_by uuid references core.profiles(id),
  add constraint club_fees_paid_has_day check ((state = 'paid') = (paid_on is not null and payment_method is not null));

-- The round list with what is paid and what is left.
create or replace function internal.get_club_fee_rounds_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object('rounds', coalesce((select jsonb_agg(internal.club_fee_round_json(fee_round)
      || (select jsonb_build_object('fee_count', count(*) filter (where totals.amount > 0),
        'total', coalesce(sum(totals.amount), 0),
        'paid_count', count(*) filter (where totals.state = 'paid'),
        'paid_total', coalesce(sum(totals.amount) filter (where totals.state = 'paid'), 0),
        'open_count', count(*) filter (where totals.state = 'open' and totals.amount > 0),
        'open_total', coalesce(sum(totals.amount) filter (where totals.state = 'open'), 0))
        from (select line.amount, 'open'::text as state from internal.club_fee_round_lines(fee_round.id) line
            where fee_round.state = 'draft'
          union all
          select fee.amount, fee.state from core.club_fees fee
            where fee.round_id = fee_round.id and fee_round.state = 'issued' and fee.state <> 'cancelled') totals)
      order by fee_round.created_at desc)
    from core.club_fee_rounds fee_round
    where fee_round.club_id = target_club_id and fee_round.state <> 'cancelled'), '[]'::jsonb));
end;
$$;

-- One round with its fees; issued fees carry their id, revision and payment.
create or replace function internal.get_club_fee_round_for_actor(target_club_id uuid, target_round_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare fee_round core.club_fee_rounds%rowtype;
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into fee_round from core.club_fee_rounds where id = target_round_id and club_id = target_club_id and state <> 'cancelled';
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.club_fee_round_json(fee_round) || jsonb_build_object(
    'fees', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('fee_id', line.fee_id,
        'person_id', line.person_id, 'name', line.name,
        'category', line.category, 'family_key', line.family_key, 'base_amount', line.base_amount,
        'discount_amount', line.discount_amount, 'amount', line.amount, 'state', line.state,
        'revision', line.revision, 'paid_on', line.paid_on, 'payment_method', line.payment_method,
        'note', line.note, 'marked_at', line.marked_at))
        || jsonb_build_object('guardians', internal.club_person_guardian_names(target_club_id, line.person_id))
        order by line.name, line.person_id)
      from (
        select null::uuid as fee_id, computed.person_id, computed.name, computed.category, computed.family_key,
          computed.base_amount, computed.discount_amount, computed.amount,
          case when computed.amount = 0 then 'waived' else 'open' end as state, 0::bigint as revision,
          null::date as paid_on, null::text as payment_method, null::text as note, null::timestamptz as marked_at
        from internal.club_fee_round_lines(fee_round.id) computed where fee_round.state = 'draft'
        union all
        select fee.id, fee.club_person_id, person.display_name, fee.category, fee.family_key, fee.base_amount,
          fee.discount_amount, fee.amount, fee.state, fee.revision, fee.paid_on, fee.payment_method, fee.note, fee.marked_at
        from core.club_fees fee join core.club_people person on person.id = fee.club_person_id
        where fee.round_id = fee_round.id and fee_round.state = 'issued' and fee.state <> 'cancelled') line), '[]'::jsonb),
    'missing', case when fee_round.kind = 'membership' and fee_round.state = 'draft' then
      coalesce((select jsonb_agg(member.name order by member.name)
        from internal.club_effective_members(target_club_id) member where member.category is null), '[]'::jsonb)
      else '[]'::jsonb end);
end;
$$;

-- target_fees: [{fee_id, revision}], all from one issued round of the club.
-- decision: paid (with paid_on and method), waived, or open (undo).
create or replace function internal.mark_club_fees_for_actor(target_club_id uuid, target_fees jsonb, decision text,
  new_paid_on date, new_method text, new_note text, idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); cached jsonb; result jsonb; wanted int; matched int; round_ids uuid[];
  fee_ids uuid[]; revisions bigint[];
  clean_note text := nullif(btrim(coalesce(new_note, '')), '');
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if idempotency_key is null or decision is null or decision not in ('paid', 'waived', 'open')
    or jsonb_typeof(target_fees) is distinct from 'array' or jsonb_array_length(target_fees) not between 1 and 500
    or (decision = 'paid' and (new_paid_on is null or new_method is null
      or new_method not in ('swish', 'bank', 'cash', 'other') or new_paid_on > current_date + 1))
    or length(clean_note) > 200 then
    raise invalid_parameter_value using message = 'invalid_fee_mark';
  end if;
  select d.result into cached from internal.command_deduplication d where d.actor_profile_id = actor_id
    and d.command_type = 'club.fee.marked.v1' and d.idempotency_key = mark_club_fees_for_actor.idempotency_key;
  if cached is not null then return cached; end if;
  begin
    select array_agg(parsed.fee_id), array_agg(parsed.revision) into fee_ids, revisions
    from (select distinct on ((item->>'fee_id')::uuid) (item->>'fee_id')::uuid as fee_id, (item->>'revision')::bigint as revision
      from jsonb_array_elements(target_fees) item) parsed;
  exception when others then
    raise invalid_parameter_value using message = 'invalid_fee_mark';
  end;
  wanted := cardinality(fee_ids);
  if exists (select 1 from unnest(fee_ids, revisions) t(fee_id, revision) where t.fee_id is null or t.revision is null) then
    raise invalid_parameter_value using message = 'invalid_fee_mark';
  end if;
  select count(*), array_agg(distinct fee.round_id) into matched, round_ids
  from core.club_fees fee join unnest(fee_ids, revisions) target(fee_id, revision) on target.fee_id = fee.id
  join core.club_fee_rounds fee_round on fee_round.id = fee.round_id and fee_round.state = 'issued'
  where fee.club_id = target_club_id and fee.state <> 'cancelled';
  if matched <> wanted or cardinality(round_ids) <> 1 then
    raise insufficient_privilege using message = 'not_found';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('club-fee-round:' || round_ids[1]::text, 0));
  if exists (select 1 from core.club_fees fee join unnest(fee_ids, revisions) target(fee_id, revision) on target.fee_id = fee.id
      where fee.revision <> target.revision) then
    raise sqlstate 'PT409' using message = 'stale_revision';
  end if;
  -- Nothing to pay: a 0 kr fee stays waived.
  if decision <> 'waived' and exists (select 1 from core.club_fees fee join unnest(fee_ids, revisions) target(fee_id, revision)
      on target.fee_id = fee.id where fee.amount = 0) then
    raise invalid_parameter_value using message = 'nothing_to_pay';
  end if;
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  select target_club_id, actor_id, 'club.fee.marked.v1', 'club_fee', fee.id, fee.revision + 1,
    jsonb_build_object('from', jsonb_build_object('state', fee.state, 'paid_on', fee.paid_on, 'payment_method', fee.payment_method,
        'note', fee.note),
      'to', jsonb_build_object('state', decision, 'paid_on', case when decision = 'paid' then new_paid_on end,
        'payment_method', case when decision = 'paid' then new_method end, 'note', clean_note))
  from core.club_fees fee join unnest(fee_ids, revisions) target(fee_id, revision) on target.fee_id = fee.id;
  update core.club_fees fee set state = decision,
    paid_on = case when decision = 'paid' then new_paid_on end,
    payment_method = case when decision = 'paid' then new_method end,
    note = clean_note, marked_at = now(), marked_by = actor_id, revision = fee.revision + 1
  from unnest(fee_ids, revisions) target(fee_id, revision) where target.fee_id = fee.id;
  get diagnostics matched = row_count;
  result := jsonb_build_object('decision', decision, 'count', matched);
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'club.fee.marked.v1', result);
  return result;
end;
$$;

create or replace function api.mark_club_fees(target_club_id uuid, target_fees jsonb, decision text,
  new_paid_on date, new_method text, new_note text, idempotency_key uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.mark_club_fees_for_actor(target_club_id, target_fees, decision, new_paid_on, new_method, new_note,
    idempotency_key) $$;

revoke all on function
  internal.mark_club_fees_for_actor(uuid, jsonb, text, date, text, text, uuid),
  api.mark_club_fees(uuid, jsonb, text, date, text, text, uuid)
from public, anon, authenticated;
grant execute on function
  internal.mark_club_fees_for_actor(uuid, jsonb, text, date, text, text, uuid),
  api.mark_club_fees(uuid, jsonb, text, date, text, text, uuid)
to authenticated;
notify pgrst, 'reload schema';
