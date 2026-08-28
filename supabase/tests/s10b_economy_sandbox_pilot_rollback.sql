\set ON_ERROR_STOP on
begin;
\ir ../migrations/20260817200611_s10b_economy_sandbox_pilot.sql

do $$
begin
 if not exists(select 1 from core.club_entitlements where club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae' and entitlement_key='module.economy' and access_mode='write') then raise exception 'economy entitlement missing'; end if;
 if (select count(*) from core.capability_grants where club_id='e423cb36-eaf3-44a5-b6d0-0406914a21ae' and capability like 'economy.%' and ends_at is null)<>7 then raise exception 'economy pilot grants mismatch'; end if;
end$$;

rollback;
