-- Stripe TeamzoneApp sandbox mappings. The referenced pricebook remains draft.
-- audit-only: Stripe sandbox price ids belong to the test project only. Outside the test (audit) project, where the pilot
-- club e423cb36-eaf3-44a5-b6d0-0406914a21ae does not exist (an empty database, production), this
-- migration does nothing; production billing gets its own live price
-- mappings and grants by a separate, approved change.
do $audit$
begin
 if not exists (select 1 from core.clubs where id = 'e423cb36-eaf3-44a5-b6d0-0406914a21ae') then
  raise notice 'skipped: audit-only migration';
  return;
 end if;
 insert into internal.billing_provider_prices(
   pricebook_version,plan_key,billing_interval,provider,provider_price_ref,active
 ) values
  ('se.v1-draft','plan.small','month','stripe','price_1U50LI7PpJ8jdE0FbIw0FEkt',true),
  ('se.v1-draft','plan.small','year','stripe','price_1U50OH7PpJ8jdE0FvSDvNuSA',true),
  ('se.v1-draft','plan.medium','month','stripe','price_1U50OH7PpJ8jdE0FQi6oHR6c',true),
  ('se.v1-draft','plan.medium','year','stripe','price_1U50OH7PpJ8jdE0FnBCN9LsL',true),
  ('se.v1-draft','plan.large','month','stripe','price_1U50OH7PpJ8jdE0FQ64Fwk38',true),
  ('se.v1-draft','plan.large','year','stripe','price_1U50OH7PpJ8jdE0Fs90kv0XO',true);
end $audit$;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260816111900_s10a_stripe_sandbox_price_mapping','greenfield');
