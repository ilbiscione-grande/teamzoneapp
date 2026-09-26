-- MSG-03: announcements target server-derived role groups rather than
-- hand-picked profiles, and the first message is created atomically with the
-- announcement thread.
do $$
declare
  function_definition text;
  updated_definition text;
begin
  function_definition := pg_get_functiondef(
    'internal.create_announcement_for_actor(uuid,text,uuid[],uuid)'::regprocedure
  );
  updated_definition := replace(
    function_definition,
    'cardinality(recipient_profile_ids) > 50',
    'cardinality(recipient_profile_ids) > 1000'
  );
  if updated_definition = function_definition then
    raise exception 'msg03_announcement_recipient_limit_patch_not_applied';
  end if;
  execute updated_definition;
end
$$;

create or replace function internal.create_role_group_announcement_for_actor(
  target_context_id uuid,
  new_subject text,
  new_body text,
  audience_roles text[],
  idempotency_key uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  context_row record;
  normalized_roles text[];
  recipient_profile_ids uuid[];
  thread_id uuid;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;

  select * into context_row
  from internal.get_my_contexts_for_actor()
  where context_id = target_context_id;

  if context_row.context_id is null
     or length(btrim(coalesce(new_subject, ''))) not between 1 and 120
     or length(btrim(coalesce(new_body, ''))) not between 1 and 4000
     or audience_roles is null
     or cardinality(audience_roles) < 1
     or array_position(audience_roles, null) is not null then
    raise invalid_parameter_value using message = 'invalid_announcement';
  end if;

  if 'all' = any(audience_roles) then
    normalized_roles := array['player', 'leader', 'guardian', 'club_functionary'];
  else
    select array_agg(distinct role_name order by role_name)
    into normalized_roles
    from unnest(audience_roles) role_name;
    if exists (
      select 1
      from unnest(normalized_roles) role_name
      where role_name not in ('player', 'leader', 'guardian', 'club_functionary')
    ) then
      raise invalid_parameter_value using message = 'invalid_audience';
    end if;
  end if;

  if context_row.team_id is null
     and not internal.actor_has_capability(
       context_row.club_id,
       null,
       'club.messaging.manage'
     ) then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select array_agg(distinct link.profile_id order by link.profile_id)
  into recipient_profile_ids
  from core.person_account_links link
  join core.assignments assignment
    on assignment.club_id = link.club_id
   and assignment.club_person_id = link.club_person_id
  where link.club_id = context_row.club_id
    and link.profile_id <> actor_id
    and link.state = 'active'
    and assignment.state = 'active'
    and assignment.starts_at <= now()
    and (assignment.ends_at is null or assignment.ends_at > now())
    and assignment.role_package = any(normalized_roles)
    and (context_row.team_id is null or assignment.team_id = context_row.team_id)
    and internal.messaging_relationship_allowed(
      actor_id,
      link.profile_id,
      context_row.club_id,
      context_row.team_id
    );

  if recipient_profile_ids is null or cardinality(recipient_profile_ids) = 0 then
    raise check_violation using message = 'no_recipients';
  end if;

  thread_id := internal.create_announcement_for_actor(
    target_context_id,
    btrim(new_subject),
    recipient_profile_ids,
    idempotency_key
  );
  perform internal.send_message_for_actor(
    thread_id,
    btrim(new_body),
    idempotency_key
  );
  return thread_id;
end
$$;

create or replace function api.create_role_group_announcement(
  context_id uuid,
  subject text,
  body text,
  audience_roles text[],
  idempotency_key uuid
) returns uuid
language sql
security invoker
set search_path = ''
as $$
  select internal.create_role_group_announcement_for_actor(
    context_id,
    subject,
    body,
    audience_roles,
    idempotency_key
  )
$$;

revoke all on function internal.create_role_group_announcement_for_actor(
  uuid, text, text, text[], uuid
) from public, anon, authenticated;
revoke all on function api.create_role_group_announcement(
  uuid, text, text, text[], uuid
) from public, anon;
grant execute on function api.create_role_group_announcement(
  uuid, text, text, text[], uuid
) to authenticated;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260922043656_msg03_role_group_announcements',
  'greenfield',
  'MSG-03 atomic role-group announcement with team/authorized-club scope'
);

notify pgrst, 'reload schema';
