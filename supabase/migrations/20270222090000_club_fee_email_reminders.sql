-- Påminnelser via e-post (club-members-and-fees.md, step 5): a reminder also
-- goes by e-mail to whoever has no TeamZone account - the person, or for a
-- child the guardians - when the club's register has their e-mail address.
-- Decided for the build (2026-11-11): sent as "<club> via TeamZone"
-- <avgifter@teamzoneapp.se>, no replies (contact the club); the same limit
-- as in the app (a fee at most once in 20 hours); every e-mail has an
-- unsubscribe link and List-Unsubscribe, and an address that unsubscribed
-- gets no more fee e-mail. The fee-email-worker Edge Function sends the
-- queue every minute through Resend, like the club site's answers.
-- The reminder functions are their versions from 20270218090000 with the
-- e-mail added.

create table internal.club_fee_emails (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  round_id uuid not null references core.club_fee_rounds(id),
  recipient_person_id uuid not null,
  email text not null check (length(email) between 3 and 254),
  fee_ids uuid[] not null,
  amount bigint not null check (amount >= 0),
  state text not null default 'pending' check (state in ('pending', 'processing', 'sent', 'failed', 'suppressed')),
  attempts integer not null default 0,
  provider_id text,
  error_code text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index club_fee_emails_queue on internal.club_fee_emails (state, created_at) where state in ('pending', 'failed');
alter table internal.club_fee_emails enable row level security;
revoke all on internal.club_fee_emails from public, anon, authenticated;

-- Addresses that do not want fee e-mail, as a hash of the lower-case address.
create table internal.fee_email_optouts (
  email_hash bytea primary key,
  created_at timestamptz not null default now()
);
alter table internal.fee_email_optouts enable row level security;
revoke all on internal.fee_email_optouts from public, anon, authenticated;

create or replace function internal.fee_email_hash(address text)
returns bytea language sql immutable set search_path = '' as $$
  select extensions.digest(lower(btrim(address)), 'sha256')
$$;

-- Who gets the e-mail about a fee: the person and the guardians without an
-- account, with an address, not unsubscribed.
create or replace function internal.club_fee_email_recipients(target_fee_id uuid)
returns table (club_person_id uuid, email text)
language sql stable security definer set search_path = '' as $$
  with fee as (select * from core.club_fees where id = target_fee_id), people as (
    select fee.club_person_id as person_id from fee
    union
    select relation.guardian_person_id from fee
    join core.guardian_relations relation on relation.club_id = fee.club_id
      and relation.child_person_id = fee.club_person_id and relation.state = 'active'
      and (relation.ends_at is null or relation.ends_at > now())
  )
  select distinct on (lower(btrim(person.contact_email))) person.id, lower(btrim(person.contact_email))
  from people join fee on true
  join core.club_people person on person.id = people.person_id and person.club_id = fee.club_id
    and person.status = 'active'
  where nullif(btrim(person.contact_email), '') is not null and position('@' in person.contact_email) > 1
    and not exists (select 1 from core.person_account_links link where link.club_person_id = person.id
      and link.club_id = fee.club_id and link.state = 'active')
    and not exists (select 1 from internal.fee_email_optouts optout
      where optout.email_hash = internal.fee_email_hash(person.contact_email))
  order by lower(btrim(person.contact_email)), person.id
$$;

-- Whether anyone hears about the fee, in the app or by e-mail.
create or replace function internal.club_fee_reachable(target_fee_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from internal.club_fee_recipients(target_fee_id))
    or exists (select 1 from internal.club_fee_email_recipients(target_fee_id))
$$;

-- As in 20270218090000; reachable counts e-mail too.
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
        'note', line.note, 'marked_at', line.marked_at, 'reminded_at', line.reminded_at,
        'reminder_count', line.reminder_count))
        || jsonb_build_object('guardians', internal.club_person_guardian_names(target_club_id, line.person_id),
          'reachable', case when line.fee_id is null then null
            else internal.club_fee_reachable(line.fee_id) end)
        order by line.name, line.person_id)
      from (
        select null::uuid as fee_id, computed.person_id, computed.name, computed.category, computed.family_key,
          computed.base_amount, computed.discount_amount, computed.amount,
          case when computed.amount = 0 then 'waived' else 'open' end as state, 0::bigint as revision,
          null::date as paid_on, null::text as payment_method, null::text as note, null::timestamptz as marked_at,
          null::timestamptz as reminded_at, 0 as reminder_count
        from internal.club_fee_round_lines(fee_round.id) computed where fee_round.state = 'draft'
        union all
        select fee.id, fee.club_person_id, person.display_name, fee.category, fee.family_key, fee.base_amount,
          fee.discount_amount, fee.amount, fee.state, fee.revision, fee.paid_on, fee.payment_method, fee.note,
          fee.marked_at, fee.reminded_at, fee.reminder_count
        from core.club_fees fee join core.club_people person on person.id = fee.club_person_id
        where fee.round_id = fee_round.id and fee_round.state = 'issued' and fee.state <> 'cancelled') line), '[]'::jsonb),
    'missing', case when fee_round.kind = 'membership' and fee_round.state = 'draft' then
      coalesce((select jsonb_agg(member.name order by member.name)
        from internal.club_effective_members(target_club_id) member where member.category is null), '[]'::jsonb)
      else '[]'::jsonb end);
