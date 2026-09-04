-- REL-02 hardening: a club_functionary role does not imply access to the
-- complete club recipient directory. Broad club messaging is an explicit
-- capability and the same relationship predicate remains reusable by every
-- message mutation introduced by MSG-02.

create or replace function internal.messaging_relationship_allowed(
  actor_profile_id uuid,
  target_profile_id uuid,
  target_club_id uuid,
  target_team_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select actor_profile_id is not null
    and target_profile_id is not null
    and actor_profile_id <> target_profile_id
    and exists (
      select 1
      from core.person_account_links actor_link
      join core.assignments actor_assignment
        on actor_assignment.club_id = actor_link.club_id
       and actor_assignment.club_person_id = actor_link.club_person_id
      join core.person_account_links target_link
        on target_link.profile_id = target_profile_id
       and target_link.club_id = actor_assignment.club_id
       and target_link.state = 'active'
      join core.assignments target_assignment
        on target_assignment.club_id = target_link.club_id
       and target_assignment.club_person_id = target_link.club_person_id
      where actor_link.profile_id = actor_profile_id
        and actor_link.state = 'active'
        and actor_assignment.club_id = target_club_id
        and target_assignment.club_id = target_club_id
        and (
          target_team_id is null
          or (
            actor_assignment.team_id = target_team_id
            and target_assignment.team_id = target_team_id
          )
        )
        and actor_assignment.state = 'active'
        and actor_assignment.starts_at <= now()
        and (actor_assignment.ends_at is null or actor_assignment.ends_at > now())
        and target_assignment.state = 'active'
        and target_assignment.starts_at <= now()
        and (target_assignment.ends_at is null or target_assignment.ends_at > now())
        and (
          actor_assignment.role_package = 'leader'
          or (
            actor_assignment.role_package = 'club_functionary'
            and exists (
              select 1
              from core.capability_grants grant_row
              where grant_row.assignment_id = actor_assignment.id
                and grant_row.club_id = actor_assignment.club_id
                and grant_row.capability = 'club.messaging.manage'
                and grant_row.starts_at <= now()
                and (grant_row.ends_at is null or grant_row.ends_at > now())
                and (
                  (grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id)
                  or (
                    target_team_id is not null
                    and grant_row.scope_type = 'team'
                    and grant_row.scope_id = target_team_id
                  )
                )
            )
          )
          or (
            actor_assignment.role_package = 'player'
            and target_assignment.role_package in ('leader', 'guardian')
          )
          or (
            actor_assignment.role_package = 'guardian'
            and target_assignment.role_package = 'leader'
          )
        )
    )
    and not exists (
      select 1
      from core.contact_controls block
      where block.control_type = 'block'
        and block.state = 'active'
        and (
          (block.requester_profile_id = actor_profile_id and block.target_profile_id = target_profile_id)
          or (block.target_profile_id = actor_profile_id and block.requester_profile_id = target_profile_id)
        )
    );
$$;

create or replace function internal.resolve_allowed_recipients_for_actor(
  target_context_id uuid,
  search_text text default null
)
returns table(profile_id uuid, display_name text, role_package text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_context record;
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select * into actor_context
  from internal.get_my_contexts_for_actor()
  where context_id = target_context_id;

  if actor_context.context_id is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if search_text is not null and length(search_text) > 80 then
    raise invalid_parameter_value using message = 'invalid_search';
  end if;

  return query
  select distinct link.profile_id, profile.display_name, assignment.role_package
  from core.assignments assignment
  join core.person_account_links link
    on link.club_id = assignment.club_id
   and link.club_person_id = assignment.club_person_id
   and link.state = 'active'
  join core.profiles profile on profile.id = link.profile_id
  where assignment.club_id = actor_context.club_id
    and (actor_context.team_id is null or assignment.team_id = actor_context.team_id)
    and assignment.state = 'active'
    and assignment.starts_at <= now()
    and (assignment.ends_at is null or assignment.ends_at > now())
    and internal.messaging_relationship_allowed(
      auth.uid(),
      link.profile_id,
      actor_context.club_id,
      actor_context.team_id
    )
    and (
      search_text is null
      or profile.display_name ilike
        '%' || replace(replace(left(btrim(search_text), 80), '%', '\%'), '_', '\_') || '%'
        escape '\'
    )
  order by profile.display_name
  limit 50;
end;
$$;

revoke all on function internal.messaging_relationship_allowed(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function internal.resolve_allowed_recipients_for_actor(uuid, text)
  from public, anon, authenticated;
grant execute on function internal.resolve_allowed_recipients_for_actor(uuid, text)
  to authenticated;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
select
  '20260831045035_msg02_explicit_functionary_messaging_capability',
  'greenfield',
  'REL-02 explicit club.messaging.manage gate for club-wide recipient access'
where not exists (
  select 1
  from internal.migration_provenance
  where migration_name = '20260831045035_msg02_explicit_functionary_messaging_capability'
);
