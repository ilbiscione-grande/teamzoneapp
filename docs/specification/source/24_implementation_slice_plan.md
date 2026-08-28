# Implementerbar sliceplan för TeamZone-rebuild

**Status: godkänd av produktägaren 2026-08-07. Greenfieldbeslutet inför S00; planen ger fortfarande inte implementationstillstånd.**

## Syfte och beslutsgränser

Planen omvandlar dokument 17–23 till en greenfield-bootstrap S00 och elva vertikala leveranser S01–S11. Implementation sker i `C:\Dev\TeamzoneApp`; `C:\Dev\TeamZone` är legacy-/audit-/specifikationskälla och får inte bli rebuildens kodbas. Varje slice ska kunna byggas, testas i auditprojektet, demonstreras och återställas oberoende innan nästa slice förlitar sig på den.

Tre separata beslut gäller:

1. **Plangodkännande:** låser ordning, scope och exitgrindar.
2. **Implementationstillstånd:** ges separat per slice och tillåter lokala filer/migrationer samt test i auditprojektet.
3. **Livegodkännande:** ges först efter godkänd evidensrapport för den aktuella slicen.

Inget plangodkännande ger automatiskt rätt att ändra Teamzone6 live.

## Statusnotation

- `[ ]` inte påbörjad
- `[~]` pågår
- `[x]` verifierad och evidenslänkad
- `[!]` blockerad med namngivet beroende

En ruta kryssas inte för när kod är skriven, utan först när dess acceptanskriterium har verifierats i angiven miljö.

## Gemensam arbetsgång per slice

| Fas | Obligatoriskt arbete | Grind |
|---|---|---|
| A – Baseline | Läs live/audit skrivskyddat, frys schema/API/ACL/funktionsfingerprint och legacykonsumenter | Inga okända driftobjekt |
| B – Design freeze | Fastställ exakta DDL/API-signaturer, taskscope, parameterberoenden och hotmodell | Reviewad slice-spec |
| C – Expand | Skapa migration via Supabase CLI, additiva objekt, default revoke, RLS/grants, feature flag av | Tom replay och gamla tester passerar |
| D – Backfill/shadow | Återstartbar backfill, provenance, reconciliation och shadow reads | Noll oförklarade differenser |
| E – Client/API | Aktivera API och klient för auditcohort; loading/error/offline/resync | Kontrakttester + UI-smoke |
| F – Security/release | JWT/tenant/Storage/Realtime/Edge/advisors/logscan/rollback | Evidenspaket godkänt |
| G – Live | Separat deploygodkännande, canary, smoke, trafik/telemetry | Signerad live-efterkontroll |
| H – Contract | Stoppa legacywrite/read först efter compatibilityfönster | Separat contract/drop-godkännande |

## Definition of ready

En slice får implementationstillstånd först när:

- produktkontrakt och berörda taskrader är godkända;
- alla P0-parametrar för slicens dataspec är beslutade eller slicen uttryckligen begränsad till säker avstängd struktur;
- auditprojekt, JWT-fixtures och rollbackmål är identifierade;
- berörda användarkodändringar i arbetsytan är kartlagda och bevaras;
- Supabase changelog/dokumentation har verifierats för använda funktioner;
- inga secrets eller råa testcredentials ska skrivas till repo/evidens.

## Definition of done

Varje slice kräver:

- repositorymigration som replayas från tom miljö och uppgraderar live-lik kopia;
- privilege manifest för schemas, grants, RLS, policies, views och function ACL;
- SQL-unit- och negativa JWT/tenant/state/idempotencytester;
- Flutter/Next kontraktstest, svenska/engelska, a11y och säkra feltillstånd där UI berörs;
- Storage/Realtime/Edge-test där dessa ytor används;
- reconciliation, advisorreview, secret/logscan och rollback/roll-forward;
- versionsbundet evidensmanifest med commit, miljö, testresultat och kända undantag;
- uppdaterad status `[x]` i denna plan och separat godkännande före live.

## Översikt och beroenden

