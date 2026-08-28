begin;

do $$
begin
  if has_function_privilege(
    'authenticated',
    'internal.normalize_unknown_billing_subscription_revision()',
    'execute'
  ) then
    raise exception 'normalization trigger function exposed to clients';
  end if;
end
$$;

select 's10a checkout subscription revision passed' as result;
rollback;
