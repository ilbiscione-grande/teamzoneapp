-- TEAM-12: the team picker names your title (e.g. Huvudtränare) rather than
-- only the role package. One call returns your own titles for every team
-- where you hold an active leader role; titles only exist with that role.

create or replace function internal.get_my_team_titles_for_actor()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'club_id',details.club_id,'team_id',details.team_id,
      'titles',to_jsonb(details.functions),
      'custom_titles',to_jsonb(coalesce(details.custom_titles,'{}'::text[])))
      order by details.team_id)
    from core.person_account_links link
    join core.team_person_details details on details.club_id=link.club_id
      and details.club_person_id=link.club_person_id
    where link.profile_id=auth.uid() and link.state='active'
      and (cardinality(details.functions)>0 or cardinality(coalesce(details.custom_titles,'{}'::text[]))>0)
      and exists(select 1 from core.assignments assignment
        where assignment.club_id=details.club_id and assignment.team_id=details.team_id
          and assignment.club_person_id=details.club_person_id and assignment.role_package='leader'
          and assignment.state='active' and assignment.starts_at<=now()
          and (assignment.ends_at is null or assignment.ends_at>now()))
  ),'[]'::jsonb);
end$$;

create or replace function api.get_my_team_titles()
returns jsonb language sql stable security invoker set search_path='' as $$
  select internal.get_my_team_titles_for_actor();
$$;

revoke all on function internal.get_my_team_titles_for_actor(),api.get_my_team_titles()
  from public,anon,authenticated;
grant execute on function internal.get_my_team_titles_for_actor(),api.get_my_team_titles()
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260929190000_my_team_titles','greenfield','TEAM-12 own titles per team for the team picker');
notify pgrst,'reload schema';
