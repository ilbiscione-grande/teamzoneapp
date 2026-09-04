# REL-02 – steg-för-steg-verifiering

**Status:** `[x]` – samtliga automatiserade, hosted och fysiska/webbfall är verifierade 2026-09-01
**Beroende:** REL-01 måste vara grön innan slutlig klarmarkering  
**Maskinläsbar matris:** `docs/implementation/rel02_verification_matrix.json`

**Automatiserad baslinje 2026-08-28:** `[x]` – alla 12 roll × viewport-fall öppnar Hem, Laget, Kalender och Inbox utan layout-/runtimefel. Detta ersätter inte hosted/fysisk slutkörning.

**Automatiserad samlad grind 2026-09-01:** `[x]` – 44/44 roll-, avbrotts-, tillgänglighets- och statuskontraktstester passerar via `tool/rel02_automated_gate.ps1`.

## 1. Regler för klarmarkering

- [x] Varje fall har ett stabilt ID och får status `passed`, `failed`, `blocked`, `structural_only` eller `prior_evidence_requires_regression`.
- [x] Äldre bevis får användas som referens men aldrig som aktuell releasepassering.
- [x] Samma buildidentitet ska användas för hela slutmatrisen.
- [x] Ett UI-fall är inte godkänt om serverbehörigheten inte också ger förväntat tillåtet eller nekat resultat.
- [x] Fel ska dokumenteras med reproduktionssteg; raden klarmarkeras först efter regression.
- [x] Buildidentitet, produktägare och verifieringsdatum finns i JSON-matrisen och evidencen.
- [x] Kör den lokala 4 × 3-baslinjen med `test/rel02_automated_release_matrix_test.dart`.
- [x] Kör lokal cold-link/back/session/felhantering samt fokus/textskalning/kontrast/reduced-motion.

## 2. Förbered testdata och konton

- [x] Aktivt testlag med tidigare/kommande träning, match och möte användes.
- [x] Kallelse-, deltagardraft-, låst trupp- och närvarofall verifierades utan kvarvarande testmutation.
- [x] Minst två lagkontexter användes för leader-kontot; den tillfälliga andra kontexten togs bort efter slutförd matris.
- [x] Separata verifierade konton finns för `leader`, `player`, `guardian` och `club_functionary`; player-/guardian-relationerna är tillfälliga REL-02-fixtures.
- [x] Guardian har två aktiva testbarnrelationer så att acting-as och isolering kan kontrolleras.
- [x] Player och guardian har endast team-scopad `team.roster.view` för begränsad laglista; inga roster-skrivgrants.
- [x] Separat klubbfunktionär hade endast uttryckliga ekonomi-/styrelsemandat och saknade teamcapabilities.
- [x] Registrera testdata-ID:n utan e-postadresser, personnamn eller privata meddelandetexter i evidencen.

## 3. Kör roll × enhet

Kör `REL02-RD-01`–`REL02-RD-12` i JSON-matrisen. För varje kombination:

1. [x] Separata testkonton och synlig roll/kontext bekräftades.
2. [x] Hem kontrollerades för rollprioriteringar och förbjudna actions.
3. [x] Laget → Översikt, Trupp och Kalender kontrollerades för dataminimering och capabilities.
   - [x] Guardian/telefon: Översikt och begränsad Trupp utan administrationsåtgärder; Kalender laddar efter klientens uppdelning av treårsintervallet i backend-säkra fönster (2026-08-31).
4. [x] Kalender och EventDetails kontrollerades inklusive rollstyrda underområden.
   - [x] Guardian/telefon: vanliga Kalender och EventDetails laddar och visar förväntat innehåll utan guardian-otillåtna redigeringsåtgärder (2026-08-31).
5. [x] Inbox, trådar och positiva/negativa mottagarrelationer kontrollerades.
   - [x] Guardian/telefon: Inbox fungerar och Nytt meddelande visar endast relationsmässigt tillåten mottagare (`Coach Emilson`), utan bred klubbexponering (2026-08-31).
6. [x] Mobil-, tablet- och desktop/webbeteende kontrollerades i respektive viewport.
7. [x] Resultat och defects/regressioner finns i samlad evidence; samtliga matrisrader är `passed`.

`REL02-RD-08` Guardian/tablet 800×1100 (2026-08-31):

- [x] Hem med två barn, synlig vald barnkontext och fungerande tablet-layout.
- [x] Laget → Översikt/Trupp/Kalender utan overflow eller guardian-otillåtna administrationsåtgärder.
- [x] Lagets händelselista med filter och tidigare/kommande fungerar.
- [x] Vanliga Kalenderns vyer och EventDetails fungerar med korrekt läsbehörighet.
- [x] Inbox fungerar och Nytt meddelande visar endast relationsmässigt tillåtna `Coach Emilson`.

`REL02-RD-04` Player/telefon 390×844 (2026-08-31):

