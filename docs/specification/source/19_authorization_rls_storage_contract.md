# Steg 2C – authorization, RLS, Storage och servergränser

**Status: produktgodkänt och tekniskt/säkerhetsmässigt reviewat med villkor 2026-08-07; implementationsverifiering återstår. Fail-closed krav, inte rekommendationer.**

## Beslutsordning per operation

1. Verifiera session och `auth.uid()`; känsliga commands kan även kräva giltig `session_id`.
2. Härled profile/account link server-side.
3. Härled objektets `club_id`, team/event och aktuella revision från databasen.
4. Kontrollera aktiv assignment/mandate och exakt capability för objektets scope.
5. Kontrollera entitlement separat om funktionen är en betald klubbmodul.
6. Kontrollera state transition, eligibility, acting-as, parameterpolicy och idempotency.
7. Skriv facts + audit + outbox atomiskt.

Route, client role, JWT `user_metadata`, inskickat `club_id` och modulknapp är aldrig authorizationbevis.

## Rollpaket till capabilities

| UI-paket | Normal scope | Exempel, inte full access |
|---|---|---|
| Player | person/team | egna callups/responses, tillåten teamläsning |
| Guardian | guardianrelation | barns tillåtna reads/responses med explicit acting-as |
| Leader | team/club | event/squad/attendance enligt assignment; cross-club contact request |
| Club functionary | club | endast tilldelade admin/board/economy capabilities |
| Guest/loan | tidsbegränsad person/team | uttryckligt smalt event/team scope |
| System super-admin | systemmandat | separat step-up, reason och audit; inte syntetiskt medlemskap |

Okänt paket ger noll capabilities. Capabilities från flera aktiva assignments kan förenas för läsning; varje mutation binds till en explicit target scope och actor assignment.

## RLS- och grantkontrakt

- `anon` saknar grants till `core`, `internal` och `audit`. `authenticated` saknar skrivgrants; minsta SELECT/USAGE får endast ges när en security-invoker-query kräver det och skyddas då av RLS.
- Exponerade `api`-/`public_api`-relationer har RLS där tabeller används och minsta explicita grants.
- Tenanttabeller i `core` har RLS som defense in depth även om schemat inte exponeras.
- Default privileges återkallas för tabeller, sekvenser och funktioner i nya schemas; varje migration ger därefter explicita grants och verifierar dem.
- Authenticated SELECT-policy kräver alltid tenant-/objektrelation; `TO authenticated` ensam är förbjudet.
- UPDATE-policy har både `USING` och `WITH CHECK`; objektets tenant/owner får inte kunna flyttas.
- Permissiva policies granskas som OR-mängd. En bred policy får inte samexistera som “fallback”.
- Exponerad query-view använder anroparens säkerhetskontext (`security_invoker`) och kräver minsta underliggande SELECT + RLS; intern owner-/materialized view exponeras aldrig direkt.
- Funktioner får `REVOKE ALL ... FROM PUBLIC` som default och därefter explicit execute-grant.
- Exponerade API-wrappers är `SECURITY INVOKER`. Ett wrapper-command får anropa en snäv `SECURITY DEFINER`-funktion i icke-exponerat schema med explicit USAGE/EXECUTE; den interna funktionen har fixerad `search_path`, kvalificerade objektnamn och full egen authorization. Ingen anon-körbar definer används för publik läsning.

## Policyfamiljer

| Familj | Läsregel | Skrivregel |
|---|---|---|
| Club/team | aktiv club relation + `club/team.read` | command + manage capability |
| Person/roster | minsta projection för behörig relation | claim/assignment/transfer commands |
| Guardian/health | subject, aktiv guardianrelation eller särskild sensitive capability | auditerat acting-as/clearance command |
| Event/squad/callup | `event.read` via event teams/audience | owning/shared capability + transition/eligibility |
| Messaging | aktiv participant härledd från threadscope | send/add/remove genom samma recipientregel |
| Billing/economy | klubbcapability + entitlement där relevant | signerad provider eller auditerat command/dual control |
| Publication | internt manage scope | anon läser bara `public_api`-projektion |

