create function internal.require_economy_actor(target_club_id uuid,target_capability text)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,null,target_capability)
   or not internal.entitlement_allows_write(target_club_id,'module.economy') then
  raise insufficient_privilege using message='not_found';
 end if;
 return actor_id;
end$$;

create function internal.create_economy_account_for_actor(
 target_club_id uuid,target_team_id uuid,new_name text,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid; account_id uuid; prior jsonb;
begin
 actor_id:=internal.require_economy_actor(target_club_id,'economy.manage');
 select result into prior from internal.command_deduplication where actor_profile_id=actor_id
  and internal.command_deduplication.idempotency_key=create_economy_account_for_actor.idempotency_key
  and command_type='economy.account.create.v1';
 if prior is not null then return (prior->>'id')::uuid; end if;
 if target_team_id is not null and not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id) then
  raise insufficient_privilege using message='not_found'; end if;
 insert into core.economy_accounts(club_id,team_id,name) values(target_club_id,target_team_id,btrim(new_name)) returning id into account_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'economy.account.create.v1',jsonb_build_object('id',account_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id)
 values(target_club_id,actor_id,'economy.account.created.v1','economy_account',account_id);
 return account_id;
end$$;

create function internal.create_economy_entry_for_actor(
 target_club_id uuid,target_account_id uuid,new_amount_minor bigint,new_direction text,
 new_category text,new_reason text,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid; entry_id uuid; prior jsonb; risk text;
begin
 actor_id:=internal.require_economy_actor(target_club_id,'economy.post');
 select result into prior from internal.command_deduplication where actor_profile_id=actor_id
  and internal.command_deduplication.idempotency_key=create_economy_entry_for_actor.idempotency_key
  and command_type='economy.entry.create.v1';
 if prior is not null then return (prior->>'id')::uuid; end if;
 if not exists(select 1 from core.economy_accounts where id=target_account_id and club_id=target_club_id and state='active') then
  raise insufficient_privilege using message='not_found'; end if;
 if new_amount_minor<=0 or new_direction not in ('inflow','outflow') then raise check_violation using message='invalid_entry'; end if;
 risk:=case when new_amount_minor>=1000000 then 'high' else 'regular' end;
 insert into core.economy_ledger_entries(club_id,account_id,amount_minor,currency,direction,category,state,risk_level,reason,source_kind,created_by)
 values(target_club_id,target_account_id,new_amount_minor,'SEK',new_direction,new_category,'pending',risk,btrim(new_reason),'manual',actor_id)
 returning id into entry_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'economy.entry.create.v1',jsonb_build_object('id',entry_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata)
 values(target_club_id,actor_id,'economy.entry.created.v1','economy_entry',entry_id,btrim(new_reason),jsonb_build_object('risk_level',risk));
 return entry_id;
end$$;

create function internal.approve_economy_entry_for_actor(
 target_entry_id uuid,new_decision text,new_reason text,idempotency_key uuid
) returns void language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); entry core.economy_ledger_entries%rowtype;
begin
 select * into entry from core.economy_ledger_entries where id=target_entry_id;
 if entry.id is null then raise insufficient_privilege using message='not_found'; end if;
 actor_id:=internal.require_economy_actor(entry.club_id,'economy.approve');
 if exists(select 1 from internal.command_deduplication where actor_profile_id=actor_id and internal.command_deduplication.idempotency_key=approve_economy_entry_for_actor.idempotency_key and command_type='economy.entry.approve.v1') then return; end if;
 if entry.state<>'pending' or entry.risk_level<>'high' or entry.created_by=actor_id or new_decision not in ('approved','rejected') then
  raise insufficient_privilege using message='approval_denied'; end if;
 insert into core.economy_entry_approvals(club_id,entry_id,approver_profile_id,decision,reason)
 values(entry.club_id,entry.id,actor_id,new_decision,btrim(new_reason));
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'economy.entry.approve.v1',jsonb_build_object('ok',true));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata)
 values(entry.club_id,actor_id,'economy.entry.approval.v1','economy_entry',entry.id,btrim(new_reason),jsonb_build_object('decision',new_decision));
end$$;

create function internal.post_economy_entry_for_actor(target_entry_id uuid,idempotency_key uuid)
returns void language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); entry core.economy_ledger_entries%rowtype;
begin
 select * into entry from core.economy_ledger_entries where id=target_entry_id for update;
 if entry.id is null then raise insufficient_privilege using message='not_found'; end if;
 actor_id:=internal.require_economy_actor(entry.club_id,'economy.post');
 if exists(select 1 from internal.command_deduplication where actor_profile_id=actor_id and internal.command_deduplication.idempotency_key=post_economy_entry_for_actor.idempotency_key and command_type='economy.entry.post.v1') then return; end if;
 if entry.state<>'pending' then raise check_violation using message='invalid_state'; end if;
 if entry.risk_level='high' and (select count(*) from core.economy_entry_approvals where entry_id=entry.id and decision='approved')<2 then
  raise insufficient_privilege using message='approval_required'; end if;
 if exists(select 1 from core.economy_entry_approvals where entry_id=entry.id and decision='rejected') then
  raise insufficient_privilege using message='approval_rejected'; end if;
 update core.economy_ledger_entries set state='posted',posted_at=now(),revision=revision+1 where id=entry.id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'economy.entry.post.v1',jsonb_build_object('ok',true));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
 values(entry.club_id,actor_id,'economy.entry.posted.v1','economy_entry',entry.id,entry.revision+1);