| Slice | Resultat | Beroenden | Storlek/risk |
|---|---|---|---|
| S00 | Tomt greenfield-repo, verifierad toolchain, Flutter-skal, secrets-/kvalitetsgrund och specsnapshot | Godkänd plan + separat bootstrapstillstånd | M / låg–medel |
| S01 | Platform foundation, identity, context och tomt femsidigt skal | S00 + steg 2 + teknisk review | XL / hög |
| S02 | Klubb, lag, roster, invite, claim, guardian och transfer | S01 | XL / hög |
| S03 | Event, recurrence, audience, plats och kalender | S01–02 | XL / hög |
| S04 | Squad, callup, response, attendance och notification outbox | S03 | XL / mycket hög |
| S05 | Hem och fem huvudytors rollanpassade projections | S01–04 | L / medel |
| S06 | Inbox, meddelanden, filer, push och notification center | S01–05 | XL / mycket hög |
| S07 | Match Space-adapter ovanpå v2 | S03–05 | L / hög |
| S08 | Development, statistik, signaler och Assistant Coach v1 | S02–07 | XL / mycket hög |
| S09 | Publik webb, consent och public API | S02–03 | XL / mycket hög |
| S10 | Billing/entitlements och Economy/Board | S01–02; 10B efter 10A | XL / mycket hög |
| S11 | Workspaces och fristående webtoolintegrationer | S03, S07–10 efter behov | XL / hög |

S00 är första exekveringen; S01 är första produkt-/domänslicen. S07 kan utvecklas parallellt med senare delar av S06 efter att S03–05 är stabila. S09 kan förberedas utan att publicering aktiveras. S10A måste vara stabil innan någon betald modul använder entitlement.

---

## S01 – platform foundation, identity och context

**Mål:** En signerad auditbuild kan logga in, härleda kanoniska contexts/capabilities, visa väntrum vid noll context och navigera i ett tomt femsidigt skal utan att använda legacyrollen som authorization.

**Blockerare före authrelease:** PAR-OPS-01, PAR-API-02, PAR-OPS-03 samt operationsbeslut om leaked-password-skydd och step-up/MFA. Struktur och auditpilot kan byggas före produktionsvärden.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S01-BASE-01 | Fingerprint av live/audit: Postgresversion, exposed schemas, `pg_default_acl`, grants, 65 tabeller, 179 definers och migrationshistorik |
| [ ] | S01-DB-01 | Skapa `core`, `internal`, `audit`, `api` med återkallade default privileges; inga klientgrants utan manifest |
| [ ] | S01-DB-02 | Skapa/backfilla foundational `profiles`, `clubs`, `teams`, `club_people`, account links, assignments och capability grants med RLS/constraints |
| [ ] | S01-DB-03 | Skapa command dedupe/audit/provenance och prototypa exposed invoker-wrapper → internal definer med fixerad search path |
| [ ] | S01-API-01 | Versionerad `get_my_contexts` och `get_profile`; unknown/ended/suspended fail-closed, multi-context deduplicerad |
| [ ] | S01-MIG-01 | Deterministisk mapping av befintliga profile/member/club/team/role-relationer; ambiguous rows till privat exception queue |
| [ ] | S01-CLI-01 | Session bootstrap, explicit loading/timeout/retry, väntsal och context selector |
| [ ] | S01-CLI-02 | Fem stabila huvudroutes med deep-link/refresh/back och feature flag; endast tomma säkra surfaces |
| [ ] | S01-TEST-01 | JWT-matris: anon, player, guardian, leader, functionary, guest, unknown, super-admin, cross-club och ended assignment |
| [ ] | S01-TEST-02 | Privilege/definer/advisor/logscan samt tom replay, live-lik upgrade, rollback och old-client regression |

**Exit:** Ingen okänd roll blir player; klienten kan inte välja extra capability; noll context ger väntsal, inte onboardingfel; inga nya advisors utan godkänt undantag.

## S02 – klubb, lag och rosterlivscykel

**Mål:** Behörig klubb-/lagadministration kan skapa och hantera tenantägda personer och temporala relationer utan att radera global identitet.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S02-DB-01 | Slutför club/team/person/assignment/eligibility/guardian/transfer-tabeller, sammansatta tenant-FK och temporalregler |
| [ ] | S02-API-01 | Scopeade list/detail-queries för klubb, lag och roster med dataminimerad PII |
| [ ] | S02-CMD-01 | Create/end assignment, invite, secure claim och import med atomisk audit/idempotens |
| [ ] | S02-CMD-02 | Guardian relation och transfer/loan/guest med source/target approval och explicit acting-as |
| [ ] | S02-MIG-01 | Backfill `members`, memberships, club members, guardians och playable teams; exception/reconciliationrapport |
| [ ] | S02-CLI-01 | Club/team/roster/list/detail/invite/claim/transferflöden med rollanpassade actions |
| [ ] | S02-TEST-01 | Claim race, duplicate identity, cross-club escalation, unauthorized move, ended relation och history attribution |
| [ ] | S02-REL-01 | Feature-flagad auditcohort och verifierad rollback till legacy reads utan dataförlust |

