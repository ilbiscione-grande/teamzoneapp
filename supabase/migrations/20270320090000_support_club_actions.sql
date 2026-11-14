-- Supportens adminsida, del 3: åtgärder på klubbar.
--
-- Support can help a club that is stuck, always with a reason and a log
-- entry (audit.command_events, support.*):
--   * make someone in the club who can sign in club admin (Medlemmar och
--     lag over the club), through a club functionary role as club roles do;
--   * apply or cancel a board change that is stuck (applying runs the same
--     checks as the board's own apply, without the board's approvals);
--   * take the admin right from someone. When that leaves the club without
--     an admin who can sign in, the lock from 20270316090000 is lifted for
--     this change only: teamzone.allow_no_club_admin is set, the lock's
--     constraint trigger is checked at once, and the setting is turned off
--     again before the function returns.
-- The club view also gets ids (admins, pending board changes) and the
-- people who can sign in, for choosing a new admin.

create or replace function internal.get_club_for_support_for_actor(target_club_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  club_row core.clubs%rowtype;
  result jsonb;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into club_row from core.clubs club where club.id = target_club_id;
  if club_row.id is null then
    raise invalid_parameter_value using message = 'not_found';
  end if;

  result := jsonb_build_object(
    'club_id', club_row.id,
    'club_name', club_row.name,
    'club_status', club_row.status,
    'verification_status', club_row.verification_status,
    'created_at', club_row.created_at,
    'has_admin_with_account', internal.club_has_admin_with_account(club_row.id),
    'board_forming', internal.board_forming(club_row.id),
    -- Everyone holding Medlemmar och lag over the club, also those who
    -- would not count (no account, or a right with an end date).
    'admins', coalesce((select jsonb_agg(jsonb_build_object(
        'person_id', admin.id, 'name', admin.display_name, 'has_account', admin.has_account,
        'ends_at', admin.ends_at) order by admin.display_name)
      from (select person.id, person.display_name,
          bool_or(link.id is not null) has_account,
          max(coalesce(grant_row.ends_at, assignment.ends_at)) ends_at
        from core.capability_grants grant_row
        join core.assignments assignment on assignment.id = grant_row.assignment_id
          and assignment.club_id = grant_row.club_id and assignment.state = 'active'
        join core.club_people person on person.id = assignment.club_person_id
        left join core.person_account_links link on link.club_person_id = person.id
          and link.club_id = person.club_id and link.state = 'active'
        where grant_row.club_id = club_row.id and grant_row.capability = 'club.memberships.manage'
          and grant_row.scope_type = 'club' and grant_row.scope_id = club_row.id
          and (grant_row.ends_at is null or grant_row.ends_at > now())
        group by person.id, person.display_name) admin), '[]'::jsonb),
    'board', coalesce((select jsonb_agg(jsonb_build_object(
        'name', person.display_name, 'office', mandate.office,
        'starts_at', mandate.starts_at, 'ends_at', mandate.ends_at,
        'has_account', exists (select 1 from core.person_account_links link
          where link.club_person_id = person.id and link.club_id = person.club_id
            and link.state = 'active'))
        order by mandate.office, person.display_name)
      from core.board_mandates mandate
      join core.assignments assignment on assignment.id = mandate.assignment_id
        and assignment.club_id = mandate.club_id
      join core.club_people person on person.id = assignment.club_person_id
      where mandate.club_id = club_row.id and mandate.state = 'active'
        and mandate.ends_at > now()), '[]'::jsonb),
    'pending_board_changes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', change.id, 'action', change.action, 'office', change.office, 'name', person.display_name,
        'created_at', change.created_at,
        'approvals', (select count(*) from core.board_mandate_change_approvals approval
          where approval.change_id = change.id and approval.decision = 'approved'))
        order by change.created_at)
      from core.board_mandate_changes change
      left join core.assignments assignment on assignment.id = change.target_assignment_id
      left join core.club_people person on person.id = assignment.club_person_id
      where change.club_id = club_row.id and change.state = 'pending'), '[]'::jsonb),
    -- People who can sign in: whom support can make club admin.
    'people_with_account', coalesce((select jsonb_agg(jsonb_build_object(
        'person_id', person.id, 'name', person.display_name,
        'is_admin', exists (select 1 from core.capability_grants grant_row
          join core.assignments assignment on assignment.id = grant_row.assignment_id
            and assignment.state = 'active' and assignment.ends_at is null
          where assignment.club_person_id = person.id and grant_row.club_id = person.club_id
            and grant_row.capability = 'club.memberships.manage' and grant_row.scope_type = 'club'
            and grant_row.scope_id = person.club_id and grant_row.starts_at <= now()
            and grant_row.ends_at is null))
        order by person.display_name)
      from core.club_people person
      where person.club_id = club_row.id and person.status = 'active'
        and exists (select 1 from core.person_account_links link
          where link.club_person_id = person.id and link.club_id = person.club_id
            and link.state = 'active')), '[]'::jsonb),
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
        'name', team.name, 'status', team.status,
        'people', (select count(distinct assignment.club_person_id)
          from core.assignments assignment
          where assignment.team_id = team.id and assignment.state = 'active'))
        order by team.name)
      from core.teams team where team.club_id = club_row.id), '[]'::jsonb)
  );

  insert into audit.command_events(club_id, actor_profile_id, command_type,
    aggregate_type, aggregate_id, metadata)
  values (club_row.id, auth.uid(), 'support.club_viewed', 'club', club_row.id,
    jsonb_build_object('source', 'support_admin'));
  return result;
