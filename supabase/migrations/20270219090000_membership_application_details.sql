-- Membership applications say who is asking (2026-11-11): the reviewer saw
-- "Ny användare", a team and a role, and could not tell who it was.
-- - The review list adds the applicant's e-mail address (the product
--   owner's decision: whoever may approve sees it) and how they applied:
--   with a team code or by finding the team.
-- - Someone without a name sets one before applying (the waiting room
--   asks): a name of their own, 2-80 characters.
-- The list functions are their live versions with these columns added.

drop function api.list_pending_membership_applications(uuid, uuid);
drop function internal.list_pending_membership_applications_for_actor(uuid, uuid);

create function internal.list_pending_membership_applications_for_actor(target_club_id uuid, target_team_id uuid default null)
returns table(application_id uuid, applicant_display_name text, team_name text, requested_role text,
  created_at timestamptz, applicant_email text, source text)
language plpgsql stable security definer set search_path to '' as $function$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not (
      internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
      or (
        target_team_id is not null
        and internal.actor_has_capability(
          target_club_id,target_team_id,'team.roster.manage'
        )
      )
    ) then
    raise insufficient_privilege using message='not_found';
  end if;
  return query
  select application.id,
    coalesce(nullif(profile.display_name,''),'Ny användare'),team.name,
    application.requested_role,application.created_at,
    account.email::text,
    case when exists (select 1 from audit.command_events event
        where event.aggregate_type='membership_application' and event.aggregate_id=application.id
          and event.command_type='roster.team_code.claim.v1')
      then 'team_code' else 'search' end
  from core.membership_applications application
  join core.profiles profile on profile.id=application.applicant_profile_id
  join core.teams team on team.id=application.team_id and team.club_id=application.club_id
  left join auth.users account on account.id=application.applicant_profile_id
  where application.club_id=target_club_id and application.status='pending'
    and (target_team_id is null or application.team_id=target_team_id)
  order by application.created_at,application.id
  limit 100;
end
$function$;

create function api.list_pending_membership_applications(target_club_id uuid, target_team_id uuid default null)
returns table(application_id uuid, applicant_display_name text, team_name text, requested_role text,
  created_at timestamptz, applicant_email text, source text)
language sql stable set search_path to '' as $function$
  select * from internal.list_pending_membership_applications_for_actor(target_club_id,target_team_id)
$function$;

revoke all on function internal.list_pending_membership_applications_for_actor(uuid, uuid),
  api.list_pending_membership_applications(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.list_pending_membership_applications_for_actor(uuid, uuid),
  api.list_pending_membership_applications(uuid, uuid) to authenticated;

-- The signed-in person's own name, from the waiting room.
create or replace function internal.set_my_display_name_for_actor(new_display_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); clean text := btrim(regexp_replace(coalesce(new_display_name, ''), '\s+', ' ', 'g'));
  saved core.profiles%rowtype;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if length(clean) not between 2 and 80 then raise invalid_parameter_value using message = 'invalid_display_name'; end if;
  update core.profiles set display_name = clean, updated_at = now(), revision = revision + 1
  where id = actor_id returning * into saved;
  if saved.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  return jsonb_build_object('display_name', saved.display_name, 'revision', saved.revision);
end;
$$;

create or replace function api.set_my_display_name(new_display_name text) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.set_my_display_name_for_actor(new_display_name) $$;

revoke all on function internal.set_my_display_name_for_actor(text), api.set_my_display_name(text)
  from public, anon, authenticated;
grant execute on function internal.set_my_display_name_for_actor(text), api.set_my_display_name(text) to authenticated;
notify pgrst, 'reload schema';
