-- Checkout events bind provider references but are not subscription revisions.
-- Keep the revision empty until a subscription lifecycle event is processed.

create function internal.normalize_unknown_billing_subscription_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.state = 'unknown' then
    new.provider_revision := null;
  end if;
  return new;
end
$$;

create trigger normalize_unknown_billing_subscription_revision
before insert or update on core.billing_subscriptions
for each row execute function internal.normalize_unknown_billing_subscription_revision();

update core.billing_subscriptions
set provider_revision = null,
    updated_at = now(),
    revision = revision + 1
where state = 'unknown' and provider_revision is not null;

revoke all on function internal.normalize_unknown_billing_subscription_revision() from public, anon, authenticated;

insert into internal.migration_provenance(migration_name, source_kind)
values ('20260817101000_s10a_fix_checkout_subscription_revision', 'greenfield');
