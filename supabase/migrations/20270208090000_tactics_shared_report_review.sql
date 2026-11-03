-- Tacticsboard's library, reviewing reports (plan item 16): support sees
-- a reported item whole, its boards and texts, also when three reports
-- have hidden it, before deciding with decide_tactics_shared_reports
-- (20261214090000). Reporting and the list are as they were.

create or replace function internal.get_tactics_shared_report_item_for_admin(target_shared_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare item core.tactics_shared_items;
begin
  if not internal.actor_is_support_admin() then raise insufficient_privilege using message = 'not_found'; end if;
  select * into item from core.tactics_shared_items where id = target_shared_id;
  if item.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.tactics_shared_summary(item) || jsonb_build_object(
    'document', item.document,
    'hidden_by_support', item.hidden_by_support,
    'reports', coalesce((select jsonb_agg(jsonb_build_object('reason', report.reason, 'created_at', report.created_at,
        'resolution', report.resolution, 'resolved_at', report.resolved_at) order by report.created_at)
      from core.tactics_shared_reports report where report.shared_item_id = item.id), '[]'::jsonb));
end;
$$;

create or replace function api.get_tactics_shared_report_item(target_shared_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_tactics_shared_report_item_for_admin(target_shared_id) $$;

revoke all on function internal.get_tactics_shared_report_item_for_admin(uuid), api.get_tactics_shared_report_item(uuid)
from public, anon, authenticated;
grant execute on function internal.get_tactics_shared_report_item_for_admin(uuid), api.get_tactics_shared_report_item(uuid)
to authenticated;
notify pgrst, 'reload schema';
