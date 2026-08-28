-- S08 fail-closed development foundation. Health, sanction, check-in and AI
-- processing are intentionally absent while their specification gates are open.

create table core.development_plans (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  team_id uuid not null,
  subject_club_person_id uuid,
  plan_type text not null check (plan_type in ('team', 'player')),
  title text not null check (length(btrim(title)) between 2 and 120),
  focus text not null default '' check (length(focus) <= 4000),
  state text not null default 'draft' check (state in ('draft', 'active', 'completed', 'archived')),
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  foreign key (team_id, club_id) references core.teams(id, club_id),
  foreign key (subject_club_person_id, club_id) references core.club_people(id, club_id),
  check ((plan_type = 'team' and subject_club_person_id is null)
      or (plan_type = 'player' and subject_club_person_id is not null))
);

create table core.development_actions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  plan_id uuid not null,
  title text not null check (length(btrim(title)) between 2 and 160),
  description text not null default '' check (length(description) <= 4000),
  due_at timestamptz,
  state text not null default 'open' check (state in ('open', 'completed', 'dismissed')),
  source_kind text not null default 'manual' check (source_kind in ('manual', 'assistant_preview')),
  source_ref jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  foreign key (plan_id, club_id) references core.development_plans(id, club_id) on delete cascade
);

create index development_plans_team_state_idx
  on core.development_plans (club_id, team_id, state, updated_at desc);
create index development_plans_subject_idx
  on core.development_plans (club_id, subject_club_person_id, state)
  where subject_club_person_id is not null;
create index development_actions_plan_state_idx
  on core.development_actions (club_id, plan_id, state, due_at);

alter table core.development_plans enable row level security;
alter table core.development_actions enable row level security;

create function internal.actor_owns_club_person(target_club_id uuid, target_club_person_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from core.person_account_links link
    where link.profile_id = auth.uid() and link.club_id = target_club_id
      and link.club_person_id = target_club_person_id and link.state = 'active'
  );
$$;

create function internal.actor_can_read_development_plan(plan core.development_plans)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (
    internal.actor_has_capability(plan.club_id, plan.team_id, 'development.manage')
    or (plan.plan_type = 'player'
        and internal.actor_owns_club_person(plan.club_id, plan.subject_club_person_id))
  );
$$;

create function internal.list_development_plans_for_actor(target_club_id uuid, target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not exists (
    select 1 from core.development_plans plan
    where plan.club_id = target_club_id and plan.team_id = target_team_id
      and internal.actor_can_read_development_plan(plan)
  ) and not internal.actor_has_capability(target_club_id, target_team_id, 'development.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', plan.id, 'club_id', plan.club_id, 'team_id', plan.team_id,
    'subject_club_person_id', plan.subject_club_person_id,
    'plan_type', plan.plan_type, 'title', plan.title, 'focus', plan.focus,
    'state', plan.state, 'revision', plan.revision, 'updated_at', plan.updated_at,
    'actions', coalesce((select jsonb_agg(jsonb_build_object(
      'id', action.id, 'title', action.title, 'description', action.description,
      'due_at', action.due_at, 'state', action.state,
      'source_kind', action.source_kind, 'revision', action.revision
    ) order by action.created_at) from core.development_actions action
      where action.plan_id = plan.id), '[]'::jsonb)
  ) order by plan.updated_at desc), '[]'::jsonb) into result
  from core.development_plans plan
  where plan.club_id = target_club_id and plan.team_id = target_team_id
    and internal.actor_can_read_development_plan(plan);
  return result;
end;
$$;

create function internal.create_development_plan_for_actor(
  target_club_id uuid, target_team_id uuid, new_plan_type text,
  new_subject_club_person_id uuid, new_title text, new_focus text,
  idempotency_key uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); existing jsonb; plan_id uuid;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id, target_team_id, 'development.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select result into existing from internal.command_deduplication
   where actor_profile_id = actor_id and command_type = 'development.plan.created.v1'
     and internal.command_deduplication.idempotency_key = create_development_plan_for_actor.idempotency_key;
  if existing is not null then return (existing->>'plan_id')::uuid; end if;

  insert into core.development_plans(
    club_id, team_id, subject_club_person_id, plan_type, title, focus, created_by, updated_by)
  values (target_club_id, target_team_id, new_subject_club_person_id, new_plan_type,
    btrim(new_title), coalesce(new_focus, ''), actor_id, actor_id)
  returning id into plan_id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'development.plan.created.v1',jsonb_build_object('plan_id',plan_id));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
  values(target_club_id,actor_id,'development.plan.created.v1','development_plan',plan_id,1,
    jsonb_build_object('plan_type',new_plan_type,'team_id',target_team_id));
  return plan_id;
