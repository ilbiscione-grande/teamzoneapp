-- The member register shows and sets the e-mail address fee reminders go
-- to (2026-11-11): step 5 sends e-mail to those without a TeamZone account,
-- but the club could not see or enter the address. Only for someone without
-- an account (an account holder keeps their own contact and privacy rules)
-- and never for a protected person (safeguarding_required). Set by the club
-- admin; audited without the address.

-- As in 20270215090000, with the e-mail address.
create or replace function internal.get_club_member_register_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object('people', coalesce((select jsonb_agg(entry order by entry->>'name', entry->>'person_id') from (
    select jsonb_build_object(
      'person_id', person.id,
      'name', person.display_name,
      'birth_year', person.birth_year,
      'has_account', exists (select 1 from core.person_account_links link
        where link.club_person_id = person.id and link.club_id = target_club_id and link.state = 'active'),
      'club_role', exists (select 1 from core.assignments a
        where a.club_id = target_club_id and a.club_person_id = person.id and a.team_id is null
          and a.role_package = 'club_functionary' and a.state = 'active'
          and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())),
      'teams', coalesce((select jsonb_agg(distinct jsonb_build_object('team_id', team.id, 'name', team.name, 'role', role_row.role))
        from (
          select ta.team_id, 'player'::text as role from core.team_assignments ta
          where ta.club_id = target_club_id and ta.club_person_id = person.id and ta.state = 'active'
          union
          select a.team_id, a.role_package from core.assignments a
          where a.club_id = target_club_id and a.club_person_id = person.id and a.team_id is not null
            and a.state = 'active' and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())
        ) role_row
        join core.teams team on team.id = role_row.team_id and team.club_id = target_club_id), '[]'::jsonb),
      'guardians', coalesce((select jsonb_agg(distinct guardian.display_name)
        from core.guardian_relations relation
        join core.club_people guardian on guardian.id = relation.guardian_person_id and guardian.status = 'active'
        where relation.club_id = target_club_id and relation.child_person_id = person.id and relation.state = 'active'
          and (relation.ends_at is null or relation.ends_at > now())), '[]'::jsonb),
      'children', coalesce((select jsonb_agg(distinct child.display_name)
        from core.guardian_relations relation
        join core.club_people child on child.id = relation.child_person_id and child.status = 'active'
        where relation.club_id = target_club_id and relation.guardian_person_id = person.id and relation.state = 'active'
          and (relation.ends_at is null or relation.ends_at > now())), '[]'::jsonb),
      'is_member', coalesce(membership.is_member, internal.club_person_is_default_member(target_club_id, person.id)),
      'member_set', membership.club_person_id is not null,
      'category', coalesce(membership.category, internal.club_member_default_category(person.birth_year)),
      'category_set', membership.category is not null,
      'revision', coalesce(membership.revision, 0),
      -- The address fee reminders go to, for someone without an account; not
      -- for a protected person.
      'email', case when not person_has_account and not coalesce(person.safeguarding_required, false)
        then person.contact_email end,
      'email_editable', not person_has_account and not coalesce(person.safeguarding_required, false)) as entry
    from core.club_people person
    cross join lateral (select exists (select 1 from core.person_account_links link
      where link.club_person_id = person.id and link.club_id = target_club_id and link.state = 'active') as person_has_account) account
    left join core.club_memberships membership on membership.club_person_id = person.id
    where person.club_id = target_club_id and person.status = 'active') register_rows), '[]'::jsonb));
end;
$$;


create or replace function internal.set_club_person_email_for_actor(target_club_id uuid, target_person_id uuid,
  new_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); contact jsonb; person core.club_people%rowtype;
begin
  if actor_id is null or not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into person from core.club_people where id = target_person_id and club_id = target_club_id and status = 'active'
  for update;
  if person.id is null or coalesce(person.safeguarding_required, false)
     or exists (select 1 from core.person_account_links link where link.club_person_id = person.id
       and link.club_id = target_club_id and link.state = 'active') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  contact := internal.normalized_contact(new_email, person.phone);
  update core.club_people set contact_email = contact->>'email', revision = revision + 1 where id = person.id;
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id,
    aggregate_revision, metadata)
  values (target_club_id, actor_id, 'club.person.contact.update.v1', 'club_person', person.id, person.revision + 1,
    jsonb_build_object('has_email', contact->>'email' is not null, 'source', 'member_register'));
  return jsonb_build_object('email', contact->>'email');
end;
$$;

create or replace function api.set_club_person_email(target_club_id uuid, target_person_id uuid, new_email text)
returns jsonb language sql security invoker set search_path = '' as
$$ select internal.set_club_person_email_for_actor(target_club_id, target_person_id, new_email) $$;

revoke all on function internal.set_club_person_email_for_actor(uuid, uuid, text), api.set_club_person_email(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function internal.set_club_person_email_for_actor(uuid, uuid, text), api.set_club_person_email(uuid, uuid, text)
  to authenticated;
notify pgrst, 'reload schema';