end$$;

create function internal.reverse_economy_entry_for_actor(
 target_entry_id uuid,new_reason text,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); original core.economy_ledger_entries%rowtype; reversal_id uuid; prior jsonb;
begin
 select * into original from core.economy_ledger_entries where id=target_entry_id;
 if original.id is null then raise insufficient_privilege using message='not_found'; end if;
 actor_id:=internal.require_economy_actor(original.club_id,'economy.reverse');
 select result into prior from internal.command_deduplication where actor_profile_id=actor_id and internal.command_deduplication.idempotency_key=reverse_economy_entry_for_actor.idempotency_key and command_type='economy.entry.reverse.v1';
 if prior is not null then return (prior->>'id')::uuid; end if;
 if original.state<>'posted' or exists(select 1 from core.economy_ledger_entries where reversal_of=original.id) then raise check_violation using message='invalid_state'; end if;
 insert into core.economy_ledger_entries(club_id,account_id,amount_minor,currency,direction,category,state,risk_level,reversal_of,reason,source_kind,created_by)
 values(original.club_id,original.account_id,original.amount_minor,original.currency,case original.direction when 'inflow' then 'outflow' else 'inflow' end,original.category,'pending','high',original.id,btrim(new_reason),'adjustment',actor_id)
 returning id into reversal_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'economy.entry.reverse.v1',jsonb_build_object('id',reversal_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata)
 values(original.club_id,actor_id,'economy.entry.reversal.requested.v1','economy_entry',reversal_id,btrim(new_reason),jsonb_build_object('reversal_of',original.id));
 return reversal_id;
end$$;

create function internal.get_economy_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.require_economy_actor(target_club_id,'economy.read');
 return jsonb_build_object(
  'accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'team_id',a.team_id,'name',a.name,'currency',a.currency,'state',a.state) order by a.name),'[]'::jsonb) from core.economy_accounts a where a.club_id=target_club_id),
  'entries',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'account_id',e.account_id,'amount_minor',e.amount_minor,'currency',e.currency,'direction',e.direction,'category',e.category,'state',e.state,'risk_level',e.risk_level,'reversal_of',e.reversal_of,'created_at',e.created_at,'posted_at',e.posted_at) order by e.created_at desc),'[]'::jsonb) from core.economy_ledger_entries e where e.club_id=target_club_id)
 );
end$$;

create function api.create_economy_account(target_club_id uuid,target_team_id uuid,new_name text,idempotency_key uuid) returns uuid language sql security definer set search_path='' as $$select internal.create_economy_account_for_actor(target_club_id,target_team_id,new_name,idempotency_key)$$;
create function api.create_economy_entry(target_club_id uuid,target_account_id uuid,new_amount_minor bigint,new_direction text,new_category text,new_reason text,idempotency_key uuid) returns uuid language sql security definer set search_path='' as $$select internal.create_economy_entry_for_actor(target_club_id,target_account_id,new_amount_minor,new_direction,new_category,new_reason,idempotency_key)$$;
create function api.approve_economy_entry(target_entry_id uuid,new_decision text,new_reason text,idempotency_key uuid) returns void language sql security definer set search_path='' as $$select internal.approve_economy_entry_for_actor(target_entry_id,new_decision,new_reason,idempotency_key)$$;
create function api.post_economy_entry(target_entry_id uuid,idempotency_key uuid) returns void language sql security definer set search_path='' as $$select internal.post_economy_entry_for_actor(target_entry_id,idempotency_key)$$;
create function api.reverse_economy_entry(target_entry_id uuid,new_reason text,idempotency_key uuid) returns uuid language sql security definer set search_path='' as $$select internal.reverse_economy_entry_for_actor(target_entry_id,new_reason,idempotency_key)$$;
create function api.get_economy(target_club_id uuid) returns jsonb language sql stable security definer set search_path='' as $$select internal.get_economy_for_actor(target_club_id)$$;

revoke all on function internal.require_economy_actor(uuid,text),internal.create_economy_account_for_actor(uuid,uuid,text,uuid),internal.create_economy_entry_for_actor(uuid,uuid,bigint,text,text,text,uuid),internal.approve_economy_entry_for_actor(uuid,text,text,uuid),internal.post_economy_entry_for_actor(uuid,uuid),internal.reverse_economy_entry_for_actor(uuid,text,uuid),internal.get_economy_for_actor(uuid) from public,anon,authenticated;
revoke all on function api.create_economy_account(uuid,uuid,text,uuid),api.create_economy_entry(uuid,uuid,bigint,text,text,text,uuid),api.approve_economy_entry(uuid,text,text,uuid),api.post_economy_entry(uuid,uuid),api.reverse_economy_entry(uuid,text,uuid),api.get_economy(uuid) from public,anon;
grant execute on function api.create_economy_account(uuid,uuid,text,uuid),api.create_economy_entry(uuid,uuid,bigint,text,text,text,uuid),api.approve_economy_entry(uuid,text,text,uuid),api.post_economy_entry(uuid,uuid),api.reverse_economy_entry(uuid,text,uuid),api.get_economy(uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind) values('20260817155109_s10b_economy_commands','greenfield');