end;
$$;


-- As in 20270218090000, with the e-mail: a fee is reminded when someone
-- hears about it in the app or by e-mail; one e-mail per address and send.
create or replace function internal.send_club_fee_reminders_for_actor(target_club_id uuid, target_round_id uuid,
  target_fee_ids uuid[], idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); cached jsonb; result jsonb; fee_round core.club_fee_rounds%rowtype;
  event_id uuid := gen_random_uuid(); reminded uuid[]; recent int; unreachable jsonb; sent int; emails int;
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if idempotency_key is null or cardinality(target_fee_ids) = 0 or cardinality(target_fee_ids) > 1000 then
    raise invalid_parameter_value using message = 'invalid_reminder';
  end if;
  select d.result into cached from internal.command_deduplication d where d.actor_profile_id = actor_id
    and d.command_type = 'club.fee.reminded.v1' and d.idempotency_key = send_club_fee_reminders_for_actor.idempotency_key;
  if cached is not null then return cached; end if;
  select * into fee_round from core.club_fee_rounds
  where id = target_round_id and club_id = target_club_id and state = 'issued';
  if fee_round.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  if target_fee_ids is not null and exists (select 1 from unnest(target_fee_ids) given(id)
      where not exists (select 1 from core.club_fees fee where fee.id = given.id and fee.round_id = fee_round.id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('club-fee-round:' || fee_round.id::text, 0));
  with wanted as (
    select fee.*, internal.club_fee_reachable(fee.id) as reachable from core.club_fees fee
    where fee.round_id = fee_round.id and fee.state = 'open' and fee.amount > 0
      and (target_fee_ids is null or fee.id = any(target_fee_ids))
  )
  select
    array_agg(wanted.id) filter (where (wanted.reminded_at is null or wanted.reminded_at < now() - interval '20 hours')
      and wanted.reachable),
    count(*) filter (where wanted.reminded_at >= now() - interval '20 hours'),
    coalesce(jsonb_agg(person.display_name order by person.display_name) filter (where not wanted.reachable), '[]'::jsonb)
  into reminded, recent, unreachable
  from wanted join core.club_people person on person.id = wanted.club_person_id;
  reminded := coalesce(reminded, '{}');
  -- In the app: one notification per recipient, naming the fees.
  insert into internal.notification_outbox (club_id, domain_event_id, event_type, aggregate_type, aggregate_id,
    recipient_profile_id, recipient_person_id, payload_ref)
  select target_club_id, event_id, 'club.fee.reminder.v1', 'club_fee_round', fee_round.id,
    recipient.profile_id, min(recipient.club_person_id::text)::uuid,
    jsonb_build_object('round_id', fee_round.id, 'fee_ids', jsonb_agg(fee.id), 'amount', sum(fee.amount))
  from core.club_fees fee
  cross join lateral internal.club_fee_recipients(fee.id) recipient
  where fee.id = any(reminded)
  group by recipient.profile_id
  on conflict do nothing;
  get diagnostics sent = row_count;
  -- By e-mail: one per address, naming the fees.
  insert into internal.club_fee_emails (club_id, round_id, recipient_person_id, email, fee_ids, amount)
  select target_club_id, fee_round.id, min(recipient.club_person_id::text)::uuid, recipient.email,
    array_agg(fee.id order by fee.id), sum(fee.amount)
  from core.club_fees fee
  cross join lateral internal.club_fee_email_recipients(fee.id) recipient
  where fee.id = any(reminded)
  group by recipient.email;
  get diagnostics emails = row_count;
  update core.club_fees set reminded_at = now(), reminder_count = reminder_count + 1
  where id = any(reminded);
  result := jsonb_build_object('reminded', cardinality(reminded), 'notifications', sent, 'emails', emails,
    'skipped_recent', recent, 'unreachable', unreachable);
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'club.fee.reminded.v1', result);
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  values (target_club_id, actor_id, 'club.fee.reminded.v1', 'club_fee_round', fee_round.id, fee_round.revision,
    result || jsonb_build_object('fee_ids', to_jsonb(reminded)));
  return result;