end
$$;

create or replace function internal.support_reason(reason text)
returns text language plpgsql immutable set search_path = '' as $$
begin
  if reason is null or length(btrim(reason)) not between 5 and 500 then
    raise invalid_parameter_value using message = 'invalid_reason';
  end if;
  return btrim(reason);
end
$$;

-- Make someone club admin.
create or replace function internal.support_grant_club_admin_for_actor(
  target_club_id uuid, target_person_id uuid, reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid();
  clean_reason text;
  functionary_id uuid;
  created boolean := false;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  clean_reason := internal.support_reason(reason);
  if not exists (select 1 from core.clubs club where club.id = target_club_id) then
    raise invalid_parameter_value using message = 'not_found';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('club-permissions:' || target_club_id::text, 0));
  if not exists (select 1 from core.club_people person
      join core.person_account_links link on link.club_person_id = person.id
        and link.club_id = person.club_id and link.state = 'active'
      where person.id = target_person_id and person.club_id = target_club_id
        and person.status = 'active') then
    raise invalid_parameter_value using message = 'person_without_account';
  end if;
  if exists (select 1 from core.capability_grants grant_row
      join core.assignments assignment on assignment.id = grant_row.assignment_id
        and assignment.state = 'active' and assignment.starts_at <= now()
        and assignment.ends_at is null
      where assignment.club_person_id = target_person_id and grant_row.club_id = target_club_id
        and grant_row.capability = 'club.memberships.manage' and grant_row.scope_type = 'club'
        and grant_row.scope_id = target_club_id and grant_row.starts_at <= now()
        and grant_row.ends_at is null) then
    raise sqlstate 'PT409' using message = 'already_club_admin';
  end if;
  select assignment.id into functionary_id from core.assignments assignment
  where assignment.club_id = target_club_id and assignment.club_person_id = target_person_id
    and assignment.team_id is null and assignment.role_package = 'club_functionary'
    and assignment.state = 'active' and assignment.starts_at <= now() and assignment.ends_at is null
  order by assignment.starts_at limit 1;
  if functionary_id is null then
    insert into core.assignments (club_id, team_id, club_person_id, role_package, state, starts_at, created_by)
    values (target_club_id, null, target_person_id, 'club_functionary', 'active', now(), actor_id)
    returning id into functionary_id;
    created := true;
  end if;
  insert into core.capability_grants (club_id, assignment_id, capability, scope_type, scope_id, starts_at, created_by)
  values (target_club_id, functionary_id, 'club.memberships.manage', 'club', target_club_id, now(), actor_id)
  on conflict (assignment_id, capability, scope_type, scope_id) do update
  set starts_at = now(), ends_at = null, revision = core.capability_grants.revision + 1,
    created_by = excluded.created_by;
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type,
    aggregate_id, reason, metadata)
  values (target_club_id, actor_id, 'support.club_admin_granted', 'club_person', target_person_id,
    clean_reason, jsonb_build_object('source', 'support_admin', 'assignment_id', functionary_id,
      'created_club_role', created));
  return jsonb_build_object('person_id', target_person_id, 'created_club_role', created);
