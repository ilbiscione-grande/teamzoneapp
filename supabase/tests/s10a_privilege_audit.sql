do $$
declare table_name text;
begin
  foreach table_name in array array[
    'billing_accounts','billing_subscriptions','billing_subscription_items','club_entitlements'
  ] loop
    if not coalesce((select relrowsecurity from pg_class relation
      join pg_namespace namespace on namespace.oid=relation.relnamespace
      where namespace.nspname='core' and relation.relname=table_name),false) then
      raise exception 'RLS missing for core.%', table_name;
    end if;
    if has_table_privilege('anon',format('core.%I',table_name),'select')
       or has_table_privilege('authenticated',format('core.%I',table_name),'select,insert,update,delete') then
      raise exception 'direct client table privilege found for core.%', table_name;
    end if;
  end loop;
  if has_table_privilege('anon','internal.billing_provider_events','select')
     or has_table_privilege('authenticated','internal.billing_provider_events','select,insert,update,delete') then
    raise exception 'provider inbox exposed to client role';
  end if;
  if has_function_privilege('public','internal.recompute_club_entitlements(uuid)','execute')
     or has_function_privilege('anon','internal.recompute_club_entitlements(uuid)','execute')
     or has_function_privilege('authenticated','internal.recompute_club_entitlements(uuid)','execute') then
    raise exception 'server-only recompute function exposed';
  end if;
  if not has_function_privilege('authenticated','api.get_club_entitlements(uuid)','execute')
     or has_function_privilege('anon','api.get_club_entitlements(uuid)','execute') then
    raise exception 'entitlement query ACL mismatch';
  end if;
end $$;

select 's10a privilege audit passed' as result;
