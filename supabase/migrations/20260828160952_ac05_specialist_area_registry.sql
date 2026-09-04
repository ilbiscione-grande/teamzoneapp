-- AC-05: versioned specialist-area policy registry. Registration does not
-- activate signal delivery, automated actions or generative processing.

create table internal.assistant_specialist_area_registry (
  area_key text primary key check (area_key ~ '^[a-z][a-z0-9_]{2,63}$'),
  label text not null check (char_length(btrim(label)) between 2 and 60),
  icon_token text not null,
  design_token text not null,
  source_keys text[] not null check (cardinality(source_keys) > 0),
  capabilities text[] not null check (cardinality(capabilities) > 0),
  target_roles text[] not null check (cardinality(target_roles) > 0),
  presentation_fields text[] not null check (
    cardinality(presentation_fields) > 0
  ),
  allowed_actions text[] not null,
  gate_state text not null check (
    gate_state in ('pending_verification', 'blocked', 'active')
  ),
  gate_reason text not null,
  registry_version bigint not null check (registry_version > 0),
  updated_at timestamptz not null default now(),
  check (gate_state <> 'active')
);

insert into internal.assistant_specialist_area_registry (
  area_key, label, icon_token, design_token, source_keys, capabilities,
  target_roles, presentation_fields, allowed_actions, gate_state,
  gate_reason, registry_version
) values
  (
    'team_planning', 'Lagplanering', 'strategy', 'assistant.area.blue',
    array['core.events','core.squad_revisions','core.callups','core.attendance_facts'],
    array['event.manage','event.squad.manage','event.attendance.manage'],
    array['leader'],
    array['context','source','observed_at','fresh_until','explanation'],
    array['navigate.calendar','navigate.event'], 'pending_verification',
    'AC-01 runtime, freshness och fysisk flerrollsverifiering återstår.', 1
  ),
  (
    'training_support', 'Träningsstöd', 'training', 'assistant.area.green',
    array['core.events','core.attendance_facts'],
    array['event.manage','event.attendance.manage'], array['leader'],
    array['context','source','fresh_until','explanation'],
    array['navigate.calendar'], 'blocked',
    'Separat data- och integritetsgrind saknas.', 1
  ),
  (
    'individual_development', 'Individuell utveckling', 'development',
    'assistant.area.purple',
    array['core.development_plans','core.development_actions'],
    array['development.manage','development.self.view'],
    array['leader','player','guardian'],
    array['context','subject','source','fresh_until','explanation'],
    array['navigate.development'], 'blocked',
    'Person-, samtyckes- och datakvalitetsgrind saknas.', 1
  ),
  (
    'rehab_support', 'Rehabstöd', 'recovery', 'assistant.area.teal',
    array['approved_rehab_plan'], array['rehab.plan.view'],
    array['player','guardian','leader'],
    array['context','subject','approved_plan_source','fresh_until','explanation'],
    array['navigate.approved_rehab_plan'], 'blocked',
    'LATER-04 och separat hälso-/ansvarsgrind saknas; inga medicinska beslut.', 1
  ),
  (
    'club_administration', 'Klubbadministration', 'club',
    'assistant.area.orange',
    array['core.clubs','core.club_people','core.team_assignments','core.membership_applications','core.editorial_articles'],
    array['club.memberships.manage','publication.manage'],
    array['club_functionary','leader'],
    array['context','source','fresh_until','explanation'],
    array['navigate.club','navigate.publication'], 'blocked',
    'Separat klubbdata- och capabilitygrind saknas.', 1
  ),
  (
    'communication', 'Kommunikation', 'message', 'assistant.area.cyan',
    array['core.message_threads','core.messages'],
    array['message.thread.view','message.send'],
    array['club_functionary','leader','player','guardian'],
    array['context','source','fresh_until','explanation'],
    array['navigate.inbox','navigate.thread'], 'blocked',
    'Separat relations-, notifierings- och integritetsgrind saknas.', 1
  );

alter table internal.assistant_specialist_area_registry
  enable row level security;
revoke all on table internal.assistant_specialist_area_registry
  from public, anon, authenticated;

alter table internal.assistant_signal_registry
  add column primary_area_key text not null default 'team_planning'
  references internal.assistant_specialist_area_registry(area_key),
  add column area_registry_version bigint not null default 1
  check (area_registry_version > 0);

create function internal.list_assistant_specialist_areas_for_actor()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'key', area.area_key,
      'label', area.label,
      'iconToken', area.icon_token,
      'designToken', area.design_token,
      'sourceKeys', area.source_keys,
      'capabilities', area.capabilities,
      'targetRoles', area.target_roles,
      'presentationFields', area.presentation_fields,
      'actions', area.allowed_actions,
      'gateState', area.gate_state,
      'registryVersion', area.registry_version,
      'active', area.gate_state = 'active'
    ) order by area.area_key)
    from internal.assistant_specialist_area_registry area
  ), '[]'::jsonb);
end;
$$;

create function api.list_assistant_specialist_areas()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$select internal.list_assistant_specialist_areas_for_actor()$$;

revoke all on function internal.list_assistant_specialist_areas_for_actor(),
  api.list_assistant_specialist_areas()
from public, anon, authenticated;
grant execute on function internal.list_assistant_specialist_areas_for_actor(),
  api.list_assistant_specialist_areas()
to authenticated;

insert into internal.migration_provenance(
  migration_name, source_kind, source_reference
) values(
  '20260828160952_ac05_specialist_area_registry',
  'greenfield',
  'AC-05 versioned specialist policy registry; all areas remain fail-closed'
);

notify pgrst, 'reload schema';
