begin;

do $$
begin
  if not has_function_privilege(
    'authenticated', 'api.get_published_pricebook(uuid)', 'execute'
  ) then
    raise exception 'authenticated pricebook query privilege missing';
  end if;
  if has_function_privilege('anon', 'api.get_published_pricebook(uuid)', 'execute')
     or has_function_privilege(
       'authenticated', 'internal.get_published_pricebook_for_actor(uuid)', 'execute'
     ) then
    raise exception 'pricebook query privilege boundary opened';
  end if;
end
$$;

select 's10a pricebook query passed' as result;
rollback;