## Indirekt tenantbinding

Följande mismatch ska nekas av constraint före RLS när möjligt:

- team.club ≠ row.club;
- event.owning_team.club ≠ event.club;
- event_team.club ≠ event.club;
- person.club ≠ assignment/eligibility/callup.club;
- squad.event ≠ callup.event;
- message.thread ≠ attachment owner/thread;
- match event/team/person ≠ event/squad snapshot;
- entitlement/subscription/customer club mismatch;
- integration external ref ≠ link owner/system.

Tomma ID-arrays, okända ID:n och partiella joins får aldrig ge vacuous-truth-access. Bulkcommands validerar att antalet matchade och tillåtna objekt exakt motsvarar antalet unika begärda objekt.

## Storage

- Privat bucket är default; public bucket innehåller endast byggda publiceringsartefakter.
- Upload initieras med servercommand som skapar kortlivad stagingreferens med club, owner, MIME, size och checksum.
- Finalize verifierar objektet och skapar `file_objects`; fel/orphan städas av auditerat jobb.
- Read/update/delete kontrollerar metadataowner och samma capability/thread/publication som domänobjektet.
- Upsert undviks för auditmedia; ny version får ny object key. Där upsert används verifieras SELECT+INSERT+UPDATE-policy.
- Signed URL har kort TTL, objektscope och får inte loggas. Withdraw/role loss stoppar nya URL:er och följer cache-SLA.

## Edge Functions och secrets

- Publishable key får finnas i Flutter/Next browser. Secret/service-role finns endast i serverns secret store.
- User-anropad Function behåller JWT-verifiering och använder caller-scopad klient; den binder payload till caller/objekt och anropar ett snävt servercommand.
- Publishable/secret keys är inte användar-JWT:n. Serverjobb skickar namngiven secret key i `apikey`, använder explicit secret-auth och får aldrig förväxla nyckeln med `Authorization: Bearer`.
- Webhook verifierar rå body/signatur före parsing, deduplicerar provider event och litar aldrig på client-supplied entitlement.
- Scheduled/internal function använder separat service identity, minsta scope och auditerad job run.
- CORS är originallowlist; rate limit och payloadlimit gäller före dyrt arbete.

## Realtime och rate limits

- Produktionskanaler är privata och projektets generella public access stängs när inga uttryckliga publika kanaler krävs.
- Broadcast/Presence authorization uttrycks med RLS på `realtime.messages` och topic binds till exakt club/team/thread/event-scope.
- Postgres Changes eller databasbroadcast publicerar endast minimal projektion/invalidation; bastabellens RLS och kanalauthorization testas separat.
- `db_pre_request` gäller endast Data API. Storage, Realtime och Edge Functions får egna rate-/quota-/abusekontroller; ingen yta antar att PostgREST-kontrollen skyddar övriga produkter.

## Tokens

Invite, guardian response, claim, consent, integration link och reset-token har:

- kryptografiskt slumpat råvärde; endast hash lagras;
- type, target object, allowed action, issued/expiry, use count/max use;
- single-use som default och atomisk consume;
- audience/subjectbinding där account krävs;
- redaction i logg, telemetry, URL-historik och supportverktyg.

## Negativ testmatris

Varje command/query som minimum:

| Dimension | Fall |
|---|---|
| Session | anon, giltig, expired, revoked, fel account |
| Tenant | same club, other club, känt främmande UUID, borttagen relation |
| Scope | club/team/event/person mismatch, shared team, guardian acting-as |
| Capability | saknas, fel scope, suspended/ended, unknown role |
| State | valid, stale revision, invalid transition, duplicate retry |
| Entitlement | active, grace, read-only, ended, unknown, saknad modul |
| Bulk | tom, duplicate, okänd, blandad tillåten/otillåten lista |
| Storage | owner, participant, same tenant nonparticipant, cross tenant, withdrawn public |

Testet ska verifiera både svar och att inga facts, auditposter, outboxrader eller objekt ändrades vid nekad operation.
