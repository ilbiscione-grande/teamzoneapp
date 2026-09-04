-- AC-08: specialist responsibility, mutation contract and activation review.
-- All specialist areas and generative AI remain blocked.

create table internal.assistant_specialist_policy_registry (
  area_key text primary key references
    internal.assistant_specialist_area_registry(area_key),
  responsibility text not null check (char_length(btrim(responsibility)) > 20),
  digital_function boolean not null check (digital_function),
  generative_ai_allowed boolean not null check (not generative_ai_allowed),
  autonomous_domain_mutation_allowed boolean not null check (
    not autonomous_domain_mutation_allowed
  ),
  navigation_allowed boolean not null check (navigation_allowed),
  mutation_requires_preview boolean not null check (mutation_requires_preview),
  mutation_requires_explicit_confirmation boolean not null check (
    mutation_requires_explicit_confirmation
  ),
  mutation_requires_server_authorization boolean not null check (
    mutation_requires_server_authorization
  ),
  mutation_requires_idempotency boolean not null check (
    mutation_requires_idempotency
  ),
  mutation_requires_audit boolean not null check (mutation_requires_audit),
  prohibited_decisions text[] not null check (
    cardinality(prohibited_decisions) > 0
  ),
  registry_version bigint not null check (registry_version > 0),
  updated_at timestamptz not null default now()
);

insert into internal.assistant_specialist_policy_registry(
  area_key, responsibility, digital_function, generative_ai_allowed,
  autonomous_domain_mutation_allowed, navigation_allowed,
  mutation_requires_preview, mutation_requires_explicit_confirmation,
  mutation_requires_server_authorization, mutation_requires_idempotency,
  mutation_requires_audit, prohibited_decisions, registry_version
) values
  (
    'team_planning',
    'Förklara verifierade planeringssignaler och navigera till rätt lagvy.',
    true, false, false, true, true, true, true, true, true,
    array['select_players','change_event','record_attendance'], 1
  ),
  (
    'training_support',
    'Stödja praktisk träningsplanering från godkända lagdata.',
    true, false, false, true, true, true, true, true, true,
    array['prescribe_training','assess_medical_readiness'], 1
  ),
  (
    'individual_development',
    'Förklara godkända mål och progression utan personrangordning.',
    true, false, false, true, true, true, true, true, true,
    array['rank_people','set_goal_without_confirmation'], 1
  ),
  (
    'rehab_support',
    'Följa och påminna om en redan beslutad plan utan medicinsk bedömning.',
    true, false, false, true, true, true, true, true, true,
    array['diagnose','prescribe','rank_medical_risk','decide_return_to_play'], 1
  ),
  (
    'club_administration',
    'Förklara verifierade klubbuppgifter och navigera till ansvarig vy.',
    true, false, false, true, true, true, true, true, true,
    array['approve_membership','publish_without_confirmation'], 1
  ),
  (
    'communication',
    'Förklara relationstillåtna kommunikationsbehov utan att skicka själv.',
    true, false, false, true, true, true, true, true, true,
    array['send_message','contact_outside_relationship'], 1
  );

alter table internal.assistant_specialist_policy_registry
  add constraint rehab_support_policy_boundary check (
    area_key <> 'rehab_support' or prohibited_decisions @> array[
      'diagnose','prescribe','rank_medical_risk','decide_return_to_play'
    ]::text[]
  );

create table internal.assistant_area_activation_reviews (
  area_key text primary key references
    internal.assistant_specialist_area_registry(area_key),
  data_quality_verified boolean not null default false,
  data_owner_approved boolean not null default false,
  privacy_approved boolean not null default false,
  postgres_runtime_passed boolean not null default false,
  advisors_passed boolean not null default false,
  multi_role_matrix_passed boolean not null default false,
  physical_device_gate_passed boolean not null default false,
  incident_owner_assigned boolean not null default false,
  state text not null default 'blocked' check (state in ('blocked','ready')),
  reason text not null,
  reviewed_by uuid references core.profiles(id),
  reviewed_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  check (
    state <> 'ready' or (
      data_quality_verified and data_owner_approved and privacy_approved
      and postgres_runtime_passed and advisors_passed
      and multi_role_matrix_passed and physical_device_gate_passed
      and incident_owner_assigned and reviewed_by is not null
      and reviewed_at is not null
    )
  )
);

