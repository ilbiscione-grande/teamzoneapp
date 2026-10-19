-- UX review 2026-10-19: a link to the club's public page under "Mer" and
-- "Gå till" in the app (members get the slug when the club has published
-- its page), and a player's guardians on the player's page.

create or replace function internal.get_club_public_page_for_actor(target_club_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select settings.slug
  from core.club_publication_settings settings
  join core.clubs club on club.id = settings.club_id and club.status = 'active'
  where settings.club_id = target_club_id and settings.mode = 'published' and settings.slug is not null
    and exists (select 1 from core.person_account_links link
      where link.club_id = target_club_id and link.profile_id = auth.uid() and link.state = 'active')
$$;

create or replace function api.get_club_public_page(target_club_id uuid)
returns text language sql security invoker set search_path = '' as
$$select internal.get_club_public_page_for_actor(target_club_id)$$;

-- UX: a player's guardians on the player's page for those who see the
-- team's roster, with contact as get_person_contact allows, and the
-- accounts a message reaches (the player's and the guardians').
create or replace function internal.get_person_guardians_for_actor(target_club_id uuid, target_team_id uuid,
  target_person_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or target_team_id is null
    or not (internal.actor_has_capability(target_club_id, target_team_id, 'team.roster.view')
      or internal.actor_has_capability(target_club_id, target_team_id, 'team.roster.manage')
      or internal.actor_manages_club(target_club_id))
    or not exists (select 1 from core.team_assignments home where home.team_id = target_team_id
      and home.club_person_id = target_person_id and home.state = 'active'
      union all select 1 from core.assignments assignment where assignment.team_id = target_team_id
      and assignment.club_person_id = target_person_id and assignment.state = 'active') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object(
    'guardians', coalesce((select jsonb_agg(jsonb_build_object('person_id', guardian.id,
        'name', guardian.display_name,
        'has_account', link.profile_id is not null,
        'contact_email', contact->>'contact_email', 'phone', contact->>'phone',
        'can_see_contact', coalesce((contact->>'can_see_contact')::boolean, false))
        order by guardian.display_name)
      from core.guardian_relations relation
      join core.club_people guardian on guardian.id = relation.guardian_person_id and guardian.status = 'active'
      left join core.person_account_links link on link.club_person_id = guardian.id and link.state = 'active'
      cross join lateral (select internal.get_person_contact_for_actor(target_club_id, target_team_id, guardian.id)
        as contact) visible
      where relation.club_id = target_club_id and relation.child_person_id = target_person_id
        and relation.state = 'active' and relation.starts_at <= now()
        and (relation.ends_at is null or relation.ends_at > now())), '[]'::jsonb),
    'message_profile_ids', coalesce((select jsonb_agg(distinct link.profile_id)
      from core.person_account_links link
      where link.club_id = target_club_id and link.state = 'active' and link.profile_id <> auth.uid()
        and (link.club_person_id = target_person_id or link.club_person_id in (
          select relation.guardian_person_id from core.guardian_relations relation
          where relation.club_id = target_club_id and relation.child_person_id = target_person_id
            and relation.state = 'active' and relation.starts_at <= now()
            and (relation.ends_at is null or relation.ends_at > now())))), '[]'::jsonb));
end;$$;

create or replace function api.get_person_guardians(target_club_id uuid, target_team_id uuid, target_person_id uuid)
returns jsonb language sql security invoker set search_path = '' as
$$select internal.get_person_guardians_for_actor(target_club_id, target_team_id, target_person_id)$$;

revoke all on function internal.get_club_public_page_for_actor(uuid), api.get_club_public_page(uuid),
  internal.get_person_guardians_for_actor(uuid, uuid, uuid), api.get_person_guardians(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function internal.get_club_public_page_for_actor(uuid), api.get_club_public_page(uuid),
  internal.get_person_guardians_for_actor(uuid, uuid, uuid), api.get_person_guardians(uuid, uuid, uuid)
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261111090000_ux_public_page_and_guardians', 'greenfield', 'UX: public page link and guardians on the player page'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261111090000_ux_public_page_and_guardians');
notify pgrst, 'reload schema';
