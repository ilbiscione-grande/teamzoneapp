# REL-02 – steg-för-steg-verifiering

**Status:** `[~]` – matris och körordning fastställda; aktuell fysisk/webbmatris återstår  
**Beroende:** REL-01 måste vara grön innan slutlig klarmarkering  
**Maskinläsbar matris:** `docs/implementation/rel02_verification_matrix.json`

**Automatiserad baslinje 2026-08-28:** `[x]` – alla 12 roll × viewport-fall öppnar Hem, Laget, Kalender och Inbox utan layout-/runtimefel. Detta ersätter inte hosted/fysisk slutkörning.

**Automatiserad samlad grind 2026-08-28:** `[x]` – 43/43 roll-, avbrotts- och tillgänglighetstester passerar via `tool/rel02_automated_gate.ps1`.

## 1. Regler för klarmarkering

- [x] Varje fall har ett stabilt ID och får status `passed`, `failed`, `blocked`, `structural_only` eller `prior_evidence_requires_regression`.
- [x] Äldre bevis får användas som referens men aldrig som aktuell releasepassering.
- [x] Samma buildidentitet ska användas för hela slutmatrisen.
- [x] Ett UI-fall är inte godkänt om serverbehörigheten inte också ger förväntat tillåtet eller nekat resultat.
- [x] Fel ska dokumenteras med reproduktionssteg; raden klarmarkeras först efter regression.
- [ ] Skriv in aktuell buildidentitet, testare och starttid före slutkörningen.
- [x] Kör den lokala 4 × 3-baslinjen med `test/rel02_automated_release_matrix_test.dart`.
- [x] Kör lokal cold-link/back/session/felhantering samt fokus/textskalning/kontrast/reduced-motion.

## 2. Förbered testdata och konton

- [ ] Skapa eller välj ett aktivt testlag med kommande och tidigare träning, match och möte.
- [ ] Säkerställ obesvarad och besvarad kallelse, event med och utan närvaro samt minst två lagkontexter.
- [ ] Förbered separata konton för `leader`, `player`, `guardian` och `club_functionary`.
- [ ] Guardian ska ha två barnrelationer så att acting-as och isolering kan kontrolleras.
- [ ] Klubbfunktionären ska ha ett begränsat mandat och sakna minst en teamcapability för negativ kontroll.
- [ ] Registrera testdata-ID:n utan personnamn eller privata meddelandetexter i evidencen.

## 3. Kör roll × enhet

Kör `REL02-RD-01`–`REL02-RD-12` i JSON-matrisen. För varje kombination:

1. [ ] Logga in med rätt separat testkonto och bekräfta synlig roll/kontext.
2. [ ] Öppna Hem; kontrollera rollens prioriteringar och att förbjudna actions saknas.
3. [ ] Öppna Laget → Översikt, Trupp och Kalender; kontrollera dataminimering och behörighetsstyrda actions.
4. [ ] Öppna Kalender och ett EventDetails; kontrollera Info, Deltagare, Förberedelser och Uppföljning.
5. [ ] Öppna Inbox; kontrollera tillåtna trådar, announcement, unread och förbjudna mottagare.
6. [ ] Kontrollera att mobil prioriterar snabba actions, tablet planering/master-detail och desktop/web administration.
7. [ ] Spara skärmbild eller loggreferens och markera fallet `passed`, `failed` eller `blocked`.

Godkännandekrav per roll:

- [ ] Leader: skapa/redigera event, deltagare, kallelse och närvaro endast med capability.
- [ ] Player: egna kallelser/event men ingen roster-, närvaro- eller eventadministration.
- [ ] Guardian: explicit valt barn följer query/mutation; andra barns data läcker inte.
- [ ] Club functionary: endast klubbmandat; ingen implicit coach-, ekonomi-, styrelse- eller teamsuperaccess.

## 4. Kör avbrottsmatrisen

- [ ] `REL02-I-01` Cold start: tvångsstäng och starta; endast fortsatt giltig session/kontext återställs.
- [ ] `REL02-I-02` Deep link: kallstarta `/team`, `/calendar?event=…`, `/inbox?thread=…` och `/assistant`; fel scope ger neutral fallback.
- [ ] `REL02-I-03` Back/forward: Android system-back och webbläsarens back/forward bevarar canonical route utan loop eller data från fel kontext.
- [ ] `REL02-I-04` Kontextbyte: byt snabbt mellan två lag under pågående laddning; sent svar får inte skriva över vald kontext.
- [ ] `REL02-I-05` Offline: bryt nätet efter laddning; tidigare data märks stale och mutationer misslyckas säkert utan falsk framgång.
- [ ] `REL02-I-06` Reconnect: återställ nätet; exakt resync sker utan dubbletter och användarens valda kontext består.
- [ ] `REL02-I-07` Session expiry: återkalla/utgång session ger fail-closed yta, neutral förklaring och säker ny inloggning.

## 5. Kör tillgänglighetsmatrisen

- [ ] `REL02-A-01` Skärmläsare: navigation, badges, status, formulärfel och AC-ingång har begriplig ordning och etikett.
- [ ] `REL02-A-02` Tangentbord/fokus: alla interaktiva kontroller nås; modal fångar fokus och återlämnar det vid stängning.
- [ ] `REL02-A-03` Text 200 %: phone/tablet/desktop saknar overflow, klippning och blockerade actions.
- [ ] `REL02-A-04` Kontrast: light/dark/system och status använder text/ikon utöver färg samt uppfyller AA.
- [ ] `REL02-A-05` Reduced motion: rörelser reduceras utan att statusövergång eller feedback försvinner.

## 6. Evidence och slutbeslut

- [ ] Fyll samtliga JSON-rader med aktuell status och evidence-referens.
- [ ] Länka alla defects till exakt matris-ID och kör om efter rättning.
- [ ] Bekräfta att alla 12 roll-/enhetsfall, 7 avbrottsfall och 5 tillgänglighetsfall är `passed`.
- [ ] Bekräfta att REL-01 är grön.
- [ ] Uppdatera arbetskortets fyra REL-02-punkter till `[x]` och skriv slutligt evidence.

## 7. Befintlig strukturell täckning

- FND-04 låser fyra roller × fyra grundytor och positiva/negativa actions.
- FND-03 verifierade phone 390×844, tablet 800×1100 och desktop 1440×900 samt cold link/rebuild/back-kontrakt.
- FND-02 täcker stale, offline→online-resync och context-race.
- AUTH-02 täcker sessionåterställning, delad webbenhet och fail-closed session.
- FND-05 täcker semantik, fokus, 200 % text, AA-kontrast och reduced motion, inklusive tidigare fysisk Android-kontroll.

Dessa bevis minskar regressionsrisken men ersätter inte den aktuella samlade REL-02-körningen.
