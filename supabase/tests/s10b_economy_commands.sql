\set ON_ERROR_STOP on
begin;
set role postgres;

insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at)
select 'e423cb36-eaf3-44a5-b6d0-0406914a21ae',assignment_id,capability,'club','e423cb36-eaf3-44a5-b6d0-0406914a21ae',now()
from (values
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'economy.manage'),
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'economy.post'),
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'economy.read'),
 ('b7089d1b-2fa4-4efc-bcda-f779bfeea868'::uuid,'economy.approve'),
 ('d6c33c2f-a54c-4960-a470-b7d12650b469'::uuid,'economy.approve')
) value(assignment_id,capability)
on conflict do nothing;

set local role authenticated;
set local request.jwt.claim.sub='6379829a-1258-4893-aae7-d063979ef118';
do $$begin
 perform api.create_economy_account('e423cb36-eaf3-44a5-b6d0-0406914a21ae',null,'Denied',gen_random_uuid());
 raise exception 'economy write allowed without entitlement';
exception when insufficient_privilege then null; end$$;

set local role postgres;
insert into core.club_entitlements(club_id,billing_account_id,entitlement_key,access_mode,quantity,source_subscription_revision,effective_at)
select a.club_id,a.id,'module.economy','write',1,s.revision,now()
from core.billing_accounts a join core.billing_subscriptions s on s.billing_account_id=a.id
where a.club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae' and a.environment='test'
on conflict(club_id,entitlement_key) do update set access_mode='write';

set local role authenticated;
set local request.jwt.claim.sub='6379829a-1258-4893-aae7-d063979ef118';
do $$
declare account_id uuid; duplicate_id uuid; regular_id uuid; high_id uuid;
begin
 account_id:=api.create_economy_account('e423cb36-eaf3-44a5-b6d0-0406914a21ae',null,'Rollback API test','10000000-0000-4000-8000-000000000001');
 duplicate_id:=api.create_economy_account('e423cb36-eaf3-44a5-b6d0-0406914a21ae',null,'Ignored duplicate','10000000-0000-4000-8000-000000000001');
 if account_id<>duplicate_id then raise exception 'account idempotency failed'; end if;
 regular_id:=api.create_economy_entry('e423cb36-eaf3-44a5-b6d0-0406914a21ae',account_id,999999,'inflow','member_fee','Regular rollback entry','10000000-0000-4000-8000-000000000002');
 perform api.post_economy_entry(regular_id,'10000000-0000-4000-8000-000000000003');
 high_id:=api.create_economy_entry('e423cb36-eaf3-44a5-b6d0-0406914a21ae',account_id,1000000,'outflow','equipment','High rollback entry','10000000-0000-4000-8000-000000000004');
 begin perform api.post_economy_entry(high_id,'10000000-0000-4000-8000-000000000005'); raise exception 'high entry posted without approvals'; exception when insufficient_privilege then null; end;
 begin perform api.approve_economy_entry(high_id,'approved','Self approval denied','10000000-0000-4000-8000-000000000006'); raise exception 'initiator self-approved'; exception when insufficient_privilege then null; end;
 perform api.get_economy('e423cb36-eaf3-44a5-b6d0-0406914a21ae');
 perform set_config('s10b.high_id',high_id::text,true);
end$$;

set local request.jwt.claim.sub='1c59f7e1-64be-4c20-aecf-430edbd80e99';
select api.approve_economy_entry(current_setting('s10b.high_id')::uuid,'approved','First independent approval','10000000-0000-4000-8000-000000000007');

set local request.jwt.claim.sub='6379829a-1258-4893-aae7-d063979ef118';
do $$begin
 perform api.post_economy_entry(current_setting('s10b.high_id')::uuid,'10000000-0000-4000-8000-000000000008');
 raise exception 'high entry posted with only one approval';
exception when insufficient_privilege then null; end$$;

set local role postgres;
select 's10b economy commands passed' as result;
rollback;
