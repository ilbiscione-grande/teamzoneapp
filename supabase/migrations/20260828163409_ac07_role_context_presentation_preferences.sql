-- AC-07: role/context presentation and private per-area preferences. This
-- migration does not activate assistant delivery or domain mutations.

create table core.assistant_area_preferences (
  profile_id uuid not null references core.profiles(id) on delete cascade,
  area_key text not null references
    internal.assistant_specialist_area_registry(area_key),
  visible boolean not null default true,
  delivery_mode text not null default 'off' check (
    delivery_mode in ('direct','digest','in_assistant','off')
  ),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  primary key(profile_id, area_key)
);

alter table core.assistant_area_preferences enable row level security;
revoke all on table core.assistant_area_preferences
  from public, anon, authenticated;

create function internal.get_assistant_area_preferences_for_actor()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when auth.uid() is null then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object(
      'area_key', preference.area_key,
      'visible', preference.visible,
      'delivery_mode', preference.delivery_mode,
      'revision', preference.revision
    ) order by preference.area_key)
    from core.assistant_area_preferences preference
    where preference.profile_id = auth.uid()
  ), '[]'::jsonb) end
$$;

create function internal.set_assistant_area_preference_for_actor(
  area_key text,
  visible boolean,
  delivery_mode text,
  expected_revision bigint,
  idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  current_revision bigint;
  next_revision bigint;
  existing_result jsonb;
begin
  if actor_id is null or idempotency_key is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if delivery_mode not in ('direct','digest','in_assistant','off')
    or not exists(
      select 1 from internal.assistant_specialist_area_registry area
      where area.area_key = set_assistant_area_preference_for_actor.area_key
    ) then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select dedupe.result into existing_result
  from internal.command_deduplication dedupe
  where dedupe.actor_profile_id = actor_id
    and dedupe.idempotency_key =
      set_assistant_area_preference_for_actor.idempotency_key
    and dedupe.command_type = 'assistant.area.preference.updated.v1';
  if existing_result is not null then return existing_result; end if;

  select preference.revision into current_revision
  from core.assistant_area_preferences preference
  where preference.profile_id = actor_id
    and preference.area_key = set_assistant_area_preference_for_actor.area_key
  for update;
  current_revision := coalesce(current_revision, 0);
  if current_revision <> expected_revision then
    raise exception 'stale_revision';
  end if;
  next_revision := current_revision + 1;

  insert into core.assistant_area_preferences(
    profile_id, area_key, visible, delivery_mode, revision, updated_at
  ) values(
    actor_id, area_key, visible, delivery_mode, next_revision, now()
  ) on conflict(profile_id, area_key) do update set
    visible = excluded.visible,
    delivery_mode = excluded.delivery_mode,
    revision = excluded.revision,
    updated_at = excluded.updated_at;

  existing_result := jsonb_build_object(
    'area_key', area_key,
    'visible', visible,
    'delivery_mode', delivery_mode,
    'revision', next_revision
  );
  insert into internal.command_deduplication(
    actor_profile_id, idempotency_key, command_type, result
  ) values(
    actor_id, idempotency_key,
    'assistant.area.preference.updated.v1', existing_result
  );
  return existing_result;
end;
$$;

create function internal.list_role_adapted_assistant_queue_for_actor(
  target_context_id uuid,
  acting_as_person_id uuid default null,
  include_dismissed boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  context_row record;
  acting_as_name text;
  queue_value jsonb;
  allowed_area_keys text[];
  can_team_planning boolean;
begin
  select assignment.id as context_id, assignment.club_id, club.name club_name,
    assignment.team_id, team.name team_name, assignment.club_person_id,
    assignment.role_package
  into context_row
  from core.person_account_links link
  join core.assignments assignment
    on assignment.club_id = link.club_id
    and assignment.club_person_id = link.club_person_id
  join core.clubs club on club.id = assignment.club_id
  left join core.teams team
    on team.id = assignment.team_id and team.club_id = assignment.club_id
  where link.profile_id = actor_id and link.state = 'active'
    and assignment.id = target_context_id and assignment.state = 'active'
    and assignment.starts_at <= now()
    and (assignment.ends_at is null or assignment.ends_at > now());
  if actor_id is null or context_row.context_id is null then
    raise insufficient_privilege using message = 'not_found';
  end if;

  if acting_as_person_id is not null then
    if context_row.role_package <> 'guardian' or not exists(
      select 1 from core.guardian_relations relation
      where relation.club_id = context_row.club_id
        and relation.guardian_person_id = context_row.club_person_id
        and relation.child_person_id = acting_as_person_id
        and relation.state = 'active' and relation.starts_at <= now()
        and (relation.ends_at is null or relation.ends_at > now())
    ) then
      raise insufficient_privilege using message = 'not_found';
    end if;
    select person.display_name into acting_as_name
    from core.club_people person
    where person.id = acting_as_person_id
      and person.club_id = context_row.club_id;
  end if;

  select coalesce(array_agg(area.area_key order by area.area_key), array[]::text[])
  into allowed_area_keys
  from internal.assistant_specialist_area_registry area
  where context_row.role_package = any(area.target_roles)
    and exists(
      select 1 from core.capability_grants capability
      where capability.assignment_id = context_row.context_id
        and capability.club_id = context_row.club_id
        and capability.capability = any(area.capabilities)
        and capability.starts_at <= now()
        and (capability.ends_at is null or capability.ends_at > now())
        and (
          capability.scope_type = 'club'
          and capability.scope_id = context_row.club_id
          or capability.scope_type = 'team'
          and capability.scope_id = context_row.team_id
        )
    );
  can_team_planning := 'team_planning' = any(allowed_area_keys);

  if can_team_planning and context_row.team_id is not null then
    queue_value := internal.list_assistant_signals_for_actor(
      context_row.club_id, context_row.team_id, include_dismissed
    );
    select jsonb_set(
      queue_value, '{signals}',
      coalesce(jsonb_agg(
        jsonb_set(
          signal, '{deliveryMode}',
          to_jsonb(case
            when area.gate_state = 'active' then coalesce(
              preference.delivery_mode,
              signal->>'defaultDeliveryMode',
              'in_assistant'
            )
            else 'off'
          end), true
        ) order by (signal->>'priority')::integer,
          signal->>'canonicalKey'
      ), '[]'::jsonb), true
    ) into queue_value
    from jsonb_array_elements(
      coalesce(queue_value->'signals', '[]'::jsonb)
    ) signal
    join internal.assistant_specialist_area_registry area
      on area.area_key = signal->>'primaryAreaKey'
    left join core.assistant_area_preferences preference
      on preference.profile_id = actor_id
      and preference.area_key = area.area_key
    where signal->>'primaryAreaKey' = any(allowed_area_keys);
  else
    queue_value := jsonb_build_object(
      'state', 'blocked',
      'generativeAiEnabled', false,
      'signals', '[]'::jsonb,
      'queueContract', jsonb_build_object(
        'scope', 'shared_cross_area',
        'separateSpecialistQueues', false,
        'deliveryEnabled', false
      )
    );
  end if;

  return queue_value || jsonb_build_object(
    'presentationContext', jsonb_build_object(
      'contextId', context_row.context_id,
      'clubId', context_row.club_id,
      'clubName', context_row.club_name,
      'teamId', context_row.team_id,
      'teamName', context_row.team_name,
      'rolePackage', context_row.role_package,
      'actingAsPersonId', acting_as_person_id,
      'actingAsName', acting_as_name,
      'allowedAreaKeys', allowed_area_keys
    )
  );
end;
$$;

create function api.get_assistant_area_preferences()
returns jsonb language sql stable security invoker set search_path = ''
as $$select internal.get_assistant_area_preferences_for_actor()$$;

create function api.set_assistant_area_preference(
  area_key text, visible boolean, delivery_mode text,
  expected_revision bigint, idempotency_key uuid
)
returns jsonb language sql security invoker set search_path = ''
as $$select internal.set_assistant_area_preference_for_actor(
  area_key, visible, delivery_mode, expected_revision, idempotency_key
)$$;

create function api.list_role_adapted_assistant_queue(
  context_id uuid, acting_as_person_id uuid default null,
  include_dismissed boolean default false
)
returns jsonb language sql stable security invoker set search_path = ''
as $$select internal.list_role_adapted_assistant_queue_for_actor(
  context_id, acting_as_person_id, include_dismissed
)$$;

revoke all on function internal.get_assistant_area_preferences_for_actor(),
  internal.set_assistant_area_preference_for_actor(text,boolean,text,bigint,uuid),
  internal.list_role_adapted_assistant_queue_for_actor(uuid,uuid,boolean),
  api.get_assistant_area_preferences(),
  api.set_assistant_area_preference(text,boolean,text,bigint,uuid),
  api.list_role_adapted_assistant_queue(uuid,uuid,boolean)
from public, anon, authenticated;
grant execute on function internal.get_assistant_area_preferences_for_actor(),
  internal.set_assistant_area_preference_for_actor(text,boolean,text,bigint,uuid),
  internal.list_role_adapted_assistant_queue_for_actor(uuid,uuid,boolean),
  api.get_assistant_area_preferences(),
  api.set_assistant_area_preference(text,boolean,text,bigint,uuid),
  api.list_role_adapted_assistant_queue(uuid,uuid,boolean)
to authenticated;

insert into internal.migration_provenance(
  migration_name, source_kind, source_reference
) values(
  '20260828163409_ac07_role_context_presentation_preferences',
  'greenfield',
  'AC-07 role/capability context projection, guardian acting-as and private area preferences'
);

notify pgrst, 'reload schema';
