# Steg 2E – migration, compatibility och verifiering

**Status: genomförandekontrakt produktgodkänt 2026-08-07. Ingen migration har skapats eller körts.**

## Strategi

Rebuilden migreras additivt per vertikal slice. Repositorymigrationer är enda deploybara schemahistorik. Ingen destruktiv rename/drop eller write-cutover görs i samma release som första backfill.

| Fas | Innehåll | Exitgrind |
|---|---|---|
| 0 Baseline | Live fingerprint, Postgresversion, exponerade schemas, default/object grants, migration list, datavolym, null/orphan/duplicateprofil | Evidens sparad; inga okända driftobjekt |
| 1 Expand | Nya schemas/tabeller/constraints `NOT VALID`, API v1, feature flag av | Tom replay + gamla klienter passerar |
| 2 Backfill | Deterministisk, återstartbar mapping med provenance/checkpoint | Count/hash/relation reconciliation utan orphan |
| 3 Shadow | Nya writes via command; projection/dual-read comparison, inte fri dual-write | Skillnader mätbara och noll inom godkänd tolerans |
| 4 Cutover | Cohort läser/skriver nya kontrakt; legacywrite blockeras domänvis | JWT/tenant/smoke/rollback test passerar |
| 5 Contract | Legacy API/grants/tabeller arkiveras eller droppas senare | Ingen observerad trafik, retention/export och godkännande |

Dual-write används endast inne i ett servercommand med en transaktion och tydlig source of truth. Klienten får aldrig skriva två modeller.

## Sliceordning

1. Identity, club person, assignment, guardian och context.
2. Club/team/roster/invite/claim/transfer.
3. Event/recurrence/audience/location.
4. Squad/callup/response/attendance + notification outbox.
5. Fem huvudytors query projections.
6. Messaging/file lifecycle/notification center.
7. Match v2-adapter utan semantisk regression.
8. Development/signals/Assistant Coach regelmotor.
9. Publication/public API.
10. Billing/entitlements och därefter economy.
11. Workspaces och webtoolintegrationer.

## Legacyregister

Varje gammalt objekt får: domain owner, målobjekt, read consumers, write consumers, backfillregel, discrepancy query, write-stop release, read-stop release, retention/dropbeslut och rollbackväg. Minst följande grupper registreras:

- `members`, `team_memberships`, `club_members`, `guardian_relations`, `member_playable_teams`;
- event/shared/recurrence/preliminary/group/generated squad/callup-tabeller;
- message participant/read/mute/settings och Storage buckets/policies;
- matchplan/events/stats samt bevarad v2 commandlogg;
- development/workload/injury/suspension/watchpoint-tabeller;
- `subscriptions`, `club_plans`, module/webtool subscriptions;
- team/club funds, fees, sponsorship och boardtabeller;
- public team/news/contactprojektioner och anon-RPC:er.

## Backfillregler

- Varje outputrad sparar `migration_run_id`, legacy source/id och mappingversion i intern provenance eller separat mapptabell.
- Körning är batchad, idempotent och återupptas från checkpoint.
- Ambiguous personlink, roll, tenant eller consent gissas inte; raden hamnar i exception queue och hålls privat/inaktiv.
- Historiska event/match/ledgerfacts behåller ursprunglig representation och timestamp.
- Öppningsbalanser markeras som importerade facts med underlagsreferens; de blir inte fabricerade transaktioner.
- Tokens/secrets flyttas inte i rå form om rotation/ny claim är säkrare.

## Compatibility och rollback

- Schema och queries expanderas additivt; gammal och ny signerad klient stöds under beslutat fönster.
- Feature flag har environment, club/cohort, owner, expiry och kill switch.
- Rollback stänger ny route/write path men tar inte bort redan kompatibelt schema.
- När ny write skapat facts måste roll-forward/replay vara primär återhämtning; data kastas inte bort för att återgå till gammal klient.
- Legacy API-nycklar stängs först efter verifierad Auth/Data/Storage/Realtime/Function-trafik på nya nycklar enligt PAR-OPS-03.

## Verifieringspyramid

| Lager | Obligatoriskt bevis |
|---|---|
| SQL unit | constraints, helpersemantik, transitions, idempotency |
| JWT integration | operation × roll × tenant × state, inklusive anon/expired/revoked |
| Migration | tom replay, live-lik upgrade, återkörning, rollback/roll-forward |
| Reconciliation | row counts, nyckelsummor, referential/orphan, domain totals |
| Storage | owner/participant/cross-tenant/public withdraw/orphan lifecycle |
| Edge/webhook | signature, caller/payloadbinding, duplicate/out-of-order/partial failure |
| Client contract | Flutter/Next schema, error mapping, offline/reconnect/deep links |
| Release | advisors, lint/analyze/tests, secret/log scan, smoke, telemetry och traffic |

Security Advisor granskas även för avsiktligt exponerade definerfunktioner, mutable `search_path`, extensions i `public`, Auth-skydd och RLS utan policy. Varningar får inte massaccepteras; varje undantag kräver owner, hotmodell och evidens.

Nekade tester verifierar att ingen rad, revision, audit, outbox eller fil ändrades. Advisors är en grind men ersätter inte semantiska JWT-tester.

## Domänspecifika acceptanskriterier

| Domän | Måste bevisas före cutover |
|---|---|
| Identity | okänd roll fail-closed; multi-context; claim race; ended assignment |
| Roster | source/target transfer; cross-club/person mismatch; historik bevarad |
| Event | DST/all-day/overnight; recurrence scope; shared edit/audience separerade |
| Squad/callup | eligibility snapshot; stale revision; guardian acting-as; partial push |
| Messaging | recipient=query=create=send-scope; cross-club request; mute fail-closed |
| Match | samtliga befintliga v2 command/state/idempotency/revision regressioner |
| Publication | minor private default; consent withdrawal; cache invalidation; enumeration |
| Billing | signed duplicate/out-of-order webhook; unknown entitlement; grace/read-only |
| Economy | immutable ledger/reversal; currency; mandate/dual control |
| Integration | tenant link/unlink; provenance; replay; inget direct DB-write |

## Evidensartefakt per release

Varje slice lämnar ett versionsbundet manifest med commit, migrationsintervall, schema/API-version, target project, testidentiteter (inga credentials), testresultat, advisors, reconciliation, kända undantag, rollback/roll-forward och namngivna godkännare.
