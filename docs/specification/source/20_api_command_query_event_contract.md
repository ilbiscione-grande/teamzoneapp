# Steg 2D – API-, command-, query- och eventkontrakt

**Status: v1-kontrakt produktgodkänt 2026-08-07. Exakta SQL-signaturer/OpenAPI genereras i implementationen.**

## Gemensamt kontrakt

Authenticated app använder `api` och publik webb `public_api`. Klienten skickar `request_id`; mutationer skickar `idempotency_key` och revisionsskyddade commands `expected_revision`.

Success envelope:

```json
{"data":{},"meta":{"request_id":"uuid","revision":12,"server_time":"timestamp"}}
```

Error envelope:

```json
{"error":{"code":"stale_revision","message_key":"errors.stale_revision","request_id":"uuid","retryable":false}}
```

Tillåtna felkoder inkluderar `unauthenticated`, `forbidden`, `not_found`, `invalid_input`, `invalid_transition`, `stale_revision`, `conflict`, `rate_limited`, `entitlement_required`, `temporarily_unavailable`. `not_found` används när existens annars skulle läcka främmande objekt. Rå SQL/providertext returneras aldrig.

Listqueries använder stabil cursor, maxlimit och deterministisk sort. Timestamps är UTC ISO-8601; lokal timezone/all-day följer eventfält. Alla payloads har versionsnummer när de sparas eller skickas externt.

## Identity och roster

| API | Typ | Huvudkontrakt |
|---|---|---|
| `get_my_contexts()` | Query | Härleder alla läscontexts/capabilities; ingen synthetic override som döljer direkt relation |
| `get_profile()` | Query | Minimal global profil + preferences |
| `list_club_people(club,cursor,filter)` | Query | Capabilityscopead rosterprojektion |
| `claim_club_person(token,key)` | Command | Atomisk tokenconsume + account link; conflict vid redan claimad |
| `create_assignment(target,role,period,key)` | Command | Capability/tenant/period/rolemapping verifieras |
| `end_assignment(id,expected,key)` | Command | Avslutar relation, aldrig profile/personhistorik |
| `set_guardian_relation(...)` | Command | Safeguarding/dual-control enligt policy |
| `request_transfer(...)`, `decide_transfer(...)`, `complete_transfer(...)` | Commands | Källa/mål godkänner; completion skapar nya temporala facts atomiskt |

## Event, squad och callup

| API | Typ | Huvudkontrakt |
|---|---|---|
| `list_calendar(contexts,from,to,cursor)` | Query | Multi-context, deduplicerad, visibilityscopead |
| `get_event_details(event)` | Query | Info + caller actions + revision; aldrig authorization från UI actions |
| `create_event(draft,key)` | Command | Owner team/club/time/audience binds server-side |
| `revise_event(event,scope,patch,expected,key)` | Command | one/forward/all; atomisk recurrence och outbox |
| `transition_event(event,to,expected,reason,key)` | Command | Explicit cancel/complete/reopen transition |
| `save_squad_draft(event,members,expected,key)` | Command | Exakt eligibilitykontroll och ny revision |
| `lock_squad(event,expected,key)` | Command | Snapshotar eligibility; stale/invalid members nekas |
| `send_callups(squad_revision,expiry,key)` | Command | Skapar callups + outbox en gång |
| `respond_callup(callup,response,acting_as,expected,key)` | Command | Subject/guardian/token scope verifieras |
| `record_attendance(event,changes,expected,key)` | Command | Bulk all-or-nothing, explicit unknown/absent |

Generator, grupp och “alla” är inputs till `save_squad_draft`, aldrig alternativa callupmutatorer.

## Messaging och notifications

| API | Typ | Huvudkontrakt |
|---|---|---|
| `list_threads`, `get_thread`, `list_messages` | Queries | Endast aktiv participant/threadscope; cursor/revision |
| `resolve_allowed_recipients(scope,query)` | Query | Samma authhelper som create/add/send; inga godtyckliga thread-ID:n |
| `request_cross_club_contact(target_leader,key)` | Command | Aktiv verifierad ledare, rate limit, block/report |
| `decide_contact_request(request,decision,key)` | Command | Endast target; accept skapar active direct thread |
| `create_thread(scope,participants,key)` | Command | Servern räknar exakt tillåten recipientmängd |
| `send_message(thread,body,staged_files,key)` | Command | Participant/sendaccess, retention class, outbox atomiskt |
| `revise_or_recall_message(message,expected,key)` | Command | Tids-/policyfönster; auditversion bevaras |
| `mark_read(thread,through_revision,key)` | Command | Monoton marker per profile/device |
| `set_thread_mute(thread,state,key)` | Command | Owner-only; notification query fail-closed |
| `register_device_endpoint`, `revoke_device_endpoint` | Commands | Caller own endpoint; tokenhash unik |