end;
$$;

-- The worker's batch: the e-mail's facts, never more. Only fees still
-- unpaid are named; an e-mail whose fees are all paid is suppressed.
create or replace function internal.claim_club_fee_emails(batch_size integer default 20)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  update internal.club_fee_emails mail set state = 'suppressed'
  where mail.state in ('pending', 'failed')
    and (not exists (select 1 from core.club_fees fee where fee.id = any(mail.fee_ids) and fee.state = 'open')
      or exists (select 1 from internal.fee_email_optouts optout where optout.email_hash = internal.fee_email_hash(mail.email)));
  with picked as (
    select mail.id from internal.club_fee_emails mail
    where mail.state = 'pending' or (mail.state = 'failed' and mail.attempts < 5)
    order by mail.created_at limit least(greatest(batch_size, 1), 50)
    for update skip locked
  ), claimed as (
    update internal.club_fee_emails mail set state = 'processing', attempts = mail.attempts + 1
    from picked where mail.id = picked.id returning mail.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'email_id', claimed.id, 'to', claimed.email, 'club_name', club.name,
    'title', fee_round.title, 'due_on', fee_round.due_on, 'payment_info', fee_round.payment_info,
    'fees', (select coalesce(jsonb_agg(jsonb_build_object('name', person.display_name, 'amount', fee.amount)
        order by person.display_name), '[]'::jsonb)
      from core.club_fees fee join core.club_people person on person.id = fee.club_person_id
      where fee.id = any(claimed.fee_ids) and fee.state = 'open'))), '[]'::jsonb)
  into result
  from claimed join core.clubs club on club.id = claimed.club_id
  join core.club_fee_rounds fee_round on fee_round.id = claimed.round_id;
  return result;
end;$$;