**Exit:** Lagremove påverkar inte profile/club person-historik; transfer kräver båda sidor; alla indirekta person/team/club-mismatch nekas.

## S03 – event och kalender

**Mål:** Ett kanoniskt eventaggregate stöder primary/shared teams, recurrence, audience, plats och korrekta tidssemantiker.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S03-DB-01 | Event, recurrence, revisions, event teams, audience och location med exakt primary owner och tenant-FK |
| [ ] | S03-API-01 | Calendar multi-context query och EventDetails projection med caller actions/revision |
| [ ] | S03-CMD-01 | Create/revise/transition event med one/forward/all-scope och audit/outbox |
| [ ] | S03-MIG-01 | Backfill events/shared teams/recurrence/audience/location med revisionsbas |
| [ ] | S03-CLI-01 | Kalender + EventDetails Info; create/edit/cancel/completed och tydliga loading/error/offline states |
| [ ] | S03-TEST-01 | DST, all-day, overnight, stale revision, shared leader, audience≠edit och seriepartial-failure |
| [ ] | S03-RT-01 | Scopead privat invalidation + full resync vid reconnect/app resume |

**Exit:** Eventets klubb/owner/team kan inte mismatche; recurrence lämnar inga partiella occurrences; audience ger aldrig mutationstillstånd.

## S04 – squad, callup, response och attendance

**Mål:** Enda uttagningskedjan är event → revisionerad squad → callup; response och attendance är separata, auditerade facts.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S04-DB-01 | Squad revisions/members, eligibility snapshot, callup/response/attendance och notification outbox |
| [ ] | S04-CMD-01 | Save/lock squad; group/all/generator som input till samma draftkommando |
| [ ] | S04-CMD-02 | Send/cancel/remind callups, respond med acting-as och bulk attendance all-or-nothing |
| [ ] | S04-MIG-01 | Mappa preliminary/groups/generated/squad plans/callups utan dubbla write paths |
| [ ] | S04-CLI-01 | EventDetails Squad/Callups/Attendance med pending delivery och explicit unknown/absent |
| [ ] | S04-NOT-01 | Outbox worker, retry/dedupe/delivery status och sanerad providertelemetry |
| [ ] | S04-TEST-01 | Cross-team member, stale squad, guardian wrong child, expired/replayed token, partial push och duplicate command |
| [ ] | S04-REL-01 | Shadow comparison mot legacy och kontrollerad legacywrite-stop per cohort |

**Exit:** Ingen oscopead medlem kan nå callup; notificationfel blir inte domänsuccess; attendance `unknown` blir aldrig `absent`.

## S05 – Hem och huvudytornas projections

**Mål:** Hem, Kalender, Inbox, Lag och Mer drivs av riktiga domäntillstånd och flera contexts utan egna authorizationregler.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S05-API-01 | Dataminimerade home/action/count projections med versionerad sync cursor |
| [ ] | S05-CLI-01 | Roll-/capabilityanpassade cards/actions; explicit contexttarget för writes |
| [ ] | S05-CLI-02 | Centrala phone/tablet/desktop-web breakpoints, sv/en, light/dark/system och navigation |
| [ ] | S05-STATE-01 | Loading/empty/error/stale/retry och offline timestamp utan rå backendtext |
| [ ] | S05-TEST-01 | Multi-context dedupe, deep links, text scale, screen reader, keyboard/focus och processrestart |

**Exit:** UI-actions exakt motsvarar servercapabilities men är aldrig enda spärr; samtliga fem routes är stabila på stödda klienter.

## S06 – Inbox, filer och notifications

**Mål:** Direct/group/broadcast och cross-club leader requests delar en recipientmodell; filer, reads, mute och retention följer trådens scope.

**P0 före dataspec:** PAR-PRIV-01 och PAR-PRIV-03.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S06-DB-01 | Threads/scopes/participants/messages/versions/reads/mutes/blocks/reports och retention classes |
| [ ] | S06-FILE-01 | Staging/finalize `file_objects`, privata buckets, owner/threadbinding och orphan cleanup |
| [ ] | S06-API-01 | Allowed recipients, list/get/send/read/mute och cross-club request/accept/block med samma authhelper |
| [ ] | S06-MIG-01 | Backfill befintliga threads/messages/settings/attachments; metadata/object reconciliation |
| [ ] | S06-CLI-01 | Inbox, thread, compose, request state, uploadprogress, recall och notification center |
| [ ] | S06-RT-01 | Privata topicbundna kanaler, minimal payload och gap/full-resync |
| [ ] | S06-TEST-01 | Known foreign thread UUID, recipient leak, unauthorized add/send, mute failure, cross-tenant file och withdrawn URL |
| [ ] | S06-RET-01 | Retention/legal hold/delete/leave/read cleanup med audit och återkörbart jobb |

