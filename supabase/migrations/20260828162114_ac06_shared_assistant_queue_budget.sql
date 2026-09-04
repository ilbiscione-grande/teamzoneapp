-- AC-06: one cross-area queue and one notification budget. This migration
-- does not activate assistant areas or emit notifications.

alter table internal.assistant_signal_registry
  add column canonical_family text not null default 'event'
    check (canonical_family ~ '^[a-z][a-z0-9_]{2,63}$'),
  add column canonical_scope text not null default 'source'
    check (canonical_scope in ('source','team')),
  add column global_priority integer not null default 30
    check (global_priority between 1 and 100),
  add column default_delivery text not null default 'in_assistant'
    check (default_delivery in ('direct','digest','in_assistant','off'));

update internal.assistant_signal_registry
set global_priority = case signal_key
    when 'event.missing_attendance' then 10
    when 'event.near_without_participants' then 15
    when 'callup.unanswered' then 20
    when 'calendar.future_gap' then 30
    when 'event.responses_complete' then 40
    else 50
  end,
  default_delivery = case signal_key
    when 'event.missing_attendance' then 'direct'
    when 'event.responses_complete' then 'digest'
    when 'calendar.future_gap' then 'in_assistant'
    else 'digest'
  end;

update internal.assistant_signal_registry
set canonical_family = 'planning_gap', canonical_scope = 'team'
where signal_key = 'calendar.future_gap';

create table internal.assistant_notification_budget_policy (
  policy_key text primary key,
  supported_modes text[] not null check (
    supported_modes = array['direct','digest','in_assistant','off']::text[]
  ),
  direct_limit_per_24h integer not null check (direct_limit_per_24h >= 0),
  digest_limit_per_24h integer not null check (digest_limit_per_24h >= 0),
  positive_default text not null check (positive_default = 'digest'),
  system_messages_excluded boolean not null check (system_messages_excluded),
  registry_version bigint not null check (registry_version > 0),
  updated_at timestamptz not null default now()
);

insert into internal.assistant_notification_budget_policy(
  policy_key, supported_modes, direct_limit_per_24h,
  digest_limit_per_24h, positive_default, system_messages_excluded,
  registry_version
) values(
  'shared_v1', array['direct','digest','in_assistant','off'],
  3, 1, 'digest', true, 1
);

alter table internal.assistant_notification_budget_policy
  enable row level security;
revoke all on table internal.assistant_notification_budget_policy
  from public, anon, authenticated;

create or replace function internal.list_assistant_signals_for_actor(
  target_club_id uuid,
  target_team_id uuid,
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
  gate_value jsonb;
  items jsonb;
  budget jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'not_found';
  end if;
  gate_value := internal.get_assistant_data_gate_for_actor(
    target_club_id, target_team_id
  );

  select coalesce(jsonb_agg(
    winner.payload order by winner.global_priority,
    winner.observed_at desc, winner.signal_key, winner.source_id
  ), '[]'::jsonb)
  into items
  from (
    select distinct on (candidate.canonical_key)
      candidate.payload,
      candidate.canonical_key,
      candidate.global_priority,
      candidate.observed_at,
      candidate.signal_key,
      candidate.source_id
    from (
      select
        signal->>'signalKey' as signal_key,
        signal->>'sourceId' as source_id,
        (signal->>'observedAt')::timestamptz as observed_at,
        registry.global_priority,
        case registry.canonical_scope
          when 'team' then registry.canonical_family || ':' || target_team_id::text
          else registry.canonical_family || ':' || signal->>'sourceId'
        end as canonical_key,
        signal || jsonb_build_object(
          'canonicalKey', case registry.canonical_scope
            when 'team' then registry.canonical_family || ':' || target_team_id::text
            else registry.canonical_family || ':' || signal->>'sourceId'
          end,
          'primaryAreaKey', registry.primary_area_key,
          'priority', registry.global_priority,
          'defaultDeliveryMode', registry.default_delivery,
          'deliveryMode', case
            when area.gate_state = 'active' then registry.default_delivery
            else 'off'
          end,
          'area', jsonb_build_object(
            'key', area.area_key,
            'label', area.label,
            'iconToken', area.icon_token,
            'designToken', area.design_token
          ),
          'dismissed', coalesce(receipt.state = 'dismissed', false),
          'dismissedAt', receipt.dismissed_at,
          'receiptRevision', receipt.revision,
          'actionContract', jsonb_build_object(
            'kind', 'navigate',
            'requiresExplicitUserAction', true,
            'performsDomainMutation', false
          )
        ) as payload
      from jsonb_array_elements(
        coalesce(gate_value->'signals', '[]'::jsonb)
      ) signal
      join internal.assistant_signal_registry registry
        on registry.signal_key = signal->>'signalKey'
      join internal.assistant_specialist_area_registry area
        on area.area_key = registry.primary_area_key
      left join internal.assistant_signal_receipts receipt
        on receipt.profile_id = actor_id
        and receipt.club_id = target_club_id
        and receipt.team_id = target_team_id
        and receipt.signal_key = signal->>'signalKey'
        and receipt.source_id = (signal->>'sourceId')::uuid
      where coalesce((signal->>'authorized')::boolean, false)
        and (
          include_dismissed
          or coalesce(receipt.state, 'visible') <> 'dismissed'
        )
    ) candidate
    order by candidate.canonical_key, candidate.global_priority,
      candidate.observed_at desc, candidate.signal_key, candidate.source_id
  ) winner;

  select jsonb_build_object(
    'key', policy.policy_key,
    'supportedModes', policy.supported_modes,
    'directLimitPer24Hours', policy.direct_limit_per_24h,
    'digestLimitPer24Hours', policy.digest_limit_per_24h,
    'positiveDefault', policy.positive_default,
    'systemMessagesExcluded', policy.system_messages_excluded,
    'registryVersion', policy.registry_version
  ) into budget
  from internal.assistant_notification_budget_policy policy
  where policy.policy_key = 'shared_v1';

  return jsonb_set(gate_value, '{signals}', items, true)
    || jsonb_build_object(
      'queueContract', jsonb_build_object(
        'scope', 'shared_cross_area',
        'deduplication', 'canonical_key_deterministic_winner',
        'separateSpecialistQueues', false,
        'budget', budget
      ),
      'presentationContract', jsonb_build_object(
        'summaryKind', 'deterministic',
        'riskScore', false,
        'medicalInference', false,
        'personComparison', false,
        'generativeAi', false,
        'domainMutation', false
      )
    );
end;
$$;

revoke all on function internal.list_assistant_signals_for_actor(
  uuid, uuid, boolean
) from public, anon, authenticated;
grant execute on function internal.list_assistant_signals_for_actor(
  uuid, uuid, boolean
) to authenticated;

insert into internal.migration_provenance(
  migration_name, source_kind, source_reference
) values(
  '20260828162114_ac06_shared_assistant_queue_budget',
  'greenfield',
  'AC-06 one canonical cross-area queue and shared notification budget; delivery remains fail-closed'
);

notify pgrst, 'reload schema';