end
$$;

-- Take the admin right from someone, also from the club's last admin.
create or replace function internal.support_remove_club_admin_for_actor(
  target_club_id uuid, target_person_id uuid, reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid();
  clean_reason text;
  ended integer;
  without_admin boolean;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  clean_reason := internal.support_reason(reason);
  perform pg_advisory_xact_lock(hashtextextended('club-permissions:' || target_club_id::text, 0));
  update core.capability_grants grant_row
  set ends_at = greatest(now(), grant_row.starts_at + interval '1 microsecond'),
    revision = grant_row.revision + 1
  from core.assignments assignment
  where assignment.id = grant_row.assignment_id and assignment.club_person_id = target_person_id
    and grant_row.club_id = target_club_id and grant_row.capability = 'club.memberships.manage'
    and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
    and (grant_row.ends_at is null or grant_row.ends_at > now());
  get diagnostics ended = row_count;
  if ended = 0 then
    raise sqlstate 'PT409' using message = 'not_club_admin';
  end if;
  without_admin := not internal.club_has_admin_with_account(target_club_id);
  if without_admin then
    -- The logged emergency exception: only this change passes the lock.
    perform set_config('teamzone.allow_no_club_admin', 'on', true);
    set constraints core.capability_grants_club_keeps_admin immediate;
    set constraints core.capability_grants_club_keeps_admin deferred;
    perform set_config('teamzone.allow_no_club_admin', 'off', true);
  end if;
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type,
    aggregate_id, reason, metadata)
  values (target_club_id, actor_id, 'support.club_admin_removed', 'club_person', target_person_id,
    clean_reason, jsonb_build_object('source', 'support_admin', 'grants_ended', ended,
      'left_without_admin', without_admin));
  return jsonb_build_object('person_id', target_person_id, 'left_without_admin', without_admin);
end
$$;