**Exit:** `resolve recipients = create/add/send access`; mute fail-closed; privat fil är aldrig globalt authenticated-läsbar.

## S07 – Match Space v2-adapter

**Mål:** Ny klient och projections använder verifierat match v2-kontrakt utan att skapa en parallell matchmodell.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S07-BASE-01 | Frys nuvarande v2-signaturer, commands, states, revisioner och regressionsevidens |
| [ ] | S07-API-01 | Adapter/projection och resync cursor utan semantikbyte i v2 commands |
| [ ] | S07-DB-01 | Bind event/team/matchday roster; score/stats fortsatt härledda från aktiva facts |
| [ ] | S07-CLI-01 | Matchprep/live/fulltime/unlock med pending/retry och serverauthoritativ revision |
| [ ] | S07-TEST-01 | Alla befintliga v2 regressioner plus frozen roster, void/edit, offline gap och duplicate command |
| [ ] | S07-REL-01 | Feature flag/canary; fallback till gammal UI mot samma v2 backend |

**Exit:** `match_commands` förblir append-only source; klienten kan inte skriva score/statistik direkt.

## S08 – development, signaler och Assistant Coach

**Mål:** Developmentplaner och transparenta versionsbundna signaler fungerar; Assistant Coach v1 är regelbaserad och muterar endast efter vanlig commandbekräftelse.

**P0/P1:** PAR-METHOD-02 före healthdataspec; PAR-METHOD-01/PAR-PRIV-04 före signal/self-rating-aktivering; PAR-AI-01/02 före generativ pilot.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S08-DB-01 | Development plans/actions, signal definitions/facts/provenance, clearance och suspension facts |
| [ ] | S08-API-01 | Scopeade stats/development/signals queries med version/stale/semantic class |
| [ ] | S08-CMD-01 | Plan/check-in/clearance/suspension/dismissal med expected revision och audit |
| [ ] | S08-MIG-01 | Backfill development/workload/injury/suspension/watchpoint med explicit semantic mapping |
| [ ] | S08-AC-01 | Regelmotor och explainable recommendations; preview/confirm går genom vanligt domain command |
| [ ] | S08-CLI-01 | Development/AC surfaces som skiljer råfakta, proxy och medicinskt tillstånd |
| [ ] | S08-TEST-01 | Provenance/replay/stale, guardian/age visibility, no-ranking, invalid clearance och suspension decrement |

**Exit:** Ingen proxy presenteras som diagnos; generativ behandling är avstängd tills separat godkännande.

## S09 – publication och publik webb

**P0 före freeze:** PAR-PRIV-02, PAR-PRIV-03, PAR-API-01, PAR-OPS-01 och PAR-OPS-02.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S09-DB-01 | Publication settings, purpose-bound consents, publications och separata public projection tables |
| [ ] | S09-API-01 | Explicit anon endpoint-/fältallowlist, maxlimit, rate/enumeration/abuse och withdraw invalidation |
| [ ] | S09-WEB-01 | Kanonisk Next.js-route för club/team/event/news/media och säkert contact form |
| [ ] | S09-MIG-01 | Befintlig public data importeras private/listed/published endast med bevisad policy/consent |
| [ ] | S09-TEST-01 | Minor/private default, consent withdraw, cache/CDN SLA, metadata/Storage leak, scrape/enumeration och contact abuse |
| [ ] | S09-REL-01 | DNS/headers/SEO/smoke/canary samt omedelbar kill switch för public projection |

**Exit:** Anon kan bara läsa `public_api`; intern PII och opublicerat media kan inte nås via API, Storage, cache eller metadata.

## S10 – billing, entitlements och ekonomi

### S10A – billing och klubbomfattande entitlements

