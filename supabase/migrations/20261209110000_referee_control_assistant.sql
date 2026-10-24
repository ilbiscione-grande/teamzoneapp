-- The assistant's "Kontrollfråga om domaren" (2026-10-24): the control
-- questions waiting for an answer from you, one row per match, for the
-- matches you manage, the same rule as the question on the match's Info tab
-- (internal.get_event_referees_for_actor). The questions still reach the
-- leaders as notifications in the inbox as before.
create or replace function internal.list_my_referee_control_questions_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'event_id', match.event_id, 'club_id', match.club_id, 'team_id', match.team_id,
      'title', match.title, 'starts_at', match.starts_at, 'count', match.count, 'name', match.name
    ) order by match.starts_at desc)
    from (
      select report.event_id, event_row.club_id, event_row.owning_team_id team_id, event_row.title, event_row.starts_at,
        count(*) count, min(coalesce(person.display_name, 'Borttagen person')) name
      from core.club_referee_reports report
      join core.events event_row on event_row.id = report.event_id
      left join core.club_people person on person.id = report.referee_person_id
      where report.control_state = 'asked'
        and exists (select 1 from core.person_account_links link
          where link.profile_id = auth.uid() and link.club_id = event_row.club_id and link.state = 'active')
        and internal.actor_can_manage_event(report.event_id)
      group by report.event_id, event_row.club_id, event_row.owning_team_id, event_row.title, event_row.starts_at
    ) match
  ), '[]'::jsonb);
end;
$$;

create or replace function api.list_my_referee_control_questions() returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_my_referee_control_questions_for_actor() $$;

revoke all on function internal.list_my_referee_control_questions_for_actor(), api.list_my_referee_control_questions()
  from public, anon, authenticated;
grant execute on function internal.list_my_referee_control_questions_for_actor(), api.list_my_referee_control_questions()
  to authenticated;
notify pgrst, 'reload schema';
