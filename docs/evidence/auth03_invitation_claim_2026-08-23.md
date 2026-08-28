# AUTH-03 – Inbjudan och säker claim

**Datum:** 2026-08-23  
**Status:** LOKALT IMPLEMENTERAD OCH KLIENTVERIFIERAD, SQL/EDGE-GRIND ÅTERSTÅR  
**Livepåverkan:** Ingen. Migrationen har inte applicerats och Edge-funktionen har inte distribuerats.

## Implementerat

- Canonical länkar stöds som `/invite?token=…` och `teamzone://app/invite?token=…`, med längdgräns och okända routes fail-closed.
- Kallstart och länkar medan appen körs fångas. Preview visas före auth och flödet återupptas efter verifierad session.
- Preview visar endast klubb, lag, förskapad person, roll och giltighet. Ogiltig, utgången eller återkallad token ger samma neutrala svar.
- Pre-auth-preview går genom `invitation-preview` Edge-gränsen. Databasen ger ingen ny anon-privilege; X-QA:s frysta gräns bevaras.
- Ny issuer v2 hashar avsedd mottagares normaliserade e-post. Rå e-post sparas inte i inviteposten.
- Claim v2 verifierar avsedd mottagare, låser inviteraden, kontrollerar state/expiry, använder command-deduplication och konsumerar token atomiskt.
- Claim binder exakt den `club_person_id` som inviteraden skapades för. Ingen namnmatchning förekommer.
- Fel mottagare eller redan länkad person skapar ett deduplicerat granskningsärende och returnerar en neutral status utan motpartens kontodata.
- Android och iOS registrerar fortsatt `teamzone`-schemat; paketidentiteten är oförändrad.

## Säkerhetsgräns

- Ingen `anon`-grant infördes.
- Preview-RPC är endast körbar av `service_role` bakom Edge-funktionen.
- Claim/issuer är endast körbara som `authenticated` och använder interna, låsta serverfunktioner.
- Edge-funktionen har exakt CORS-lista, `no-store`, bundna inputlängder och sanerade loggar utan rå token.
- Klienten innehåller ingen `service_role` eller serverhemlighet.

## Filer

- `supabase/migrations/20260823202947_auth03_invitation_claim.sql`
- `supabase/functions/invitation-preview/index.ts`
- `supabase/config.toml`
- `lib/src/features/auth/invitation_flow.dart`
- `lib/src/features/roster/roster_models.dart`
- `lib/src/features/roster/roster_services.dart`
- `lib/src/app/teamzone_app.dart`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `test/auth03_invitation_claim_test.dart`

## Verifiering

- `flutter analyze`: **No issues found**.
- Riktad AUTH-03-svit: **4/4 passerar**.
- Full regressionssvit efter klient/preview-gränsen: **130/130 passerar**.
- Slutlig AUTH-03-källkontroll efter recipient-bound issuer: **4/4 passerar**.
- Slutlig X-QA-svit: **4/4 passerar**.
- Fullsviten upptäckte och stoppade en första anon-RPC-design. Preview flyttades till servermedierad Edge-gräns och X-QA passerar därefter utan undantag.

## Kvarvarande grind

1. Applicera migrationen i en lokal eller uttryckligen godkänd hosted testdatabas och köra SQL-fixtures för replay/race, fel mottagare, fel tenant, expiry och dubblett.
2. Köra Edge-funktionen lokalt eller i godkänd hosted testmiljö och verifiera CORS, neutrala fel och loggredaktion.
3. Fysisk deep-linkkontroll på Android samt motsvarande webb/iOS-grind.

Ingen av dessa åtgärder gjordes mot Supabase live.

## Lokal verifieringsuppföljning 2026-08-24

- En reproducerbar SQL-fixture har lagts till i `supabase/tests/auth03/`. Den täcker giltig och neutral preview, mottagarbunden claim, replay/idempotens, konsumerad token, fel mottagare med granskningsärende, bibehållen invite vid review samt nekad issuer utan capability.
- `supabase status` kunde inte starta eftersom varken Docker eller Podman finns installerat.
- En fristående PostgreSQL 18.4-instans provades utan nätverk och utan livekoppling. `initdb` kraschade under post-bootstrap med Windows-felet `0xC0000005`; SQL-fixturen kunde därför inte exekveras i denna miljö.
- Deno finns inte installerat, så Edge-funktionen kunde inte typkontrolleras eller köras lokalt.
- Ny körning av `flutter analyze` och det riktade AUTH-03-testet nådde analys respektive testladdning men runnern gav därefter ingen output. Båda avbröts kontrollerat; tidigare godkända resultat ovan ersätts inte av ett nytt godkänt resultat.
- Statisk säkerhetskontroll bekräftar fortsatt explicit revoke för `public`/`anon`, service-role-only preview och authenticated-only claim/issuer.
- Ingen åtkomst till eller ändring av Supabase live gjordes.