- [x] Rollanpassat Hem utan guardian-, ledar-, ekonomi- eller styrelseåtgärder.
- [x] Laget → Översikt/Trupp/Kalender fungerar; begränsad Trupp saknar rosteradministration.
- [x] Vanliga Kalendern och EventDetails fungerar utan event-, deltagar- eller närvaroadministration.
- [x] Mobil återgång från EventDetails behåller Kalender och avslutar inte appen.
- [x] Inbox fungerar och Nytt meddelande visar endast verifierad `guardian` och `Coach Emilson`.

`REL02-RD-05` Player/tablet 800×1100 (2026-08-31):

- [x] Hem och Laget → Översikt/Trupp/Kalender fungerar utan rapporterade layoutfel eller otillåtna actions.
- [x] Vanliga Kalenderns vyer och EventDetails fungerar med spelarens behörighetsgräns.
- [x] Inbox fungerar och mottagarurvalet begränsas till verifierad `guardian` och `Coach Emilson`.
- [x] Nytt direktmeddelande till en befintlig part återanvänder den aktiva konversationen och dess historik.

`REL02-RD-01` Leader/telefon 390×844 (2026-08-31):

- [x] Rollanpassat Hem fungerar i `Thomas lag`.
- [x] Laget → Översikt och Trupp fungerar med lagscopad `team.roster.manage`.
- [x] Medlemsansökningar, Hantera och personredigering visas; klubbomfattande Skapa ytterligare lag/Klubbverifiering förblir dolda.
- [x] Lagets Kalender, vanliga Kalendern och EventDetails fungerar.
- [x] Deltagardraft kan skapas och låsas; CAL-06-runtimefunktionerna är live och fysiskt verifierade.
- [x] Närvarobehörighet och närvaroformulär fungerar via livepublicerad CAL-08; ingen testnärvaro sparades.
- [x] Inbox, tillåtet mottagarurval, återanvänd direkttråd och mobil återgång fungerar.
- [x] `REL02-RD-01` komplett godkänd.

`REL02-RD-02` Leader/tablet 800×1100 (2026-09-01):

- [x] Hem fungerar med ledarprioriteringar och stabil tablet-layout.
- [x] Laget → Översikt/Trupp/Kalender fungerar med lagscopad rosterhantering och utan klubbadminval.
- [x] Vanliga Kalenderns vyer, EventDetails, eventformulär, deltagardraft/låst trupp och närvarovy fungerar.
- [x] Inbox, mottagargräns, återanvänd direkttråd och tabletåtergång fungerar.

`REL02-RD-10` Club functionary/telefon 390×844 (2026-09-01):

- [x] Hem visar endast uttryckliga ekonomi-/styrelsemandat och inga ledaråtgärder.
- [x] Laget visar ett säkert tomläge med `Använd kod` för klubbkontext utan lagkoppling.
- [x] Kalender visar inga otillåtna laghändelser eller eventadministration.
- [x] Inbox exponerar inga mottagare utan tillåten relation.
- [x] Mobilnavigation och de fyra grundytorna fungerar utan layoutavvikelse.

`REL02-RD-11` Club functionary/tablet 800×1100 (2026-09-01):

- [x] Hem visar endast uttryckliga ekonomi-/styrelsemandat i tablet-layout.
- [x] Laget visar säkert tomläge med `Använd kod` och ingen lagadministration.
- [x] Kalender exponerar inga otillåtna laghändelser eller eventåtgärder.
- [x] Inbox exponerar inga mottagare utan tillåten relation.
- [x] Navigation Rail och tillbaka-navigering fungerar.

Godkännandekrav per roll:

- [x] Leader: skapa/redigera event, deltagare, kallelse och närvaro endast med capability.
- [x] Player: egna kallelser/event men ingen roster-, närvaro- eller eventadministration.
- [x] Guardian: explicit valt barn följer query/mutation; andra barns data läcker inte.
- [x] Club functionary: endast uttryckliga klubbmandat; ingen implicit coach-, ekonomi-, styrelse- eller teamsuperaccess.

## 4. Kör avbrottsmatrisen

- [x] `REL02-I-01` Cold start: fysisk Mi 9-kallstart och bakgrund/återgång återställde endast fortsatt giltig session och `Thomas lag`.
- [x] `REL02-I-02` Deep link: kallstart av grundytor, riktiga/obefintliga detalj-ID:n och verkliga fel-scope event-/tråd-ID:n ger canonical route och neutral fail-closed fallback utan dataläckage.
  - [x] Android: `/team`, `/calendar`, `/inbox` och `/assistant` samt okänd route, obefintligt event-ID och obefintligt thread-ID.
  - [x] Webb: `/team`, `/calendar`, `/inbox` och `/assistant` öppnar canonical path direkt utan `#/home` efter gemensam path-strategi.
  - [x] Webb: obefintligt event-/tråd-UUID behåller Kalender/Inbox och visar neutral `går inte att ladda` utan främmande data eller rå backendtext.
  - [x] Webb: riktig EventDetails/tråd synkas till `?event=`/`?thread=`, återställs vid stängning och öppnar samma detalj i ny flik med bibehållen session/kontext.
  - [x] Webb: okänd path visar neutral saknas-yta utan rå teknisk text eller data och tillåter fortsatt navigation.
  - [x] Verkligt event-/tråd-ID med fel scope gav neutralt tomläge utan främmande data.