## Match och development

- Befintlig v2 `apply_match_command`-semantik fortsätter som enda matchwrite: idempotency, state, revision, actor och append-only commandlogg.
- Queries: `get_match_projection(event,since_revision)`, `list_player_stats(subject,scope,period)` och `resync_match(event,revision)`.
- Commands: `save_development_plan`, `record_check_in`, `set_injury_clearance`, `apply_suspension_event`, `dismiss_watchpoint` med capability, provenance och expected revision.
- Query `list_signals(context,as_of)` returnerar definition/version, input window, stale status och semantic class. Ingen signalaction muterar utan ett separat vanligt domäncommand.

## Publication, billing, economy och integrations

| API | Typ | Huvudkontrakt |
|---|---|---|
| `set_publication_settings`, `grant/withdraw_consent`, `publish/withdraw` | Commands | Privacy default, revision/audit, projection rebuild/invalidation |
| `public_api.list_clubs/get_team/get_event` | Anon queries | Endast allowlistad projektion, rate/maxlimit/enumerationsskydd |
| `public_api.submit_contact` | Anon command | Abuse token, dedupe, fixed retention, inget account discovery |
| `create_checkout_session` | Server function | Caller club billing capability; server pricebook lookup |
| `ingest_provider_event` | Webhook | Signatur, providerrevision, idempotens, subscription/entitlement transaction |
| `get_entitlements(club)` | Query | Serverhärledd status och read-only/grace metadata |
| `post_ledger_entry`, `reverse_ledger_entry` | Commands | Money minor units, mandate, reason, immutable history |
| `approve_high_risk_command` | Command | Annan behörig actor, samma command revision |
| `create_fee_run`, `record_fee_payment`, `settle_pledge` | Commands | Idempotenta obligations-/settlementfacts |
| `create/revoke_integration_link` | Commands | Explicit scopes/consent; revoke stoppar ny sync |
| `push/pull_integration_object` | Commands/queries | owner system, external id/version, idempotent sync |

## Domain events och outbox

Eventnamn använder `<domain>.<aggregate>.<past-tense>.v1`, exempelvis:

- `roster.assignment.activated.v1`;
- `event.event.revised.v1`;
- `callup.callup.sent.v1`, `callup.response.recorded.v1`;
- `message.message.sent.v1`;
- `match.command.applied.v2`;
- `billing.entitlement.changed.v1`;
- `publication.projection.withdrawn.v1`.

Envelope innehåller `event_id`, `type`, `occurred_at`, `aggregate_type/id`, `aggregate_revision`, `club_id`, `actor_profile_id` där tillåtet, `correlation_id`, `causation_id`, `schema_version` och en dataminimerad payload/ref. Consumer deduplicerar `event_id`, accepterar out-of-order enligt aggregate revision och flyttar permanenta fel till synlig dead-letter-state.

## Realtime och resync

- Klient subscribar på scopead, minimal invalidation/projection – aldrig breda bastabeller.
- Meddelande innehåller aggregate ID + revision, inte känslig full payload om query krävs.
- Gap, reconnect, app resume och auth refresh anropar `sync_<domain>(context,since_cursor)`.
- Cursor är opaque, monotonic inom scope och kan svara `full_resync_required`.
- UI markerar stale/pending tills serverquery bekräftar revisionen.

## Versionering och deprecation

- Additiv förändring inom v1; borttag/semantikbyte kräver v2.
- Gamla/nnya queryfält samexisterar under PAR-API-02:s compatibilityfönster.
- Command semantics ändras aldrig tyst; ny command/version används.
- API-dokumentation genereras från faktiska signaturer och kontrakttestas mot Flutter, Next.js, Edge Functions och web tools.
- OpenAPI hämtas inte anonymt från produktion. Sedan 2026 års Supabaseändring genererar CI kontrakt från lokal/auditerad schemaartefakt eller autentiserad management-/toolingväg.