end;
$$;

create function internal.add_development_action_for_actor(
  target_plan_id uuid, new_title text, new_description text, new_due_at timestamptz,
  expected_plan_revision bigint, idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); plan core.development_plans%rowtype; existing jsonb; action_id uuid; new_revision bigint;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into plan from core.development_plans where id = target_plan_id for update;
  if plan.id is null or not internal.actor_has_capability(plan.club_id, plan.team_id, 'development.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select result into existing from internal.command_deduplication
   where actor_profile_id = actor_id and command_type = 'development.action.created.v1'
     and internal.command_deduplication.idempotency_key = add_development_action_for_actor.idempotency_key;
  if existing is not null then return existing; end if;
  if plan.revision <> expected_plan_revision then raise serialization_failure using message = 'stale_revision'; end if;
  if plan.state in ('completed','archived') then raise check_violation using message = 'plan_not_editable'; end if;

  insert into core.development_actions(club_id,plan_id,title,description,due_at,created_by,updated_by)
  values(plan.club_id,plan.id,btrim(new_title),coalesce(new_description,''),new_due_at,actor_id,actor_id)
  returning id into action_id;
  update core.development_plans set revision=revision+1,updated_at=now(),updated_by=actor_id
   where id=plan.id returning revision into new_revision;
  existing := jsonb_build_object('action_id',action_id,'plan_revision',new_revision);
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'development.action.created.v1',existing);
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
  values(plan.club_id,actor_id,'development.action.created.v1','development_plan',plan.id,new_revision,
    jsonb_build_object('action_id',action_id));
  return existing;
end;
$$;

revoke all on function internal.actor_owns_club_person(uuid,uuid),
  internal.actor_can_read_development_plan(core.development_plans),
  internal.list_development_plans_for_actor(uuid,uuid),
  internal.create_development_plan_for_actor(uuid,uuid,text,uuid,text,text,uuid),
  internal.add_development_action_for_actor(uuid,text,text,timestamptz,bigint,uuid)
  from public, anon, authenticated;
grant execute on function internal.list_development_plans_for_actor(uuid,uuid),
  internal.create_development_plan_for_actor(uuid,uuid,text,uuid,text,text,uuid),
  internal.add_development_action_for_actor(uuid,text,text,timestamptz,bigint,uuid)
  to authenticated;

create function api.list_development_plans(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.list_development_plans_for_actor(target_club_id,target_team_id)$$;
create function api.create_development_plan(target_club_id uuid,target_team_id uuid,plan_type text,
  subject_club_person_id uuid,title text,focus text,idempotency_key uuid)
returns uuid language sql security invoker set search_path='' as
$$select internal.create_development_plan_for_actor(target_club_id,target_team_id,plan_type,subject_club_person_id,title,focus,idempotency_key)$$;
create function api.add_development_action(target_plan_id uuid,title text,description text,due_at timestamptz,
  expected_plan_revision bigint,idempotency_key uuid)
returns jsonb language sql security invoker set search_path='' as
$$select internal.add_development_action_for_actor(target_plan_id,title,description,due_at,expected_plan_revision,idempotency_key)$$;

revoke all on function api.list_development_plans(uuid,uuid),
  api.create_development_plan(uuid,uuid,text,uuid,text,text,uuid),
  api.add_development_action(uuid,text,text,timestamptz,bigint,uuid)
  from public, anon;
grant execute on function api.list_development_plans(uuid,uuid),
  api.create_development_plan(uuid,uuid,text,uuid,text,text,uuid),
  api.add_development_action(uuid,text,text,timestamptz,bigint,uuid)
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260815092734_s08_development_plan_foundation','greenfield');