- [x] `REL02-I-03` Back/forward: Android system-back och webbläsarens back/forward bevarar canonical route utan loop eller data från fel kontext.
  - [x] Android-back: persondetalj, direkttråd, Min assistent och eventeditor med båda grenarna för osparade ändringar.
  - [x] Webb: Hem → Laget → Kalender → Inbox och tre steg bakåt/framåt bevarade routeordning och lagkontext 2026-08-30.
- [x] `REL02-I-04` Kontextbyte: byt snabbt mellan två lag under pågående laddning; sent svar får inte skriva över vald kontext.
  - [x] Automatiserad stale-response-grind finns.
  - [x] Fysisk webb: snabb växling `Thomas lag` → tillfällig verifieringskontext → `Thomas lag` behöll senast vald kontext utan sent överskrivande svar.
  - [x] Fixture-ID:n är registrerade utan personnamn eller privat innehåll; cleanup avslutade tillfälliga relationer och tog bort extralaget med historiska referenser bevarade.
- [x] `REL02-I-05` Offline: bryt nätet efter laddning; tidigare data märks stale och mutationer misslyckas säkert utan falsk framgång.
  - [x] Laddade Inbox-trådar bevaras och märks `Visar senast verifierade data` efter misslyckad refresh.
  - [x] Webbens DevTools Offline blockerade eventskapande med begripligt fel; ingen falsk framgång eller listpost skapades och normal refresh fungerade efter återanslutning.
- [x] `REL02-I-06` Reconnect: automatisk backoff-resync tar bort stale-markering utan dubbletter och bevarar `Thomas lag`.
- [x] `REL02-I-07` Session expiry: lokal sessionsförlust och riktig serveråterkallelse ger fail-closed inloggning utan återställd klubbdata.
  - [x] Webb: rensad lokal site/session-data gav ren inloggning utan gammal kontext eller tekniskt fel; ny inloggning återställde `Thomas lag`.
  - [x] En aktiv testsession återkallades server-side; reload gick direkt fail-closed till inloggning.

## 5. Kör tillgänglighetsmatrisen

- [x] `REL02-A-01` Skärmläsare: svensk TalkBack på telefon godkänd för Hem, Laget, Kalender/Månad, Inbox/direkttråd och Min assistent.
- [x] `REL02-A-02` Tangentbord/fokus: alla interaktiva kontroller nås; modal fångar fokus och återlämnar det vid stängning.
  - [x] Automatiserad fokusordning och modalgrind finns.
  - [x] Lokal releasewebb: tangentbordsinträde via `F6`, `Tab`, `Shift+Tab`, `Enter`, modal fokusfälla, `Esc` och fokusåtergång fysiskt godkända 2026-08-30.
- [x] `REL02-A-03` Text 200 %: phone/tablet/desktop saknar overflow, klippning och blockerade actions.
  - [x] Fysisk telefon, webb och effektiv tabletviewport samt automatiserad phone/tablet/desktop.
- [x] `REL02-A-04` Kontrast: automatiserad AA-grind samt fysisk light/dark-kontroll på telefon för Hem, Kalender, Inbox och Min assistent; status använder text/ikon utöver färg.
- [x] `REL02-A-05` Reduced motion: automatiserad grind och fysisk webbemulering med `prefers-reduced-motion: reduce` behåller navigation, dialoger och återkoppling; Xiaomi-systemtoggle kunde inte aktiveras och noteras separat som enhetsbegränsning.
  - [x] Automatiserat kontrakt verifierar att delade rörelsevaraktigheter blir noll.
  - [n/a] MIUI exponerade ingen fungerande systemtoggle; fysisk webbemulering och automatiserad grind utgör den godkända passeringen.

## 6. Evidence och slutbeslut

- [x] Samtliga JSON-rader har aktuell status och samlad evidence-referens.
- [x] Upptäckta defects är kopplade till matrisfallen och fysiskt omkörda efter rättning.
- [x] Bekräftat att alla 12 roll-/enhetsfall, 7 avbrottsfall och 5 tillgänglighetsfall är `passed`.
- [x] REL-01 är grön.
- [x] Arbetskortets fyra REL-02-punkter är `[x]` och slutlig evidence är dokumenterad.

## 7. Befintlig strukturell täckning

- FND-04 låser fyra roller × fyra grundytor och positiva/negativa actions.
- FND-03 verifierade phone 390×844, tablet 800×1100 och desktop 1440×900 samt cold link/rebuild/back-kontrakt.
- FND-02 täcker stale, offline→online-resync och context-race.
- AUTH-02 täcker sessionåterställning, delad webbenhet och fail-closed session.
- FND-05 täcker semantik, fokus, 200 % text, AA-kontrast och reduced motion, inklusive tidigare fysisk Android-kontroll.

Dessa bevis minskar regressionsrisken men ersätter inte den aktuella samlade REL-02-körningen.
