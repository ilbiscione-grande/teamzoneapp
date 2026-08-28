-- Explicit sandbox-only Economy pilot for Thomas club.

do $$
declare target_subscription_id uuid; target_account_id uuid;
begin
 select s.id,a.id into target_subscription_id,target_account_id
 from core.billing_accounts a
 join core.billing_subscriptions s on s.billing_account_id=a.id
 where a.club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae'
   and a.environment='test' and s.state='active' and s.base_plan_key='plan.small';
 if target_subscription_id is null then raise no_data_found using message='sandbox_subscription_not_found'; end if;

 insert into core.billing_subscription_items(subscription_id,entitlement_key,quantity,state,starts_at)
 values(target_subscription_id,'module.economy',1,'active',now())
 on conflict(subscription_id,entitlement_key) do update set
  quantity=1,state='active',starts_at=least(core.billing_subscription_items.starts_at,excluded.starts_at),
  ends_at=null,updated_at=now(),revision=core.billing_subscription_items.revision+1;

 perform internal.recompute_club_entitlements(target_account_id);
end$$;

insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at)
select 'e423cb36-eaf3-44a5-b6d0-0406914a21ae',assignment_id,capability,'club',
 'e423cb36-eaf3-44a5-b6d0-0406914a21ae',now()
from (values
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'economy.read'),
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'economy.manage'),
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'economy.post'),
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'economy.approve'),
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'economy.reverse'),
 ('d6c33c2f-a54c-4960-a470-b7d12650b469'::uuid,'economy.read'),
 ('d6c33c2f-a54c-4960-a470-b7d12650b469'::uuid,'economy.approve')
) value(assignment_id,capability)
on conflict(assignment_id,capability,scope_type,scope_id) do update set
 ends_at=null,starts_at=least(core.capability_grants.starts_at,excluded.starts_at),
 revision=core.capability_grants.revision+1;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260817200611_s10b_economy_sandbox_pilot','greenfield');
