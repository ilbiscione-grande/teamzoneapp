begin;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'economy_accounts','economy_ledger_entries','economy_entry_approvals',
    'fee_obligations','sponsor_pledges','board_mandates'
  ] loop
    if has_table_privilege('anon',format('core.%I',table_name),'select')
       or has_table_privilege('authenticated',format('core.%I',table_name),'select,insert,update,delete') then
      raise exception 'direct client privilege found for core.%',table_name;
    end if;
  end loop;
  if has_function_privilege('authenticated','internal.protect_posted_economy_entry()','execute') then
    raise exception 'ledger protection trigger exposed';
  end if;
end
$$;

do $$
declare account_id uuid:=gen_random_uuid(); entry_id uuid:=gen_random_uuid();
begin
  insert into core.economy_accounts(id,club_id,name)
  values(account_id,'e423cb36-eaf3-44a5-b6d0-0406914a21ae','S10B rollback validation');
  insert into core.economy_ledger_entries(
    id,club_id,account_id,amount_minor,currency,direction,category,state,
    risk_level,reason,source_kind,created_by
  ) values(
    entry_id,'e423cb36-eaf3-44a5-b6d0-0406914a21ae',account_id,10000,'SEK',
    'inflow','test_entry','pending','regular','Rollback validation only','manual',
    '6379829a-1258-4893-aae7-d063979ef118'
  );
  update core.economy_ledger_entries set state='posted',posted_at=now() where id=entry_id;
  begin
    update core.economy_ledger_entries set category='mutated' where id=entry_id;
    raise exception 'posted entry was mutable';
  exception when check_violation then null;
  end;
end
$$;

select 's10b economy board foundation passed' as result;
rollback;
