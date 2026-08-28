-- Explicit Stripe sandbox pilot for Thomas klubb only.

insert into core.billing_pricebooks(
 version,market,currency,state,tax_presentation,display_vat_basis_points,
 annual_month_equivalent,published_at
)
select 'se.v1',market,currency,'published',tax_presentation,
 display_vat_basis_points,annual_month_equivalent,now()
from core.billing_pricebooks where version='se.v1-draft';

insert into core.billing_pricebook_plans(
 pricebook_version,plan_key,display_order,monthly_amount_minor,annual_amount_minor,
 max_active_teams,max_billable_people,quote_required
)
select 'se.v1',plan_key,display_order,monthly_amount_minor,annual_amount_minor,
 max_active_teams,max_billable_people,quote_required
from core.billing_pricebook_plans where pricebook_version='se.v1-draft';

update internal.billing_provider_prices set pricebook_version='se.v1'
where pricebook_version='se.v1-draft' and provider='stripe';

insert into core.capability_grants(
 club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by
)
select assignment.club_id,assignment.id,'club.billing.manage','club',assignment.club_id,now(),
 '6379829a-1258-4893-aae7-d063979ef118'::uuid
from core.assignments assignment
where assignment.id='b7089d1b-2fa4-4efc-bcda-f779bfeea868'
 and assignment.club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae'
 and assignment.club_person_id in (
  select link.club_person_id from core.person_account_links link
  where link.profile_id='6379829a-1258-4893-aae7-d063979ef118' and link.state='active'
 );

do $$ begin
 if not exists(select 1 from core.capability_grants
  where assignment_id='b7089d1b-2fa4-4efc-bcda-f779bfeea868'
   and capability='club.billing.manage'
   and scope_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae') then
  raise exception 'sandbox pilot capability target mismatch';
 end if;
 if (select count(*) from internal.billing_provider_prices where pricebook_version='se.v1' and active)<>6 then
  raise exception 'sandbox price mapping count mismatch';
 end if;
end $$;

insert into audit.command_events(
 club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata
) values(
 'e423cb36-eaf3-44a5-b6d0-0406914a21ae','6379829a-1258-4893-aae7-d063979ef118',
 'billing.sandbox_pilot.activated.v1','club','e423cb36-eaf3-44a5-b6d0-0406914a21ae',
 'Explicit S10A Stripe sandbox pilot approval',jsonb_build_object('pricebook_version','se.v1')
);

insert into internal.migration_provenance(migration_name,source_kind)
values('20260816112000_s10a_stripe_sandbox_pilot_activation','greenfield');
