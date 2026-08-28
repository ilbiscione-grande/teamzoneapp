-- Capability-gated, provider-neutral projection for the web billing surface.

create function internal.get_published_pricebook_for_actor(target_club_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  pricebook core.billing_pricebooks%rowtype;
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if not internal.actor_has_capability(target_club_id, null, 'club.billing.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select * into pricebook
  from core.billing_pricebooks
  where market = 'se' and state = 'published';

  if pricebook.version is null then
    raise no_data_found using message = 'pricebook_not_found';
  end if;

  return jsonb_build_object(
    'version', pricebook.version,
    'state', pricebook.state,
    'currency', pricebook.currency,
    'tax_presentation', pricebook.tax_presentation,
    'display_vat_basis_points', pricebook.display_vat_basis_points,
    'plans', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', plan.plan_key,
        'monthly_amount_minor', plan.monthly_amount_minor,
        'annual_amount_minor', plan.annual_amount_minor,
        'max_active_teams', plan.max_active_teams,
        'max_billable_people', plan.max_billable_people,
        'quote_required', plan.quote_required
      ) order by plan.display_order), '[]'::jsonb)
      from core.billing_pricebook_plans plan
      where plan.pricebook_version = pricebook.version
    )
  );
end
$$;

create function api.get_published_pricebook(target_club_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select internal.get_published_pricebook_for_actor(target_club_id)
$$;

revoke all on function internal.get_published_pricebook_for_actor(uuid) from public, anon, authenticated;
revoke all on function api.get_published_pricebook(uuid) from public, anon;
grant execute on function api.get_published_pricebook(uuid) to authenticated;

insert into internal.migration_provenance(migration_name, source_kind)
values ('20260816112100_s10a_pricebook_query', 'greenfield');
