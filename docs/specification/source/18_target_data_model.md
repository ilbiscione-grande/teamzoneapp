# Steg 2B – mål-datamodell

**Status: logisk v1-modell produktgodkänd 2026-08-07. Detta är inte DDL eller migrationsgodkännande.**

## Schemastrategi

| Schema | Syfte | Data API |
|---|---|---|
| `core` | Kanoniska tenant-/domänfacts med RLS som defense in depth | Inte direkt exponerat |
| `audit` | Append-only command/audit/history | Inte exponerat |
| `internal` | authorizationhelpers, outbox, provider inbox, jobs | Inte exponerat |
| `api` | Authenticated queries/commands och security-invoker projections | Explicit exponerat |
| `public_api` | Minimal allowlistad anonprojektion | Explicit exponerat |
| `auth`, `storage` | Supabase-ägda systemtabeller | Enligt plattformskontrakt |

`anon` får inga grants mot `core`. `authenticated` får inga INSERT/UPDATE/DELETE-grants; minsta SELECT kan ges på enskilda RLS-skyddade bastabeller när en `security_invoker`-view i `api` kräver anroparens underliggande rättigheter. `core` exponeras aldrig som Data API-schema. Vanliga läsningar sker genom scopeade `api`-queries/projections och mutationer genom commands. Om implementationen tillfälligt måste ligga i `public` gäller samma grants/RLS och en dokumenterad avvecklingsplan.

Alla tenanttabeller har `id uuid`, `club_id uuid`, `created_at timestamptz`, `created_by uuid` och vid mutation `revision bigint`. Soft lifecycle använder explicit status/`ended_at`, inte generisk `deleted` utan domänsemantik.

## Identity, club och roster

| Tabell | Kritiska fält | Constraints/index |
|---|---|---|
| `core.profiles` | `id = auth.users.id`, display/locale/timezone | PK/FK auth; ingen authorization i user metadata |
| `core.clubs` | name, slug, status, default_timezone | unik normaliserad slug; status allowlist |
| `core.teams` | club_id, name, age_class, season_id, status | unik aktiv identitet inom klubb; `(id,club_id)` unik |
| `core.club_people` | club_id, display_name, birth_date_class, status, provenance | `(id,club_id)`; PII-fält dataklassas |
| `core.person_account_links` | club_person_id, profile_id, state, verified_at, ended_at | högst en active link/person; claim audit |
| `core.assignments` | club_id, team_id nullable, club_person_id, role_package, starts_at, ends_at, state | scope matchar person/teamklubb; temporal overlap-regel per roll |
| `core.capability_grants` | assignment_id/mandate_id, capability, scope_type, scope_id, starts/ends | capability allowlist; scope belongs to club |
| `core.guardian_relations` | guardian_person_id, child_person_id, kind, state, starts/ends | samma klubb; guardian ≠ child; temporal |
| `core.play_eligibilities` | person_id, team_id, kind(home/loan/guest/cross-team), starts/ends, source | samma klubb eller explicit cross-club agreement |
| `core.transfer_cases` | person_id, source_club/team, target_club/team, state, revisions | source/target approval facts; completed unik |
| `audit.transfer_approvals` | case_id, side, actor, decision, reason, at | append-only; unik active decision per side/revision |

Birth date exponeras inte som generell rosterkolumn; projektioner returnerar endast det minsta som behövs, exempelvis åldersklass eller safeguardingflagga.

## Event, squad, callup och attendance

| Tabell | Kritiska fält | Constraints/index |
|---|---|---|
| `core.recurrence_rules` | club_id, timezone, rule, local_start, until/count | validerad rule och timezone |
| `core.events` | club_id, owning_team_id, recurrence_id, occurrence_key, type, state, starts/ends, all_day, timezone, location | end>start; unik occurrence; owner team matchar club |
| `core.event_teams` | event_id, team_id, relation(primary/shared), capability_profile | samma club; exakt en primary |
| `core.event_audiences` | event_id, audience_type, team/person/group id | mål matchar eventscope; påverkar inte edit auth |
| `core.event_revisions` | event_id, revision, snapshot, actor, reason | append-only unik revision |
| `core.squad_revisions` | event_id, revision, state, eligibility_version, created_by | en active draft/locked revision per event |
| `core.squad_members` | squad_revision_id, person_id, eligibility_id, selection_state, source | unik person/revision; eligibility giltig vid event |
| `core.callups` | event_id, squad_revision_id, person_id, state, sent_at, expires_at | unik aktiv callup/person/event; endast locked/sent squad |
| `core.callup_responses` | callup_id, response, actor_profile_id, acting_as_person_id, revision | append-only/revisionerad; guardianrelation verifierad |
| `core.attendance_facts` | event_id, person_id, status, minutes/late fields, actor, revision | status allowlist; unik aktuell projektion + historik |

## Messaging, notification och filer

| Tabell | Kritiska fält | Constraints/index |
|---|---|---|
| `core.message_threads` | club_id nullable only for controlled cross-club request, type, state, subject | scopevariant constraint |
| `core.thread_scopes` | thread_id, club/team/event id, scope_role | exakt tillåten scopekombination |
| `core.thread_participants` | thread_id, profile/person, role, state, joined/left | recipient måste härledas från samma scope |
| `core.messages` | thread_id, sender_profile, acting_as_person nullable, body, revision, state | sender active participant + send capability |
| `audit.message_versions` | message_id, revision, body_hash/snapshot, actor, action | append-only enligt retentionklass |
| `core.message_reads` | thread/message, profile_id, read_at, device_revision | unik monotonic marker |
| `core.thread_mutes` | thread_id, profile_id, muted_until | fail-closed preference query |
| `core.contact_controls` | requester/target, state(block/report/request), expires | cross-club request/rate-limit input |
| `internal.notification_outbox` | event_type, aggregate, payload_ref, recipient_rule, state | unik domain event/idempotency |
| `internal.delivery_attempts` | outbox_id, channel, endpoint, attempt, state, provider_ref | inget rått tokenvärde i logg/audit |
| `core.device_endpoints` | profile_id, token_cipher/ref, platform, state, last_seen | unik aktiv tokenhash; owner-only lifecycle |
| `core.file_objects` | club_id, owner_type/id, bucket, object_key, visibility, retention_class, state | unik object key; owner/clubbinding |

