# AUTH-03 – Inbjudan och säker claim

**Datum:** 2026-08-23  
**Status:** IMPLEMENTERAD OCH VERIFIERAD PÅ HOSTED WEBB OCH FYSISK ANDROID  
**Livepåverkan:** Databasgränsen och `invitation-preview` version 1 är aktiva i det uttryckligen godkända Supabase-testprojektet. Ingen produktionsmiljö har ändrats.

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

## Kvarvarande plattformsuppföljning

1. Motsvarande fysisk iOS-kontroll genomförs när en iOS-miljö finns tillgänglig; den blockerar inte AUTH-03 i nuvarande godkända leveransomfattning.

Ingen produktionsmiljö eller äldre TeamZone-databas har ändrats.

## Hosted Edge-verifiering 2026-09-03

- `invitation-preview` driftsattes som aktiv version 1 i testprojekt `hgcshgunvooyudvrcpig` efter uttryckligt godkännande av den publika bearer-länkgränsen.
- Tillåtet `http://localhost:5000` gav korrekt CORS, `cache-control: no-store`, korrelations-ID och neutral `200 {"status":"invalid"}` för ogiltig token.
- Otillåtet origin nekades med 403 och tillåten preflight gav 200 med exakt localhost-origin.
- En kortlivad riktad testinvite gav `status=valid` och endast klubbnamn, lagnamn, personnamn, roll samt utgångstid.
- Testinviten återkallades direkt. Samma token gav därefter neutral `status=invalid`; ingen medlems- eller guardianrelation skapades.
- Edge-loggen innehöll metod, status och funktionsadress men ingen rå token eller persondata.
- `anon` och `PUBLIC` saknar fortsatt execute på `api.preview_roster_invitation`; endast Edge-funktionens serverroll når RPC:n.

## Fysisk webbverifiering 2026-09-03

- En riktig riktad invite öppnades i ett separat ej inloggat webbläsarfönster via `/invite?token=…`.
- Förhandsdialogen visade accepteringsåtgärd och krävde inloggning för fortsatt claim.
- Efter inloggning med exakt avsett spelarkonto återupptogs samma invite.
- Första claimförsöket exponerade en äldre kvalificerad parameterreferens efter funktionsomdöpning. Migration `20260903082224_auth03_fix_renamed_invitation_claim_parameter.sql` rättade endast referensen; execute förblev authenticated-only och 5/5 AUTH-03-tester passerade.
- Lyckad claim lämnade först webbläsarens råa `/invite` som GoRouter-startväg. Produktskalet använder nu uttryckligen det canonicaliserade startläget; AUTH-03-/route-regressionen passerade 19/19.
- Efter ny releasebuild landade användaren korrekt på Hem efter acceptans.
- Den tillfälliga testinviten återkallades efter verifieringen och är `revoked`, revision 2.

## Fysisk Android-verifiering 2026-09-03

- Aktuell debug-APK installerades på Xiaomi Mi 9 via USB utan att paketidentiteten `com.teamzone.teamzone` ändrades.
- En ogiltig `teamzone://app/invite?token=…`-länk öppnade appen och visade samma neutrala fel som andra ogiltiga eller utgångna länkar.
- En giltig riktad länk öppnade rätt förhandsvisning vid kallstart.
- Fysisk omtest upptäckte att en redan monterad invitevy behöll föregående preview när en ny länk levererades till samma appinstans. `_InvitationFlowState.didUpdateWidget` laddar nu om preview och nollställer transient status när token ändras; riktad AUTH-03-svit passerar 7/7.
- Acceptans med fel inloggat konto stoppades som `review_required`, vilket verifierar mottagarbindningen utan att konsumera inbjudan.
- Efter inloggning med exakt avsett konto accepterades samma inbjudan och användaren landade korrekt på Hem.
- Den tillfälliga Android-inbjudan återkallades efter testet och är `revoked`, revision 2.

## Lokal verifieringsuppföljning 2026-08-24

- En reproducerbar SQL-fixture har lagts till i `supabase/tests/auth03/`. Den täcker giltig och neutral preview, mottagarbunden claim, replay/idempotens, konsumerad token, fel mottagare med granskningsärende, bibehållen invite vid review samt nekad issuer utan capability.
- `supabase status` kunde inte starta eftersom varken Docker eller Podman finns installerat.
- En fristående PostgreSQL 18.4-instans provades utan nätverk och utan livekoppling. `initdb` kraschade under post-bootstrap med Windows-felet `0xC0000005`; SQL-fixturen kunde därför inte exekveras i denna miljö.
- Deno finns inte installerat, så Edge-funktionen kunde inte typkontrolleras eller köras lokalt.
- Ny körning av `flutter analyze` och det riktade AUTH-03-testet nådde analys respektive testladdning men runnern gav därefter ingen output. Båda avbröts kontrollerat; tidigare godkända resultat ovan ersätts inte av ett nytt godkänt resultat.
- Statisk säkerhetskontroll bekräftar fortsatt explicit revoke för `public`/`anon`, service-role-only preview och authenticated-only claim/issuer.
- Ingen åtkomst till eller ändring av Supabase live gjordes.
