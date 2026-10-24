-- The assistant's "Ansökningar om lagsida": pending team page requests in each
-- club where you hold publication.manage, whether or not you have a context
-- on the club level there (the decider is often a leader in one of its teams).
create or replace function internal.list_my_team_page_requests_for_actor() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('club_id', club.club_id, 'pending', club.pending) order by club.club_id)
    from (
      select link.club_id, (select count(*) from core.team_publication_requests request
        where request.club_id = link.club_id and request.status = 'pending') as pending
      from (select distinct club_id from core.person_account_links
        where profile_id = auth.uid() and state = 'active') link
      where internal.actor_has_capability(link.club_id, null, 'publication.manage')
    ) club
    where club.pending > 0
  ), '[]'::jsonb);
end;
$$;

create or replace function api.list_my_team_page_requests() returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_my_team_page_requests_for_actor() $$;

revoke all on function internal.list_my_team_page_requests_for_actor(), api.list_my_team_page_requests()
  from public, anon, authenticated;
grant execute on function internal.list_my_team_page_requests_for_actor(), api.list_my_team_page_requests()
  to authenticated;
notify pgrst, 'reload schema';