-- Apply or cancel a board change that is stuck.
create or replace function internal.support_resolve_board_change_for_actor(
  target_change_id uuid, decision text, reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid();
  clean_reason text;
  change_row core.board_mandate_changes%rowtype;
  mandate_id uuid;
  approvals integer;
begin
  if not internal.actor_is_support_admin() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  clean_reason := internal.support_reason(reason);
  if decision is null or decision not in ('apply', 'cancel') then
    raise invalid_parameter_value using message = 'invalid_decision';
  end if;
  select * into change_row from core.board_mandate_changes change
  where change.id = target_change_id for update;
  if change_row.id is null then
    raise invalid_parameter_value using message = 'not_found';
  end if;
  if change_row.state <> 'pending' then
    raise sqlstate 'PT409' using message = 'board_change_not_pending';
  end if;
  select count(*) into approvals from core.board_mandate_change_approvals approval
  where approval.change_id = change_row.id and approval.decision = 'approved';
  if decision = 'cancel' then
    update core.board_mandate_changes set state = 'cancelled', revision = revision + 1
    where id = change_row.id;
  else
    if change_row.action = 'grant' then
      if change_row.ends_at <= now() or not exists (select 1 from core.assignments assignment
          where assignment.id = change_row.target_assignment_id and assignment.club_id = change_row.club_id
            and assignment.state = 'active' and assignment.starts_at <= now()
            and (assignment.ends_at is null or assignment.ends_at > now())) then
        raise check_violation using message = 'mandate_target_inactive';
      end if;
      if exists (select 1 from core.board_mandates existing
          where existing.club_id = change_row.club_id
            and existing.assignment_id = change_row.target_assignment_id
            and existing.office = change_row.office and existing.state = 'active'
            and tstzrange(existing.starts_at, existing.ends_at, '[)')
              && tstzrange(change_row.starts_at, change_row.ends_at, '[)')) then
        raise check_violation using message = 'mandate_overlap';
      end if;
      insert into core.board_mandates (club_id, assignment_id, office, starts_at, ends_at)
      values (change_row.club_id, change_row.target_assignment_id, change_row.office,
        change_row.starts_at, change_row.ends_at)
      returning id into mandate_id;
    else
      select mandate.id into mandate_id from core.board_mandates mandate
      where mandate.id = change_row.target_mandate_id and mandate.club_id = change_row.club_id
        and mandate.state = 'active'
      for update;
      if mandate_id is null then
        raise check_violation using message = 'invalid_state';
      end if;
      update core.board_mandates set state = 'revoked', revision = revision + 1 where id = mandate_id;
    end if;
    update core.board_mandate_changes set state = 'applied', applied_at = now(), revision = revision + 1
    where id = change_row.id;
  end if;
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type,
    aggregate_id, reason, metadata)
  values (change_row.club_id, actor_id,
    case decision when 'apply' then 'support.board_change_applied' else 'support.board_change_cancelled' end,
    'board_mandate_change', change_row.id, clean_reason,
    jsonb_build_object('source', 'support_admin', 'action', change_row.action,
      'office', change_row.office, 'approvals', approvals, 'mandate_id', mandate_id));
  return jsonb_build_object('change_id', change_row.id, 'decision', decision, 'mandate_id', mandate_id);
end
$$;

create or replace function api.support_grant_club_admin(target_club_id uuid, target_person_id uuid, reason text)
returns jsonb language sql volatile security invoker set search_path = ''
as $$select internal.support_grant_club_admin_for_actor(target_club_id, target_person_id, reason)$$;

create or replace function api.support_remove_club_admin(target_club_id uuid, target_person_id uuid, reason text)
returns jsonb language sql volatile security invoker set search_path = ''
as $$select internal.support_remove_club_admin_for_actor(target_club_id, target_person_id, reason)$$;

create or replace function api.support_resolve_board_change(target_change_id uuid, decision text, reason text)
returns jsonb language sql volatile security invoker set search_path = ''
as $$select internal.support_resolve_board_change_for_actor(target_change_id, decision, reason)$$;

revoke all on function
  internal.support_reason(text),
  internal.support_grant_club_admin_for_actor(uuid, uuid, text),
  internal.support_remove_club_admin_for_actor(uuid, uuid, text),
  internal.support_resolve_board_change_for_actor(uuid, text, text),
  api.support_grant_club_admin(uuid, uuid, text),
  api.support_remove_club_admin(uuid, uuid, text),
  api.support_resolve_board_change(uuid, text, text)
from public, anon, authenticated;

grant execute on function
  internal.support_grant_club_admin_for_actor(uuid, uuid, text),
  internal.support_remove_club_admin_for_actor(uuid, uuid, text),
  internal.support_resolve_board_change_for_actor(uuid, text, text),
  api.support_grant_club_admin(uuid, uuid, text),
  api.support_remove_club_admin(uuid, uuid, text),
  api.support_resolve_board_change(uuid, text, text)
to authenticated;

notify pgrst, 'reload schema';