create or replace function internal.finish_club_fee_email(target_email_id uuid, sent boolean, provider_id text,
  error_code text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  update internal.club_fee_emails set
    state = case when finish_club_fee_email.sent then 'sent' else 'failed' end,
    sent_at = case when finish_club_fee_email.sent then now() else club_fee_emails.sent_at end,
    provider_id = case when finish_club_fee_email.sent then left(finish_club_fee_email.provider_id, 200)
      else club_fee_emails.provider_id end,
    error_code = case when finish_club_fee_email.sent then null else left(finish_club_fee_email.error_code, 80) end
  where id = target_email_id and state = 'processing';
end;$$;

-- The unsubscribe link (signed by the Edge Function): no more fee e-mail.
create or replace function internal.opt_out_fee_email(address text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  if nullif(btrim(coalesce(address, '')), '') is null then return; end if;
  insert into internal.fee_email_optouts (email_hash) values (internal.fee_email_hash(address))
  on conflict do nothing;
end;$$;

create or replace function internal.invoke_fee_email_worker()
returns bigint language plpgsql security definer set search_path = '' as $$
declare project_url text; worker_token text; request_id bigint;
begin
  if not exists (select 1 from internal.club_fee_emails
      where state = 'pending' or (state = 'failed' and attempts < 5)) then
    return null;
  end if;
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into worker_token from vault.decrypted_secrets where name = 'support_email_worker_token' limit 1;
  if nullif(project_url, '') is null or nullif(worker_token, '') is null then return null; end if;
  select net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/fee-email-worker',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-teamzone-worker-token', worker_token),
    body := '{}'::jsonb, timeout_milliseconds := 15000) into request_id;
  return request_id;
end;$$;

create or replace function api.claim_club_fee_emails(batch_size integer default 20)
returns jsonb language sql security invoker set search_path = '' as $$ select internal.claim_club_fee_emails(batch_size) $$;
create or replace function api.finish_club_fee_email(target_email_id uuid, sent boolean, provider_id text, error_code text)
returns void language sql security invoker set search_path = '' as
$$ select internal.finish_club_fee_email(target_email_id, sent, provider_id, error_code) $$;
create or replace function api.opt_out_fee_email(address text)
returns void language sql security invoker set search_path = '' as $$ select internal.opt_out_fee_email(address) $$;

revoke all on function internal.fee_email_hash(text), internal.club_fee_email_recipients(uuid),
  internal.club_fee_reachable(uuid), internal.claim_club_fee_emails(integer),
  internal.finish_club_fee_email(uuid, boolean, text, text), internal.opt_out_fee_email(text),
  internal.invoke_fee_email_worker(), api.claim_club_fee_emails(integer),
  api.finish_club_fee_email(uuid, boolean, text, text), api.opt_out_fee_email(text)
from public, anon, authenticated;
grant execute on function internal.claim_club_fee_emails(integer), internal.finish_club_fee_email(uuid, boolean, text, text),
  internal.opt_out_fee_email(text), api.claim_club_fee_emails(integer),
  api.finish_club_fee_email(uuid, boolean, text, text), api.opt_out_fee_email(text)
to service_role;

-- The unsubscribe link names the e-mail, not the address: the address it
-- went to stops getting fee e-mail.
create or replace function internal.opt_out_fee_email_by_id(target_email_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare address text;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  select email into address from internal.club_fee_emails where id = target_email_id;
  if address is null then return false; end if;
  insert into internal.fee_email_optouts (email_hash) values (internal.fee_email_hash(address))
  on conflict do nothing;
  return true;
end;$$;
create or replace function api.opt_out_fee_email_by_id(target_email_id uuid)
returns boolean language sql security invoker set search_path = '' as
$$ select internal.opt_out_fee_email_by_id(target_email_id) $$;
revoke all on function internal.opt_out_fee_email_by_id(uuid), api.opt_out_fee_email_by_id(uuid)
  from public, anon, authenticated;
grant execute on function internal.opt_out_fee_email_by_id(uuid), api.opt_out_fee_email_by_id(uuid) to service_role;

do $$
declare existing_job_id bigint;
begin
  for existing_job_id in select jobid from cron.job where jobname = 'fee-email-worker' loop
    perform cron.unschedule(existing_job_id);
  end loop;
  perform cron.schedule('fee-email-worker', '* * * * *', 'select internal.invoke_fee_email_worker();');
end $$;
notify pgrst, 'reload schema';
