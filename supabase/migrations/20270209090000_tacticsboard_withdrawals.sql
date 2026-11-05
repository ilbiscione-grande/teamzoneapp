-- Withdrawing from a Tacticsboard purchase (2 kap. 10 a § distansavtalslagen,
-- in force 2026-06-19): the person's message and when we received it, kept as
-- proof with the bookkeeping, so the row outlives the account. The function
-- tacticsboard-billing checks the deadline against Stripe, ends the
-- subscription and sends the receipt. A refund is made by hand in Stripe.
create table internal.personal_billing_withdrawals (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references core.profiles(id) on delete set null,
  livemode boolean not null,
  provider_subscription_ref text not null unique
    check (provider_subscription_ref ~ '^sub_[A-Za-z0-9]+$'),
  customer_name text not null check (char_length(btrim(customer_name)) between 1 and 200),
  customer_email text not null check (char_length(customer_email) between 3 and 320),
  purchased_at timestamptz not null,
  received_at timestamptz not null default now(),
  receipt_sent_at timestamptz
);
alter table internal.personal_billing_withdrawals enable row level security;
revoke all on internal.personal_billing_withdrawals from public, anon, authenticated;

create function internal.tacticsboard_withdrawal_for_server(target_subscription_ref text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', id, 'received_at', received_at, 'receipt_sent_at', receipt_sent_at)
    from internal.personal_billing_withdrawals
   where provider_subscription_ref = target_subscription_ref
$$;

-- One withdrawal per purchase: a repeat returns the first, with its time.
create function internal.record_tacticsboard_withdrawal_for_server(target_profile_id uuid, target_livemode boolean,
  target_subscription_ref text, target_name text, target_email text, target_purchased_at timestamptz)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  insert into internal.personal_billing_withdrawals
    (profile_id, livemode, provider_subscription_ref, customer_name, customer_email, purchased_at)
  values (target_profile_id, target_livemode, target_subscription_ref, btrim(target_name), target_email, target_purchased_at)
  on conflict (provider_subscription_ref) do nothing;
  return internal.tacticsboard_withdrawal_for_server(target_subscription_ref);
end $$;

create function internal.mark_tacticsboard_withdrawal_receipt_for_server(target_withdrawal_id uuid)
returns void language sql security definer set search_path = '' as $$
  update internal.personal_billing_withdrawals set receipt_sent_at = coalesce(receipt_sent_at, now())
   where id = target_withdrawal_id
$$;

create function api.tacticsboard_withdrawal(target_subscription_ref text) returns jsonb
language sql stable security invoker set search_path = '' as
$$ select internal.tacticsboard_withdrawal_for_server(target_subscription_ref) $$;
create function api.record_tacticsboard_withdrawal(target_profile_id uuid, target_livemode boolean,
  target_subscription_ref text, target_name text, target_email text, target_purchased_at timestamptz) returns jsonb
language sql security invoker set search_path = '' as
$$ select internal.record_tacticsboard_withdrawal_for_server(target_profile_id, target_livemode,
  target_subscription_ref, target_name, target_email, target_purchased_at) $$;
create function api.mark_tacticsboard_withdrawal_receipt(target_withdrawal_id uuid) returns void
language sql security invoker set search_path = '' as
$$ select internal.mark_tacticsboard_withdrawal_receipt_for_server(target_withdrawal_id) $$;

revoke all on function
  internal.tacticsboard_withdrawal_for_server(text),
  internal.record_tacticsboard_withdrawal_for_server(uuid, boolean, text, text, text, timestamptz),
  internal.mark_tacticsboard_withdrawal_receipt_for_server(uuid),
  api.tacticsboard_withdrawal(text),
  api.record_tacticsboard_withdrawal(uuid, boolean, text, text, text, timestamptz),
  api.mark_tacticsboard_withdrawal_receipt(uuid)
from public, anon, authenticated;
grant execute on function
  internal.tacticsboard_withdrawal_for_server(text),
  internal.record_tacticsboard_withdrawal_for_server(uuid, boolean, text, text, text, timestamptz),
  internal.mark_tacticsboard_withdrawal_receipt_for_server(uuid),
  api.tacticsboard_withdrawal(text),
  api.record_tacticsboard_withdrawal(uuid, boolean, text, text, text, timestamptz),
  api.mark_tacticsboard_withdrawal_receipt(uuid)
to service_role;
notify pgrst, 'reload schema';