insert into internal.assistant_area_activation_reviews(area_key, reason)
select area.area_key,
  'Blockerad: PostgreSQL-runtime, advisors, flerrollsmatris, fysisk enhetsgrind och områdesspecifika godkännanden återstår.'
from internal.assistant_specialist_area_registry area;

create table internal.assistant_generative_ai_gate (
  gate_key text primary key check (gate_key = 'generative_ai_v1'),
  state text not null check (state = 'blocked'),
  enabled boolean not null check (not enabled),
  product_approved boolean not null default false,
  privacy_approved boolean not null default false,
  provider_approved boolean not null default false,
  region_approved boolean not null default false,
  retention_approved boolean not null default false,
  minor_data_approved boolean not null default false,
  evaluation_passed boolean not null default false,
  operations_approved boolean not null default false,
  incident_flow_approved boolean not null default false,
  reason text not null,
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);

insert into internal.assistant_generative_ai_gate(
  gate_key, state, enabled, reason
) values(
  'generative_ai_v1', 'blocked', false,
  'Separat produkt-, integritets-, leverantörs-, region-, retention-, minderårigdata-, eval-, drift- och incidentgrind saknas.'
);

create table audit.assistant_area_activation_events (
  id uuid primary key default gen_random_uuid(),
  area_key text not null,
  action text not null check (action in ('reviewed','activated','blocked')),
  actor_profile_id uuid,
  review_revision bigint not null check (review_revision > 0),
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table internal.assistant_specialist_policy_registry enable row level security;
alter table internal.assistant_area_activation_reviews enable row level security;
alter table internal.assistant_generative_ai_gate enable row level security;
alter table audit.assistant_area_activation_events enable row level security;
revoke all on table internal.assistant_specialist_policy_registry,
  internal.assistant_area_activation_reviews,
  internal.assistant_generative_ai_gate,
  audit.assistant_area_activation_events
from public, anon, authenticated;

create function internal.get_assistant_policy_contract_for_actor()
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
  return jsonb_build_object(
    'digitalFunction', true,
    'humanOrLicensedExpert', false,
    'generativeAi', (
      select jsonb_build_object(
        'state', gate.state,
        'enabled', gate.enabled,
        'reason', gate.reason
      ) from internal.assistant_generative_ai_gate gate
      where gate.gate_key = 'generative_ai_v1'
    ),
    'mutationContract', jsonb_build_object(
      'navigationAllowed', true,
      'autonomousDomainMutationAllowed', false,
      'requiresPreview', true,
      'requiresExplicitConfirmation', true,
      'requiresServerAuthorization', true,
      'requiresIdempotency', true,
      'requiresAudit', true
    ),
    'areas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'areaKey', policy.area_key,
        'responsibility', policy.responsibility,
        'prohibitedDecisions', policy.prohibited_decisions,
        'state', review.state,
        'activationAllowed',
          area.gate_state = 'active' and review.state = 'ready',
        'reason', review.reason,
        'registryVersion', policy.registry_version
      ) order by policy.area_key)
      from internal.assistant_specialist_policy_registry policy
      join internal.assistant_specialist_area_registry area
        on area.area_key = policy.area_key
      join internal.assistant_area_activation_reviews review
        on review.area_key = policy.area_key
    ), '[]'::jsonb)
  );
end;
$$;

create function api.get_assistant_policy_contract()
returns jsonb language sql stable security invoker set search_path = ''
as $$select internal.get_assistant_policy_contract_for_actor()$$;

revoke all on function internal.get_assistant_policy_contract_for_actor(),
  api.get_assistant_policy_contract()
from public, anon, authenticated;
grant execute on function internal.get_assistant_policy_contract_for_actor(),
  api.get_assistant_policy_contract()
to authenticated;

insert into internal.migration_provenance(
  migration_name, source_kind, source_reference
) values(
  '20260828164402_ac08_specialist_policy_activation_gate',
  'greenfield',
  'AC-08 digital-function responsibility, rehab boundary and per-area fail-closed activation review'
);

notify pgrst, 'reload schema';
