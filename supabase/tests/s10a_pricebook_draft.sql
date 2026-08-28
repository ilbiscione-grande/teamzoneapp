begin;
set local role postgres;

do $$ begin
 if (select state from core.billing_pricebooks where version='se.v1-draft') <> 'draft'
 then raise exception 'pricebook is not draft'; end if;
 if exists(select 1 from core.billing_pricebooks where state='published')
 then raise exception 'a pricebook is unexpectedly published'; end if;
 if (select count(*) from core.billing_pricebook_plans where pricebook_version='se.v1-draft') <> 5
 then raise exception 'pricebook plan count mismatch'; end if;
 if exists(select 1 from core.billing_pricebook_plans plan
   where plan.pricebook_version='se.v1-draft' and not plan.quote_required
     and plan.annual_amount_minor <> plan.monthly_amount_minor * 10)
 then raise exception 'annual price mismatch'; end if;
 if has_table_privilege('anon','core.billing_pricebooks','select')
    or has_table_privilege('authenticated','core.billing_pricebooks','select')
    or has_table_privilege('anon','core.billing_pricebook_plans','select')
    or has_table_privilege('authenticated','core.billing_pricebook_plans','select')
 then raise exception 'draft pricebook exposed directly'; end if;
end $$;

rollback;
