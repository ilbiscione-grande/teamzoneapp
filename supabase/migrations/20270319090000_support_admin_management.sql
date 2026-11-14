-- Supportadministratörer i supportsidan (adminsidan för TeamZones support, del 4).
--
-- Who is a support administrator could only be changed in the database
-- (internal.support_admins). The product owner wants support done from an
-- account of its own, apart from the personal account that has roles in
-- clubs (2026-11-14). Three functions, for support administrators only:
--
-- * api.list_support_admins(): everyone who is or has been a support
--   administrator, with name, sign-in address, and how many clubs the
--   account has a role in (a support account should have none).
-- * api.grant_support_admin(email, reason): an existing account, found by
--   its sign-in address, becomes support administrator (again).
-- * api.revoke_support_admin(profile, reason): the right ends. The last
--   active support administrator can never be removed (last_support_admin).
--
-- Both changes need a reason and are written to audit.command_events.
-- Active support administrators also receive the support emails
-- (internal.claim_support_email_batch).

create or replace function internal.list_support_admins_for_actor()
returns table(
  profile_id uuid, display_name text, email text, active boolean,
  created_at timestamptz, revoked_at timestamptz, is_self boolean,
  club_count integer
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return query
    select admin.profile_id, profile.display_name, user_row.email::text, admin.active,
      admin.created_at, admin.revoked_at, admin.profile_id = auth.uid(),
      (select count(distinct link.club_id)::integer from core.person_account_links link
        where link.profile_id = admin.profile_id and link.state = 'active')
    from internal.support_admins admin
    join core.profiles profile on profile.id = admin.profile_id
    left join auth.users user_row on user_row.id = admin.profile_id
    order by admin.active desc, profile.display_name, admin.profile_id;
end
$$;

create or replace function internal.grant_support_admin_for_actor(target_email text, reason text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  target_id uuid;
  was_active boolean;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if length(btrim(coalesce(reason, ''))) not between 5 and 500 then
    raise invalid_parameter_value using message = 'reason_required';
  end if;
  select user_row.id into target_id from auth.users user_row
  where lower(user_row.email) = lower(btrim(coalesce(target_email, '')))
    and exists (select 1 from core.profiles profile where profile.id = user_row.id);
  if target_id is null then
    raise invalid_parameter_value using message = 'account_not_found';
  end if;

  select admin.active into was_active from internal.support_admins admin
  where admin.profile_id = target_id for update;
  if was_active then
    raise sqlstate 'PT409' using message = 'already_support_admin';
  end if;
  insert into internal.support_admins(profile_id, active, created_at, created_by, revoked_at)
  values (target_id, true, now(), auth.uid(), null)
  on conflict (profile_id) do update set
    active = true, created_at = now(), created_by = auth.uid(), revoked_at = null;

  insert into audit.command_events(actor_profile_id, command_type, aggregate_type,
    aggregate_id, reason, metadata)
  values (auth.uid(), 'support.admin_granted', 'support_admin', target_id,
    btrim(reason), jsonb_build_object('again', was_active is not null));
  return target_id;
end
$$;

create or replace function internal.revoke_support_admin_for_actor(target_profile_id uuid, reason text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  remaining integer;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if length(btrim(coalesce(reason, ''))) not between 5 and 500 then
    raise invalid_parameter_value using message = 'reason_required';
  end if;
  -- Lock every active row so two removals cannot both leave nobody.
  perform 1 from internal.support_admins admin where admin.active for update;
  if not exists (select 1 from internal.support_admins admin
      where admin.profile_id = target_profile_id and admin.active) then
    raise sqlstate 'PT409' using message = 'not_support_admin';
  end if;
  select count(*) into remaining from internal.support_admins admin
  where admin.active and admin.profile_id <> target_profile_id;
  if remaining = 0 then
    raise check_violation using message = 'last_support_admin';
  end if;

  update internal.support_admins set active = false, revoked_at = now()
  where profile_id = target_profile_id;
  insert into audit.command_events(actor_profile_id, command_type, aggregate_type,
    aggregate_id, reason, metadata)
  values (auth.uid(), 'support.admin_revoked', 'support_admin', target_profile_id,
    btrim(reason), jsonb_build_object('self', target_profile_id = auth.uid()));
end
$$;

create or replace function api.list_support_admins()
returns table(
  profile_id uuid, display_name text, email text, active boolean,
  created_at timestamptz, revoked_at timestamptz, is_self boolean,
  club_count integer
)
language sql stable security invoker set search_path = ''
as $$select * from internal.list_support_admins_for_actor()$$;

create or replace function api.grant_support_admin(target_email text, reason text)
returns uuid language sql security invoker set search_path = ''
as $$select internal.grant_support_admin_for_actor(target_email, reason)$$;

create or replace function api.revoke_support_admin(target_profile_id uuid, reason text)
returns void language sql security invoker set search_path = ''
as $$select internal.revoke_support_admin_for_actor(target_profile_id, reason)$$;

revoke all on function
  internal.list_support_admins_for_actor(),
  internal.grant_support_admin_for_actor(text, text),
  internal.revoke_support_admin_for_actor(uuid, text),
  api.list_support_admins(),
  api.grant_support_admin(text, text),
  api.revoke_support_admin(uuid, text)
from public, anon, authenticated;

grant execute on function
  internal.list_support_admins_for_actor(),
  internal.grant_support_admin_for_actor(text, text),
  internal.revoke_support_admin_for_actor(uuid, text),
  api.list_support_admins(),
  api.grant_support_admin(text, text),
  api.revoke_support_admin(uuid, text)
to authenticated;

notify pgrst, 'reload schema';
