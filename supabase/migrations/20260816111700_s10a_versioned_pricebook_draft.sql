-- Versioned Swedish draft pricebook. It is not published and cannot authorize checkout.

create table core.billing_pricebooks (
  version text primary key check (version ~ '^[a-z]{2}\.v[0-9]+(-draft)?$'),
  market text not null check (market ~ '^[a-z]{2}$'),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  state text not null default 'draft' check (state in ('draft', 'published', 'retired')),
  tax_presentation text not null check (tax_presentation in ('inclusive', 'exclusive')),
  display_vat_basis_points integer check (display_vat_basis_points between 0 and 10000),
  annual_month_equivalent integer not null check (annual_month_equivalent between 1 and 12),
  published_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  check ((state = 'published' and published_at is not null and retired_at is null)
      or (state = 'retired' and published_at is not null and retired_at is not null)
      or (state = 'draft' and published_at is null and retired_at is null))
);

create table core.billing_pricebook_plans (
  pricebook_version text not null references core.billing_pricebooks(version),
  plan_key text not null check (plan_key ~ '^plan\.[a-z0-9_]+$'),
  display_order integer not null check (display_order > 0),
  monthly_amount_minor integer check (monthly_amount_minor >= 0),
  annual_amount_minor integer check (annual_amount_minor >= 0),
  max_active_teams integer check (max_active_teams > 0),
  max_billable_people integer check (max_billable_people > 0),
  quote_required boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (pricebook_version, plan_key),
  unique (pricebook_version, display_order),
  check ((quote_required and monthly_amount_minor is null and annual_amount_minor is null
      and max_active_teams is null and max_billable_people is null)
    or (not quote_required and monthly_amount_minor is not null and annual_amount_minor is not null
      and max_active_teams is not null and max_billable_people is not null))
);

create unique index billing_pricebooks_one_published_market
  on core.billing_pricebooks (market) where state = 'published';

alter table core.billing_pricebooks enable row level security;
alter table core.billing_pricebook_plans enable row level security;

insert into core.billing_pricebooks(
  version,market,currency,state,tax_presentation,display_vat_basis_points,annual_month_equivalent
) values ('se.v1-draft','se','SEK','draft','inclusive',2500,10);

insert into core.billing_pricebook_plans(
  pricebook_version,plan_key,display_order,monthly_amount_minor,annual_amount_minor,
  max_active_teams,max_billable_people,quote_required
) values
 ('se.v1-draft','plan.free',1,0,0,1,25,false),
 ('se.v1-draft','plan.small',2,19900,199000,3,75,false),
 ('se.v1-draft','plan.medium',3,49900,499000,10,250,false),
 ('se.v1-draft','plan.large',4,99900,999000,30,750,false),
 ('se.v1-draft','plan.custom_xl',5,null,null,null,null,true);

alter table core.billing_subscriptions
  add constraint billing_subscriptions_pricebook_fk
  foreign key (pricebook_version) references core.billing_pricebooks(version);

insert into internal.migration_provenance(migration_name,source_kind)
values('20260816111700_s10a_versioned_pricebook_draft','greenfield');