**P0:** PAR-BILL-02 före entitlementdataspec; PAR-BILL-01/03 före kommersiell checkout; PAR-OPS-03 före key retirement.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S10A-DB-01 | Provider inbox, billing customer, canonical subscription och klubbomfattande entitlement projection |
| [ ] | S10A-API-01 | Server pricebook checkout och get entitlements; klient kan inte välja pris/feature/state |
| [ ] | S10A-WEBHOOK-01 | Raw signature, dedupe, providerrevision, out-of-order och transactional projection |
| [ ] | S10A-MIG-01 | Reconcile legacy subscriptions/club plans/module/webtool rows till en source of truth |
| [ ] | S10A-TEST-01 | Duplicate/out-of-order/partial failure, unknown/grace/read-only/ended och club-vs-team module access |
| [ ] | S10A-REL-01 | Checkout/webhook auditpilot, secret isolation och fail-closed kill switch |

### S10B – Economy och Board

**P0:** PAR-FIN-01 och PAR-FIN-02 före ekonomiska writes; PAR-FIN-03 före fees/settlement automation.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S10B-DB-01 | Append-only ledger/reversal, obligations, pledges, mandates och dual-control approvals |
| [ ] | S10B-API-01 | Post/reverse/approve, fee run/payment och pledge settlement med money minor units |
| [ ] | S10B-MIG-01 | Import funds/fees/sponsor/board med öppningsbalansprovenance och reconciliation |
| [ ] | S10B-CLI-01 | Club/team economy, fees, sponsorship och board surfaces med read-only/exportläge |
| [ ] | S10B-TEST-01 | Currency, duplicate settlement, mandate expiry, different approvers och immutable history |

**Exit:** Modul köps en gång per klubb och kan användas av alla klubbens lag med rätt capability; okänd entitlement ger aldrig premiumwrite.

## S11 – workspaces och webtoolintegrationer

**P1/P2:** PAR-PRIV-06 före video; PAR-INTEG-01 före första link; PAR-INTEG-02 före SMS.

| Status | Task | Leverans/acceptans |
|---|---|---|
| [ ] | S11-INT-01 | Integration links, external refs, provenance, version, sync attempts, unlink och incident ownership |
| [ ] | S11-WS-01 | Training/Season/Team/Player Development projections med separat owner/source of truth |
| [ ] | S11-TAC-01 | Tactics Board publicerad artifact → granskningsbar draft/snapshot; aldrig tyst overwrite |
| [ ] | S11-VID-01 | Video Analyzer delar endast explicit publicerad projection efter media policy |
| [ ] | S11-MATCHPOOL-01 | Verifierad ledarpublicering/request/accept → eventdraft, med expiry/block/report |
| [ ] | S11-BOOK-01 | Fristående bokningswebtool med valbar TeamZone/EventDetails API-integration och fri platsfallback |
| [ ] | S11-TEST-01 | Tenant link/unlink, identity proof, version conflict, retry/replay, owner system och zero direct DB-write |

**Exit:** Varje web tool fungerar fristående; TeamZone kan förlora integrationen utan att kärnflöden eller historik förstörs.

## Tvärgående parameter- och releasearbete

Följande löper parallellt men får inte smygas in som klientkonstanter:

| Status | Task | Leverans |
|---|---|---|
| [ ] | X-PARAM-01 | Ägarna beslutar P0-parametrar i dokument 16 före berörd slice freeze |
| [ ] | X-OPS-01 | Miljöer, domäner, secrets, key rotation, canary, compatibility och rollback enligt PAR-OPS-01/03 |
| [ ] | X-QA-01 | Gemensam JWT fixture factory, testdata builder, privilege diff och evidensmanifest |
| [ ] | X-OBS-01 | Sanerad logger/correlation IDs/advisors/telemetry/kill switches enligt PAR-OPS-05 |
| [ ] | X-UX-01 | Design tokens, breakpoints, sv/en, a11y och statekomponenter enligt PAR-OPS-04 |
| [ ] | X-LEGACY-01 | Legacyregister med read/write-stop, consumer, reconciliation, retention och dropapproval per objekt |

## Godkännandegrind för planen

Produktägaren bekräftade 2026-08-07:

1. S00–S11:s ordning och scope.
2. Att S00 skapar greenfieldgrunden i `C:\Dev\TeamzoneApp` och att S01 är första produktimplementationen; båda kräver separata implementationstillstånd.
3. Att varje livekörning kräver egen evidensreview och uttryckligt godkännande.
4. Att legacy contract/drop alltid är en senare separat åtgärd.
5. Att öppna parametrar håller berörd funktion avstängd/fail-closed i stället för att uppskattas.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | Sliceplanen godkänd. Rebuilden ska skapas helt från grunden i `C:\Dev\TeamzoneApp`; utvecklingsmiljön får konfigureras vid behov efter verifierad S00-baseline. | Produktägaren |
