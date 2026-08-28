begin;
set local role postgres;

insert into auth.users(id,raw_user_meta_data) values
 ('a1000000-0000-0000-0000-000000000001','{"display_name":"S10 Admin"}'),
 ('a1000000-0000-0000-0000-000000000002','{"display_name":"S10 Outsider"}');
insert into core.clubs(id,name,slug) values
 ('a1100000-0000-0000-0000-000000000001','S10 Klubb','s10-klubb');
insert into core.club_people(id,club_id,display_name) values
 ('a1200000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','S10 Admin');
insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at) values
 ('a1100000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001','active',now());
insert into core.assignments(club_id,club_person_id,role_package,state,starts_at) values
 ('a1100000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001',
  'club_functionary','active',now()-interval '1 day');

insert into core.billing_accounts(id,club_id,environment,state) values
 ('a1300000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','production','active');
insert into core.billing_subscriptions(id,billing_account_id,pricebook_version,base_plan_key,state,
 current_period_starts_at,current_period_ends_at) values
 ('a1400000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000001',
  'se.v1-draft','plan.free','active',now()-interval '1 day',now()+interval '30 days');
insert into core.billing_subscription_items(subscription_id,entitlement_key,starts_at) values
 ('a1400000-0000-0000-0000-000000000001','module.match_workspace',now()-interval '1 day');
select internal.recompute_club_entitlements('a1300000-0000-0000-0000-000000000001');

do $$ begin
 if not internal.entitlement_allows_write('a1100000-0000-0000-0000-000000000001','module.match_workspace')
 then raise exception 'active entitlement did not allow write'; end if;
end $$;

update core.billing_subscriptions set state='grace',grace_ends_at=now()+interval '14 days',revision=2
 where id='a1400000-0000-0000-0000-000000000001';
select internal.recompute_club_entitlements('a1300000-0000-0000-0000-000000000001');
do $$ begin
 if not internal.entitlement_allows_write('a1100000-0000-0000-0000-000000000001','module.match_workspace')
 then raise exception 'grace entitlement did not allow write'; end if;
end $$;

update core.billing_subscriptions set grace_ends_at=now()-interval '1 second',revision=3
 where id='a1400000-0000-0000-0000-000000000001';
select internal.recompute_club_entitlements('a1300000-0000-0000-0000-000000000001');
do $$ begin
 if internal.entitlement_allows_write('a1100000-0000-0000-0000-000000000001','module.match_workspace')
 then raise exception 'expired grace allowed write'; end if;
 if (select access_mode from core.club_entitlements where entitlement_key='module.match_workspace') <> 'read_only'
 then raise exception 'expired grace was not read-only'; end if;
end $$;

update core.billing_subscriptions set state='unknown',grace_ends_at=null,revision=4
 where id='a1400000-0000-0000-0000-000000000001';
select internal.recompute_club_entitlements('a1300000-0000-0000-0000-000000000001');
do $$ begin
 if exists(select 1 from core.club_entitlements where club_id='a1100000-0000-0000-0000-000000000001')
 then raise exception 'unknown state retained entitlements'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
select api.get_club_entitlements('a1100000-0000-0000-0000-000000000001');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
do $$ begin
 begin
  perform api.get_club_entitlements('a1100000-0000-0000-0000-000000000001');
  raise exception 'outsider read entitlements';
 exception when insufficient_privilege then null; end;
end $$;

rollback;
