-- Supportens logg (adminsidan för TeamZones support, del 5, 2026-11-14).
--
-- What support has done, newest first, from audit.command_events: support
-- administrators added and removed, club admins appointed and removed, board
-- changes applied or cancelled, verification and protected-name decisions,
-- answers in support cases and match-pool reports. Each entry says who in
-- support did it, when, in which club, to whom and with what reason.
--
-- * Entries written by the people asking for help (a protected-name request,
--   their own messages) are left out: they are not support's actions.
-- * Opening a club (support.club_viewed) is shown only when asked for.
-- * Support administrators only; others get insufficient_privilege
--   (not_found). Metadata is passed on only for a few known keys, never ids.

create index if not exists command_events_support_idx
  on audit.command_events (occurred_at desc, id desc)
  where command_type like 'support.%';

create or replace function internal.list_support_actions_for_actor(
  area text, include_views boolean, before timestamptz, page_size integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  size integer := greatest(1, least(coalesce(page_size, 50), 100));
  rows jsonb;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if area is not null and area not in ('clubs', 'admins', 'cases') then
    raise invalid_parameter_value using message = 'invalid_area';
  end if;

  select coalesce(jsonb_agg(entry order by occurred_at desc, id desc), '[]'::jsonb)
    into rows
  from (
    select event.id, event.occurred_at, jsonb_build_object(
      'id', event.id,
      'occurred_at', event.occurred_at,
      'type', event.command_type,
      'actor', actor.display_name,
      'actor_is_me', event.actor_profile_id = auth.uid(),
      'club_id', event.club_id,
      'club', club.name,
      'target', case event.aggregate_type
        when 'club_person' then (select person.display_name from core.club_people person
          where person.id = event.aggregate_id)
        when 'support_admin' then (select profile.display_name from core.profiles profile
          where profile.id = event.aggregate_id)
        when 'board_mandate_change' then (select person.display_name from core.board_mandate_changes change
          left join core.assignments assignment on assignment.id = change.target_assignment_id
          left join core.club_people person on person.id = assignment.club_person_id
          where change.id = event.aggregate_id)
        else null end,
      'reason', event.reason,
      'details', jsonb_strip_nulls(jsonb_build_object(
        'left_without_admin', event.metadata->'left_without_admin',
        'created_club_role', event.metadata->'created_club_role',
        'action', event.metadata->'action',
        'office', event.metadata->'office',
        'approvals', event.metadata->'approvals',
        'again', event.metadata->'again',
        'self', event.metadata->'self',
        'decision', event.metadata->'decision',
        'status', event.metadata->'status',
        'resolution_kind', event.metadata->'resolution_kind',
        'hide', event.metadata->'hide'))) entry
    from audit.command_events event
    left join core.profiles actor on actor.id = event.actor_profile_id
    left join core.clubs club on club.id = event.club_id
    where event.command_type like 'support.%'
      and event.command_type <> 'support.protected_name.request.v1'
      and not (event.command_type like 'support.protected_name.message.%'
        and coalesce(event.metadata->>'sender_kind', '') <> 'support')
      and (coalesce(include_views, false) or event.command_type <> 'support.club_viewed')
      and (before is null or event.occurred_at < before)
      and (area is null
        or (area = 'admins' and event.aggregate_type = 'support_admin')
        or (area = 'clubs' and event.aggregate_type in ('club', 'club_person', 'board_mandate_change'))
        or (area = 'cases' and event.aggregate_type not in ('support_admin', 'club', 'club_person',
          'board_mandate_change')))
    order by event.occurred_at desc, event.id desc
    limit size + 1
  ) page;

  return jsonb_build_object(
    'entries', (select coalesce(jsonb_agg(value order by ordinality), '[]'::jsonb)
      from jsonb_array_elements(rows) with ordinality where ordinality <= size),
    'more', jsonb_array_length(rows) > size);
end
$$;

create or replace function api.list_support_actions(
  area text default null, include_views boolean default false,
  before timestamptz default null, page_size integer default 50)
returns jsonb language sql stable security invoker set search_path = ''
as $$select internal.list_support_actions_for_actor(area, include_views, before, page_size)$$;

revoke all on function
  internal.list_support_actions_for_actor(text, boolean, timestamptz, integer),
  api.list_support_actions(text, boolean, timestamptz, integer)
from public, anon, authenticated;

grant execute on function
  internal.list_support_actions_for_actor(text, boolean, timestamptz, integer),
  api.list_support_actions(text, boolean, timestamptz, integer)
to authenticated;

notify pgrst, 'reload schema';