Storage paths är opaka och får inte vara enda accesskontroll. Policy slår upp `file_objects` och kräver samma owner-/tenantregel som metadata. Public media kopieras/projiceras explicit; privat objekt görs aldrig publikt genom URL-gissning.

## Match, development och signaler

| Tabell | Kritiska fält | Constraints/index |
|---|---|---|
| `audit.match_commands` | event_id, command_id, expected_revision, type, actor, payload, result_revision | unik command/idempotency; append-only |
| `core.match_facts` | event_id, fact_id, type, match_time, person/team, source_command, state | void/revision, aldrig hard-delete |
| `core.match_projections` | event_id, revision, score/stats JSON | härledbar från aktiva facts |
| `core.development_plans` | club/person/team, type, state, revision | scopevariant constraint |
| `core.development_actions` | plan_id, goal/focus, due/status, actor | revisionerad |
| `core.check_ins` | person_id, event_id, value, visibility_class | avstängd tills PAR-PRIV-04 |
| `core.signal_definitions` | key, version, semantic_class, inputs, thresholds, active | versionerad/metodgodkänd |
| `core.signal_facts` | definition/version, subject, window, value, provenance, stale_at | reproducerbar; ingen medicinsk etikett utan godkännande |
| `core.injury_clearances` | person, restriction/state, valid_from/to, actor, reason | känsligt scope; manuell behörig transition |
| `core.suspensions` | person, competition/scope, remaining, state | decrement endast explicit eligible eventfact |

Match v2:s verifierade kommandomodell bevaras. Namn kan mappas under migrering men semantiken och regressionstesterna får inte försvagas.

## Publication, billing, economy och integration

| Tabell | Kritiska fält | Constraints/index |
|---|---|---|
| `core.publication_settings` | club/team, visibility, revision | private default |
| `core.consents` | subject, purpose, data_classes, grantor, starts/ends, state | purpose-bound; withdraw auditeras |
| `core.publications` | source_type/id/revision, projection_version, state, published/withdrawn | giltigt consent/policy krävs |
| `public_api.club/team/event/media_projection` | endast allowlistade public fields | separat projektionstabell byggd av intern publisher, eller security-invoker-view över anon-läsbara RLS-källor; aldrig privilegierad materialized view direkt över intern PII |
| `internal.provider_events` | provider, external_event_id, signature_state, payload_hash/ref, received/processed | unik provider event; råpayload skyddad/retained |
| `core.billing_customers` | club_id, provider_customer_ref | unik per club/provider |
| `core.subscriptions` | club_id, provider ref, plan/version, state, provider_revision, period | en kanonisk aktiv subscriptionkälla |
| `core.entitlements` | club_id, feature/module, state, source_subscription, valid_to | härledd; unik feature/club |
| `core.ledger_entries` | club_id, team_id nullable, amount_minor, currency, type, effective_at, actor | append-only; reversal_ref; currency match |
| `core.fee_obligations` | person, amount_minor, currency, due, state | payment/reminder separata facts |
| `core.sponsor_pledges` | campaign, terms_snapshot, cap, state | settlement idempotent |
| `core.mandates` | person, capability, amount_limit, starts/ends | board title ger ingen implicit superaccess |
| `audit.approvals` | command_ref, actor, decision, reason, at | olika actors vid dual control |
| `core.integration_links` | local club, remote system/tenant, state, scopes, consent revision | explicit/revocable; unik active link |
| `core.external_refs` | owner_system, object_type, local/external id, version | unik per owner/object |
| `internal.sync_attempts` | link, object, direction, idempotency, state/error_code | retry/provenance; sanerat fel |

## Datatyper och constraints

- Pengar: `bigint amount_minor` + ISO-valuta, aldrig float.
- Revisioner: positiv `bigint`, ökas atomiskt.
- Status/capability/type: lookup/check med explicit okändhantering; fri klienttext tillåts inte.
- JSON används för versionsbundna snapshots/payloads, inte för relationer som måste FK-valideras.
- Indirekta relationer använder sammansatta unika nycklar/FK som `(id, club_id)` och vid behov `(id, event_id)`.
- Alla externa/provider-ID:n namespaceras och har unika index.
- Audit/outbox-tabeller partitioneras först när volymdata motiverar det; retention ska vara verifierad före partitiondrop.

## Legacy mapping som måste bevisas

| Nuläge | Mål | Regel |
|---|---|---|
| `members` | `club_people` + account links | ingen automatisk cross-club merge utan verifiering |
| `team_memberships`, `club_members`, playable teams | assignments + eligibilities | temporala intervall och rollmapping |
| preliminary/group/generated squadvägar | squad revisions/members | en kanonisk write path |
| `subscriptions`, `club_plans`, module/webtool subscriptions | subscription + entitlements | provider source och klubbomfattande modul |
| message/storagetabeller | scoped thread/file lifecycle | recipient- och objectbinding före cutover |
| fund/fee/sponsor-tabeller | ledger/obligation/pledge | bevara historik; härled öppningsbalans med audit |
