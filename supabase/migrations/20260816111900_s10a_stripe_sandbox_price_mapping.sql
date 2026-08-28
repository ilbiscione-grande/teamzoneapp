-- Stripe TeamzoneApp sandbox mappings. The referenced pricebook remains draft.

insert into internal.billing_provider_prices(
  pricebook_version,plan_key,billing_interval,provider,provider_price_ref,active
) values
 ('se.v1-draft','plan.small','month','stripe','price_1U50LI7PpJ8jdE0FbIw0FEkt',true),
 ('se.v1-draft','plan.small','year','stripe','price_1U50OH7PpJ8jdE0FvSDvNuSA',true),
 ('se.v1-draft','plan.medium','month','stripe','price_1U50OH7PpJ8jdE0FQi6oHR6c',true),
 ('se.v1-draft','plan.medium','year','stripe','price_1U50OH7PpJ8jdE0FnBCN9LsL',true),
 ('se.v1-draft','plan.large','month','stripe','price_1U50OH7PpJ8jdE0FQ64Fwk38',true),
 ('se.v1-draft','plan.large','year','stripe','price_1U50OH7PpJ8jdE0Fs90kv0XO',true);

insert into internal.migration_provenance(migration_name,source_kind)
values('20260816111900_s10a_stripe_sandbox_price_mapping','greenfield');
