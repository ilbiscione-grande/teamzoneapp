-- Expired grace is a persistent read-only state, not a future expiry window.

create or replace function internal.recompute_club_entitlements(target_billing_account_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  account core.billing_accounts%rowtype;
  subscription core.billing_subscriptions%rowtype;
  mode text := 'denied';
  effective_time timestamptz := now();
begin
  select * into account from core.billing_accounts
   where id = target_billing_account_id for update;
  if account.id is null then raise no_data_found using message = 'billing_account_not_found'; end if;

  select * into subscription from core.billing_subscriptions
   where billing_account_id = account.id;

  delete from core.club_entitlements where billing_account_id = account.id;
  if subscription.id is null or subscription.state = 'unknown' then return; end if;

  mode := case
    when subscription.state in ('active', 'trialing') then 'write'
    when subscription.state = 'grace' and subscription.grace_ends_at > effective_time then 'write'
    when subscription.state in ('grace', 'read_only', 'ended') then 'read_only'
    else 'denied'
  end;

  insert into core.club_entitlements(
    club_id,billing_account_id,entitlement_key,access_mode,quantity,
    source_subscription_revision,effective_at,expires_at
  ) values (
    account.club_id,account.id,replace(subscription.base_plan_key,'plan.','base.'),mode,null,
    subscription.revision,effective_time,
    case when subscription.state = 'grace' and subscription.grace_ends_at > effective_time
      then subscription.grace_ends_at else null end
  );

  insert into core.club_entitlements(
    club_id,billing_account_id,entitlement_key,access_mode,quantity,
    source_subscription_revision,effective_at,expires_at
  )
  select account.club_id,account.id,item.entitlement_key,mode,item.quantity,
    subscription.revision,effective_time,
    case when item.ends_at > effective_time then item.ends_at else null end
  from core.billing_subscription_items item
  where item.subscription_id = subscription.id and item.state = 'active'
    and item.starts_at <= effective_time
    and (item.ends_at is null or item.ends_at > effective_time);
end;
$$;

revoke all on function internal.recompute_club_entitlements(uuid)
  from public, anon, authenticated;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260816111600_s10a_fix_expired_grace_projection','greenfield');
