# TeamZone grundapp – implementerbara arbetskort

**Status:** AKTIVT ARBETSDOKUMENT (senast uppdaterat 2026-10-01)  
**Upprättat:** 2026-08-23  
**Källa:** fastställd paritetsmatris och fastställd arbetsplan  
**Livegräns:** inga Supabase-liveändringar utan separat uttryckligt godkännande

## 1. Så används dokumentet

Det här är genomförandelagret under:

- `docs/implementation/core_app_workplan.md`
- `docs/implementation/core_app_parity_matrix.md`
- `docs/implementation/min_assistent_concept.md`

Status:

| Status | Betydelse |
|---|---|
| `[ ]` | Inte påbörjad |
| `[~]` | Pågår eller endast delvis verifierad |
| `[x]` | Samtliga acceptanskriterier och verifieringsgrindar är godkända |
| `[n/a]` | Ersatt av ett dokumenterat produktbeslut |

Ett kort får inte markeras `[x]` enbart för att en teknisk grund redan finns. Den godkända produktupplevelsen, robustheten och verifieringen måste också vara klar.

## 2. Fasta genomföranderegler

- Gamla `C:/Dev/TeamZone` används endast som skrivskyddad referens.
- Paketidentiteten förblir `com.teamzone.teamzone`.
- Befintliga lokala ändringar bevaras och återställs inte.
- Ingen import eller kompatibilitetskoppling mot gamla databaser byggs.
- Supabase-live, produktionsprovisionering, webtools och workspaces ligger utanför kortens automatiska behörighet.
- Klienter använder endast publika/publishable nycklar. Service role eller secrets får aldrig nå klienten.
- Exponerade dataytor är deny-by-default, tenantbundna och capabilitystyrda.
- Säkerhetskritiska kommandon är serverauktoriserade, idempotenta där retry kan ske och auditloggade.
- Varje kort ska bevara säkra loading-, empty-, stale-, offline-, error- och retry-lägen.

## 3. Leveransvågor

| Våg | Mål | Kort | Startvillkor |
|---|---|---|---|
| 0 | Stabil klientgrund | FND-01–FND-05 | Paritetsmatris fastställd |
| 1 | Inloggning och organisationsstart | AUTH-01–AUTH-07 | FND-01–FND-04 |
| 2 | Lagets fas 1 | TEAM-01–TEAM-08 | AUTH-05–AUTH-07 |
| 3 | Kalender och EventDetails | CAL-01–CAL-10 | TEAM-03–TEAM-06 |
| 4 | Publik klubbsajt | PUB-01–PUB-06 | TEAM-01, CAL-01, publiceringsgrindar |
| 5 | Inbox och notiser | MSG-01–MSG-08 | AUTH-06, TEAM-03 |
| 6 | Rollspecifikt Hem | HOME-01–HOME-05 | TEAM/CAL/MSG stabila läsmodeller |
| 7 | Min assistent-grund | AC-01–AC-08 | HOME-04 och stabila domänsignaler |
| 8 | Senare funktioner | LATER-01–LATER-04 | Separat prioriteringsbeslut |
| 9 | Samlad releasegrind | REL-01–REL-03 | Våg 0–6 klara |
| 10 | Utbyggnad efter grundappen | TEAM-09–TEAM-16, CAL-12–CAL-14, MSG-09, PROF-01–PROF-04, AUTH-08, PUB-10–PUB-13, SET-01 | Produktägarens prioriteringar efter 2026-09-26 |

Endast en våg ska normalt vara produktmässigt `pågår`. Tekniskt fristående verifiering kan ske parallellt när det inte skapar konkurrerande kontrakt.

## 4. Våg 0 – stabil klientgrund

### FND-01 – Dela upp produktens appfil utan beteendeförändring

**Status:** `[x]`  
**Paritet:** UX-01, UX-06  
**Beroenden:** inga  
**Nuläge:** `lib/src/app/teamzone_app.dart` innehåller flera stora produkt- och detaljytor i samma fil.

- [x] Flytta auth, shell/router, roster, calendar, inbox och overview till namngivna featurefiler.
- [x] Behåll befintliga routes, deep links, state och visuellt beteende under extraktionen.
- [x] Gör ytorna testbara utan privat åtkomst genom hela appfilen.
- [x] Förhindra cirkulära featureberoenden; gemensamt läggs under `shared` eller `core`.
- [x] Kör formattering, analys och hela Flutter-testsviten efter varje säker delning.

**Godkänd när:** appfilen äger bootstrap/router/shell men inte featureimplementation, och befintliga kontraktstester passerar oförändrade.

### FND-02 – Gemensam async-, fel-, stale- och offlinekontrakt

**Status:** `[x]`  
**Paritet:** UX-03, UX-04, UX-05  
**Beroenden:** FND-01

- [x] Definiera en gemensam vy-state för initial load, refresh, data, empty, stale, offline och safe error.
- [x] Ignorera resultat från gammal klubb-/lagkontext efter kontextbyte eller avmontering.
- [x] Definiera per mutation om offline ska blockeras, köas eller kräva explicit retry.
- [x] Visa Realtime-status på relevanta ytor och gör deterministisk full resync efter gap.
- [x] Säkerställ att råa backendfel aldrig visas och att retry inte duplicerar mutationer.

**Verifiering:** race-test för kontextbyte, offline/reconnect-test, stale-cache-test och widgettest för samtliga huvudstatusar.

### FND-03 – Gemensamma formulär-, lista- och navigationsmönster

**Status:** `[x]`  
**Paritet:** AUTH-01–AUTH-07, TEAM-03, CAL-01–CAL-05, MSG-01  
**Beroenden:** FND-01

- [x] Gemensam validering, pending/double-submit-skydd och varning för osparade ändringar.
- [x] Gemensam sök/filter/sortering/pagination/refresh-modell.
- [x] Kanoniskt deep-linkkontrakt för huvudytor och definierade detaljvyer.
- [x] Android back, web refresh samt browser back/forward bevarar rätt behörig kontext.
- [x] Centrala breakpointtokens används utan lokala konkurrerande gränser.
- [x] Navigationsskalet (appbar, drawer/sidopanel, bottom nav) byggdes om 2026-09-07 efter en referensbild.
- [x] Appbaren byter färg bara vid helsidescroll, inte när en lista under ett fast sidhuvud scrollar (2026-10-05).
- [x] Genvägsmenyn (svep upp på Hem) leder med den aktuella sidans åtgärder under "Gör nu"; övriga åtgärder och
  destinationer ligger i varsin horisontellt scrollande rad. Nya direktlänkar för lagets roller och
  kontaktuppdatering, informationsmeddelande och förvald eventtyp (2026-10-05).

**Verifiering:** phone/tablet/desktop widgetmatris samt navigationstest för cold link, refresh och back.

**Aktuellt navigationsskal** (`lib/src/app/product_shell.dart`, `product_routes.dart`, `lib/src/shared/layout/app_breakpoints.dart`):

- **Appbar:** tvåradig lag-/klubbväljare till vänster (`_ContextTwoLineLabel` — lagnamn fetstil överst, klubbnamn mindre därunder; tryck öppnar `_showContextPicker`-bottom sheeten). På telefon visas dessutom en profilavatar längst till höger som öppnar drawern via `_scaffoldKey.currentState?.openDrawer()` — och stängs sedan 2026-09-07 via samma nyckels `.closeDrawer()` när en meny-rad trycks (`_AppNavigationPanel.closeDrawer`), inte `Navigator.pop` som tidigare tyst gjorde ingenting eftersom en Scaffold-drawer inte är en route på den yttre Navigatorn.
- **Meny-innehåll** delas mellan telefonens drawer och tablet/desktops permanenta sidopanel av samma widget, `_AppNavigationPanel`: profilhuvud (avatar, namn, rollpaket), lagväljarraden, huvuddestinationerna i `_drawerMainOrder` (Hem, Kalender, Laget, Inbox, Statistik), `Utveckling`, ett kluster med capabilitystyrda adminlänkar (Abonnemang/Ekonomi/Styrelse/Nyhetsredaktion — visas bara om rollen har respektive capability) samt Inställningar/Logga ut och en "TeamZone"-vinjett längst ner. Listan har nyckeln `Key('app-navigation-panel-list')` så test kan scrolla dit. **Inställningar** öppnar sedan 2026-09-07 inte längre en liten bottom sheet utan en egen sida, `_ProfileSettingsSurface` (`lib/src/features/account/profile_settings_surface.dart`, route `ProductRouteContract.settings` = `/settings`), med sektioner för "Mina lagkopplingar" (lista över lag-/rollkopplingar plus en "Använd kod"-åtgärd), "Färgtema" (välj mellan Grön/Blå/Lila/Orange, se nedan) och "Integritetsinställningar" (marknadsföringstogglen, tidigare `_MarketingPreferenceSheet`). Panelens **bakgrund** är sedan 2026-09-07 en mörk toning i det valda temats accentfärg (`AppColorTheme.heroGradient`, ljusare upptill mot nästan svart nedtill) i stället för Materials vanliga ljusa `Drawer`-yta, med panelens eget innehåll omkopplat till ett lokalt mörkt `Theme` så text/ikoner förblir läsbara oavsett appens ljus/mörkt-läge.
- **Bottom nav (endast telefon):** exakt fem knappar i ordningen Laget, Kalender, Hem, Inbox, Statistik (`_bottomNavOrder` i `product_routes.dart` — notera att ordningen medvetet skiljer sig från drawerns läsordning för att hålla Hem i mitten).
- **Brytpunkter** (`AppBreakpoints`): `usesNavigationRail`/sidopanelen slår på vid ≥600 px (tablet+desktop, ersätter drawern med en permanent 280 px `SizedBox(key: Key('permanent-navigation-sidebar'))`). Native tablet använder alltid Min assistent-FAB oavsett orientering eller rapporterad bredd; sidans högra kolumn reserveras för funktionens egen kontextuella information. En permanent assistentpanel kräver en verklig desktopyta på ≥1024 px.
- **Medvetet uteslutet:** mockupens "Workspaces" (Planering/Träning/Match/Spelarutveckling/Lagsutveckling) och "Web Tools" (Taktiktavla/IDP) — användarens val, eftersom de flesta av dessa poster inte motsvarar riktiga funktioner i appen än. Lägg till dem i `_AppNavigationPanel` när/om respektive funktion finns på riktigt.
- **Systemets tillbaka-knapp** (Android): `_ProductShellState` håller sedan 2026-09-07 en `_locationHistory`-lista (synkad via en listener på `_router.routeInformationProvider`, eftersom `.go()` — bottom nav/drawer — ersätter aktuell plats i stället för att lägga till ett historikposet) och en `PopScope` som stegar tillbaka genom besökta sidor en i taget; på den allra första sidan som öppnades den här sessionen visas i stället en "Stäng TeamZone?"-bekräftelse. Dialoger och `_router.push`-ytor (Min assistent) poppas fortsatt av GoRouters egen back-button-dispatcher innan `PopScope` någonsin nås.

### FND-04 – Roll- och situationsmatris

**Status:** `[x]`  
**Paritet:** HOME-01–HOME-05, TEAM-02–TEAM-09, UX-01  
**Beroenden:** FND-01

- [x] Dokumentera mål, viktig information och primära actions för leader, player, guardian och klubbfunktionär per prioriterad yta.
- [x] Markera data/actions som varje roll uttryckligen inte får se.
- [x] Dokumentera mobil under aktivitet, tabletbaserad planering och desktop/web-administration.
- [x] Översätt matrisen till tester som verifierar både synlighet och frånvaro.

**Godkänd när:** varje huvudkort kan hänvisa till ett fast roll- och situationskontrakt.

### FND-05 – Tillgänglighet och lokalisering som kontrakt

**Status:** `[x]`  
**Paritet:** UX-02, UX-07, UX-08  
**Beroenden:** FND-01–FND-03

- [x] Verifiera 48 px touchmål, semantik, fokusordning, tangentbord och reduced motion.
- [x] Verifiera textskalning och kontrast i telefon-, tablet- och desktoplayout.
- [x] Inga nya hårdkodade blandade sv/en-strängar i kärnflöden.
- [x] Ikon/färg används aldrig som enda informationsbärare.

**Verifiering:** automatiserade kontraktstester plus dokumenterad manuell tillgänglighetskontroll.

## 5. Våg 1 – Inloggning och organisationsstart

### AUTH-01 – Tydlig start: Logga in och Skapa konto

**Status:** `[~]` – lokalt implementerad och verifierad; hosted Auth REST-nivå delvis verifierad 2026-09-04, e-postleverans/dubblett/fysisk grind återstår  
**Paritet:** AUTH-01–AUTH-04  
**Beroenden:** FND-02, FND-03, FND-05

- [x] Separata begripliga ingångar för `Logga in` och `Skapa konto`.
- [x] Både lösenord och e-postkod/magic link erbjuds.
- [x] Kontoskapande kräver verifierad e-post utan dubblettidentitet.
- [x] Glömt lösenord visar neutralt svar och återupptar rätt vy via deep link.
- [x] OTP/resend har cooldown, expiry, pending och återhämtningsbar fel-UX.

**Verifiering:** widgettest, auth-emulator/hosted godkänd testmiljö, secret/log-redaction och deep-linktest. Live kräver separat godkännande. Hosted GoTrue REST-anrop 2026-09-04 bekräftade svagt-lösenord-avvisning, neutralt recovery-svar för okända adresser, aktiv domänvalidering, aktiv inbyggd mejl-rate-limit och inga läckta hemligheter i API-svaren (`docs/evidence/auth01_entry_flows_2026-08-23.md`). E-postleverans, dubblettbeteende för en verkligt existerande adress, redirect-allowlist och serverloggar kräver fortsatt en läsbar inkorg eller fysisk enhet.

### AUTH-02 – Session, återkallelse och utloggning

**Status:** `[~]` – lokalt implementerad och verifierad; fysisk/hosted sessiongrind återstår  
**Paritet:** AUTH-05, AUTH-12–AUTH-14  
**Beroenden:** AUTH-01, FND-02

- [x] Mobil återställer säker session; web kan väljas som delad enhet.
- [x] Utgången/återkallad session ger tydlig återhämtning och fail-closed data.
- [x] Utloggning rensar lokal känslig state och ogiltigförklarar pågående förfrågningar.
- [x] Senast giltiga kontext återställs; avslutad/suspenderad relation avvisas.

**Verifiering:** cold start, token/session expiry, sign-out, flera kontexter och cross-context-race.

### AUTH-03 – Inbjudan och säker claim

**Status:** `[x]` – hosted databas/Edge samt fysisk webb- och Android-deep-linkgrind verifierade  
**Paritet:** AUTH-06, AUTH-15, TEAM-07, TEAM-08  
**Beroenden:** AUTH-01, AUTH-02

- [x] Invitekod/-länk kan tas emot före eller efter auth och återupptas efter verifiering.
- [x] Preview visar klubb, lag, person/roll och giltighet före acceptans.
- [x] Acceptans är scopead, tidsbegränsad, single-use/idempotent och dubblettsäker.
- [x] Kontot binds till samma förskapade personpost; namnlikhet ensam får aldrig claima.
- [x] Konflikt går till manuell granskning utan dataexponering.

**Verifiering:** replay/race, fel mottagare, fel tenant, utgången invite och dubblettkonflikt.

### AUTH-04 – Sök klubb/lag och medlemsansökan

**Status:** `[x]` – hosted runtime samt fysisk Android-grind för sökande och reviewer verifierade
**Paritet:** AUTH-07, AUTH-10, AUTH-14  
**Beroenden:** AUTH-01, FND-03

- [x] Sökningen returnerar endast tillåten minimal information.
- [x] Officiell status visas med text och ikon.
- [x] Ansökan väljer klubb, lag och avsedd relation/roll.
- [x] Vänteläge visar status, återkallelse och nästa steg.
- [x] Behörig mottagare kan godkänna/avslå med audit i serverkontraktet och
  capabilityanpassad reviewer-UI.
- [x] Reviewer kan godkänna med korrigerad roll; ansökt och tilldelad roll
  bevaras separat och en avvikelse auditloggas.

**Verifiering:** enumerationsskydd, outsider/cross-club, dubblettansökan och avstängd relation.

### AUTH-05 – Skapa klubb och första lag

**Status:** `[x]` – hosted runtime samt fysisk Android-grind verifierade 2026-09-10
**Paritet:** AUTH-08, AUTH-09  
**Beroenden:** AUTH-01, AUTH-02

- [x] Verifierad ny användare kan skapa inofficiell klubb och första lag atomiskt.
- [x] Skaparen får beslutad administrativ relation och en användbar aktiv kontext.
- [x] Behörig klubbadministratör kan senare skapa ytterligare lag.
- [x] Delvis misslyckande lämnar inte en föräldralös klubb, relation eller lagpost.

**Verifiering:** idempotent retry, duplicate submit, rollback och omedelbart kontextbyte.

### AUTH-06 – Skyddade namn och officiell klubb

**Status:** `[x]` – hosted, automatiskt och fysiskt Android-verifierad inklusive supportärenden
**Paritet:** AUTH-10, AUTH-11  
**Beroenden:** AUTH-04, AUTH-05

- [x] Normaliserat namn, kända varianter/förkortningar och förväxlingsrisk kontrolleras före skapande.
- [x] Utomstående kan inte skapa en förväxlingsbar officiell kopia.
- [x] Användaren kan begära verifiering och följa status.
- [x] Endast TeamZone kan godkänna, avslå eller återkalla officiell status.
- [x] Alla beslut och underlagshändelser auditloggas och klienten kan inte själv sätta status.

**Verifiering:** homoglyph/normalisering, reserverat namn, nekad klientmutation och tillgänglig statusvisning.

**Supportdrift 2026-10-03:** Officiella klubbansökningar och tre övriga
plattformstyper samlas i `/support` och aviseras genom en privat Supabase-outbox,
minutcron och Edge Function till Resend. `support@teamzoneapp.se` tas emot genom
ImprovMX och vidarebefordras till den operativa inkorgen. Endast det separata
mottagarregistret får mejl; supportadministratörernas privata kontoadresser
används enbart för behörighet och spårbara beslut. Se
[`../operations/support_email_runbook.md`](../operations/support_email_runbook.md)
och
[`../evidence/support_club_verification_queue_2026-10-03.md`](../evidence/support_club_verification_queue_2026-10-03.md).

**Supportflöde 2026-10-04:** Ett godkänt ärende om skyddat klubbnamn kan
slutföra skapandet av officiell klubb, första lag, sökandens klubbfunktionärsroll
och publik kontext i en idempotent transaktion. Support och sökande kan föra en
ärendebunden dialog med privata bilagor. Sökanden hittar ärendet i Inbox med
oläst-räknare; konton utan aktiv lagkontext behåller ingången i vänteläget. Se
[samlad iteration 2026-10-02–2026-10-04](../evidence/core_app_iteration_2026-10-02_10-04.md).

### AUTH-07 – Villkor, integritet och frivilliga samtycken

**Status:** `[~]` – tekniskt hosted-verifierad och publika placeholderroutes driftsatta; juridiskt slutligt innehåll och fysisk slutgrind återstår och blockerar extern publik lansering
**Paritet:** beslut i arbetsplan steg 3A  
**Beroenden:** AUTH-01

- [x] Versionerad acceptans av användarvillkor och läst integritetspolicy.
- [x] Marknadsföring är separat, frivillig och aldrig förvald.
- [x] Väsentligt nya villkor kräver nytt uttryckligt godkännande.
- [x] Minderårig-/guardianbeslut blandas inte ihop med generella villkor.

**Verifiering:** versionsbyte, nekad obligatorisk acceptans, frivillig opt-out och auditspår.

## 6. Våg 2 – Lagets fas 1

### TEAM-01 – Lagets tre grundflikar

**Status:** `[x]` – hosted, 367/367 regression samt fysiskt verifierad på mobil, tabletresponsiv webb och desktop/webb inklusive deep link/refresh/back  
**Paritet:** TEAM-01, TEAM-17, TEAM-18  
**Beroenden:** FND-03, FND-04

- [x] Exakt `Översikt`, `Trupp`, `Kalender`.
- [x] Kalenderfliken visar kommande som standard, växlar till tidigare, samlar eventtyp bakom filterknapp och visar färdiga matchresultat.
- [x] Listpost öppnar samma EventDetails som huvudkalendern.
- [x] Deep link, refresh och mobilnavigation bevarar vald flik.

### TEAM-02 – Rollstyrd lagöversikt

**Status:** `[x]` – hosted SQL/privat Storage och räknarfixture, 369/369 regression samt fysisk webb- och Androidgrind inklusive upload/byte/borttagning/fallback och 200 % text verifierade  
**Paritet:** TEAM-02, HOME-06  
**Beroenden:** TEAM-01, AUTH-03, AUTH-04

- [x] Lagbild, grundinformation, ledare och relevanta genvägar visas.
- [x] Behöriga ledare ser aktiva invites, väntande ansökningar och åtgärdsbehov.
- [x] Player/guardian ser inte administrativa ärenden utan capability.
- [x] Tom lagbild/information har professionellt fallbackläge.
- [x] Behörig användare kan redigera lagtyp, åldersklass och presentation samt välja, förhandsvisa, byta och ta bort en privat lagbild; staging, upload och profilaktivering är capabilitystyrda, revisionerade, idempotenta och auditloggade.

**Mediagräns:** privat lagbilduppladdning är aktiv med JPG/PNG/WebP, 5 MB-gräns, exakt stagingnyckel, privat bucket, aktiv-profilbunden SELECT-RLS och signerad läsning. Originalet blir aldrig automatiskt publikt; skanning/transformering och publik variant tillhör fortfarande PUB-04.

### TEAM-03 – Trupplista och medlemsdetalj

**Status:** `[x]` – hosted SQL-runtime, 22/22 riktad regression samt ny enhetlig detaljsida fysiskt verifierad på webb och Android  
**Paritet:** TEAM-03, TEAM-06, TEAM-09  
**Beroenden:** TEAM-01, FND-02–FND-05

- [x] Sök/filter/status och pagination fungerar i stora trupper.
- [x] Detalj visar endast rolltillåtna lag- och spelaruppgifter; kontaktfält saknas i nuvarande schema och exponeras därför inte.
- [x] Guest/okänd roll får begriplig fail-closed upplevelse.
- [x] Mobil, tablet, desktop och webb använder samma egna detaljsida med kopierbar route och säker bakåtnavigering till Trupp.

**Verifierat:** releasewebb öppnar kopierbar medlemsroute; Xiaomi Mi 9 öppnar samma helsida och Android-back återgår till Trupp. Den tidigare tvåpanels-/sheetpresentationen är ersatt och utgör ingen kvarstående grind.

### TEAM-04 – Skapa och redigera rosterperson

**Status:** `[x]` – hosted SQL-runtime samt fysisk webb-, Android- och tabletgrind verifierade  
**Paritet:** TEAM-04, TEAM-05  
**Beroenden:** TEAM-03

- [x] Person, klubbpost och lagrepresentation skapas atomiskt och dubblettsäkert.
- [x] Namn och åldersklass används inte som personidentitet; flera verkliga personer får dela båda värdena och tekniska retries dedupliceras enbart med idempotensnyckeln.
- [x] Personer har obligatoriskt födelseår och valfritt exakt födelsedatum som kan kompletteras senare; generell trupp visar endast år och exakt datum är privat managementdata.
- [x] Klubben redigerar endast sin tenantägda rosterinformation.
- [x] Global identitet skrivs inte över av lokal lagredigering.
- [x] Formulär har pending, safe validation och osparade ändringar.

**Verifierat:** webb, Xiaomi Mi 9 och fysisk Android-tablet är godkända för create/edit, samma namn+år, osparat-skydd, årsväljare samt valfri senare komplettering av exakt datum.

### TEAM-05 – Guardian och riktad inbjudan

**Status:** `[x]` – hosted API/Edge samt fysisk invite-, lagkod-, guardian- och webb-deep-linkgrind verifierade  
**Paritet:** TEAM-07, TEAM-08, AUTH-15  
**Beroenden:** AUTH-03, TEAM-04

- [x] Riktad invite och generell lagkod har tydlig status, expiry och revoke.
- [x] Guardianrelation verifieras och kan avslutas säkert.
- [x] Acting-as och barnets integritet bevaras i alla följdflöden.

**Verifierat:** riktad invite, lagkod, guardianrelation och webb-deep-link före/efter inloggning fungerar mot den godkända testmiljön. Android/iOS-deep-linkverifiering spåras separat av AUTH-03.

**Runtimefix 2026-09-01:** fysisk webbtest hittade att adminlistans direkta `UNION ALL`-sortering gav HTTP 400. Projektionen kapslades före sortering, 5/5 regression passerade och hosted körning gav `runtime_ok=true` utan datamutation.

**Invite-UX-fix 2026-09-01:** tyst avbruten riktad invite vid ogiltig e-post ersattes med fältvalidering som håller dialogen öppen. Dialogen gjordes skrollbar och controller-livscykelfelet togs bort; TEAM-05 passerar 6/6 och konfigurerad webbbuild är uppdaterad.

**Invite-behörighetsfix 2026-09-01:** HTTP 403 för lagledares riktade invite spårades till en klubbomfattad kontroll med `team_id = null`. Hosted-funktionen kräver nu i stället en aktiv mottagarplacering i ett lag som aktören administrerar, eller befintlig klubbomfattad behörighet. Runtimekontrollen lyckades i en helt återställd transaktion och fysisk omtest är godkänd.

**Fysisk invite-verifiering 2026-09-01:** riktad kod skapas, posten visas och återkallelse ger status `revoked`. Backendflödet är godkänt; råstatusen är lokalt mappad till svenska `Återkallad` inför nästa webbbuild.

**Återvisningsbar lagkod 2026-09-01:** nya delade lagkoder lagras krypterat i Supabase Vault utöver claim-hashen och kan visas/kopieras igen av behörig lagledare. Varje reveal auditloggas och direkt Vaultåtkomst saknas för klientrollen. Hosted create/reveal/audit passerar i rollback-transaktion, riktad klientanalys är ren och konfigurerad webbbuild serveras på port 5000; fysisk omtest återstår. Äldre lagkoder måste roteras eftersom deras klartext aldrig lagrades.

**Guardian-UX och behörighet 2026-09-01:** guardianinvite-felet spårades till att testlaget saknade markerat barn och att backend endast kontrollerade klubbomfattad safeguardingbehörighet. Personredigeringen kan nu markera behov av vårdnadshavarkoppling, dialogen filtrerar barn och backend begränsar ledaren till barnets aktiva lag. Hosted kommando/invite/audit och klientanalys passerar; fysisk omtest återstår.

### TEAM-06 – Behörighet att representera andra lag

**Status:** `[x]` – hosted runtime och fysisk Android-tabletgrind verifierade  
**Paritet:** TEAM-10  
**Beroenden:** TEAM-03, säsongskontrakt

- [x] Typ: utvecklingsspel, dispens, lån eller gästspel.
- [x] Giltighet: säsong, valt slutdatum eller tills vidare.
- [x] Säsongsbundna behörigheter upphör vid säsongsslut; tillsvidare granskas regelbundet.
- [x] Ordinarie lag och historiska fakta ändras inte.
- [x] Servern validerar representation vid eventtidpunkt.

**Verifierat:** fysisk Android-tablet har skapat, listat och avslutat en säsongsbunden representation. Spelarens ordinarie lag låg kvar oförändrat. Responsiv klient och samma serverkommandon används för phone/tablet/desktop; separat formfaktorsomtest är inte en blockerande produktgrind.

### TEAM-07 – Flytta spelare med bevarad historik

**Status:** `[x]`  
**Paritet:** TEAM-11  
**Beroenden:** TEAM-03, TEAM-06

- [x] Flytt inom klubb avslutar tidigare assignment och skapar ny från valt datum.
- [x] Gamla event, närvaro och statistik ligger kvar på historisk representation.
- [x] Överlapp, bakdatering och samtidiga flyttar valideras atomiskt.
- [x] Cross-club använder separat source/target-/guardianflöde.
- [x] Ledare kan markera och flytta flera spelare till samma lag i ett sammanhållet flöde.
- [x] Samma flyttflöde nås från truppverktygen och den enskilda spelarprofilen.

**Verifierat:** hosted rollback-runtime och full Flutter-svit är gröna. På fysisk Android-tablet har en ledare flyttat spelare mellan två lag och tillbaka, verifierat att gammalt lag tappar den aktiva representationen medan mållaget får den, samt godkänt profilgenväg, flerval, samlad resultatdialog och omladdning efter avslutad flytt. Samma responsiva klient och serverkommando används för phone/tablet/desktop; separat formfaktorsomtest är inte en blockerande produktgrind.

### TEAM-08 – Avslutad lagtillhörighet, anonymisering och kontoradering

**Status:** `[x]`  
**Paritet:** TEAM-12  
**Beroenden:** TEAM-03, retention-/integritetspolicy

- [x] **Avsluta i laget** är normalflödet: aktiv lagrepresentation avslutas medan namn, personliga rekord och verksamhetshistorik bevaras.
- [x] Arkiverade/tidigare spelare kan hittas i separat filtrerad vy.
- [x] **Begär anonymisering** är integritetsflödet: identitet och personliga rekord anonymiseras medan neutral laghistorik bevaras; separat laginitiator och klubbapprover krävs.
- [x] **Radera hela kontot** är ett separat globalt flöde som kräver TeamZone-granskning och där initiatorn inte får godkänna själv.
- [x] Anonymiserad neutral representation bevarar nödvändiga verksamhetsfakta och obrutna referenser.
- [x] Raderad identitet kan inte oavsiktligt återkopplas eller återidentifieras.
- [ ] Separata regler för intern namngiven historik och eventuell publicering av arkiverade spelares namn fastställs före extern lansering, med särskild restriktivitet för minderåriga.

**Verifierat:** hosted SQL-runtime, profilomfattande anonymisering och Auth Admin-worker är driftsatta i testprojektet. På fysisk Android-tablet har normal avslutning/återaktivering, dual-control-anonymisering och global kontoradering verifierats med separata användare. Historiken bevaras som en neutral `Tidigare spelare` i rätt lagkontext och det raderade Auth-kontot kan inte längre logga in. Separata regler för eventuell publik namngiven historik är fortsatt en lanserings-/juridikgrind, inte en blockerare för TEAM-08.

**Verifiering:** hela appens relevanta historikvyer körs mot anonymiserad fixture utan fel eller identifierande data.

## 7. Våg 3 – Kalender och EventDetails

### CAL-01 – Kalenderns vyer och filter

**Status:** `[x]`  
**Paritet:** CAL-01, CAL-02  
**Beroenden:** FND-02–FND-05

- [x] Agenda/lista, månad, vecka och dag använder samma datakälla och datumlogik.
- [x] Lag-/eventtypfilter är konsekventa och begripliga.
- [x] DST, nattpass, heldag och timezonegränser testas.
- [x] Mobil/tablet/desktop prioriterar om utan capabilityskillnad.

**Verifierat:** mobil, fysisk Android-tablet och desktop/webb är godkända. Tablet/desktop visar Månad och Vecka till vänster med eventkolumn till höger; Dag visar tidslinje och kommande agenda. Månad kan växla mellan `Vald dag` och hela kalendermånaden. EventDetails återställer vy, datum och filter, och event från Dag-vyns kommande agenda flyttar först kalendern till eventets dag. Native tablet reserverar högerkolumnen för sidan och visar Min assistent som FAB.

### CAL-02 – Skapa och redigera event/serie

**Status:** `[x]`  
**Paritet:** CAL-03–CAL-05, CAL-08  
**Beroenden:** CAL-01, FND-03

- [x] Engångsevent och serie använder validerad typ, tid, plats, lag, audience och status.
- [x] Redigering väljer förekomst, framtida eller hela serien med revision/conflict-skydd.
- [x] Sparade platsförslag är tenantsäkra.

**Verifierat:** typstyrda formulär för träning, match, möte och aktivitet; automatiska titlar; samlingstid med typstandard; start-/slutdatumbaserad serie; samt revisionssäker redigering av `Bara detta`, `Detta och framåt` och `Hela serien`. Hosted SQL, riktade Fluttertester, rollbacktest mot riktig PostgreSQL och fysisk webbgrind är godkända.

### CAL-03 – Delade event och audience

**Status:** `[x]`  
**Paritet:** CAL-06, CAL-07  
**Beroenden:** CAL-02, TEAM-06

- [x] Primärt lag äger eventet; deltagande lag får explicita capabilities.
- [x] Audience styr synlighet/mottagare men aldrig redigeringsrätt.
- [x] Sekundärlagsledare kan bara utföra uttryckligen tillåtna handlingar.

**Verifierat:** fysisk webbgrind 2026-09-19 med riktigt delat event och byte
mellan huvudlag och mottagarlag. `Kan se` visar endast event som tillhör eller
är delade med det aktiva laget och ger inga mutationer för deltagare,
kallelser, förberedelser eller uppföljning. Flerlagsdelning, neutral
delningsmarkör och explicit `Alla lag`-filter är verifierade. En person med
uppdrag i flera deltagande lag visas med en enda person-/eventbunden kallelse.
Riktade CAL-01/CAL-03/CAL-06/CAL-11-tester är gröna.

### CAL-04 – Säker eventlivscykel och radering

**Status:** `[x]`  
**Paritet:** CAL-09  
**Beroenden:** CAL-02

- [x] Opublicerat utkast/oberoende event kan raderas efter konsekvenskontroll.
- [x] Event med publicering, callups, svar, närvaro eller historik ställs in/arkiveras.
- [x] Cancel återkallar relevanta callups och skapar notifieringshändelser atomiskt.
- [x] Permanent radering finns endast i skyddat admin-/retentionflöde.
- [x] Arkiverade event listas separat med orsak och datum, öppnas skrivskyddat och kan återställas med bevarad ursprungsstatus.

**Verifierat 2026-09-20:** delete, cancel, återställning från cancel, archive, separat arkivlista, skrivskyddad arkivdetalj och återställning från arkiv. Hosted recovery-migration och 15 riktade regressionstester är gröna.

**Uppdatering 2026-10-05:** "Ta bort event" gäller nu även planerade och inställda engångsevent så länge ingen kallelse har skickats och eventet saknar skickad trupp, närvaro, matchläge, sponsorlöfte, publik publicering och delning med andra lag (`20261005090000`). Annars ställs eventet in och arkiveras som tidigare; serietillfällen arkiveras alltid. Arkivering kraschade på telefon (`_dependents.isEmpty`) och är rättad. Se [iteration 2026-10-05](../evidence/core_app_iteration_2026-10-05.md).

### CAL-05 – EventDetails informationsarkitektur

**Status:** `[x]`  
**Paritet:** CAL-10, CAL-11  
**Beroenden:** CAL-01, FND-04

- [x] Flikarna heter Info, Deltagare, Förberedelser och Uppföljning.
- [x] Deltagare omfattar urval, kallelser, svar och närvaro — sedan 2026-09-07 inline på fliken själv, se CAL-11 för den fullständiga ombyggnaden (sida i stället för dialog, statusrad, sökbar rosterlista).
- [x] Innehåll/actions anpassas efter eventtyp och roll.
- [x] Mobil visar begripliga fulla namn via rullning/sekundär navigation, inte otydliga förkortningar.

**Verifierat 2026-09-20:** egen responsiv EventDetails-sida, fullständiga horisontellt rullbara fliknamn, desktop och smalt webb-/mobilbrytpunktsläge samt leader-, player-, guardian- och delad `Kan se`-kontext. `Kan se` är administrativt skrivskyddad men användaren kan svara på sin egen kallelse. Analys och 9/9 riktade tester är gröna.

### CAL-06 – En revisionerad deltagardraft

**Status:** `[x]`  
**Paritet:** CAL-11–CAL-13  
**Beroenden:** CAL-03, TEAM-06

- [x] Manuell, alla, grupp och generator fyller samma draft.
- [x] Send låser aktuell draft automatiskt; lock/send validerar eligibility vid eventtidpunkten och fryser revision utan separat låsknapp.
- [x] Late callup och cancel är explicita och skriver inte över tidigare utskick.
- [x] Retry/idempotens och stale revision testas.

**Verifierat 2026-09-20:** fysisk webbgrind godkände manuell, alla behöriga, behörighetsgrupp och generator; helt tomt manuellt utkast; automatisk låsning och första utskick; sena kallelser; samt återkallning utan att personen återkommer som valt utkast eller påverkar andra kallelser. Kallelsesvaren är kompakta och responsiva med valt svar direkt markerat i knappen. Migrationen för tomt manuellt utkast är verifierat applicerad på testprojektet. Analys och 14/14 riktade tester är gröna.

### CAL-07 – Svar, guardian och påminnelse

**Status:** `[x]` – hosted och fysiskt verifierad inklusive tvåkontoflöde, join/leave samt capability revoke/restore  
**Paritet:** CAL-14–CAL-16, CAL-18  
**Beroenden:** CAL-06, TEAM-05

- [x] Player/guardian svarar via samma auktoritativa transition.
- [x] Guardian acting-as verifieras och auditloggas.
- [x] Decline reason skiljer strukturerad anledning från fritext.
- [x] Reminder har cooldown, dedupe och separat leveransstatus.
- [x] Push-actiontoken är scopead, kortlivad och single-use/idempotent.

**Verifierat 2026-09-20:** spelarens Acceptera/Avböj med obligatorisk anledning och vald svarsknapp, ledarens Påminn med bestående `Påmind`, samt behörighetsfiltrerad avböjandeorsak på deltagarraden är fysiskt godkända. Migrationen finns hosted och 12/12 riktade tester samt analys är gröna.

**Guardian verifierad 2026-09-20:** `Testspelare S04` kunde avböjas via guardian acting-as; raden märktes `Svara som vårdnadshavare` och visade sparad orsak. En separat direkt kallelse märktes `Din kallelse`, så relationstypen är synlig i gränssnittet.

**Återstår:** push-actiontoken. Extern pushleverantör ingår inte i denna grind.

### CAL-08 – Närvaro

**Status:** `[x]`  
**Paritet:** CAL-17, HOME-06  
**Beroenden:** CAL-06

- [x] Unknown, present, late, partial och absent är separata tillstånd.
- [x] Unknown räknas aldrig som present eller frånvarande.
- [x] Batchmutation är atomisk; sen ändring kräver capability och revisionsspår.
- [x] Mobilregistrering under aktivitet är snabb och har säkert retrybeteende.
- [x] `event.attendance.correct_late` beviljas lagledare (2026-09-07, se ändringslogg) — capabiliteten kontrollerades men delades aldrig ut innan dess.

**Verifierat 2026-09-20:** fysisk webbgrind godkände atomisk flerradssparning, bestående status, Sen/Delvis med synligt minutfält och bestående minutantal samt efterföljande korrigering. Smal mobilvy verifierade användbar radlayout utan overflow. 13/13 riktade tester och analys är gröna.

### CAL-09 – Förbered gränser för senare planeringsfunktioner

**Status:** `[x]`  
**Paritet:** CAL-19–CAL-22  
**Beroenden:** CAL-05

- [x] Import, anteckningar, bilagor och fulla match-/träningsworkspaces ligger inte i första leveransen.
- [x] Nuvarande data- och navigationsgränser blockerar inte senare tillägg.
- [x] Inga tomma eller falskt aktiva funktioner visas i kärn-UX.

**Verifierat:** fysisk telefon-, tabletresponsiv och desktop/webb-kontroll finns i REL-02 samt senare CAL-01/CAL-05-genomgångar. EventDetails och dess rollstyrda, responsiva navigation är godkända utan falskt aktiva ytor för uppskjutna funktioner.

### CAL-10 – Ledarstyrd synlighet för kallelser

**Status:** `[x]`  
**Beroenden:** CAL-05–CAL-07

- [x] Varje event har en ledarstyrd inställning för om spelare och guardians får se andra kallade.
- [x] Standardvärdet är privat: spelaren ser endast sin egen kallelse och guardian endast valt barns kallelse.
- [x] När ledaren aktiverar delning får deltagarna se vilka som kallats och deras kallelsestatus; närvaro och administrativa uppgifter exponeras aldrig.
- [x] Ledare med deltagarbehörighet ser fortsatt hela kallelseunderlaget oberoende av inställningen.
- [x] Regeln verkställs i serverprojektionen och kan inte kringgås genom direkta RPC-anrop eller deep links.
- [x] EventDetails deltagarhantering visar inställningen begripligt, inklusive att privat är rekommenderat standardläge.
- [x] Ändringen revisionsskyddas och auditeras; automatiska kontraktstester täcker privat standardläge och projektionen.

**Verifierat:** leader kan slå av/på inställningen. Player och guardian ser endast egen respektive valt barns kallelse i privat läge och hela kallade-listan i delat läge, men aldrig andra deltagares närvaro eller administrativa åtgärder. Testeventet återställdes därefter till rekommenderat privat läge.

### CAL-11 – Deltagare-fliken: sökbar rosterlista och egen sida

**Status:** `[x]`  
**Paritet:** CAL-05, CAL-06, CAL-07, CAL-08  
**Beroenden:** CAL-03 (delade event), TEAM-06 (cross-team-representation)

- [x] EventDetails är en egen sida (`/calendar/event/:eventId`), inte längre en dialog/bottom sheet.
- [x] En färgkodad statusrad (utkast/kallade/accepterat/obesvarade/avböjt, plus deltog efter eventet) är synlig oavsett aktiv flik.
- [x] Deltagare-fliken har ett klubbövergripande sökfält (namn eller lagnamn), flervalsbart direkt till utkastet, sorterat lag-först (äldst) sedan bokstavsordning.
- [x] "Hantera urval"-knappen och den separata Trupp-bottom-sheeten är borttagna; allt sker inline på fliken.
- [x] Rosterlistan visar hela laget uppdelat i fyra hinkar i den efterfrågade ordningen: kallade spelare (accepterat/obesvarat/avböjt), kallade ledare (samma ordning), okallade spelare, okallade ledare.
- [x] Före eventet: hela raden markeras (ingen kryssruta) för att välja utkastmedlemskap. Efter utskickade kallelser: kallelsestatus visas i stället (med påminn/återkalla där behörighet finns — påminn är dolt om kallelsen inte faktiskt är påminnbar just nu). Efter eventets slut: närvarostatus väljs inline för kallade rader.
- [x] Delade event (`core.event_teams`, primär + delad) gör bägge lagens spelare valbara — bakåtgående backend-lucka (`person_eligibility_at_event` kollade tidigare bara `owning_team_id`) hittad och fixad.
- [x] Ny `roster`-projektion i `get_event_squad` slår ihop lag-, roll- (spelare/ledare), utkasts-, kallelse- och närvarodata per person i en fråga.
- [x] En kallad/utkastvald person utan aktiv lagtillhörighet på eventets lag (gäst/cross-team) visas i en egen "Gästspelare"-sektion och räknas med i statusraden, i stället för att bli osynlig.
- [x] Massåtgärder ("Välj alla spelare"/"Påminn alla obesvarade"/"Sätt alla accepterade som deltog") bakom en "..."-meny bredvid sökfältet — jämfört mot och medvetet förbättrat relativt det äldre Teamzone-projektets motsvarighet.
- [x] Sidan uppdaterar sig själv efter en åtgärd utan att tappa flikval eller sökfältets tillstånd (tidigare fysiskt fynd: varje kryssrutetryck laddade om till Info-fliken).
- [x] Header utan tillbakapil, centrerad titel, litet X för att stänga.
- [x] Rader är valbara var som helst på raden (inte bara ikonen längst till höger), med mindre text/padding och lite mellanrum mellan raderna.
- [x] "Skicka kallelser" är dold tills minst en faktisk osänd utkastmedlem finns (inte bara "någon i utkastet", vilket tidigare kunde vara sant även när alla redan var kallade) och flyttad till en flytande knapp längst ner (samma position som assistent-faben) med en räknare för hur många som väljs.
- [x] Statuscirklarna i headern är centrerade i stället för vänsterjusterade.
- [x] Headern krymper (mindre padding, mindre cirklar) på Deltagare/Förberedelser/Uppföljning-flikarna och är full storlek bara på Info-fliken, kopplat till själva svepanimationen mellan flikar (inspirerat av det äldre projektets `_EventHeader`, inte rakt kopierat).
- [x] "Skicka kallelser" låser truppen (`lock_squad`) precis innan sändning när den är i `draft` — `send_callups_for_actor` kräver `state='locked'`, ett steg den gamla "Hantera urval"-vyn hade men som cal11-ombyggnaden tappade (elfte/tionde omgången).
- [x] Spar-tidens behörighetskontroll (`person_eligibility_at_event`) läser samma `core.assignments`-tabell som rosterprojektionen, inte den parallella `core.team_assignments` — annars avvisades personer som visades som valbara (nionde omgången, migration `cal11d`).
- [x] En kallad person kan svaras för från Deltagare-fliken: sig själv ('self'), eller — för den som redan får hantera truppen — vem som helst på rostret ('manager', spelare och ledare lika, samma behörighet som påminn/återkalla). Info-fliken visar egen kallelsestatus (read-only) med en "Svara"-genväg till Deltagare; ledarhemmets "nästa"-kort visar och besvarar egen kallelse. Backend: 'manager'-gren i `actor_callup_response_context`/`respond_callup_for_actor`, `can_respond`/`response_role` i rosterprojektionen, `my_callup` i `get_leader_home_for_actor` (migration `cal11e`).
- [x] Svarsalternativen är bara Kommer/Kan inte — "Kanske" (tentative) är borttaget ur alla UI-ytor.
- [x] `onReload` väntas in (`Future<void> Function()`, inte `VoidCallback`) i alla fem åtgärdsmetoder så `busy`-spärren håller under omladdningen — annars kunde ett snabbt andratryck skicka en inaktuell `expected_revision` (åttonde omgången).
- [x] Nya widgettester kör hela flödet (öppna sida, statusrad, hinksortering, sök och lägg till klubbövergripande kandidat, gästroster, massval, manager-svar på en lagkamrats kallelse).
- [x] Samma klubbperson dedupliceras till en deltagarrad och en kallelsestatus även när personen har aktiva uppdrag i flera lag som deltar i samma event.

**Medvetet avgränsat:** grupper (spara/återanvända spelarurval) är en separat, ännu obyggd funktion — inget backend-stöd finns; användarens egna produktbeslut var att göra sida/statusrad/deltagarflik i ett svep och grupper som ett senare steg. Realtidsuppdatering (live när någon annan svarar på en kallelse) övervägdes efter jämförelse med det äldre projektet men kräver en ny broadcast-trigger på `core.callups`/`attendance_facts` (den befintliga `calendar:club:`-kanalen sänder bara på `core.events`-ändringar) — inte byggd än. Backendens `respond_callup_for_actor` accepterar fortfarande `tentative` som värde (token-svarsflödet via e-post inte genomgånget) — bara app-UI:t erbjuder det inte.

**Verifierat:** Deltagare-flödet, egna och managerstyrda svar, delat event,
view-only-behörighet och flerlagspersonens deduplicerade kallelse är fysiskt
verifierade på enhet/webb genom den iterativa CAL-genomgången. Hem- och
Info-ytornas kallelsestatus/svar är dessutom liveverifierade på Mi 9:an.

## 8. Våg 4 – Publik klubbsajt

### PUB-01 – Professionell klubb- och lagstruktur

**Status:** `[~]`  
**Paritet:** PUB-02, PUB-03, PUB-11  
**Beroenden:** TEAM-01, CAL-01

- [x] Klubbens officiella sida har profil, navigation, nyheter, lag, event och partners.
- [x] Varje lag har officiell kanal under klubben.
- [x] Standardadress är `teamzoneapp.se/{clubslug}` och routas automatiskt.
- [x] Metadata, canonical, 404 och tomlägen är professionella och testade.

**Återstår:** fysisk visuell kontroll med publicerad fixture på mobil/desktop samt komplett lag-/partnerprojektion i PUB-02/PUB-04 innan full status.

### PUB-02 – Katalog och publiceringsmodell

**Senaste verifiering 2026-09-25:** klubbens och lagets av-/återpublicering
är användarverifierad i appen. Efter separat godkännande har de två
worker-rättningarna tillämpats, sju jobb slutförts och testprojektets publika
runtime aktiverats. Riktiga klubb-/lagsidor visas lokalt; befintlig extern
webb visar också innehåll men har äldre klientversion. Se
[aktiveringsbevis](../evidence/pub02_real_web_readiness_2026-09-25.md).
Äldre noteringar i kortet om avstängd runtime avser tidigare grindläge.

**Status:** `[~]`  
**Paritet:** PUB-01, PUB-08–PUB-10  
**Beroenden:** AUTH-06

- [x] Verifierad/listad klubb kan visas minimalt i skyddad katalog.
- [x] Teamstatus är private/listed/published, private som default.
- [x] Fältvis publicering och samtycke är audit- och expiryhanterade.
- [x] Minderårigdata är dold som default.
- [x] Publik data går via allowlistad projection/API med limits och rate limiting.

**Beslutad ändring 2026-09-25 – självbetjäning för publika sidor:** Officiell
klubbverifiering ska vara ett separat förtroendemärke, inte ett villkor för att
en klubb ska kunna publicera sin sida. Nuvarande servergrind kräver fortfarande
`verification_status='official'` i äldre migration, men ersätts av de
godkända självbetjäningsmigrationerna från 2026-09-25 i Supabase-testprojektet.
Den publika webbruntimen är fortfarande avstängd.

- [ ] En behörig klubbansvarig kan själv förhandsgranska och aktivera/avaktivera klubbens publika sida i appen, utan TeamZone-granskning. Privat är fortsatt säkert grundläge.
- [ ] Klubben väljer uttryckligen vilka av dess lag som får egna publika undersidor; lag blir inte publika automatiskt när klubbsidan aktiveras.
- [ ] En lagledare kan begära en egen publik lagsida från klubben. Ansökan, beslut och status visas i appen; klubbansvarig godkänner eller avslår. Laget kan inte kringgå klubbens beslut.
- [ ] En publicerad klubb- eller lagsida visar tydligt om klubben är officiellt verifierad eller inofficiell. Skyddade klubbnamn och TeamZone-granskning av officiell status är separata flöden.
- [ ] Även inofficiella klubbar som själva valt `listed` eller `published` visas i den publika klubbkatalogen, tydligt märkta som inofficiella. Privata klubbar visas aldrig. Sökgräns, sidstorlek och rate limit behålls.
- [ ] Publiceringsgrinden för nyheter och andra publika poster kräver en aktiv publik klubbsida, men inte officiell status. Befintlig fältallowlist, integritetsskydd, samtycke, revisionskontroll och audit behålls.

**Genomförandeordning:**

1. [x] Separera `official` från rätten att publicera i serverfunktioner, projektionsworker och katalog/API. Släpp katalogens nuvarande `and official`-filter endast för explicit `listed`/`published`; returnera fortsatt officiell markör och behåll skyddade namn som egen regel. Lokalt implementerat; runtime ej verifierad.
2. [~] Bygg klubbens självbetjäningsvy: välj publik adress och tillåtna fält, bekräfta publiceringsvillkor, aktivera eller gör privat igen. Lokal vy finns; tydlig separat förhandsgranskning återstår.
3. [~] Bygg klubbens lagval och lagets ansökan om publik sida med väntande/godkänd/avslagen status, tydlig notis till klubbansvariga och audit av beslut. Lokal ansökan/beslut/status och sammanräkning av väntande ansökningar i publiceringsvyn finns. Besluts-audit finns i självbetjäningsmigrationen men är inte separat runtimeverifierad. Koppling till notiscentralen och fysisk rollkontroll återstår.
4. [~] Koppla publicerade lag- och nyhetskanaler till den aktiva klubbsidan; verifiera att inga privata trupp- eller minderåriguppgifter läcker. Lokal servergrind finns; databas- och fysisk kontroll återstår.
5. [ ] Kör automatiska roll-/integritetstester och fysiska kontroller för inofficiell och officiell klubb, katalogsökning, mobil och desktop, avpublicering samt återgång till privat läge.
6. [~] Separat godkännande har lämnats och avgränsade PUB-02-migrationer samt Edge-funktionen är lagda i Supabase-testprojektet. Thomas klubb och Thomas lag har publicerats i appen och statusen har kontrollerats av produktägaren. App/webb-driftsättning och eventuell aktivering av publik runtime återstår.

**Återstår:** roll- och integritetstest med verkliga konton, återstående fysiska
appflöden (särskilt avpublicering och lagansökan), tydlig notis om väntande lagansökan samt beslut om när den publika
webbruntimen får aktiveras. Backendändringen är godkänd och driftsatt i
Supabase-testprojektet; runtime förblir avstängd tills flödet är verifierat.

### PUB-03 – Nyheter och redaktionellt flöde

**Status:** `[~]`  
**Paritet:** PUB-04  
**Beroenden:** PUB-01, PUB-02

- [x] Rollstyrt utkast, preview, schemaläggning, publicera och avpublicera finns som revisionerade serverkommandon; publik artikel-preview renderar endast strukturerade, allowlistade block.
- [x] Klubbkanal och valda lagkanaler är explicita, publiceringsstatus ingår i redaktörsvyn och bildstatus är tydligt `not_configured` tills PUB-04 inför säker publik mediavariant.
- [x] Avpublicering tar atomiskt bort API-projektionen och köar invalidation för klubb- och artikelväg.
- [x] Autentiserade redaktörer har en capabilitystyrd Flutter-yta för att lista, skapa och redigera strukturerade artiklar samt schemalägga, publicera och avpublicera dem.

**Återstår:** publik bildvariant i PUB-04, mätning av cache-SLA, fysisk responsivitets- och flerrollsverifiering samt separat godkänd liveutrullning.

### PUB-04 – Publika event, partners och kontakt

**Status:** `[~]`  
**Paritet:** PUB-05–PUB-07  
**Beroenden:** PUB-01, PUB-02, CAL-03

- [x] Event publiceras separat och revisionerat; endast titel, starttid, typ och uttryckligt vald plats förs till publik projektion och klubb-/laglistor.
- [x] Partners kräver HTTPS-länk och eventuell logotyp måste vara skannad samt ha servicegenererad publik variant innan publicering.
- [x] Kontaktformuläret har same-origin, CAPTCHA, 5 försök/timme, maxlängder, neutral respons för okänd/otillgänglig klubb samt 30 dagars innehållsretention.
- [x] Autentiserade redaktörer har en capability- och tenantstyrd Flutter-panel för att förhandsgranska, publicera och göra event privata samt skapa, ordna, publicera och avpublicera partners.
- [x] Mediaflödet är ärligt fail-closed i klienten: logotypuppladdning erbjuds inte innan den skannande mediaworkern och den publika varianten finns.
- [x] Privat source-/variantlagring, capabilitystyrd staging, service-only claim/finish, fail-closed skanner-/transformeradapter och opaque publik WebP-leverans finns lokalt utan providerhemligheter eller runtimeaktivering.

**Återstår:** val och konfiguration av faktisk skannings-/transformeringsprovider, upload-UX när providern är godkänd, Storage-runtime och advisors, fysisk visuell fixture samt separat godkänd liveutrullning.

### PUB-05 – Domänförberedelse utan manuell klubbdrift

**Status:** `[~]`  
**Paritet:** PUB-12, PUB-13  
**Beroenden:** PUB-01, separat driftgodkännande

- [x] Egen premiumdomän har unik claim, hashad ägarverifiering, entitlementgrind, DNS-guide, TLS-livscykel, en canonical och permanenta 308-redirects.
- [x] Premiumsubdomän är strukturellt blockerad tills wildcard DNS, wildcard TLS och automatisk tenantrouting öppnas tillsammans genom en senare migration.
- [x] Hostname→klubb-routing och fallback till path-adress är datadriven; normalflödet kräver ingen manuell kod-, route- eller hostingändring per klubb.
- [x] Capabilitystyrd Flutter-självbetjäning visar kostnadsfri path-adress, domänstatus och canonical-val samt skapar en egen domän med engångs-DNS-instruktion. Kommersiell, DNS- och TLS-grind visas separat och premiumsubdomänen är synligt låst.
- [x] PUB-03–PUB-05:s mutationskommandon ingår explicit i den mätta kommandogatewayens allowlist; okända operationer förblir nekade.

**Återstår:** fastställd premium-entitlement, provideradapter/worker, faktisk wildcard- och TLS-provisionering, hosted redirect/certifikat-smoke samt separat driftgodkännande.

### PUB-06 – Webbkvalitet och framtida livegräns

**Status:** `[~]`  
**Paritet:** PUB-14, PUB-15  
**Beroenden:** PUB-01–PUB-04

- [x] Publik HTML har högst 60 sekunders CDN-cache med `must-revalidate`; API/kontakt förblir `no-store` och köad path-invalidation har autentiserad worker, retry och timeoutåtertagning.
- [x] Security headers, canonical SEO, dynamisk sitemap, robots och repeterbart synthetic smoke-script ingår i grinden.
- [x] Opaque publik media passerar aldrig HTML-/tenant-rewrite och behåller sin egen immutable bildcache även på egna klubbdomäner.
- [x] Live matchrapportering ligger endast i LATER-03 och kontraktstest blockerar live-/matchklocka-/realtimebegrepp i PUB-06-leveransen.

**Återstår:** hosted synthetic smoke, cache-hit/invalidation-SLA med publicerad fixture, workerhemlighet/schemaläggning och separat driftgodkännande.

## 9. Våg 5 – Inbox och notiser

### MSG-01 – Inbox och automatisk team-/ledarchat

**Status:** `[x]` – hosted och fysiskt verifierad inklusive tvåkontoflöde, join/leave samt capability revoke/restore  
**Paritet:** MSG-01–MSG-03  
**Beroenden:** TEAM-03, FND-02–FND-04

- [x] Inbox har sök, Alla/Olästa/Lag/Ledare/Tystade-filter, senaste avsändare/aktivitet, unread, mute, manuell refresh och debouncad privat Realtime-resync.
- [x] Lagchat och ledarchat binds deterministiskt till laget; triggers skapar/reconcilerar deltagare från aktiva assignment- och kontorelationer samt stänger trådarna med laget.
- [x] Ledarchatt kräver aktivt deltagande och aktuell `team.roster.view`-capability vid varje central accesskontroll för både läsning och send.
- [x] Flytt av kontolänk eller capability-grant reconcilerar både gammalt och nytt lag i samma triggerkörning, så gamla systemtrådar inte behåller inaktuella aktiva deltagare.
- [x] Capability revoke tar omedelbart bort ledarchatten och nekar gamla direktlänkar utan att påverka vanlig lagchatt eller övriga ledarfunktioner; återställning ger tillbaka samma tråd och historik utan dubblett.

**Verifierat:** tvårolls send/unread/read, mute, reconnect/resync, join/leave samt capability revoke/restore.

### MSG-02 – Group, direct och relationsstyrd kontakt

**Status:** `[x]` – hosted och fysiskt webbverifierad för relationsstyrd direkt-/gruppkontakt samt hela cross-club-flödet från sökning och förfrågan till accepterad, namngiven tvåvägschatt  
**Paritet:** MSG-04–MSG-06  
**Beroenden:** MSG-01, TEAM-05

- [x] Samma centrala relationsregel styr mottagarsökning, skapande, tillägg och send; grupp- och direktflödena använder endast serverns tillåtna mottagare.
- [x] Player-to-player är av som default; spelare kan kontakta ledare/vårdnadshavare medan ledare kan kontakta relevanta roller i aktuell klubb-/lagkontext.
- [x] Cross-club leader request förblir dataminimerad, rate-limitad till 3/24 timmar och 10/30 dagar samt skapar ingen tråd före mottagarens acceptans.
- [x] Acceptans återvaliderar båda parters vuxenverifiering, aktuella ledaruppdrag, cross-club-relation och blockstatus innan tråden skapas.

**Verifierat:** tillåten och nekad mottagarprojektion för player, guardian, leader och begränsad klubbfunktionär; direkttråd återanvänds; grupp kan skapas och kompletteras med servergodkända deltagare; global Inbox behåller tydlig lag-/klubbkontext. Cross-club-ledare kan sökas via klubb/lag/namn, skicka en motiverad förfrågan och först efter mottagarens acceptans få en privat tvåvägschatt. Förfrågans text bevaras som första meddelande, motpartens namn visas och svar är fysiskt verifierat. Riktad regression passerar 15/15.

### MSG-03 – Announcement och lässtatus

**Status:** `[x]` – hostad och fysiskt verifierad för ledare, spelare och vårdnadshavare
**Paritet:** MSG-07, MSG-10  
**Beroenden:** MSG-01

- [x] Announcement skapas av aktiv ledare/klubbfunktionär, är envägs för mottagare och använder en separat per-deltagare-readmodell.
- [x] Markera läst routas till rätt readmodell; Markera alla är ett idempotent, kontextbundet serverkommando som omfattar både vanliga trådar och announcements.
- [x] Skapare och mottagare binds till samma aktiva, tidsaktuella klubb-/laguppdrag som auktoriserade tråden; förändrad relation rullar tillbaka hela skapandet.
- [x] Anslag är separata informationsobjekt: endast behöriga roller kan skapa, exakt målgrupp/omfattning visas före utskick, oläst placeras i uppmärksamhetsyta och läst flyttas till anslagsarkiv. Följdmeddelanden spärras i både klient och server.

**Verifierat:** ledare → spelare och vårdnadshavare, skrivskyddad informationsvy, oläst uppmärksamhetsyta, enskild läsning och Markera alla med två olästa guardian-anslag. Båda anslagen flyttades till det synliga arkivet; databasen visade `through_revision = 2` och `unread_count = 0` för båda. Riktade Flutter-tester och analys är gröna.

### MSG-04 – Historik, send och Realtime-resync

**Status:** `[~]`  
**Paritet:** MSG-08, MSG-09  
**Beroenden:** MSG-01, FND-02

- [x] Historiken använder en exklusiv revisionscursor med explicit `has_more`/nästa cursor; klienten deduplicerar på meddelande-ID och sorterar på revision.
- [x] Send är optimistisk men idempotent med synligt pending, failure och explicit retry som återanvänder samma idempotensnyckel och staged files.
- [x] Aktiv participantaccess verifieras centralt vid varje send, inklusive announcement-skrivbehörighet.
- [x] Privat tråd-Realtime triggar debouncad ersättning av första sidan både vid subscribe och reconnect; serverhistoriken är fortsatt källa till sanning.
- [x] Generationsgrind hindrar sena initial-/Realtime-/paginationssvar från att skriva över nyare meddelandestatus och cursor.

**Återstår:** fysisk tvåenhetsverifiering av samtidigt nytt meddelande under äldre pagination och borttagen participant före retry samt visuell kontroll av offlinestatus och tidsstämpel. Offline failure/retry verifierades 2026-09-22 i webbappen: felstatus visade återförsök, skickningen lyckades efter återanslutning och databasen innehöll exakt ett exemplar. Ett följande återanslutningstest hittade att nytt meddelande inte syntes utan omladdning; webbens online-/resume-signal hämtar nu om inkorg och öppen tråd med backoff vid tidigt nätfel. Fysisk omtest 2026-09-23 bekräftade att meddelandet dyker upp utan omladdning. En offlinerad i produktskal och fullskärmschatt har tillkommit. Kodtest med 55 meddelanden hittade och rättade att en resync kastade redan hämtad äldre historik. På produktägarens begäran skapades en separat 55-meddelandetråd `MSG-04 historiktest - 55 meddelanden` för Coach Emilson och guardian-testkontot. API-paginering 50+5 och fysisk äldre-historikvy passerar. Varje skickat chattmeddelande visar nu en liten lokaliserad tidsstämpel; 8/8 riktade MSG-04-tester och analys passerar. 2026-09-06: fysisk genomgång hittade att *varje* send faktiskt misslyckades mot hosted (audit) — inte en UI-bugg utan en trigger (`broadcast_notification_center_invalidation`, delad av två tabeller med olika kolumnnamn) som kraschade på en statisk `NEW.profile_id`-referens. Fixat i migration `20260906201500`; verifierat direkt mot Postgres och live på Mi 9:an. Detta hade inte upptäckts av den mockade testsviten.

**UI-uppföljning 2026-09-23:** chattbubblor är kompaktare (högst 360 px/78 % av vybredden), inkommande meddelanden ligger till vänster och egna till höger. Avsändarnamnet ligger ovanför inkommande bubblor och datum/tid under varje skickad bubbla; själva bubblan innehåller bara text och eventuella bilagor. Visuell fysisk kontroll återstår.

**Senare MSG-04-verifiering 2026-09-23:** historiktesttråden har 56 meddelanden efter en avgränsad sendsimulering som Coach Emilson. Guardian laddade först äldre historik och bekräftade sedan i öppen webbtråd utan omladdning att både första historiska och nytillkomna meddelandet syntes. Server-API gav 50 + 6 sidor och 56 unika ID:n. Detta verifierar att laddad äldre historik inte kastas vid resync, men inte det snävare timingfallet där pagination och resync överlappar exakt. Grupperad chatt visar en metadatarad över gruppen och 6 px luft mellan bubblor; visuell kontroll återstår.

**Behörighetsretry 2026-09-23:** i en separat testgrupp försökte guardian skicka ett offline-pending meddelande efter att samma konto lämnat tråden via API. Återförsöket skickades inte; servern hade fortfarande 0 meddelanden och 0 lyckade dedup-sends. Säkerhetsgrinden är fysiskt verifierad. UI visar dock bara **Försök skicka igen** eftersom gatewayen returnerar generiskt `command_failed` även för permanent förlorad åtkomst; detta är en UX-uppföljning.

**UX-uppföljning:** vid online-sendfel gör klienten en separat serverläsning av tråden. Bekräftad `42501` visas som förlorad åtkomst med markerbar, oskickad text och utan meningslös retry; osäkra nätfel behåller idempotent retry. Riktad analys och 15 MSG-04-tester passerar. Fysisk kontroll av förklaringen återstår.

**Överlappande historikhämtning 2026-09-23:** om resync startar medan en äldre sida hämtas förkastas det sena gamla svaret och användarens äldre-hämtning spelas automatiskt om med aktuell cursor. Ett styrt asynkront test täcker detta och fallet där senaste sidan redan innehåller all historik. MSG-04 17/17 och riktad analys passerar; exakt fysisk timingkontroll återstår.

### MSG-05 – Mute, pin och pushpreferenser

**Status:** `[~]`  
**Paritet:** MSG-11, MSG-12, MSG-20  
**Beroenden:** MSG-01

- [x] Mute och frivillig push är fail-closed och kontosynkade; push är av tills användaren uttryckligen aktiverar den och aktiv mute undertrycker workerclaim.
- [x] Pin är beslutad och implementerad som kontosynkad per profil/tråd, visas och sorteras i Inbox samt resynkas via den privata inbox-kanalen.
- [x] Push/outbox använder endast tråd-ID, meddelande-ID och generisk preview-nyckel; en databastrigger redigerar automatiskt bort övrigt och workern loggar aldrig payload.
- [x] Pushinställningen är enkelkörd i klienten; mute/pin låser målvärdet före RPC och visar rätt omvänd åtgärd efter serverbekräftelse.

**Återstår:** provider-/endpointaktivering under separat driftgodkännande, Deno-kontroll samt fysisk tvåenhetsverifiering av mute, pin och push opt-in/out. Riktade Flutter-tester och analys är gröna.

**Webbkontroll 2026-09-23:** produktägaren bekräftade att fäst konversation sorteras överst och syns under **Fästa**. Tystning syns under **Tystade** och byter åtgärden till **Slå på notiser**. Avfästning och återaktivering fungerar. Frivillig pushpreferens sparas både på och av över omladdning; testkontot lämnades med den avstängd. Pin och mute synkades till en andra webbläsarsession utan omladdning. Faktisk providerleverans och separat tvåenhetstest återstår.

### MSG-06 – Bilagor, återkallelse och moderation

**Status:** `[~]`  
**Paritet:** MSG-13, MSG-14, MSG-17  
**Beroenden:** MSG-02, MSG-04

- [x] Objektidentitet lagras privat; listprojektionen exponerar endast fil-ID/visningsmetadata och en 120-sekunders signerad URL skapas först efter separat serverauktorisering och Storage-RLS.
- [x] Återkallelsefönstret är 15 minuter och ger tombstone, ny trådrevision, auditversion, withdrawn-bilagor och privat Realtime-/inbox-resync.
- [x] Report kräver strukturerad orsak, blockerar avsändaren och är idempotent; service-only moderation kan dismiss, dölja med tombstone, stänga eller legal-hold med reviewer, reason, evidence hash och immutable auditspår.
- [x] Bilagesändning kan återspelas efter tappat svar med samma idempotensnyckel/fillista; ändrad fillista avvisas utan ny sändning.

**Återstår:** Storage-runtime och advisors, faktisk service-moderatoroperator/arbetskö under separat driftgodkännande samt fysisk tvårollsverifiering av filåtkomst, recall och report/block. Riktade Flutter-tester och analys är gröna.

**Webbkontroll 2026-09-23:** produktägaren verifierade återkallelse inom 15 minuter i avsändarens vy; meddelandet ersattes av återkallelsemarkeringen. En bifogad JPG syntes och kunde öppnas både av avsändare och mottagare i separata sessioner. Efter återkallelse visade båda öppna vyerna **Återkallat meddelande** utan bild; mottagaren behövde inte ladda om. Signerad URL, tidsgräns och rapport/block återstår. Rapport/block bör prövas med separat disponibel relation eftersom klienten ännu saknar avblockering.

### MSG-07 – Trådlivscykel och global radering

**Status:** `[~]`  
**Paritet:** MSG-15, MSG-16  
**Beroenden:** MSG-04, MSG-06, retentionpolicy

- [x] Deltagare kan dölja/lämna utan att påverka andras historik.
- [x] Behörig ansvarig kan arkivera/stänga för nya meddelanden.
- [x] Global radering kräver två separata behöriga användare.
- [x] Cross-club/integritetsärende kräver TeamZone-granskning.
- [x] Vanlig serviceapplicering använder exakt initiativtagare + separat godkännare och är replay-safe; endast TeamZone-review kräver en tredje separat granskare.
- [x] Tombstones bevarar ordning, replies, read state och notifieringsreferenser.

**Återstår:** fysisk flerrolls-/serviceoperatorverifiering. Riktade Flutter-tester och analys är gröna.

### MSG-08 – Notification center utan Watchpoints

**Status:** `[~]`  
**Paritet:** MSG-18–MSG-20, HOME-10  
**Beroenden:** MSG-03–MSG-05

- [x] Samlar handlingsbara domännotiser med säker preview och deep link.
- [x] Watchpoint-items avlägsnas utan att vanliga notifieringar försvinner.
- [x] AC-signaler introduceras inte här före AC-vågen.
- [x] Swipe-dismiss är serverbekräftad och rullar tillbaka visuellt vid fel, så klienten inte visar falskt borttagen status.

**Återstår:** fysisk tvåenhetsverifiering av badge/read/deep links. Riktade Flutter-tester och analys är gröna.

**Webbkontroll 2026-09-23:** två webbläsarsessioner visade båda 15 olästa notiser. Öppning av en enskild notis navigerade rätt och minskade badgen till 14 i båda utan omladdning. Dismiss sparades på servern men en redan öppen lista i andra sessionen var stale tills den öppnades om. Efter rättning uppdaterades båda öppna listorna direkt vid dismiss; produktägaren verifierade omtestet. Separat tvåenhetstest återstår.

**Kallelselänk 2026-09-24:** en ny kallelsenotis hos spelaren gick bara till Kalender eftersom servern fortfarande returnerade `/calendar?event=…`. Notisfunktionen returnerar nu kanonisk `/calendar/event/…` för både kallelse- och eventnotiser; befintliga poster beräknas om vid läsning. Hosted kontroll med spelar-JWT av samma notis och riktade 11/11 tester passerar. Fysisk omtest av notisens EventDetails-öppning återstår.

**Meddelandebadge 2026-09-24:** guardian hade 80 olästa notiser trots att en historiktråd redan lästs. 55 meddelanderader därifrån låg kvar som separata olästa notiser. Nu grupperas meddelanden per konversation och rätt läscursor för vanlig chatt respektive anslag avgör om de fortfarande är nya; en samlad rad visar antalet nya meddelanden. Två scoped migrationer gav hosted guardian-projektionen 9 olästa grupper utan att historik raderades. Riktade tester 30/30 och analys gröna; visuell webbkontroll och separat tvåenhetstest återstår.

**Tydligare meddelandenotiser 2026-09-24:** notisraden visar nu chatt, avsändare och början av senaste meddelandet samt antal nya. Utdraget hämtas endast i den autentiserade appvyn efter aktuell trådåtkomstkontroll; outbox/push fortsätter utan meddelandetext. Otillgängliga chattar filtreras bort från kontots notislista och oläst antal, medan återkallade meddelanden får neutral fallback. Två servermigrationer är applicerade i godkänd testdatabas. Efteråt har guardian 6 olästa grupper och inga döda meddelandelänkar. Riktade MSG-08-tester och analys passerar. Konfigurerad lokal releasewebb är ombyggd på port 5000; produktägarens visuella kontroll återstår.

**Webbverifiering 2026-09-25:** produktägaren bekräftade att den tydligare meddelandenotisen fungerar. Den visuella webbkontrollen är stängd; separat fysisk tvåenhetsverifiering återstår.

**Två webbläsare 2026-09-25:** samma konto visade identiska notisrader och oläst antal i två webbläsare. Öppning av en oläst notis i den ena uppdaterade lässtatus och antal i den andra utan omladdning. Webbregressionen för kontosynk efter den nya filtreringen är godkänd; separat enhet återstår.

**Meddelandelänk 2026-09-25:** produktägaren bekräftade att en meddelandenotis öppnar rätt chatt och att stängning återgår till Inkorgen. Webbgrinden för meddelandenotisens deep link och retur är godkänd.

**Retur från notis 2026-09-24:** produktägaren bekräftade att notisen nu öppnar rätt EventDetails, men X gick till Kalender. Inbox öppnar därför eventrutter med `push` och övriga mål fortsatt med `go`. Riktade 14/14 tester, analys och lokal releasewebb är gröna; fysisk omtest av X/Bakåt till Inbox återstår.

**Fysisk X-omtest 2026-09-24:** samma kallelsenotis öppnade rätt EventDetails och X återgick nu till Inbox. Webbläsarens Bakåt återstår att kontrollera separat.

**Fysisk Bakåt-omtest 2026-09-24:** webbläsarens Bakåt återgick också till Inbox från samma notisöppnade EventDetails. Båda retursätten är webbverifierade; separat enhet kvarstår.

## 10. Våg 6 – rollspecifikt Hem

### HOME-01 – Ledarens Hem

**Status:** `[~]`  
**Paritet:** HOME-01, HOME-04, HOME-06  
**Beroenden:** TEAM-02, CAL-07, CAL-08, MSG-08

- [x] Prioriterar dagens lagarbete, nästa event och deterministiska åtgärder.
- [x] Visar obesvarade callups/saknad närvaro endast för behörig kontext.
- [x] Tablet/desktop kan ge planeringsöverblick; mobil ger snabb handling.
- [x] Kontextbunden cache för ledar-Hem märks och visas explicit som stale med senaste servergenereringstid.
- [x] En ledare kan bli kallad som alla andra: "nästa"-kortet visar egen kallelsestatus ("Din kallelse: …") och Kommer/Kan inte-knappar (2026-09-07, `get_leader_home_for_actor.next_event.my_callup`).
- [x] "Behöver din uppmärksamhet"-listan (obesvarade kallelser/saknad närvaro) är flyttad från Hem till Min assistent — samma deterministiska `get_leader_home_for_actor.tasks`-data, inte via AC-01-spärren eller genererade signaler (2026-09-07, se HOME-05 och Våg 7). Hem visar nu bara hjältekort → Idag → snabbåtgärder.

**Återstår:** fysisk verifiering med flera ledarkontexter/skärmstorlekar. En mobil ledarkontext är genomgången (2026-09-06) och egen-kallelse på "nästa"-kortet är liveverifierad (2026-09-07). Riktade Flutter-tester och analys är gröna.

**Webbkontroll 2026-09-23:** samma ledarkonto bytte Thomas lag → Nytt lag → Thomas lag. Nästa aktivitet växlade Träning → vs Sävsjö FF → Träning utan synligt läckage mellan lagkontexterna. Bred vy hade planeringsmeny i högerkolumnen; smal webbvy visade den under aktivitetskorten utan horisontell scroll. Nästa-aktivitet-länken öppnade rätt event; efter rättning går både X och Bakåt tillbaka till Thomas-lagets Hem. Direktlänk utan föregående sida återstår att kontrollera.

**Kopierbar eventadress 2026-09-23:** webbtest hittade att pushad EventDetails trots korrekt X/Bakåt visade `/home` i adressfältet. Produktskalet aktiverar nu GoRouters URL-reflektion för de direktlänksbara pushade rutterna. Widgettest visar `/calendar/event/...` vid push och `/home` efter pop; fysisk omtest efter webbbygge återstår.

**Fysisk webbomtest:** produktägaren såg `/calendar/event/...` i adressfältet, öppnade samma Träning via kopierad adress i ny flik och stängde den till Kalender med X. Från Hem går X fortsatt tillbaka till Hem. Båda ursprungsvägarna är verifierade.

### HOME-02 – Spelarens Hem

**Status:** `[~]`  
**Paritet:** HOME-02, HOME-04, HOME-05  
**Beroenden:** CAL-07, MSG-08

- [x] Egna kallelser, nästa aktivitet, laginformation och meddelanden.
- [x] Snabbt svar bevarar korrekt callupstatus och decline reason. Knapparna heter Acceptera/Avböj och statusen visas som Kommer/Kan inte; "Kanske" (tentative) är borttaget.
- [x] Inga leader-/guardianadministrativa actions exponeras.
- [x] Kontextcache märks explicit som stale och gamla kallelser görs skrivskyddade tills färsk serverdata finns.

**Återstår:** fysisk spelarverifiering av svar/stale revision/deep links. Riktade Flutter-tester och analys är gröna.

**Webbkontroll 2026-09-23:** spelartestkontot i Thomas lag visade **Dina kallelser** samt Laget, Olästa meddelanden och Nästa aktivitet: Träning. Inga ledar-, trupp- eller närvaroåtgärder syntes. Träning öppnade rätt EventDetails och X gick tillbaka till spelarens Hem. Smal vy ordnade korten Kallelser → Laget → Meddelanden → Nästa aktivitet utan sidscroll. Ingen obesvarad kallelse fanns för svarstest.

**Liveuppdatering 2026-09-23:** riktad testkallelse blev synlig på spelarens öppna Hem först efter omladdning. Hem prenumererar nu på den befintliga privata kontonotifieringen och hämtar om rollprojektionen efter 250 ms debounce. Ingen schemaändring; HOME-01–03 18/18 och analys passerar. Fysisk omtest återstår.

**Svar och knapptexter 2026-09-23:** produktägaren accepterade en riktad kallelse från spelarens Hem och bekräftade att statusen blev Kommer. Efter önskemål byttes Hem-knapparna för både spelare och ledare till Acceptera/Avböj, utan ändring av svarskod eller status. Riktade HOME-01–03-tester 18/18, analys och lokalt releasewebbbygge passerar; fysisk etikettkontroll och separat omtest av automatisk inkommande uppdatering återstår.

**Inkommande kallelse 2026-09-24:** med spelarens Hem öppet i en separat webbläsarprofil skickade ledaren en ny riktad kallelse från ett framtida event. Produktägaren bekräftade att den visades utan omladdning. HOME-02:s liveuppdatering för nya kallelser är webbverifierad; stale revision och separat fysisk enhet återstår.

### HOME-03 – Vårdnadshavarens Hem

**Status:** `[~]`  
**Paritet:** HOME-03, HOME-05  
**Beroenden:** TEAM-05, CAL-07, MSG-08

- [x] Välj barn och visa endast relationstillåtna kallelser/event/meddelanden.
- [x] Acting-as är synligt och bevaras genom hela svarsmutationen.
- [x] Cachefallback isoleras per lag/barn, märks stale och spärrar barnbyte/kallelsesvar tills relationen verifierats igen.

**Återstår:** fysisk guardianverifiering med flera barn/lag samt avslutad relation. Riktade Flutter-tester och analys är gröna.

**Webbkontroll 2026-09-23/24:** i Thomas lag visas den nu enda aktiva relationen, Testspelare S04, med tydligt "Du agerar för" och barnets kallelse. De äldre REL-02-fixturernas två relationer är avslutade, så flerbarnstestet är fortsatt öppet. Besvarad kallelse kan ändras och markerar nu aktuellt Acceptera/Avböj-val. Efter bekräftat svarsbyte saknades avböjandeorsaken på Hem; en behörighetsbunden projektion för aktuell svarsrevision och lokaliserad klientvisning är nu implementerade. Hosted lästest med vårdnadshavarens behörighet, HOME-01–03 19/19, analys och lokalt releasewebbbygge passerar; fysisk omtest av orsaksvisningen återstår.

**Fysisk omtest 2026-09-24:** produktägaren såg avböjandeorsaken på Hem och bytte sedan till Acceptera. Den valda knappen uppdaterades och orsakstexten försvann. Enbarns-/acting-as-/svarsflödet är verifierat; flerbarns-, lagbytes-, stale-revision- och avslutad-relationsgrind står öppna.

### HOME-04 – Gemensam uppmärksamhetsmodell

**Status:** `[~]`  
**Paritet:** HOME-06, HOME-10, HOME-12  
**Beroenden:** HOME-01–HOME-03

- [x] Rollstyrda åtgärdskort och notification center använder en konsekvent prioritering.
- [x] Samma domänhändelse dupliceras inte som flera oberoende uppgifter.
- [x] Mobil och större skärmar prioriterar olika layout men samma rättigheter/data.
- [x] Notifieringsklienten återberäknar gemensam prioritet och deduplicerar defensivt och deterministiskt på kanonisk domännyckel.

**Återstår:** fysisk cross-device-/responsivitetsverifiering. Riktade Flutter-tester och analys är gröna.

**Webbkontroll 2026-09-24:** vårdnadshavarens Hem visade S04:s kallelse men inget duplicerat Nästa aktivitet-kort. Behörighetsbundet, skrivskyddat backendtest bekräftade att nästa event och barnkallelsen faktiskt har samma event-ID. Guardian-fallet av Hem-deduplicering är verifierat; övriga roller och notifierings-/enhetsmatris står öppna.

**Tvåflikssynk 2026-09-24:** produktägaren såg att ändrat kallelsesvar i en guardian-flik inte uppdaterade den andra. Svarskommandot saknade invalidieringssignal; den befintliga privata `notification:center:<profile>`-kanalen får nu en tom signal för svarande och aktiva familjekopplingar efter sparat svar. Migrationen är applicerad i godkänd testdatabas, trigger/ACL kontrollerade, HOME-01–03 20/20 och analys gröna. Fysisk omtest återstår.

**Fysisk tvåfliksomtest 2026-09-24:** produktägaren bekräftade att ändrat S04-svar nu uppdaterar den andra öppna vårdnadshavarfliken utan ny omladdning. Samma-konto-synk är godkänd; separat enhet och cross-account-synk kvarstår.

### HOME-05 – Avlägsna Watchpoints och håll AC avvaktande

**Status:** `[~]`  
**Paritet:** HOME-07–HOME-09, HOME-11  
**Beroenden:** HOME-04

- [x] Watchpoints-namn, separat UI och notification-items avlägsnas.
- [x] Deterministiska uppgifter fortsätter fungera oberoende av AC. Sedan 2026-09-07 renderas "Behöver din uppmärksamhet"-listan på Min assistent-sidan (användarens beslut: "all den sortens information ska gå genom assistenten") — men fortfarande via samma direkta `get_leader_home_for_actor.tasks`-fråga, **inte** via AC-01-spärren, `assistant_activation_gate` eller någon genererad signal. Testet (`home05_remove_watchpoints_hold_ac_test.dart`) bevakar nu det oberoendet på den nya platsen. Oberoendet av AC-1/genererade signaler är kontraktet, inte vilken fil texten ligger i.
- [x] AC-02/03 får endast vara en transparent, icke-generativ hållningsyta; datadriven aktivering förblir blockerad tills AC-01:s runtimegrind passerar.
- [x] Belastning/skada/high-load förblir senare och fail-closed.
- [x] Klientens Notification Center fail-stänger pensionerade/förtida Watchpoint-, assistant-, workload-, high-load- och medical-payloads även från gammal cache/API.

**Återstår:** fysisk kontroll av gamla poster samt HOME-01–04-regression. Riktade Flutter-tester och analys är gröna.

## 11. Våg 7 – Min assistent-grund

**Beslutad målmodell:** en gemensam assistent med fast funktionsnamn **Min assistent**, ett senare beslutat sportigt standardnamn, frivilligt personligt namn per användare och tydligt märkta specialistområden. Fullt kontrakt finns i `docs/implementation/min_assistent_concept.md`. Befintliga `AC-*`-ID:n behålls för spårbarhet och kompatibilitet.

### AC-01 – Datagrind och signalregister

**Status:** `[~]`  
**Paritet:** HOME-08, HOME-11  
**Beroenden:** CAL-06–CAL-08, HOME-04

- [x] Datakvalitet, ägande, freshness och behörighet har ett privat, fail-closed register; hosted runtime verifierad 2026-09-04.
- [x] Första deterministiska signaler: obesvarade callups; nära event utan deltagardraft/callup; avslutat event utan närvaro; positiva planerings-/svarssignaler; framtida planeringsluckor.
- [x] Varje signal visar källa, tidpunkt, förklaring och möjlig säker handling.
- [x] Ingen generativ AI aktiveras utan separat parameter-/integritetsbeslut; AC-grinden förblir blockerad.

### AC-02 – Responsiv AC-ingång

**Uppdatering 2026-10-02:** HOME-05-uppgifterna har nu en kontextanpassad
presentation med **Här och nu** och en kontoomfattande uppgiftslista, inklusive
överblick över behöriga ledarlag och direktlänkar till eventets deltagarflik. Detta
återanvänder befintliga domänprojektioner och aktiverar inte AC-01-signalkön.
Se [implementation och verifiering](../evidence/assistant_context_tasks_2026-10-02.md).

**Nästa leverans 2026-10-02:** den godkända 48-timmarsregeln för aktiviteter
utan utskickade kallelser är implementerad, med **Kallelse behövs** som undantag
på Info-fliken. Databasdelen är införd och rollback-verifierad i auditprojektet.
Se [regel, gränser och tester](../evidence/assistant_missing_callups_2026-10-02.md).

**2026-10-02 – påminnelser och matchuppföljning:** Kallelsepåminnelser har mottagargranskning med senaste påminnelse och möjlighet att avmarkera före utskick. Assistenten visar saknat slutresultat respektive matchrapport för matcher som slutat under de senaste sju dagarna, med lag- och matchbehörighet. Sparad rapport uppdaterar assistentpanelen. Databasmigrationen är applicerad i auditprojektet och klienten är automatiskt verifierad. Se [implementation och verifiering](../evidence/assistant_reminders_match_followup_2026-10-02.md).

**2026-10-02 – kalenderkrockar och förberedelser:** Assistenten visar synliga, överlappande aktiviteter i samma lag inom sju dagar och kvarvarande material-/uppgiftspunkter inför aktiviteter inom 48 timmar. Krockpar visas en gång med länkar till båda aktiviteterna. Checklistans genväg öppnar Förberedelser direkt. Databasmigrationen är applicerad i auditprojektet och klienten är automatiskt verifierad. Se [regler och verifiering](../evidence/assistant_conflicts_preparation_2026-10-02.md).

**2026-10-02 – kompakt assistent:** Kortens detaljer och assistentinställningarna är hopfällda. Åtgärda, Skjut upp och Arkivera finns direkt på korten. Uppskjutning/arkivering sparas privat på kontot, kan återställas och påverkar inte domänuppgiften. Se [beteende och verifiering](../evidence/assistant_compact_ui_2026-10-02.md).

**2026-10-05 – påminnelse släcker varningen:** En obesvarad kallelse som har påmints de senaste sex timmarna räknas inte i "Obesvarade kallelser", vilket motsvarar spärrtiden för ny påminnelse (`20261005140000`). Är den fortfarande obesvarad därefter kommer varningen tillbaka.

**Statussynk 2026-10-04:** Varningar grupperas per aktivitet, `Här och nu`
följer aktuell sida och den kontoomfattande listan kan filtreras på kategori och
aktuellt lag. Personliga krockar kan hittas mellan användarens lag och klubbar.
FAB:en visar antal aktiva uppgifter. Användaren kan styra uppgiftstyper,
lagomfattning, välkomstmeddelande, namn och en av sex profilbilder. Assistentens
namn, uppdatering och inställningar ligger i sidhuvudet. Samlad nulägesbeskrivning:
[iteration 2026-10-02–2026-10-04](../evidence/core_app_iteration_2026-10-02_10-04.md).

**Status:** `[~]`  
**Paritet:** HOME-09  
**Beroenden:** AC-01

- [x] Mobil och tablet använder FAB nere till höger, placerad ovanför sidornas primära FAB-zon och navigation.
- [x] Bred desktop kan behålla den integrerade sidopanelen där utrymme finns; användaren bekräftade detta 2026-09-25.
- [x] `_AssistantCoachHoldingSurface` renderar sedan 2026-09-07 HOME-05:s deterministiska "Behöver din uppmärksamhet"-lista (obesvarade kallelser/saknad närvaro) som ett eget kort högst upp, hämtat direkt via `OverviewServices.loadLeaderHome` — tydligt avskilt från den fortfarande blockerade "Min kö"/signalkö-sektionen nedanför (se HOME-05). Detta är inte AC-01-signaler; det är samma icke-generativa data som tidigare låg på Hem.
- [~] Fokus, semantik, back och deep link har strukturella kontrakt; fysisk responsiv verifiering och dataflöde återstår tills AC har verifierad data. Den flyttade uppmärksamhetslistan är liveverifierad på Mi 9:an (2026-09-07).

### AC-03 – Transparent assistent, inte Watchpoints i ny kostym

**Status:** `[~]`  
**Paritet:** HOME-07, HOME-08, MSG-19  
**Beroenden:** AC-01, AC-02

- [x] AC-kontraktet sammanfattar deterministiskt och navigerar till säker vy; domänkommandon kräver fortfarande explicit användarhandling.
- [x] Presentationen förbjuder dolda riskpoäng, medicinska slutsatser, otillåtna personjämförelser och generativ AI.
- [~] Signal har privat, idempotent och auditerad avfärda/återställ-livscykel utan koppling till notifieringshistorik; SQL-runtime klar 2026-09-04, verkligt dataflöde återstår.

### AC-04 – Min assistent-identitet och personligt namn

**Status:** `[~]` – kontoägda namn- och avatarpreferenser är applicerade och
automatiskt verifierade i auditprojektet; sportigt standardnamn och fysisk
kontosynk-verifiering återstår.

**Beroenden:** AC-02

- [x] Byt ny användarcopy från paraplyet Assistant Coach till **Min assistent** utan att bryta tekniska AC-ID:n, routes eller historik.
- [ ] Besluta sportigt, internationellt standardnamn efter separat clearance.
- [x] Skapa privat, revisionerad och kontosynkad namnpreferens med reset och säker fallback. Samma profil har en separat, tillåten avatarpreferens med sex bundlade bilder och standardikon.
- [x] Namnet är endast presentation och förekommer aldrig i authorization, RLS eller capabilitybeslut.
- [x] Varna för möjlig sammanblandning med systemavsändare, verklig funktionär eller legitimerad yrkesperson.

### AC-05 – Versionshanterat specialistområdesregister

**Status:** `[~]` – lokalt implementerad och Flutter-verifierad; SQL-runtime klar 2026-09-04, fysisk visuell/tillgänglighetsverifiering återstår.

**Beroenden:** AC-01, AC-04

- [x] Registrera Lagplanering, Träningsstöd, Individuell utveckling, Rehabstöd, Klubbadministration och Kommunikation med stabila nycklar.
- [x] Varje område definierar etikett, ikon, design-token, datakällor, capabilities, målroller, presentationsfält och actions.
- [~] Varje post visar etikett och ikon tillsammans med färg; återanvändbar badge, assistentvy, ljust/mörkt tema och automatisk kontrast är verifierade, medan skarpa postvyer och fysisk färgblindhetskontroll återstår.
- [x] Prioritets-/statusfärg hålls separat från områdesfärg.
- [x] Områden utan godkänd data-/integritetsgrind förblir inaktiva och fail-closed.

### AC-06 – Gemensam kö, prioritering och notifieringsbudget

**Status:** `[~]` – lokalt implementerad och Flutter-verifierad; SQL-runtime klar 2026-09-04, faktisk leverans och fysisk cross-area-verifiering återstår.

**Beroenden:** AC-05, HOME-04, MSG-08

- [x] Varje post har ett primärt område och en cross-area canonical key.
- [x] Samma domänhändelse visas endast en gång även när flera områden kan tolka den.
- [x] Global prioritet väljer deterministisk huvudpost; positiva/lågprioriterade poster kan samlas i digest.
- [~] Områden delar notifieringsbudget: direkt, sammanfattning, endast i Min assistent eller av; kontrakt och lokal planering klara, faktisk leverans förblir blockerad.
- [x] System-/säkerhetsmeddelanden ligger utanför assistentbudgeten och behåller TeamZone som avsändare.

### AC-07 – Roll-, kontext- och enhetsanpassad presentation

**Status:** `[~]` – lokalt implementerad och Flutter-verifierad; SQL-runtime klar 2026-09-04, verklig flerrollsdata och fysisk enhetsverifiering återstår.

**Beroenden:** AC-05, AC-06

- [x] Leader, player, guardian och klubbfunktionär får endast rollrelevanta, capabilityverifierade poster.
- [x] Aktiv klubb, lag, person och acting-as visas där sammanblandning annars kan uppstå.
- [x] Mobil och tablet behåller gemensam FAB; bred desktop kan använda integrerad panel med samma data och rättigheter.
- [x] Historik, filter och preferenser finns per område utan separata specialistinkorgar.
- [x] Varje post visar källa, beräkningstid, freshness/stale, förklaring och säker handling.

### AC-08 – Specialistpolicy, ansvar och aktiveringsgrind

**Status:** `[~]` – policy och fail-closed-grind lokalt implementerade och Flutter-verifierade; SQL-runtime/advisors klara 2026-09-04, flerrollsmatris och fysisk enhetsgrind återstår.

**Beroenden:** AC-05–AC-07

- [x] Navigation får ske direkt men domänmutation kräver preview, explicit bekräftelse, serverauktorisation, idempotens och audit.
- [x] Rehabstöd får följa beslutad plan men aldrig diagnostisera, ordinera, riskrangordna eller besluta om återgång till spel.
- [x] Assistenten presenteras tydligt som digital funktion, inte människa eller legitimerad expert.
- [~] PostgreSQL-runtime/advisors passerar 2026-09-04; flerrollsmatris och fysisk enhetsgrind per aktiverat område återstår.
- [x] Generativ AI förblir blockerad tills separat produkt-, integritets-, leverantörs- och driftgrind godkänts.

## 12. Våg 8 – senare funktioner

### LATER-01 – Lagets fas 2

**Status:** `[ ]`  
**Paritet:** TEAM-13–TEAM-16

- [ ] Import med preview/dubblettskydd/återställningsbar batch.
- [ ] Historik och totalstatistik ovanpå temporal representation.
- [ ] Återanvändbara grupper som endast fyller deltagardraft.
- [ ] Skada/avstängning först efter separat policy-/integritetsgrind.

### LATER-02 – Kalenderns senare fas

**Status:** `[ ]`  
**Paritet:** CAL-19–CAL-22

- [ ] Eventimport, personliga/delade anteckningar och taktiska bilagor.
- [ ] Full match-/träningsplanering efter stabila grundflöden.

### LATER-03 – Premiumadresser och liverapportering

**Status:** `[ ]`  
**Paritet:** PUB-12–PUB-14

- [ ] Egen domän och senare wildcard-subdomän enligt PUB-05.
- [ ] Live matchrapportering får separat state-, realtime-, moderation- och publiceringsspecifikation.

### LATER-04 – Utökad safeguarding och hälsosignaler

**Status:** `[ ]`  
**Paritet:** HOME-11, MSG-17

- [ ] Eventuell player-to-player kräver policy, åldersregel, samtycke, block/report och moderation.
- [ ] Belastning/skada/high-load kräver särskilt data-, metod- och integritetsbeslut.

## 13. Våg 9 – samlad releasegrind

### REL-01 – Automatiserad kvalitetsgrind

**Status:** `[x]`  
**Beroenden:** Våg 0–6

- [x] Dart-formatkontrollen passerar för samtliga 150 filer under `lib` och `test`.
- [x] Statisk Dart-analys passerar utan anmärkningar.
- [x] Hela Flutter-sviten passerar: 349 tester.
- [x] Flutter-webbbygget passerar och skapar `build/web`.
- [x] Android-debugbygget passerar och skapar `build/app/outputs/flutter-apk/app-debug.apk`.
- [x] Publiksajtens typecheck, 26/26 tester och full Next-produktionsbuild passerar i lokal miljö som tillåter child-processer.
- [x] Secret-, loggredaction-, ACL/RLS- och kontraktskontroller ingår i den gröna Flutter-sviten.

### REL-02 – Roll-, enhets- och avbrottsmatris

**Status:** `[x]`
**Beroenden:** REL-01

- [x] Leader, player, guardian och klubbfunktionär passerar hosted/fysisk 4 × 3-matris över Hem, Laget, Kalender och Inbox med separata konton och negativ behörighetskontroll.
- [x] Telefon, tablet och desktop/web passerar aktuell fysisk/webb viewport-, navigation- och rollregression.
- [x] Samtliga sju avbrottsfall passerar, inklusive fler-kontexttest, fel-scope deep links och serveråterkallad session.
- [x] Samtliga fem tillgänglighetsområden passerar genom fysisk TalkBack/webb, automatiserad grind och dokumenterad MIUI-begränsning för systemtoggle.

### REL-03 – Scope- och säkerhetsgrind

**Status:** `[x]`
**Beroenden:** REL-01, REL-02

- [x] Gamla `C:\Dev\TeamZone` är git-ren och ingen produktkod refererar till dess sökväg eller en gammal databas; read-only scopegrind passerar.
- [x] Dokumenterade Supabase-liveändringar ligger i tidigare separat godkända rolloutbevis; aktuellt arbete är lokalt och releaseverktygen innehåller inga push/deploykommandon.
- [x] Produktion är fortsatt `not_provisioned` utan Supabase-/Firebaseprojekt; inga `webtools`- eller `workspaces`-kataloger finns eller har startats.
- [x] Android namespace/applicationId och iOS bundle identifier är fortsatt `com.teamzone.teamzone`.
- [x] Alla implementerade arbetskort har evidence, REL-01 och REL-02 är gröna och första återställningspunkten `bef10fb` finns.

## 14. Våg 10 – utbyggnad efter grundappen

Kort för arbete som levererats efter dokumentationssynken 2026-09-26, uppdaterat 2026-10-02. Samlad evidens:
[`core_app_iteration_2026-09-27_10-01.md`](../evidence/core_app_iteration_2026-09-27_10-01.md). Ett kort i den här vågen
är `[~]` tills den fysiska enhetsgrinden (Android-telefon och tablet) är genomförd, även när det är hosted-verifierat och
godkänt av produktägaren.

### TEAM-09 – Roller, titlar och positioner

**Status:** `[~]` – hosted och automatiskt verifierad; fysisk grind återstår

- [x] Ledare kan lägga till ledare (sig själv, befintliga klubbledare eller nya) och byta person mellan spelare och ledare.
- [x] Titlar (t.ex. Huvudtränare) och idrottsspecifika positioner i två nivåer, plus upp till fem egna av varje.
- [x] Flera roller i samma lag blir en lagkontext som visar titeln. Ledare som också är spelare syns i båda listorna.
- [x] Lägg till person: roll, titel och position väljs i samma dialog.

Beskrivning: [`team-person-functions-positions.md`](team-person-functions-positions.md).

### TEAM-10 – Behörigheter per ledare

**Status:** `[~]` – hosted och automatiskt verifierad; fysisk grind återstår

- [x] Behörigheter per ledare med mallar, styrda av capability grants och aldrig av titeln.
- [x] Huvudtränare och klubbens medlemsadministratörer hanterar ledare. Klubbskopad `club.memberships.manage` ger
  `team.leaders.manage` och `team.roster.manage` i hela klubben.

Beskrivning: [`team-leader-permissions.md`](team-leader-permissions.md).

### TEAM-11 – Idrott ändras bara av klubbadministratör

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] `set_team_sport` kräver klubbskopad `club.memberships.manage` och svarar `club_admin_required` annars.
- [x] `list_team_roles` returnerar `can_set_sport`; övriga ledare ser idrotten skrivskyddat i lagprofilen.

### TEAM-12 – Lagöversikt, lagprofil och medlemsredigering

**Status:** `[~]` – hosted och automatiskt verifierad; godkänd av produktägaren på webb

- [x] Översikten visar lagbild, aktiva inbjudningar/förfrågningar (bara för behöriga och när sådana finns), nästa
  händelse och senaste match.
- [x] Lagprofil-dialogen är helskärm på mobil, med fast rubrikrad, sektioner, idrott som chips, felrad och osparat-skydd.
- [x] Medlemssidan har en penna uppe till höger som öppnar en sida med uppgifter, kontaktuppgifter (för personer utan
  konto) och lagåtgärder. Den separata kontaktdialogen och raden "Redigera profil" är borttagna.
- [x] Representation i två steg med godkännande från hemmalaget. Inbjudningar görs i en guide i tre steg.

### TEAM-13 – Huvudposition och profilbilder i trupplistan

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] En spelare har en huvudposition bland sina positioner; övriga är alternativa. Egna positioner kan vara huvudposition.
- [x] Trupplistan visar huvudpositionen i stället för åldern och medlemmarnas profilbilder, med initialer som reserv.
- [x] En huvudposition som inte längre är en position nollställs automatiskt, även från äldre appversioner.

### TEAM-14 – Huvudtitel för ledare

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] En ledare med flera titler väljer huvudtitel. Med en enda titel blir den huvudtitel automatiskt.
- [x] Huvudtiteln visas i trupplistan, lagväljaren och menyn i stället för "Ledare" och "Klubbfunktionär".

### TEAM-15 – Tillfälliga kontaktsidor med QR-kod

**Status:** `[~]` – driftsatt och verifierad med ett riktigt inskick av produktägaren

- [x] Ledare skapar en sida för laget och klubbadministratörer en för klubben. Sidan delas med QR-kod eller direktlänk
  och gäller i 14 dagar.
- [x] Formuläret på public-sajten har namn, telefon, e-post, födelsedatum och adress. Det skyddas av kontroll av
  ursprung, Turnstile och gränser för antal inskick, och bara `service_role` kan spara.
- [x] Ledaren lägger till personen som spelare med ett tryck, eller väljer annat lag eller ledarroll. Hanterade
  inskick raderas.

### TEAM-16 – Inskick uppdaterar befintlig person

**Status:** `[~]` – driftsatt och verifierad av produktägaren

- [x] Ett inskick kan uppdatera en befintlig spelare eller ledare. Telefon, e-post och adress ersätts, ett saknat
  födelsedatum fylls i och namnet behålls.
- [x] Personer som delar ett namn med inskicket föreslås först.

### CAL-12 – Förberedelser och matchläge

**Status:** `[~]` – hosted och automatiskt verifierad; fysisk grind återstår

- [x] Förberedelser v1 per eventtyp med synlighet per fil och realtid.
- [x] Matchläge som tunn klient över Match Space v2: klocka, perioder, mål, målskytt/assist och rättelser.

Beskrivning: [`event-preparations-v1.md`](event-preparations-v1.md).

### CAL-13 – Ny eventdialog och platser

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] Eventdialogen är omgjord med sektioner, fast rubrikrad och osparat-skydd.
- [x] Platsen består av anläggning, plan och valfritt fritextunderlag; kombinationen återanvänds.

### CAL-14 – Kalenderns vy och filter

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] "Vy och filter" i en knapp, Dag/Månad i listans rubrikrad, flera lag samtidigt och sparad standardvy.
- [x] "Planerad" är borttaget från korten. Utkast markeras med en liten ikon.
- [x] Datumraden använder hela titelraden med perioden centrerad mellan pilarna (2026-10-05).
- [x] Svep i sidled byter period i alla vyer, och månadsvyn visar event på dagarna från grannmånaderna. Hämtat datumintervall följer valt datum.
- [x] Dagvyn öppnas vid 15:00, och appbaren byter inte färg när bara kalenderns lista scrollar.

### MSG-09 – Inbox per klubb, ny meddelandedialog och notisåtgärder

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] Inbox filtreras på aktivt lag som standard, och klubbar kan fällas ihop.
- [x] Ny meddelandedialog väljer direkt- eller gruppmeddelande efter antal mottagare.
- [x] Filterdialogen scrollar och går att stänga.
- [x] Notiser kan markeras som lästa eller arkiveras direkt i listan.
- [x] Egna supportärenden ligger i Inbox med räknare för olästa supportsvar och
  privat tvåvägsdialog. Användare och support kan bifoga upp till fem privata
  filer per meddelande, högst 10 MB per fil.
- [x] Supportadministratörer når supportkön från ett kort i Inbox med antal nya
  användarmeddelanden, i stället för från sidomenyn (webb och desktop, 2026-10-05).

### PROF-01 – Egen profil, kontaktuppgifter och profilbild

**Status:** `[~]` – hosted och automatiskt verifierad; kameran fysiskt overifierad

- [x] Namn, kontakt-e-post, telefon, adress och profilbild kan redigeras. Profilbilden kan väljas från bilder eller tas
  med kameran.
- [x] Uppgifterna är synliga för personen och lagets ledare. Klubben fyller i uppgifter för personer utan konto.
- [x] Visningsnamnet slår igenom i klubbens register, drawer och profil.
- [x] Redigering öppnas från appbarens redigeringsikon och samlar profil,
  kontaktuppgifter, roll/titel och behörighetsstyrda inställningar. Stora
  källbilder skalas och komprimeras före uppladdning.
- [x] Kontot kan ha flera adresser, välja kontaktadress per klubb och använda
  skyddat läge. Det tidigare vanliga visningsnamnet återställs när skyddat läge
  stängs av.

### PROF-02 – Byte av inloggningsmejl via support

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] Bytet kräver en supportgodkänd begäran och ett bekräftelsemejl. En trigger på `auth.users` stoppar direkta byten.

### PROF-03 – Virtuellt medlemskort

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] Kortet har foto, klubbmärke, namn, lag och roller, och en baksida med fullständig adress. Helskärm på mobil,
  dialog på tablet och desktop.
- [x] Klubbadministratörer laddar upp klubbmärket. Det lagras privat och läses via signerad URL.

### PROF-04 – Profilflikar och statistik

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] Visningssidan har Medlemsinfo och Statistik. Den egna profilens redigerare
  har separata flikar för profil, kontaktuppgifter, roll/titel och inställningar;
  lag- och klubbinställningar visas bara med rätt behörighet.
- [x] Statistiken gäller alltid den visade personen: närvaro, matcher, mål, assist, kort, kallelsesvar och appanvändning.
  Personen själv och lagets ledare kan se den.

### AUTH-08 – Följarkonto som bara skapas på den publika sajten

**Status:** `[~]` – hosted och automatiskt verifierad; registrering end-to-end med mejlbekräftelse återstår

- [x] Kontotypen `follower` hör inte till något lag och har ingen roll.
- [x] Kontot kan bara skapas via den publika sajtens server (kontroll av ursprung och Turnstile). Bara `service_role`
  kan märka konton, och aldrig ett befintligt konto.
- [x] Villkor och integritetspolicy godkänns vid registreringen och sparas med källan `web`.
- [x] I appen hamnar följare i väntrummet och blir medlemmar när en klubbkoppling blir aktiv.

### PUB-10 – Matcher på lagsidan

**Status:** `[~]` – hosted verifierad och godkänd av produktägaren

- [x] Lagvalet "Visa matcher" visar alla matcher, både kommande och spelade, med titel och tid. Platsen visas bara om den
  publiceras per match, och en match som görs privat förblir dold. Valet är av som standard.

### PUB-11 – Klubbmärke på de publika sidorna

**Status:** `[~]` – migrerad och driftsatt; inget riktigt märke uppladdat ännu

- [x] Aktivt märke för en publicerad klubb visas via `/media/public/<slumpad nyckel>`. Byte eller borttagning av märket,
  eller avpublicering av klubben, stänger den gamla adressen.
- [ ] Bildbehandling (skalning och rensning av metadata) väntar på en konfigurerad leverantör för `public-media-worker`.

### PUB-12 – Klubbsajtens design och klubbfärger

**Status:** `[~]` – driftsatt och godkänd av produktägaren

- [x] Klubb-, lag- och artikelsidor har klubbsajtsdesign, inspirerad av ledande svenska fotbollsklubbar.
- [x] Klubbadministratörer väljer huvud- och accentfärg. Ett stylesheet från sajten säkrar läsbar kontrast; inga
  inline-stilar används (CSP).

Migrationen `20261001090000_club_brand_colors.sql` har kommentaren "PUB-08" men dokumenteras här.

### PUB-13 – TeamZones egna sidor i klubbsajtstil

**Status:** `[~]` – driftsatt; den inloggade startsidan återstår att kontrollera visuellt

- [x] Startsida med inloggnings- och registreringskort, personlig startsida, sök, 404, "inte publicerad" och juridiska sidor.
- [x] Godkända adresser styrs av `PUBLIC_SITE_ORIGINS`. Det rättade också kontaktformuläret på `public.teamzoneapp.se`.

### SET-01 – Klubbinställningar

**Status:** `[~]` – hosted och automatiskt verifierad

- [x] Inställningar har fliken Klubb, bara för klubbadministratörer: klubbmärke med förhandsvisning och uppladdning,
  klubbfärger och klubbverifiering.
- [x] Fliken Publika sidor (2026-10-05) samlar per klubb den publika klubbsidan och lagsidorna, lagens publika
  matcher, resultat och träningstider samt nyhetsredaktionen. Den ersätter raderna Publika sidor och
  Nyhetsredaktion i sidomenyn och visas för den som får publicera eller hantera ett lag.
- [x] Personliga inställningar har valet System, Ljust eller Mörkt, sparat på enheten.
- [x] Samma sektion finns under Inställningar på den egna profilen.
- [x] Lag som aldrig publicerats får en föreslagen webbadress, och ett ogiltigt värde förklaras.

## 15. Rekommenderat nästa konkreta arbete

**Våg 10 (2026-10-02):** genomför en samlad fysisk enhetsgrind (Galaxy S25 och Android-tablet) för TEAM-09–16, CAL-12–14, MSG-09, PROF-01–04 och SET-01; registrera ett följarkonto end-to-end med mejlbekräftelse (AUTH-08); kontrollera den inloggade personliga startsidan visuellt (PUB-13).

Grundappens ursprungliga ordning:

1. [x] Genomför **FND-01** som en ren extraktion utan produktbeteendeändring.
2. [x] Genomför **FND-02** ovanpå de extraherade ytorna.
3. [x] Genomför **FND-03–FND-05** och frys klientgrundens kontrakt.
4. [~] **AUTH-01** lokalt genomförd; hosted GoTrue REST-nivå delvis verifierad 2026-09-04, e-postleverans/dubblett/fysisk grind kräver separat livegodkännande.
5. [~] **AUTH-02** lokalt genomförd; fysisk och hosted sessionsverifiering återstår.
6. [x] **AUTH-03** hosted databas/Edge samt fysisk webb- och Android-deep-linkgrind verifierade; fysisk iOS-kontroll följs upp när iOS-miljö finns.
7. [x] **AUTH-04** hosted runtime och fysisk Android-grind verifierade för sökande, lagledare, återkallelse, avslag och godkännande.
8. [x] **AUTH-05** hosted rollback-runtime och fysisk Android-grind verifierade; nya lag öppnas direkt i sin aktiva kontext.
9. [x] **AUTH-06** skyddade namn, officiell statuskedja och support-adminärenden är hosted, automatiskt och fysiskt verifierade.
10. [~] **AUTH-07** teknisk hosted-matris, versionsbyte, retry, publika placeholderroutes och full regression klara; juridiskt slutligt innehåll och fysisk slutgrind återstår.
11. [x] **TEAM-01** hosted, 367/367 regression och fysiskt navigationsverifierad på mobil, tabletresponsiv webb och desktop/webb inklusive deep link, refresh, system-/browser-back samt bevarad period/filter efter EventDetails.
12. [x] **TEAM-02** hosted SQL/privat Storage och räknarfixture, 369/369 regression samt fysisk webb- och Androidgrind inklusive komplett privat lagbildsflöde och 200 % text verifierade.
13. [x] **TEAM-03** hosted SQL-runtime klar; enhetlig routad medlemsdetalj för alla format passerar 6/6 korttester och 22/22 riktad regression samt fysisk webb- och Androidgrind.
14. [x] **TEAM-04** hosted SQL-runtime samt fysisk webb-, Android- och tabletgrind verifierade, inklusive födelseår utan påhittat datum och senare komplettering av exakt födelsedatum.
15. [x] **TEAM-05** hosted API/Edge samt fysisk invite-, lagkod-, guardian- och webb-deep-linkgrind verifierade.
16. [x] **TEAM-06** hosted runtime samt fysisk Android-tabletgrind verifierade för kandidatval, skapa, lista, bevarat ordinarie lag och avsluta.
17. [x] **TEAM-07** hosted runtime, historikbevarande och fysisk Android-tabletgrind verifierade, inklusive profilgenväg, flerval och korrekt omladdning.
18. [x] **TEAM-08** hosted runtime, Auth-worker och fysisk Android-tabletgrind verifierade för avslutning, återaktivering, dual-control-anonymisering, neutral historik och global kontoradering.
19. [x] **CAL-01** mobil, fysisk Android-tablet och desktop/webb verifierade inklusive tvåkolumnslayout, månadsomfång och bevarad returkontext från EventDetails.
20. [x] **CAL-02** hosted SQL, 3/3 riktade Fluttertester, transaktionellt create/revise-test och fysisk webbgrind inklusive samtliga seriescope är godkända.
21. [x] **CAL-03** verkligt delat event, flerlag, view-only-/deltagarbehörighet, delningsmarkering och deduplicerad kallelse är fysiskt verifierade.
22. [x] **CAL-04** hosted och fysiskt verifierad inklusive delete, cancel, archive, arkivlista, skrivskydd och återställning med bevarad historik.
23. [x] **CAL-05** responsiv EventDetails och leader/player/guardian/delad `Kan se` fysiskt verifierade.
24. [x] **CAL-06** hosted och fysiskt verifierad för alla urvalsmetoder, tomt manuellt utkast, automatisk låsning/utskick, sena kallelser och korrekt återkallning.
25. [~] **CAL-07** player, guardian acting-as, reminder och privat avböjandeorsak är hosted/fysiskt verifierade; push-actiontoken återstår.
26. [x] **CAL-08** hosted och fysiskt verifierad för batch, minuter, korrigering och smal mobil layout.
27. [x] **CAL-09** responsiva EventDetails-gränser och frånvaro av falskt aktiva uppskjutna funktioner är verifierade.
28. [x] **CAL-10** hosted och fysisk leader/player/guardian-grind verifierade; privat standardläge återställt.
29. [x] **CAL-11** Deltagare-flödet, självsvar/manager-svar, delat event och flerlagspersonens deduplicering är fysiskt verifierade.
30. [~] **PUB-01** lokalt genomförd; publicerad fixture, fysisk visuell kontroll och PUB-02/PUB-04-projektioner återstår.
31. [~] **PUB-02** lokalt genomförd; separat livegodkännande återstår.
32. [~] **PUB-03** lokalt genomförd inklusive redaktörsyta; PUB-04-media, cache-SLA, fysisk verifiering och separat livegodkännande återstår.
33. [~] **PUB-04** lokalt genomförd inklusive publicerings-UX och fail-closed mediaworkergräns; provideraktivering/upload-UX, Storage-runtime, fysisk fixture och separat livegodkännande återstår.
34. [~] **PUB-05** lokalt genomförd inklusive domänsjälvbetjäning; entitlement, providerworker och separat DNS/TLS-/driftgodkännande återstår.
35. [~] **PUB-06** lokalt genomförd; hosted synthetic/cache-SLA, workerschemaläggning och separat driftgodkännande återstår.
36. [~] **MSG-01** lokalt genomförd och Flutter-verifierad; fysisk tvårolls-/reconnectgrind återstår.
37. [~] **MSG-02** lokalt genomförd och Flutter-verifierad; fysisk flerrollsgrind återstår.
38. [x] **MSG-03** hostad och fysiskt verifierad för ledare → spelare/vårdnadshavare, skrivskydd, uppmärksamhet, enskild läsning och Markera alla → arkiv.
39. [~] **MSG-04** lokalt genomförd och Flutter-verifierad; fysisk pagination-/retry-/reconnectgrind återstår.
40. [~] **MSG-05** lokalt genomförd och Flutter-verifierad; provider-/Deno-grind och fysisk tvåenhetspreferencegrind återstår.
41. [~] **MSG-06** lokalt genomförd och Flutter-verifierad; Storage-runtime, moderatoroperator och fysisk fil-/safeguardinggrind återstår.
42. [~] **MSG-07** lokalt genomförd och Flutter-verifierad; fysisk flerrolls-/serviceoperatorgrind återstår.
43. [~] **MSG-08** lokalt genomförd och Flutter-verifierad; fysisk tvåenhetsgrind återstår.
44. [~] **HOME-01** lokalt genomförd och Flutter-verifierad; fysisk fler-kontext-/responsivitetsgrind återstår.
45. [~] **HOME-02** lokalt genomförd och Flutter-verifierad; fysisk spelar-/svarsgrind återstår.
46. [~] **HOME-03** lokalt genomförd och Flutter-verifierad; fysisk flerbarns-/acting-as-grind återstår.
47. [~] **HOME-04** lokalt genomförd och Flutter-verifierad; fysisk dedupe-/cross-device-/responsivitetsgrind återstår.
48. [~] **HOME-05** lokalt genomförd och Flutter-verifierad; fysisk legacy-/HOME-regressionsgrind återstår.
49. [~] **AC-01** deterministisk datagrind implementerad; generativ aktivering förblir avsiktligt blockerad.
50. [~] **AC-02** responsiv ingång implementerad; återstående fysisk grind följer kortet.
51. [~] **AC-03** transparent, källmärkt presentation implementerad; återstående fysisk grind följer kortet.
52. [~] **AC-04** lokalt implementerad och Flutter-verifierad; sportigt standardnamn och fysisk kontosynk-verifiering återstår.
53. [~] **AC-05** lokalt implementerad och Flutter-verifierad; fysisk visuell/tillgänglighetsverifiering återstår.
54. [~] **AC-06** lokalt implementerad och Flutter-verifierad; faktisk leverans och fysisk cross-area-verifiering återstår.
55. [~] **AC-07** lokalt implementerad och Flutter-verifierad; verklig flerrollsdata och fysisk enhetsverifiering återstår.
56. [~] **AC-08** policy och fail-closed-grind lokalt implementerade och Flutter-verifierade; flerrollsmatris och fysisk enhetsgrind återstår.

## 16. Ändringslogg

| Datum | Ändring | Status |
|---|---|---|
| 2026-10-05 | **Teamzone 2027-listan och smalare sidomeny.** Supportkön ligger i Inbox och publika sidor och nyhetsredaktion i en egen inställningsflik. Arkiveringskrasch, blinkande Hem (45-sekunderspoll), klubbverifieringens stängning och borttagning av felbokade event utan skickade kallelser är åtgärdade. Kalendern har centrerad datumrad, svep, grannmånadernas event, datumintervall som följer valt datum, dagvy från 15:00 och appbar som bara färgas vid helsidescroll. Ljust/mörkt/system-läge, sidanpassad genvägsmeny och påminnelse som släcker kallelsevarningen i sex timmar. Migrationerna `20261005090000` och `20261005140000` är körda i testprojektet; se `core_app_iteration_2026-10-05.md`. | CAL-04, CAL-14, MSG-09, SET-01, FND-03, AC-02 `[~]` |
| 2026-10-04 | **Supportdialogen flyttad till Inbox.** Egna ärenden har oläst-räknare och privat tvåvägsdialog. Både användare och support kan bifoga bilder och dokument via privat Storage och kortlivade signerade länkar. | MSG-09, AUTH-06 `[~]` |
| 2026-10-03 | **Supportdrift och officiell klubb.** `/support` visar den fullständiga kön, skyddat namn kan godkännas till en färdig officiell klubb/lag-koppling och parterna kan begära komplettering i ärendet. Supabase Cron/`pg_net` och Edge Function skickar notifieringar via Resend; ImprovMX vidarebefordrar inkommande `support@teamzoneapp.se`. | AUTH-06 `[~]` |
| 2026-10-03 | **Personlig och kontextuell assistent.** Kategorier, aktuellt-lag-filter, sidkontext, grupperade aktivitetsvarningar, välkomstmeddelande, FAB-räknare, eget namn och sex profilbilder är infört. | AC-02, AC-04, AC-07 `[~]` |
| 2026-10-02 | **Deterministiska assistentuppgifter och kontodataskydd.** Kallelsebehov, påminnelser, matchuppföljning, förberedelser och kalenderkrockar har införts. Kontaktändringar kräver godkännande, flera adresser och skyddat läge stöds och tidigare visningsnamn återställs när skyddet tas bort. | AC-01–03, PROF-01 `[~]` |
| 2026-10-02 | **Kontaktuppdatering.** Tillfälliga kontaktsidor med QR-kod och direktlänk som gäller i 14 dagar. Inskick läggs till i ett lag med ett tryck eller uppdaterar en befintlig spelare eller ledare. Produktägaren har verifierat flödet med ett riktigt inskick. | TEAM-15–16 `[~]` |
| 2026-10-01 | **Huvudposition, huvudtitel och profilbilder i trupplistan.** Spelare har huvudposition och alternativa positioner, ledare en huvudtitel som visas i stället för rollen, och trupplistan visar profilbilder. Publikt klubbmärke (PUB-11) är nu migrerat och driftsatt. | TEAM-13–14, PUB-11 `[~]` |
| 2026-10-01 | **Våg 10 dokumenterad.** Nya kort TEAM-09–12, CAL-12–14, MSG-09, PROF-01–04, AUTH-08, PUB-10–13 och SET-01 samlar arbetet sedan 2026-09-26 med evidens i `core_app_iteration_2026-09-27_10-01.md`. Alla migrationer till och med `20261001150000` är körda i testprojektet; `20261001170000_public_club_badge` väntar. Flutter 524/524, publik sajt 56/56 och nio isolerade SQL-tester passerar. | Våg 10 `[~]` |
| 2026-10-01 | **Publik sajt, följarkonto och klubbinställningar.** Klubbsajtsdesign med klubbfärger, TeamZones egna sidor i samma stil, följarkonto som bara skapas på public-sajten, "Visa matcher" för lag, publikt klubbmärke (väntar på migration) och fliken Klubb under Inställningar. Kontaktformuläret på `public.teamzoneapp.se` och sparandet av lag som aldrig publicerats rättades. App och publik sajt driftsatta. | PUB-10–13, AUTH-08, SET-01 `[~]` |
| 2026-09-30 | **Profil, eventdialog och lagdialoger.** Egen profil med kontaktuppgifter och profilbild, inloggningsmejl via support, medlemskort, profilflikar med statistik, ny eventdialog med anläggning/plan/underlag, notisåtgärder, lagöversikt, lagprofil-dialog och idrott endast för klubbadministratörer. | PROF-01–04, CAL-13, TEAM-11–12 `[~]` |
| 2026-09-29 | **Lagroller, behörigheter, förberedelser och matchläge.** Roller, titlar och positioner per idrott, behörigheter per ledare med mallar, klubbens medlemsadministratörer hanterar ledare, förberedelser v1 och matchläge. | TEAM-09–10, CAL-12 `[~]` |
| 2026-09-27 | **Trupp och representation.** Spelare får `team.roster.view`, inbjudningsguide i tre steg, representation i två steg med rättat SQL-fel, en redigeringsvy per person, sparad kalendervy och inbox per aktivt lag. | TEAM-12, CAL-14, MSG-09 `[~]` |
| 2026-09-15 | **CAL-01 helt stängd efter tablet- och desktopverifiering.** Kalendern använder en kompakt vy-dropdown och separat filterrad. Månad/Vecka har kalenderöversikt till vänster och event för vald dag till höger; Dag har tidslinje till vänster och kommande agenda till höger. Månadsvyn kan växla mellan vald dag och hela kalendermånaden oberoende av markerat datum. EventDetails öppnas med push/pop och återställer vy, datum och filter; val från Dag-vyns högra agenda synkroniserar först till eventets dag. Native tablet använder alltid Min assistent-FAB så sidans högra kolumn förblir kontextuell. | CAL-01 samtliga grindar godkända |
| 2026-09-13 | **TEAM-08 helt stängd efter hosted och fysisk slutverifiering.** Normal avslutning och återaktivering bevarar den namngivna laghistoriken. Klubbanonymisering kräver två separata ansvariga och bevarar neutral historik som `Tidigare spelare`. Global kontoradering går genom den enhetliga supportkön och den driftsatta Auth-workern; det raderade testkontot kunde därefter inte logga in. En profilomfattande eftermigration hanterar även äldre fragmenterade personidentiteter. Slutkontrollen på fysisk Android-tablet bekräftade den neutrala historikposten i rätt lagkontext. Policy för eventuell publik namngiven historik och juridisk sluttext kvarstår som separata releasegrindar. | TEAM-08 samtliga produktgrindar godkända |
| 2026-09-13 | **TEAM-07 helt stängd efter fysisk tabletverifiering och UX-uppföljning.** En ledare flyttade en spelare mellan två lag och tillbaka; den aktiva representationen bytte lag medan historiken bevarades. PostgREST-svaret gjordes robust för generella mappar och mutationsfelet separerades från efterföljande omladdning så en lyckad flytt inte längre samtidigt visar ett falskt fel. Flyttpanelen är nu ett sammanhållet bottomsheet med flerval, mållag, anledning och fast flyttknapp. Samma flöde kan öppnas från spelarprofilen med aktuell spelare förvald. Resultatet visas ovanpå panelen, och efter bekräftad hel eller partiell flytt stängs panelen så nästa öppning alltid hämtar en aktuell kandidatlista. Riktad Flutter-analys passerar utan anmärkningar och backendansluten APK är byggd, installerad och fysiskt godkänd. | TEAM-07 samtliga grindar godkända |
| 2026-09-12 | **TEAM-02 helt stängd med riktig privat lagbilduppladdning.** HTTPS-fältet ersattes av Välj/Byt/Ta bort med förhandsvisning, JPG/PNG/WebP och 5 MB-gräns. Original lagras i privat bucket efter capabilitystyrd staging och aktiveras revisionerat med profilen; läsning kräver serverauktorisering, aktiv-profilbunden Storage-RLS och signerad URL. Fysisk Xiaomi-test hittade en saknad SELECT-policy efter lyckad upload/aktivering; policyn lades till och befintlig bild började visas utan ny upload. Upload, byte, borttagning/fallback och 200 % text är godkända. Security Advisor gav ingen ny media-/RLS-varning, riktad svit 7/7 och full regression 369/369. Slutlig rollback-fixture verifierade räknarna 1+1 → 0+0 för utgångna/återkallade invites och beslutade/tillbakadragna ansökningar. Publik variant förblir separat PUB-04-grind. | TEAM-02 samtliga grindar godkända |
| 2026-09-12 | **TEAM-01 helt stängd.** Webbgrinden bekräftade direktlänk/refresh och hittade att browser-back från EventDetails föll tillbaka till lagöversikten. Lagflikbytet använder nu `pushReplacement`, vilket gör vald flik till detaljsidans verkliga returpost utan en växande historik av flikar. Omtest bevarar Kalender samt `Tidigare + Matcher`; tabletresponsiv visuell kontroll vid cirka 800–1000 px är godkänd. Första fulla regressionskörningen hittade endast en för bred AUTH-06-testfinder efter det nya förifyllda supportmeddelandet; exakt fältmatchning rättades, AUTH-04 blev 15/15 och full omkörning 367/367. | TEAM-01 samtliga grindar godkända |
| 2026-09-12 | **TEAM-01 cold deep link/system-back fysiskt godkänd efter två verkliga navigeringsfynd.** `teamzone://app/team?tab=calendar` kallstartar korrekt på lagets Kalender. Första back visade felaktigt avsluta-dialog; första rättningen introducerade en Hem/Kalender-loop eftersom cold-linkdestinationen låg kvar bakom Hem. Slutlösningen rensar syntetisk historik när en kall extern ingång faller tillbaka till Hem. Fysisk Xiaomi-omtest: första back → Hem, andra → avsluta-dialog, Avbryt → kvar på Hem. Riktad TEAM-01-svit 3/3 och backendanslutet APK-bygge är gröna. | TEAM-01 Android cold link/system-back klar |
| 2026-09-12 | **TEAM-01 lagkalender ombyggd efter fysisk feedback.** Kommande visas ensamt som standard; segmenterad växling öppnar Tidigare och eventtyper ligger bakom en filterknapp med aktiv filterchip. Kort visar lokaliserat datum/tid, plats, status och slutresultat för avslutade matcher via den actor-läsbara kalenderprojektionen i migration `20260912054644`. En första fysisk kontroll hittade att EventDetails ersatte navigationen och nollställde `Tidigare + Matcher`; listan använder nu push/pop och bevarar båda valen. 3/3 riktade tester, backendansluten APK-bygg och fysisk Xiaomi-verifiering är gröna. | TEAM-01 mobil UX/navigation godkänd; cold link/tablet/webb kvar |
| 2026-09-12 | **AUTH-07 slutlig juridisk text uppskjuten men satt som obligatorisk releaseblocker.** Placeholderdokumenten får användas för intern testning, men extern publik lansering är förbjuden tills alla placeholders ersatts och juridiskt godkänts, en ny materiell dokumentversion publicerats och acceptansflödet verifierats mot den. Punkten får inte stängas eller flyttas till efter go-live. | Extern release blockerad av juridisk sluttext |
| 2026-09-12 | **AUTH-07 dokumentlänkar fysiskt godkända.** Inställningar visar nu Användarvillkor och Integritetspolicy separat med aktuell version och extern öppningsikon. Backendansluten APK installerades utan datarensning; Xiaomi Mi 9-verifiering bekräftade att båda appingångarna öppnar rätt publika dokument med korrekt rubrik och tydlig gul utkastmarkering. Juridisk sluttext samt återstående acceptans-/tillgänglighetsgrind är fortfarande separata öppna punkter. | AUTH-07 dokumentnavigation klar |
| 2026-09-11 | **AUTH-07 dokumentlänkar reparerade med publika platshållarsidor.** Separata responsiva sidor för `/villkor` och `/integritet` lades till i den befintliga publiksajten, explicit märkta juridiskt utkast med synliga placeholders och `noindex`. 29/29 webbtester, TypeScript och Next-produktionsbygge passerar. Rollout till befintlig App Hosting-backend `teamzoneapp-public` är klar; båda custom-domain-URL:erna svarar `200` med rätt dokument och utan inloggningsskal. Migration `20260911184009` pekar de aktiva dokumentlänkarna dit utan att ändra version eller befintliga acceptanser. Slutlig juridisk text och fysisk slutgrind återstår. | AUTH-07 routeblocker löst; juridiskt innehåll kvar |
| 2026-09-11 | **AUTH-07 frivillig marknadsföring fysiskt godkänd.** På Xiaomi ändrades inställningen av → på, låg kvar efter full appomstart och återställdes därefter till av. Hosted slutkontroll gav `marketing_opt_in=false`, revision 3, två nya separata audithändelser och fortsatt två aktiva juridiska acceptanser. Endast faktiska godkända dokument/routes samt efterföljande acceptans-, webb- och tillgänglighetsgrind återstår. | AUTH-07 marknadsföringsdel klar |
| 2026-09-11 | **AUTH-07 fysisk Android-grind påbörjad och stoppad korrekt vid ogiltiga dokumentlänkar.** Xiaomi Mi 9 verifierade blockerande grind, separata obligatoriska val, versioner, avstängd frivillig marknadsföring och att fortsättningsknappen kräver båda attesteringarna. `/villkor` öppnade inloggning; direkt HTTP-kontroll visade att både `/villkor` och `/integritet` levererar samma generiska Netlify-appskal utan juridisk text. Ingen ny acceptans gjordes. Testkontots exakt två tidigare acceptansrader återställdes med ursprunglig version/tid/källa. | AUTH-07 fysisk formdel godkänd; juridiska dokument blockerar |
| 2026-09-11 | **AUTH-06 slutförd.** `coach.emilson@gmail.com` tilldelades support-admin efter uttryckligt godkännande och tilldelningen auditloggades. Fysisk Xiaomi-verifiering bekräftade den behörighetsstyrda menylänken, väntande köpost, övergången till Granskas samt Löst med obligatorisk beslutsanteckning. Slutlig skrivskyddad hosted-kontroll gav status `resolved`, revision 3, rätt handläggare och tre auditsteg. | AUTH-06 klar |
| 2026-09-11 | **AUTH-06 utökad med internt supportärende för skyddat namn.** Fysisk Xiaomi-verifiering bekräftade att `Team-Zone` blockeras och att den nya Kontakta TeamZone-dialogen är förifylld med klubb/lag, kan redigeras och lagrar ett väntande ärende med audit. Privata tabeller, egen ärendeprojektion och en separat plattformsroll gör att klubbroller aldrig kan läsa kön; endast aktiv support-admin kan lista, påbörja, lösa eller avslå revisions- och idempotensskyddat. Rollback-matrisen hittade och framåträttade en för snäv invoker-gräns i menyproben och passerar därefter helt. Backendansluten APK kompilerad och installerad. En uttryckligt vald support-admin och fysisk operatörsgrind återstår. | AUTH-06 användarflöde klart; supportoperatör fysisk kvar |
| 2026-09-11 | **AUTH-06:s fysiska Android-statuskedja godkänd.** Xiaomi Mi 9 verifierade inofficiell status, underlagsvalidering, väntande granskning, officiellt godkännande och återkallad status med möjlighet till ny begäran. Beslut och återkallelse gjordes genom de service-skyddade testkommandona; klienten saknade beslutsåtkomst. Endast fysisk blockering av skyddat namn i skapa-klubb-formuläret återstår, eftersom samtliga befintliga `coach.emilson`-testkonton har aktiv lagkontext. | AUTH-06 fysisk statusdel klar |
| 2026-09-11 | **AUTH-06/07 icke-fysiska grindar genomförda.** AUTH-06:s hosted rollback-matris verifierade neutral namngranskning, homoglyph, befintligt/unikt namn, ACL, servicebeslut, återkallelse och audit men hittade ett riktigt retryfel: dedupe lästes efter statuskontrollen, så ett återförsök efter första lyckade begäran gav `invalid_status`. Migration `20260910202427` rättar ordningen. AUTH-07:s matris verifierade fail-closed juridisk status, separat frivillig marknadsföring, materiellt versionsbyte, ACL och audit men hittade motsvarande ordningsfel där en redan lyckad acceptans kunde ge `legal_version_changed` efter ett senare versionsbyte; migration `20260911044257` rättar detta utan att tillåta ett nytt stale submit. Båda matriserna passerar och rullas tillbaka helt. 363/363 Flutter-tester och full analys passerar. Migrationshistoriken är lokal/remote-synkad genom `20260911044257`. Global `db lint` gav inga AUTH-06/07-fynd men dokumenterade äldre fynd i `hosted_db_lint_2026-09-11.md`. | AUTH-06/07 tekniskt hosted-verifierade; fysisk/juridisk grind kvar |
| 2026-09-10 | **Statusdokumenten avstämda mot evidence och senare ändringslogg.** `slice_status.md` är daterad 2026-09-10 och markerar S10 klar inom godkänd omfattning; PAR-FIN-03 och separat produktion är uttryckliga senare beslut, inte oavslutat S10-arbete. Arbetskortens sammanfattning synkar nu TEAM-05 och CAL-10 som klara, inkluderar tidigare utelämnade CAL-11 och AC-01–03, och tar bort inaktuella påståenden om en blockerad Flutter-testwrapper där den fulla sviten senare dokumenterats grön. AUTH-06/07-evidence anger nu korrekt att migrationerna ingick i den hosted backlog som stängdes 2026-09-04, utan att överdriva kvarvarande fysisk/juridisk verifiering. | Dokumentationsstatus synkad |
| 2026-09-10 | **AUTH-05 slutförd och fysisk rödskärm åtgärdad.** Skapandet av ett ytterligare lag lyckades servermässigt men dialogens lokala `TextEditingController` disponerades under stängningsanimationen och gav `_dependents.isEmpty`; dialogen använder nu ett enkelt lokalt textvärde. Ett djupare flödesglapp rättades samtidigt: `create_team_in_club_for_actor` skapade tidigare bara lagposten. Migration `20260910183540_auth05_create_team_context.sql` skapar nu också en aktiv `club_functionary`-kontext och kopierar skaparens aktiva klubbscopade capabilities. Klienten väljer kontexten via det returnerade lag-ID:t och går direkt till det nya lagets Hem. Hosted rollback-test verifierade samma lag-ID vid retry, exakt en kontext och fyra capabilities. Riktad analys ren, 12/12 tester, fysisk Xiaomi Mi9 verifierad utan rödskärm och med korrekt automatiskt kontextbyte. | AUTH-05 klar |
| 2026-09-07 | **Uppföljning på kallelsesvaret: bara Acceptera/Avböj, och "Behöver din uppmärksamhet" flyttad till Min assistent.** Två uppföljande önskemål på förra radens kallelsesvar. (1) "Kanske" (tentative) togs bort som svarsalternativ överallt — reglerna är tydliga, det är bara Acceptera eller Avböj. Borttaget från alla tre knapprader (den delade `_CallupResponseButtons`-widgeten, spelarhemmets egen inline-rad, och hjältekortets specialstylade vita/mörka knappar). Backendens `respond_callup_for_actor` accepterar fortfarande `tentative` som värde (rör inte token-svarsflödet via e-post, som inte undersökts denna rad) — bara UI:t erbjuder det inte längre. Ett befintligt test (`home02_player_home_test.dart`) som bekräftade `tentative`-knappen uppdaterades till att bekräfta motsatsen. (2) "Behöver din uppmärksamhet"-boxen flyttad från Hem till Min assistent — användarens uttryckliga regel: "All den sortens information ska gå genom assistenten". **Viktig spärr hittad och löst medvetet, inte kringgången:** en tidigare, medveten säkerhetsspärr (migration `20260827194947_home05_...`, HOME-05) håller uttryckligen dessa deterministiska uppgifter oberoende av Assistent Coach-systemet — en databastrigger stoppar aktivt allt som liknar assistent-signaler, och AC-01-spärren blockerar generativa/AI-funktioner tills datakvalitet och behörighet är verifierade, skyddat av ett eget test. Flaggat till användaren innan kodning i stället för att tyst skriva över en tidigare säkerhetsavvägning; efter att ha förklarat att den nya koden fortfarande går via samma direkta `get_leader_home_for_actor`-fråga som Hem redan använde (inte AC-01-spärren eller några genererade signaler) valde användaren att uppdatera testet/kontraktet i stället för att låta boxen ligga kvar — bekräftat: oberoendet av AC-01/genererade signaler är det som skyddas, inte vilken fil texten råkar ligga i. `_AssistantCoachHoldingSurface` fick en ny `overview`-tjänst och hämtar samma `LeaderHomeProjection.tasks` som Hem gjorde; renderas som ett eget kort högst upp på assistentsidan, tydligt avskilt från den ännu inaktiva "Min kö"-sektionen. 358/358 tester, ren analys (backend orörd denna rad). Byggd och installerad på Mi 9:an. | "Kanske" borttaget som svarsalternativ; uppmärksamhetsboxen flyttad till Min assistent efter en medveten avvägning mot en tidigare säkerhetsspärr |
| 2026-09-07 | **CAL-11-uppföljning, elfte omgången: kunna svara på en kallelse.** Efter att "Skicka kallelser" fixades upptäcktes nästa lucka: mottagaren av en kallelse hade ingen väg att svara på den. Efterfrågat på tre ställen: synlig på hem-sidans "nästa"-kort och på Info-fliken, svarbar (Kommer/Kanske/Kan inte) på Deltagare-fliken — och en ledare ska dessutom kunna svara för hela truppens räkning (spelare **och** andra ledare) från Deltagare-fliken, inte bara sig själv. Två produktbeslut klargjorda innan kodning: fulla svarsknappar på hemkortet också (inte bara status, som spelarnas hemsida redan har) och att "svara för andra" gäller alla i truppen, inte bara spelare (samma behörighet som redan styr påminn/återkalla). **Genuint backend-gap hittat:** `internal.actor_callup_response_context`/`respond_callup_for_actor` kände bara igen kallelsens ägare själv eller en aktiv vårdnadshavare — en ledare som blivit kallad (den nya "kallade ledare"-hinken från cal11) kunde alltså inte svara på sin egen kallelse alls, och ingen kunde svara å någon annans vägnar. Migration `20260907170000_cal11e_...` lägger till en tredje 'manager'-gren (samma `actor_can_manage_squad`-behörighet som redan styr påminn/återkalla) i båda funktionerna, lägger `can_respond`/`response_role` till rosterprojektionen (`get_event_squad_for_actor`), och lägger ett `my_callup`-objekt till ledarhemmets `next_event` (`get_leader_home_for_actor`, samma `can_respond`-gräns som spelarhemmets redan beprövade `own_callups`). Klientsidan: `EventRosterPerson` fick `canRespond`/`responseRole`; en delad `_CallupResponseButtons`-widget (Kan inte/Kanske/Kommer) återanvänds av både Deltagare-flikens rader och ledarhemmets nästa-kort; en delad `_declineCallupReasonDialog` extraherades ur spelarhemmets redan befintliga implementation i stället för att skrivas om; `_LeaderHomeContent` gick från Stateless till Stateful för att hålla svarstillstånd, likt spelarhemmets motsvarighet. Info-fliken visar status (read-only) med en "Svara"-genväg som hoppar till Deltagare-fliken, i stället för att duplicera svarsknapparna där. Verifierat mot hostad databas: simulerade både självsvar (Coach Emilson på sin egen kallelse) och manager-svar (Thomas Emilson på en lagkamrats kallelse) genom hela `api.respond_callup`, båda lyckades och rullades tillbaka; rosterprojektionens nya fält bekräftade rätt `response_role` ('self' respektive 'manager') för samma två personer i en och samma fråga. Ett nytt widgettest bekräftar att en manager-svarsknapp faktiskt anropar `respondCallup` med rätt `acting_as_person_id`. 358/358 tester, ren analys, 0 migrationsdiff. Byggd och installerad på Mi 9:an. | Kallelsesvar: synligt på hem+info, svarbart på Deltagare — ledare kan nu svara för hela truppen, inte bara sig själv |
| 2026-09-07 | **CAL-11-uppföljning, tionde omgången: "Skicka kallelser" saknade truppens låsningssteg helt.** Nästa fysiska fynd efter att urvalet gick att spara: "Kallelserna kunde inte skickas. Ladda om och försök igen." på i princip varje försök. Grundorsak hittad genom att läsa `internal.send_callups_for_actor`s källkod: den kräver uttryckligen att truppens revision redan har `state='locked'` — `raise invalid_parameter_value using message='invalid_state'` annars — men `_EventDetailsBodyState._sendCallups()` anropade `sendCallups` direkt på ett utkast (`state='draft'`), utan att någonsin anropa `lockSquad` först. Den gamla "Hantera urval"-vyn (som cal11-ombyggnaden ersatte helt) hade tydligen ett eget låsningssteg som aldrig flyttades med in i den nya, inline:a Deltagare-fliken — en riktig lucka i själva ombyggnaden, inte en regression. `lockSquad` fanns redan definierad i `CalendarServices`-gränssnittet (från tidigare arbete) men anropades ingenstans i klientkoden. Fixat: `_sendCallups()` låser nu truppen (`squad.revision` som `expected_revision`) precis innan sändning, men bara när `squad.state=='draft'` — hoppas över om truppen redan är låst (t.ex. ett tidigare försök som låste men kraschade innan själva sändningen), aldrig omlåst från `sent`/`empty`. Verifierat med en fullständig simulering av båda anropen i rätt ordning som den riktiga aktören mot det riktiga eventet — lyckades (3 nya kallelser skapade, state→`sent`), sedan `rollback` så det verkliga utkastet lämnades orört. 357/357 tester, ren analys efter en null-säkerhetsfix (`squad.revision` är `int?`, `lockSquad` kräver `int`). Byggd och installerad på Mi 9:an. | "Skicka kallelser" saknade truppens låsningssteg — cal11-ombyggnaden tappade det när den gamla vyn togs bort |
| 2026-09-07 | **CAL-11-uppföljning, nionde omgången: den verkliga orsaken till "kunde inte sparas" för Coach Emilson.** Föregående rads race-fix var en riktig bugg men inte HELA orsaken — samma fel kvarstod deterministiskt (utkastrevisionen låg kvar på 15, ingen förändring alls mellan försöken) specifikt när Coach Emilson skulle kallas. Grundorsaken var ett genuint dataglapp mellan två separata tilldelningstabeller: `internal.person_eligibility_at_event` (som `save_squad_draft_v2_for_actor` använder för att validera varje `member_id` innan sparning) kollade `core.team_assignments`, medan `get_event_squad_for_actor`s egen rosterprojektion (byggd i cal11-migrationen samma dag) bygger på `core.assignments` — en annan, roll-scopad tabell. Bekräftat mot hostad databas: Coach Emilson har en aktiv ledarrad i `core.assignments` (skapad 2026-08-08 via den vanliga tillägg-till-lag-vägen) men ingen motsvarande rad alls i `core.team_assignments`, så personen visades korrekt som valbar i rostret men avvisades alltid av spar-kommandots egen behörighetskontroll — två källor till sanning som kommit i otakt, inte en engångsbugg. Kontrollerat att `core.assignments` innehåller minst en matchande rad för alla fem personer som redan fanns i `core.team_assignments` (ingen risk att någon annan tappar behörighet av bytet). Migration `20260907160000_cal11d_...` pekar om branchen till `core.assignments` med samma `role_package in ('player','leader')`-filter som rostret redan använder (så en vårdnadshavare/klubbfunktionär-rad på samma person inte plötsligt gör dem kallelsebara). Verifierat med en fullständig simulering av det riktiga sparanropet som den riktiga aktören (Thomas Emilson, ledare) med Coach Emilsons person-id i listan — lyckades (ny revision 16), sedan `rollback` så det verkliga utkastet lämnades helt orört på revision 15. 0 migrationsdiff, 357/357 tester (ren backend-fix, ingen klientkod ändrad denna rad). | Verklig dataglapp mellan två tilldelningstabeller — behörighetskontrollen litade på en tabell rostret inte längre använder |
| 2026-09-07 | **CAL-11-uppföljning, åttonde omgången: FAB-position + ett riktigt sparfel.** Två fynd. (1) "Skicka kallelser"-FABen satt ovanpå Min assistent-FABen i stället för bredvid — `_aboveAssistantFabLocation` (72px uppåt) var fel val för just den här knappen; ny `_LeftOfAssistantFabLocation` (72px åt vänster i stället, samma rad) läggs till bredvid den befintliga och används bara av just denna FAB, de andra sidornas FAB:ar rör sig fortfarande uppåt som tidigare. (2) **Ett riktigt fynd, inte en produktbugg utan en race condition:** kontot "Coach Emilson" (ledare på ett testlag, verifierat mot hostad databas — `core.person_account_links`/`core.club_people`/`core.assignments`) fick "Ändringen kunde inte sparas. Ladda om och försök igen." på i princip varje tryck. Grundorsak hittad genom att läsa `internal.save_squad_draft_v2_for_actor`s källkod: den avvisar ett anrop vars `expected_revision` inte exakt matchar den aktuella utkastrevisionen (`stale_revision`). Samtliga fem åtgärdsmetoder i `_ParticipantsTabState` (draft-toggle, hantera kallelse, spara närvaro, och de två massåtgärderna) anropade `widget.onReload()` utan `await` — typad som `VoidCallback`, alltså omöjlig att avvakta även om man velat — och rensade sin egen `busy`-spärr direkt efteråt, innan omladdningen (två nya nätverksanrop) hunnit uppdatera `widget.squad` med den nya revisionen. Ett andra tryck som hann in i det fönstret skickade det gamla, nu inaktuella `expected_revision`-värdet och blev alltid nekat av servern — lätt att trigga nu när hela raden (inte bara en liten kryssruta) är ett tryckmål och två rader kan tryckas i snabb följd. Fixat genom att typa om `onReload` till `Future<void> Function()` och `await`a den på alla fem ställen, så `busy` nu hålls kvar tills omladdningen faktiskt är klar. Bekräftat mot hostad databas att kontots tidigare försök ändå gått igenom (15 utkastrevisioner för test-eventet "träning", senaste i `draft`-läge, inte fastlåst). 357/357 tester, ren analys. Byggd och installerad på Mi 9:an; enkel-AppBar och centrerade statuscirklar återverifierade live via ett kall-start-djuplänk (`teamzone://app/calendar/event/<id>`, eftersom MIUI fortfarande blockerar syntetiska tryck/svep) — själva race-fixen och FAB-flytten kräver användarens egen touch för liveverifiering. | FAB flyttad bredvid i stället för ovanpå assistenten; race-fel i fem sparmetoder fixat (busy hölls inte kvar under omladdningen) |
| 2026-09-07 | **CAL-11-uppföljning, sjunde omgången (rad-tryck, FAB-flytt, headerkrymp).** Sju konkreta önskemål efter ännu en fysisk genomgång. **Bieffekt hittad och fixad först:** navigationsskalets egen `Scaffold` hade en ovillkorlig egen `AppBar` (lag-/klubbväljaren) för **alla** rutter, inklusive den nya `/calendar/event/:eventId`-sidan som redan bygger sin egen `AppBar` (centrerad titel, X-knapp) — två staplade headers utan att någon fysisk skärmdump fångat det, eftersom enheten legat i djup vila (MIUI blockerar även syntetisk uppvakning, bekräftat via `dumpsys power`/logcat att appen inte kraschat). Löst med en ny `hidesShellAppBar`-flagga i `_ProductShellState` som slår av skalets egen `AppBar` när platsen börjar med `/calendar/event/`. **De sju önskemålen:** (1)+(2) `_SelectableRow` byggdes om från `ListTile` till en `Material`+`InkWell` som täcker hela raden (användarens rapporterade bugg — bara högerkanten reagerade på tryck), med mindre text (`bodyMedium`/`bodySmall`) och tätare vertikal padding; samma tätare stil applicerad på `_RosterRow`s övriga två grenar (kallad-status, avslutat event) för konsekvens. (3) Litet mellanrum tillagt mellan rosterrader. (4)+(5) "Skicka kallelser" flyttad från en alltid synlig inline-knapp (vars gamla villkor, `_draftMemberIds.isNotEmpty`, faktiskt kunde vara sant även när alla i utkastet redan var kallade — en riktig bugg) till en flytande knapp längst ner som bara visas på Deltagare-fliken när minst en person faktiskt är i utkastet men ännu inte kallad (`inDraft && !isCalled`, beräknat över roster+gäster); positionerad med samma `_aboveAssistantFabLocation`-offset som redan används för att inte krocka med Min assistent-FABen, med en `Badge`-räknare på ikonen. Krävde att `_EventDetailsBody` gick från implicit `DefaultTabController` till en egen `TabController` (`SingleTickerProviderStateMixin`) och en nästlad `Scaffold` (transparent, ingen egen AppBar) enbart för att kunna ge just den här undervyn sin egen FAB. (6) Statuscirklarna centrerade via en `LayoutBuilder`+`ConstrainedBox(minWidth)`+`Center`, som fortfarande tillåter horisontell scroll om innehållet är bredare än skärmen. (7) Headern krymper nu (mindre padding, cirklarna skalas till 82 %) på alla flikar utom Info, kopplat till `_tabController.animation!` via `AnimatedBuilder` — samma `expanded = 1 - value.clamp(0,1)`-princip som det äldre projektets `_EventHeader`, men inte kopierad rakt av. 357/357 tester, ren analys. Byggd och installerad på Mi 9:an. | Rad-tryck, FAB-flytt med räknare, centrerad+krympande header; skalets dubbla AppBar-bugg fixad |
| 2026-09-07 | **CAL-11-uppföljning: jämförelse mot det äldre Teamzone-projektet (C:/Dev/Teamzone).** Bad om inspiration från den gamla appens EventDetails/Trupp-flik (`event_squad_tab.dart`, ~2600 rader) — inte en rak kopiering, utan en genomgång som (a) hittade två riktiga luckor i den nybyggda fliken och (b) tog med tre konkreta förbättringar. **Luckor hittade och fixade:** (1) en spelare/ledare som lagts till via klubbövergripande sökning men saknar aktiv lagtillhörighet på eventets eget lag (en gäst/cross-team-kallelse) syntes tidigare ingenstans alls efter tillägget — rosterprojektionen bygger bara på `core.assignments`, så en sådan person hade ingen rad att synas i. Löst med en delad `_guestRosterFor`-sammanslagning (från `squad.members`/`callups`/`attendance`, minus de som redan finns i rostret) som visas i en egen "Gästspelare"-sektion och räknas med i statusraden. (2) "Påminn"-knappen visades alltid oavsett om kallelsen faktiskt var påminnbar — servern (`remind_callup_for_actor`) kräver `pending`-status, ej utgången kallelse och minst 6 timmar sedan senaste påminnelsen, men klienten hade ingen motsvarande kontroll och skulle bara visa ett generiskt fel vid en dömd-att-misslyckas-tryckning. Ny `EventRosterPerson.canRemindAt()` speglar exakt samma regel; upptäckte samtidigt att `callups.expires_at` aldrig fångades i `CallupView`-modellen trots att RPC:n redan returnerade det. Ny migration (`20260907150000_cal11c_...`) lägger till `callup_expires_at`/`callup_last_reminded_at` i rosterprojektionen. **Förbättringar inspirerade av den gamla appen, men inte rakt kopierade:** en "..."-meny (`Fler åtgärder`) bredvid sökfältet med tre massåtgärder — "Välj alla spelare" (drafta alla ännu okallade spelare i ett sparande), "Påminn alla obesvarade" (endast de faktiskt påminnbara, inte alla obesvarade) och "Sätt alla accepterade som deltog" (endast efter att eventet avslutats, skriver aldrig över en redan satt närvarostatus) — samt en visuellt mer polerad statusrad (ljusa/ikonlika cirklar med kantlinje i stället för solidfyllda, och etiketterna döljs under tablet-brytpunkten så alla sex cirklar får plats utan att trängas, med en tooltip som ersättning). Två nya widgettester (gäströstret syns och räknas med, "Välj alla spelare" sparar rätt personer i ett anrop). Genomgången avslöjade också att `event_details_page.dart` aldrig haft sina `.feature(...)`-strängar kontrollerade mot den engelska ordlistan (samma lucka som tidigare `product_shell.dart`-fynd — den automatiska kontraktstestet skannar bara `teamzone_app.dart`), 17 saknade poster tillagda. 357/357 tester, ren analys, 0 migrationsdiff. Byggd och installerad på Mi 9:an; fysisk visuell verifiering kunde inte slutföras den här gången (skärmen somnade och MIUI blockerar även syntetisk uppvakning, inte bara tryckningar — ingen krasch i logcat) och kräver användarens egen kontroll. | Jämförde mot det gamla Teamzone-projektet: två riktiga luckor fixade (gästspelare, påminn-cooldown), tre förbättringar inspirerade (massåtgärder, statusrad) |
| 2026-09-07 | **CAL-11-uppföljning efter fysisk återkoppling:** tre fynd åtgärdade. (1) **Riktig bugg:** varje tryck på en utkasts-kryssruta laddade om hela sidan och hoppade tillbaka till Info-fliken. Grundorsak: `_EventDetailsPageState` byggde om hela `_EventDetailsBody` (inklusive `DefaultTabController` och `_ParticipantsTab`s sök-/redigeringsläge) varje gång `_reload()` anropades, eftersom `FutureBuilder` visar en laddningsindikator och river ner subträdet så fort `_load`-fältet byts ut. Fixat genom att flytta ägandet av `event`/`squad` till `_EventDetailsBody`s egen State (seedad en gång, uppdaterad in-place av en ny `_refresh()`-metod som aldrig river ner widgetträdet) — sidans egen `FutureBuilder` triggas numera bara av en riktig återförsök-omladdning, inte av varje enskild åtgärd. (2) Kryssrutorna ersatta med hela rader som färgmarkeras vid val (`ListTile.selected`/`selectedTileColor`), enligt önskemål — en delad `_SelectableRow`-widget används både i sökresultatlistan och rosterlistan. (3) Headern gjordes om: ingen tillbakapil, centrerad titel (eventets namn, nu i själva AppBar-titeln i stället för en separat rad i sidkroppen — hålls uppdaterad genom en ny callback-kedja så att en omdöpning via "Redigera" fortfarande syns utan att sidan laddas om) och ett litet X uppe till höger för att stänga. Ett nytt regressionstest bekräftar att en väljning inte längre lämnar Deltagare-fliken. 356/356 tester, ren analys. Byggd och installerad på Mi 9:an. | Rad-tryck-krascher till Info-fliken fixad; kryssrutor ersatta med färgmarkerade rader; header omgjord (X i stället för tillbakapil, centrerad titel) |
| 2026-09-07 | **CAL-11: Deltagare-fliken helt ombyggd, efter en detaljerad genomgång av önskemål.** EventDetails är sedan detta en egen sida (`_EventDetailsPage`, ny GoRoute `/calendar/event/:eventId`, ersätter dialogen/bottom-sheeten) med en färgkodad statusrad (utkast/kallade/accepterat/obesvarade/avböjt, plus "deltog" när eventet har varit) synlig ovanför flikarna oavsett vilken av Info/Deltagare/Förberedelser/Uppföljning som är aktiv. Deltagare-fliken (`_ParticipantsTab`) är helt omskriven: ett klubbövergripande sökfält (namn eller lagnamn) med flervalsbara resultat direkt till utkastet, sorterat efter lagets ålder (äldst först) och sedan bokstavsordning; "Hantera urval"-knappen och hela den gamla Trupp-bottom-sheeten är borttagen — allt (utkast, kallelser, svar, närvaro) sker nu inline i en enda rosterlista, indelad i exakt de fyra hinkar och den sorteringsordning som efterfrågades (kallade spelare — accepterat/obesvarat/avböjt — kallade ledare i samma ordning, sedan okallade spelare, okallade ledare). Två genuina backend-luckor hittades och fixades under arbetet, inte bara klientombyggnad: (1) `person_eligibility_at_event` kollade bara eventets `owning_team_id`, så ett delat event (t.ex. P10/P11 som tränar ihop via `core.event_teams`) exponerade aldrig det delade lagets spelare som valbara — fixat att gå via `core.event_teams` (primär och delad) i stället; (2) den nya sammanslagna rosterprojektionen (ny `roster`-nyckel i `get_event_squad`, med lag-, roll- och attendance-revision per person) fanns inte tidigare — bara "redan valda"/"redan kallade" listor, inte "hela laget uppdelat i spelare/ledare med aktuell status" som efterfrågades. Migrationerna `20260907140000_cal11_...` och en uppföljande `20260907141500_cal11b_...` (glömd `attendance_revision`, fixad framåt enligt sessionens etablerade princip) pushades och verifierades både med `--dry-run` (0 diff) och direkt mot hostad databas (simulerat anrop som Coach Emilson, både mot ett tomt nytt event och det riktiga Tranås-matchevent med existerande kallelser/närvaro från tidigare i sessionen — rostret slog ihop lag-, roll-, utkasts-, kallelse- och närvarodata korrekt). En verklig gräns hittades och respekteras medvetet snarare än döljs: `record_attendance_v2` kräver att personen redan har en (icke avbruten) kallelse — närvaro kan alltså inte registreras för någon som aldrig kallats; okallade rader visar i stället "Aldrig kallad" i stället för en kontroll som ändå skulle misslyckas. Ett nytt widgettest (`cal11_event_details_page_test.dart`) kör hela flödet — öppna sidan, läsa statusraden, verifiera hink-sortering, söka och lägga till en klubbövergripande kandidat i utkastet — mot en fejkad `CalendarServices`. Byggandet av testet fångade två egna buggar innan de nådde produktion: `setState(() => _load = _fetch())` returnerade av misstag Futuren (tilldelningsuttryck utvärderas till det tilldelade värdet) och kraschade Flutters egen guard, samt en redan existerande, tidigare aldrig testad 60px `RenderFlex`-overflow i händelseredigerarens dropdown-fält (samma klass av fynd som förra sessionens dropdown-bugg). En hårdkodad `'/calendar?event='`-länk i roster_surface.dart (inte `ProductRouteContract.calendarEvent(...)`) hade annars tyst gått sönder av routeformatbytet — hittad och fixad. **Medvetet avgränsat:** grupper (spara återanvändbara spelarurval, baserat på tidigare event eller manuellt) är en helt ny funktion utan någon backend-modell alls — användaren valde uttryckligen att göra sida/statusrad/deltagarflik i ett svep först och grupper som ett separat, senare steg. Delade event är fixat i backend men inte livetestat mot ett riktigt delat event (inget sådant fanns i testdatan). 356/356 tester, ren analys, 0 migrationsdiff. Byggd och installerad på Mi 9:an (Hem-sidan bekräftat oförändrad och fungerande); själva sid-navigeringen (trycka på ett event i kalendern) kräver användarens egen touch för liveverifiering. | Deltagare-fliken helt ombyggd till egen sida med sökbar rosterlista; två verkliga backend-luckor fixade |
| 2026-09-07 | **Uppföljning:** genvägsmenyn fick mer specifika åtgärder efter feedback ("lite mer specifika genvägar, t ex skapa nytt event, bjud in spelare, skicka meddelande") — tre nya rader som inte bara navigerar utan öppnar rätt flöde direkt: "Skapa nytt event" (kräver `event.manage`), "Bjud in spelare" (kräver `club.memberships.manage`/`team.roster.manage`) och "Skicka meddelande" (alla roller). Mekaniken återanvänder samma `?query`-parameter-mönster som redan fanns för `initialEventId`/`initialThreadId`/`initialTab`: tre nya `ProductRouteContract`-hjälpare (`calendarCreateEvent`/`teamInvite`/`inboxCompose`) bygger `/calendar?action=create` osv, och varje yta läser sin `initialAction` en gång i `initState` (samt `didUpdateWidget`) och öppnar samma dialog/sheet som dess egen FAB redan gör — `_CalendarSurface._createEvent()`, `_InboxSurface._compose()`, en direktöppning av `_InvitationAdminSheet` i `_RosterSurface`. Kalender- och Trupp-ytorna kontrollerar capabiliteten själva igen innan de öppnar (samma mönster som sidans egen FAB-gate), i stället för att bara lita på att genvägsmenyn gated rätt, eftersom detta går att nå via en direkt deep link. Två nya widgettester svepar upp och trycker på respektive genväg i appen (inte en kall deep link, som visade sig ge en dubblerad dialog-bugg specifik för testmiljöns kalla routing — inte en riktig produktbugg, så testerna byggdes om för att köra det faktiska svep-och-tryck-flödet i stället). Detta avslöjade en **verklig, sedan tidigare befintlig** layoutbugg: händelseredigeringsdialogens typ-/statusdropdowns (och intervalltyp-dropdownen i återkommande-serien) saknade `isExpanded: true`, vilket gav en 60 px `RenderFlex`-overflow på telefonbredd — troligen alltid närvarande men aldrig upptäckt eftersom inget tidigare automatiserat test öppnat dialogen i telefonbredd. Fixat (tre dropdowns). 355/355 tester, ren analys. Byggd och installerad på Mi 9:an. | Genvägsmenyn öppnar nu specifika flöden direkt; en verklig dropdown-overflow-bugg hittad och fixad på köpet |
| 2026-09-07 | **Ny funktion:** ett svep uppåt över Hem-knappen i telefonens bottennavigering öppnar nu en "Genvägar"-bottom sheet med rollanpassade snabbåtgärder — "en genväg för alla viktiga funktioner för just den personen", enligt användarens beskrivning (tränare får laghanterings-/eventgenvägar, spelare får event/inkorg, osv). Innehållet byggs inte från en hårdkodad per-roll-lista utan från samma capabilities som redan styr draget/sidopanelens adminlänkar (`event.manage` ger "Planera aktivitet", `club.memberships.manage` ger "Hantera laget", `club.billing.manage`/ekonomi/styrelse/redaktionscapabilities ger respektive adminrad), så den håller sig korrekt även för delvisa/scopade roller utan särskilda fall. Tekniskt: en `LayoutBuilder`+`Stack` lägger en genomskinlig `GestureDetector` (`HitTestBehavior.translucent`) exakt över Hem-segmentet av `NavigationBar` (bredd = total bredd / antal destinationer); `onVerticalDragEnd` med `primaryVelocity < -250` öppnar menyn, medan en vanlig tryckning fortfarande går till gesturarenan och löses som ett tryck på det underliggande NavigationBar-objektet — verifierat med ett nytt widgettest som både bekräftar att en vanlig tryckning inte öppnar menyn och att ett svep gör det. 353/353 tester, ren analys. Fysisk verifiering av själva svepgesten återstår (kräver användarens egen touch — samma MIUI-begränsning som tidigare). | Rollanpassad svep-upp-genvägsmeny på Hem-knappen tillagd |
| 2026-09-07 | **Designarbete, buggfix:** Hem-sidans hjältekort för nästa aktivitet var oavsiktligt smalare än korten under det (en `Column` utan `stretch` krymper till sin bredaste textrad eftersom `ListView` bara ger lösa, inte fasta, breddbegränsningar) — fixat med `width: double.infinity` på kortets `Ink`. Samtidigt bytte hjältekortet från sin egna mörka linjära toning till samma radiella `menuGradient` som draget/sidopanelen använder, per användarens uttryckliga önskemål om samma tonings-stil på båda ställena; den nu oanvända `heroGradient` togs bort. Verifierat live på Mi 9:an: kortet är nu lika brett som "Idag"-kortet och visar den radiella toningen korrekt (i det då aktiva orange-temat). 352/352 tester, ren analys. | Hem-hjältekortet fullbrett + delar radiell toning med menyn |
| 2026-09-07 | **Designarbete, uppföljning:** de fyra färgtemanas basfärger bytta till exakta hexvärden från användaren (Grön `#599370`, Blå `#16283D`, Röd `#852929` — ersätter det tidigare "Lila"-temat, Orange `#724C14`). Menyns/sidopanelens bakgrundstoning ändrades samtidigt från en linjär vertikal toning till en **radiell** toning som utgår från en punkt uppe till vänster i panelen, något ljusare än temats grundfärg (`Color.lerp(seed, Colors.white, 0.22)`), och tonar ut mot grundfärgen själv — en ny `AppColorTheme.menuGradient`, medvetet skild från Hem-sidans hjältekortstoning (`heroGradient`, oförändrad: mörkare linjär toning mot nästan svart) eftersom önskemålet uttryckligen gällde "menyn". Verifierat live på Mi 9:an: kontot hade nu en riktig kommande aktivitet, så hjältekortet och den nya "Idag"-dagbrickan syntes för första gången med de nya färgerna och renderade korrekt. Menyns egen radiella toning kunde inte synas live än (MIUI blockerar syntetiska tryck så draget kan inte öppnas via adb, och att tvinga fram den permanenta sidopanelen via `adb shell wm density` nekades av samma MIUI-begränsning) — återstår användarens egen kontroll. 352/352 tester, ren analys. | Nya temafärger + radiell menytoning; Hem-hjältekort bekräftat live med riktig data |
| 2026-09-07 | **Designarbete, pågående (del 2 av 3 från samma önskemål):** navigationspanelens (drawer på mobil, permanent sidebar på tablet/desktop) bakgrund bytt från Materials vanliga ljusa `Drawer`-yta till en mörk toning i den aktuella färgtemats accentfärg (ljusare accentton upptill, tonande mot nästan svart nedåt), med panelens egen `ListTile`/knapp-/textfärger omkopplade till ett lokalt mörkt `Theme`-overrride så innehållet förblir läsbart oavsett appens eget ljus/mörkt-läge. Gradienten extraherades som `AppColorTheme.heroGradient` i `app_theme.dart` så den kan återanvändas — vilket den direkt gör av Hem-sidans nya "NÄSTA"-hjältekort (se raden nedan), inte bara duplicerad på plats. Hem-sidan fick samtidigt en personlig hälsningsrubrik ("God eftermiddag, {förnamn}" + dagens datum) som ersätter den generiska sidtiteln, och Ledarens Hem-innehåll (mobilt läge) fick ett mörkt toningskort för nästa kommande aktivitet överst samt omdesignade "Idag"-rader med en kompakt datumbricka (veckodag + dagsnummer), efter en medskickad mockup. Tablet/desktop-rutnätslayouten och Spelar-/Vårdnadshavarrollernas Hem-innehåll är oförändrade i detta steg — ett medvetet avgränsat första steg, verifierat live på Mi 9:an med hälsningsrubriken synlig (kontot i sessionen saknade dock kommande aktiviteter, så hjältekortet/dagsraderna kunde inte synas live än). En "AFTER THAT"-sekundärsektion från mockupen är medvetet utelämnad tills vidare: modellen har bara "idag"- och "nästa"-data, inte en riktig veckovy, och en andra sektion hade riskerat att visa samma händelse dubbelt. 352/352 tester, ren analys. | Drawer/sidebar mörk accenttoning + Hem-hälsning/hjältekort för Ledare — Spelare/Vårdnadshavare och bredare skärmar återstår |
| 2026-09-07 | **Designarbete, del 1 av 3:** grund lagd för flera färgteman och Geist som appens typsnitt, efter ett medskickat mockupönskemål om att bara accentfärgen ska variera medan resten av utseendet är detsamma. `AppColorTheme`-enum (Grön/Blå/Lila/Orange, en seedfärg per tema) plus `AppColorThemeScope` (InheritedWidget, installerad ovanför `MaterialApp`) styr nu `ColorScheme.fromSeed` för både ljust och mörkt läge. Geist-typsnittet paketerades lokalt (fyra vikter, SIL Open Font License, hämtat från `vercel/geist-font`) i stället för en runtime-CDN-lösning. Valt tema persisteras via ett nytt `ThemePersistence`-tjänstfamilj (samma mönster som `ContextPersistence`) och kan bytas från en ny färgtemaväljare i profilinställningarna. Committat som `d977fb7`; 352/352 tester, ren analys. Font bekräftat visuellt live; färgväljaren bekräftad fungerande av användaren själv. Denna rad dokumenterar det arbetet i efterhand — inget nytt kodarbete i denna rad. | Flerfärgstema + Geist grundlagt och verifierat live |
| 2026-09-07 | Fysiskt fynd: drawer-menyn på mobil stängdes inte efter att en meny-rad tryckts — den blev liggande kvar över den nya sidan, vilket lästes som "knapparna fungerar inte". Grundorsak: `_go()` stängde draget med `Navigator.of(context).maybePop()`, men en Scaffold-drawer är inte en route på den omgivande Navigatorn (den visas via `ScaffoldState` direkt), så poppet gjorde tyst ingenting. Bekräftat med ett widgettest innan fix (`ScaffoldState.isDrawerOpen` förblev `true` efter en meny-tryckning) och löst genom att stänga via samma `GlobalKey<ScaffoldState>.closeDrawer()` som redan används för att öppna draget. Nytt regressionstest tillagt. Verifieras live näst. 352/352 tester, ren analys. | Draget stängdes inte efter navigering — nu fixat via ScaffoldState |
| 2026-09-07 | **Uppföljning på samma Statistik-genomgång:** efter att sen närvarokorrigering fixats (raden ovan) och användaren faktiskt registrerat närvaro för fyra spelare i en match, visade Statistik-sidan fortfarande "Ingen närvarostatistik ännu". Diagnos i tre steg, alla verifierade mot hostad databas: (1) första sparförsöket hade faktiskt misslyckats helt tyst — `attendance_facts` var tom trots att UI:t visade "4 registrerade deltagare"; det talet visade sig vara antalet **kallade** till matchen (`squad.attendance.length`, byggt från `core.callups`), inte antalet med sparad närvaro — förvirrande men inte felaktigt kodat, bara missvisande. Ett andra försök (med användaren live på skärmen, `adb logcat` övervakad) sparade korrekt. (2) Trots lyckat sparande visade Statistik fortfarande noll: `internal.get_main_surfaces_for_actor`s statistikprojektion räknar bara **aktörens egen** `attendance_facts`-rad — rätt för en spelares "min närvaro"-vy, men strukturellt omöjlig för en ledare som normalt inte själv är truppmedlem. Efter en produktbeslutsfråga (lagets samlade närvaro för roller med `event.manage`/`event.attendance.manage`, kontra oförändrat) valde användaren det förra. Migration `20260907093000` implementerade detta. (3) Det avslöjade ett tredje, eget misstag: CREATE OR REPLACE kopierade `context_json`-blocket ordagrant från S05:s **ursprungliga** migration, vilket omedvetet återinförde en `club_people.state`-kolumnbugg som en efterföljande migration samma dag (`20260808095006`) redan hade fixat via en dynamisk textersättning mot den levande funktionen — osynlig vid att bara läsa migrationskällkoden uppifrån och ner. Upptäckt direkt via en enkel testfråga mot hostad databas innan det nådde klienten; fixat framåt med migration `20260907093500` i stället för att redigera den redan pushade filen. Slutverifierat: statistik visar nu korrekt present:3, late:1, absent:1 för testlaget. 0 migrationsdiff efter varje push. | Statistik var strukturellt omöjlig för ledare — visar nu lagets samlade närvaro |
| 2026-09-07 | **Fysiskt fynd under Statistik-genomgången:** att markera närvaro på ett äldre event gav "Sen närvarorapportering kräver särskild behörighet" utan någon väg att få behörigheten. Grundorsaken var inte en klientbugg: `internal.actor_can_correct_late_attendance` kontrollerar `event.attendance.correct_late`, men ingen migration delade någonsin ut den — varken klubbgrundarens beviljande vid klubbskapande (AUTH-05) eller det historiska ledarskaps-capabilitybackfillet (S07). Ingen kunde alltså någonsin korrigera närvaro äldre än 24 timmar, vilket matchade CAL-08-kortets egen olösta "Återstår"-rad om ett aldrig fysiskt verifierat late-correction-flöde. Efter en produktbeslutsfråga till användaren (alla lagledare per automatik, kontra bara klubbfunktionär/admin via en ny adminyta, kontra en tillfällig grant bara till testkontot) valdes att ge alla lagledare capabiliteten per automatik, i linje med `event.manage` som de redan har. Migration `20260907090000` lägger till capabiliteten i klubbskapandefunktionen för framtida lag och backfillar samtliga befintliga `event.manage`-beviljanden (scope- och rolloberoende, täcker både S07:s lagscopade och AUTH-05:s klubbscopade beviljanden). Verifierat mot hostad databas: testkontot har nu capabiliteten. 0 migrationsdiff, 351/351 tester, ren analys. | Sen närvarokorrigering var omöjlig för alla — nu beviljad till lagledare |
| 2026-09-07 | Uppföljning av 2026-09-06:s öppna fråga "värt att kontrollera om samma glapp finns i produktionsmiljön, och om andra edge-funktioner har liknande eftersläpning". Först klargjort mot `docs/architecture/s01_greenfield_foundation.md`: det finns **ingen separat produktionsmiljö** att jämföra mot — `hgcshgunvooyudvrcpig` ("TeamzoneApp") är det enda driftsatta greenfield-projektet, "Teamzone6" är uttryckligen en skrivskyddad historisk referens och aldrig ett deploymentmål, och riktig produktion kräver separat godkännande som ännu inte finns. Den delen av frågan är alltså inte tillämplig än. Den andra halvan — övriga driftsatta edge-funktioner — kontrollerades på nytt (samma `supabase functions download` + `git diff` + `git checkout --`-teknik): samtliga 7 övriga funktioner (`notification-worker`, `message-retention-worker`, `billing-checkout`, `stripe-webhook`, `critical-flow-monitor`, `auth-password-sign-in`, `invitation-preview`) matchar incheckad källkod förutom en trivial saknad avslutande radbrytning i `invitation-preview/index.ts` och den delade `_shared/observability.ts`, ingen funktionell skillnad. `critical-flow-command` (version 6, redeployad 2026-09-06) är oförändrad sedan fixen. Inget nytt driftgap hittat. | Inget produktionsprojekt finns än; övriga edge-funktioner bekräftat i synk |
| 2026-09-07 | Två uppföljande FAB-fynd från fysisk användning: (1) samma icon-only-fix som Truppens Hantera-FAB fick tidigare tillämpades på de fyra kvarvarande `FloatingActionButton.extended`-knapparna i appen (Kalender "Nytt event", Inbox "Nytt meddelande", Nyhetsredaktion "Ny artikel", Domänhantering "Egen domän") — texten finns kvar som tooltip. (2) Min assistent-FABen slutade växla mellan två höjder beroende på sida; den ligger nu alltid i standardläget längst ner, och de fem sidor med egen FAB flyttar i stället upp sin egen via en ny `_AboveAssistantFabLocation` (bara under desktopbrytpunkten). Valde detta i stället för en sid-medveten assistent-höjd eftersom Domänhantering öppnas via en inbäddad `Navigator.push` som inte syns i skalets spårade route — en route-baserad uppslagning hade missat just den sidan. Verifierat live på Mi 9:an. 351/351 tester, ren analys. | Kvarvarande FAB:ar krympta; Min assistent-FAB fast position |
| 2026-09-07 | **Kritiskt fynd från fysisk användning:** systemets tillbaka-knapp stängde appen direkt i stället för att navigera bakåt. Grundorsak: `.go()` (används av bottom nav och drawer för all primär navigation) ersätter aktuell plats i routern i stället för att lägga till ett historikpost, så när en sida nåtts på det sättet fanns inget för tillbaka-knappen att poppa — den föll rakt igenom till Androids standardbeteende "inget att poppa, stäng appen". Ett diagnostiskt test skrevs innan fixen för att verifiera vilken del som faktiskt var trasig: dialoger och `_router.push`-ytor (Min assistent) visade sig redan poppa korrekt via GoRouters egen back-button-dispatcher, så själva gapet var begränsat till sidnavigering. Löst genom att `_ProductShellState` nu håller en `_locationHistory`-lista synkad via en listener på routerns `routeInformationProvider`, och en `PopScope` som stegar tillbaka genom besökta sidor en i taget; på den allra första sidan som öppnades sessionen visas i stället en "Stäng TeamZone?"-bekräftelse innan appen faktiskt stängs. Två nya regressionstest tillagda (sidhistorik-stegning, samt bekräfta-innan-stängning med en mockad `SystemNavigator.pop`-kontroll). Verifierat live på Mi 9:an. 351/351 tester, ren analys. | Tillbaka-knappen stängde appen direkt — nu sidhistorik + bekräfta stängning |
| 2026-09-07 | Uppföljning på gårdagens navigationsskal, tre användarfynd åtgärdade: (1) Truppflikens "Använd kod"-knapp (fanns i fyra lägen: sökraden, behörighetsspärrat, tomt lag, inget lag alls) togs bort och konsoliderades till en ny sida `_ProfileSettingsSurface` (`lib/src/features/account/profile_settings_surface.dart`, route `/settings`) nåbar via drawerns/sidopanelens "Inställningar"-rad, som nu visar både lagkopplingar+Använd kod och den gamla marknadsföringstoggeln (tidigare en egen liten bottom sheet) i samma sida — ett andra försök efter att användaren först bad om en fristående "Mina lagkopplingar"-rad i menyn och sedan bad att den togs bort till förmån för denna samlade inställningssida. (2) Truppens "Hantera"-FAB gjordes ikon-only (ingen text) för att ta mindre plats. (3) Hantera-menyns bottom sheets läggs nu på root-navigatorn (`useRootNavigator: true`, samma mönster som redan användes för personuppgiftsarket) så de renderas ovanför den ihållande Min assistent-FABen istället för under. De två sistnämnda fixarna avslöjade två äkta buggar som testsviten fångade: Min assistent-FABen och en sidas egen standardpositionerade FAB (Trupp, Kalender, Inbox, Nyhetsredaktion, Domänhantering) hamnade på exakt samma pixelposition vid tablet-brytpunkten sedan Trupp-FABen krympte (löst genom att återställa FABens nedre marginal till en konstant 88px istället för 16px på tablet), och en `TextEditingController` som disponerades direkt efter att "Använd kod"-dialogen stängdes kraschade mot dialogens pop-animation (löst genom att sluta disponera den, som i originalkoden). Verifierat live på Mi 9:an efter varje ändringsomgång. 349/349 tester, ren analys. | Truppens Använd kod flyttad till Inställningar; Hantera-FAB krympt; bottom sheet-FAB-krock fixad |
| 2026-09-07 | Navigationsskalet byggdes om efter en referensbild från användaren: appbaren visar nu en tvåradig lag-/klubbväljare till vänster (lagnamn fetstil överst, klubbnamn mindre därunder) och en profilbild till höger som öppnar en drawermeny; telefonens bottom nav har exakt fem knappar i ordningen Laget, Kalender, Hem, Inbox, Statistik. Tablet och desktop använder samma menyinnehåll (profil, lagväljare, huvuddestinationer, Utveckling, capabilitystyrda adminlänkar, inställningar/logga ut, TeamZone-vinjett) som en permanent 280 px vänstersidopanel istället för den gamla nakna NavigationRail. Mockupens "Workspaces"/"Web Tools"-sektioner uteslöts medvetet (användarens val) eftersom de flesta av deras poster inte motsvarar riktiga funktioner än. Ombyggnaden exponerade ett äkta layoutfel, inte bara ett testartefakt: den nya sidopanelen plus den redan existerande 288 px breda Min assistent-panelen lämnade för lite bredd åt innehållet vid realistiska tabletbredder (t.ex. 800 px porträtt) — löst genom att Min assistent-panelen nu bara tar sin egen kolumn på desktopbrytpunkten (≥1024 px) och faller tillbaka till den rörliga FAB:en på tablet, precis som på telefon. 20 testfall som detta orsakade rättades (dels genom denna breddfix, dels genom att uppdatera kvarvarande `NavigationRail`-referenser och scrolla till menyrader som annars låg under vikningen vid standardtestets 800×600-yta). Verifierat live på Mi 9:an (tvåradig väljare, profildrawer med korrekt namn/roll/capabilitystyrda länkar, femknappsraden) efter att en första debug-build fick "Backend är inte ansluten" — inte en bugg i själva ombyggnaden utan en build som saknade `--dart-define=SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY`. 349/349 tester, ren analys. | Navigationsskal ombyggt: tvåradig väljare, profildrawer, femknapps bottom nav |
| 2026-09-06 | **Driftfynd, inte en kodbugg:** fysisk genomgång av Inbox-notiscentret (Ledare) visade att varken en enskild notis eller "Läs alla" gjorde något. `adb logcat` avslöjade `FunctionException(400, operation_not_allowed)` från `setNotificationState`. Jämförelse av den deployade `critical-flow-command`-edge-funktionen mot incheckad källkod (`supabase functions download` + `git diff`) visade att den **deployade versionen saknade `set_notification_state`, `mark_all_notifications_read` och ytterligare 15 operationer** (bl.a. `set_thread_pin/visibility`, `leave_thread`, `close_thread`, trådraderingsflödet, `set_messaging_push`, samt hela publiceringsflödet: `save_editorial_article`, `transition_editorial_article`, `configure_event_publication`, `save_public_partner`, `request_publication_domain`, `set_canonical_publication_domain`) — funktionen hade helt enkelt inte deployats om sedan dessa lades till i koden. Åtgärdat genom `supabase functions deploy critical-flow-command`; verifierat genom att ladda ner den deployade versionen igen och bekräfta 0 diff mot repot. Detta är ett rent deployment-gap (koden i repot var redan korrekt) men **helt osynligt för den mockade testsviten**, precis som SQL-buggarna i migrationsbacklogen — värt att kontrollera om samma glapp finns i produktionsmiljön, och om andra edge-funktioner har liknande eftersläpning. Ominstallationen exponerade sedan en äkta klientbugg: att stänga en tråd öppnad via notis orsakade en omedelbar återöppningsloop (racet beskrivs i commit `6dc2f25`), fixat och verifierat live. 349/349 tester, ren analys. | Kritiskt driftgap i edge-funktion hittat och åtgärdat, plus en riktig navigeringsbugg |
| 2026-09-06 | Fysisk Ledare-genomgång fortsatt in i Kalender och Inbox (samma session/konto som föregående rad). Kalendern byggdes om vy för vy efter direkt användarfeedback under genomgången: Månadsvyn fick ett fast rutnät (kvadratiska celler med händelseantal-badge) ovanför en oberoende scrollande dagspanel, en kompakt filterknapp (bottom sheet) istället för två dropdown-rader, ISO-veckonummer med tooltip och en valfri "visa kvartsmarkeringar"-inställning; Veckovyn fick ett eget 4×2-rutnät (7 dagar + en "kika in i nästa vecka"-ruta) som delar utrymmet 50/50 med dagspanelen, med tvåradiga händelsekort (typikon, starttid, titel — "Borta"/"Hemma" förkortas till "(B)"/"(H)"); Dagvyn byggdes om till en riktig 24-timmars vertikal tidslinje (timmarkeringar, halvtimmestreck, valfria kvartsstreck) med händelser som positionerade, sida-vid-sida-läggbara kort vid överlapp (verifierat både i test och genom att skapa ett verkligt överlappande event live). Utöver UI-omdesignen hittades och fixades fyra verkliga fel: (1) "Kalendern visar sparad data"-bannern kunde fastna utan att kunna stängas och visade en oformaterad tidsstämpel med mikrosekunder — fick en manuell stäng-knapp och ett läsbart tidsformat (grundorsaken, en fastnad realtidskanal i audit-miljön, är en separat infrastrukturfråga — själva stale/resync-logiken är korrekt och redan testad); (2) Inbox-förhandsvisningar visade ett ensamt ": meddelande" för trådar där avsändarens visningsnamn var en tom sträng (inte null) — klientsidans kontroll täckte bara null-fallet; (3) direktmeddelande-trådar visade alltid den generiska titeln "Direktmeddelande" i stället för motpartens namn eftersom `subject`-kolumnen aldrig sätts för direktmeddelanden — löst server-side genom att falla tillbaka till den andra deltagarens visningsnamn i `list_threads_for_actor`, utan klientändring; (4) **kritiskt fel**: att skicka ETT ENDA meddelande i Inbox misslyckades alltid ("Försök skicka igen" i oändlighet) på grund av en trigger (`broadcast_notification_center_invalidation`) som delas av två tabeller med olika kolumnnamn (`recipient_profile_id` kontra `profile_id`) — en statisk `NEW.profile_id`-referens i grenen som inte skulle köras gjorde ändå att Postgres kraschade med "record \"new\" has no field \"profile_id\"" vid varje infogning i `notification_outbox`. Detta upptäcktes bara genom att faktiskt skicka ett meddelande mot riktig Postgres (precis som de 6 SQL-buggarna i migrationsbacklogen 2026-09-04) — den mockade testsviten fångar inte trigger-exekvering. Fixat genom dynamisk `to_jsonb(new)->>'fält'`-uppslagning istället för statisk kolumnreferens. Alla fyra fel verifierade både direkt mot Postgres (simulerat anrop som testanvändaren via `set local role`+spoofad JWT-claim, med rollback) och live på Mi 9:an. 349/349 tester, ren analys, 0 migrationsdiff efter varje push. | Kalender ombyggd (Månad/Vecka/Dag), kritisk skicka-meddelande-bugg fixad |
| 2026-09-06 | Fysisk genomgång fortsatt och avslutad, nu även som Ledare (befintligt testkonto `coach.emilson@gmail.com`, "Thomas lag"): HOME-01 verifierad med riktig data — "Behöver din uppmärksamhet"/"Närvaro saknas" navigerade korrekt till rätt EventDetails, Deltagare-fliken visade korrekt urval/kallelse-/svarsstatus och separata närvarostatusar ("Okänd · revision 0", inte en bugg). Två ytterligare verkliga fel hittades och fixades under den fortsatta klubbfunktionär-genomgången: (1) ett nytt tomt lags Trupp-flik saknade helt en "Använd kod"-åtgärd (en separat tidig retur i koden hoppade förbi sök-/kodraden), åtgärdat genom att lägga samma åtgärd på tomlägeskortet; (2) "Använd inbjudan eller lagkod"-dialogen krävde att användaren manuellt valde typ (förvalt "Guardianinbjudan") innan koden angavs — fel val gav samma neutrala "ogiltig/utgången"-felmeddelande som en trasig kod, vilket faktiskt inträffade live under genomgången. Bekräftat att alla kodtyper delar exakt samma ogenomskinliga tvåUUID-format, så klientsidan kan inte känna av typ från koden; löst genom att alltid försöka lagkod först och falla tillbaka till guardianinbjudan innan det neutrala felet visas, istället för en manuell väljare. Berört test uppdaterat. 349/349 tester, ren analys, verifierat live på Mi 9:an efter varje fix. Se även föregående rad för Trupp-FAB-fixet och grundläggande klubbfunktionär-genomgången samma dag. | Ledare-genomgång klar, två ytterligare buggar fixade |
| 2026-09-06 | Fysisk genomgång på Xiaomi Mi 9 (audit-miljö, ny testklubb/lag, klubbfunktionär): skapa klubb/lag, Hem, Laget (Översikt/Trupp/Kalender), huvudkalendern, Inbox (auto-skapad lagchatt, skicka meddelande) och Min assistent (vy + namngivning) gicks igenom och fungerade korrekt end-to-end mot hosted. Ett verkligt fel hittades: Truppflikens två staplade FAB:ar ("Medlemsansökningar", "Hantera") krockade visuellt med Min assistents fasta FAB-position och klippte den övre knappens text. Fixat genom att slå ihop till en FAB och flytta "Medlemsansökningar" till "Hantera"-menyn; berörda widgettester uppdaterade. 349/349 tester, ren analys. Ingen "Ledare"-specifik hemvy testad än (klubbskapare blir Klubbfunktionär, inte Ledare). | Fysisk Trupp-FAB-bugg hittad och fixad |
| 2026-09-05 | Ytterligare kortstatusar synkade mot det bekräftat 162/162-synkade hosted-läget: AUTH-05, AUTH-06, AUTH-07 och TEAM-06 hade "SQL-runtime återstår" trots att deras migrationer (från 2026-08-24/27) redan var applicerade före den här sessionens arbete — rättat till fysisk/juridisk grind som enda kvarvarande punkt. TEAM-07/08 fick samma korrigering. Även TEAM-02/03/04:s rader i sammanfattningslistan (avsnitt 14), som felaktigt fortfarande nämnde "SQL-runtime återstår" trots att deras egna kortsektioner redan angav hosted SQL-runtime som verifierad, synkades. Ren dokumentationsrättelse av en förbefintlig inkonsekvens; ingen ny databasändring gjordes. | Kortstatusar helt synkade med hosted-läget |
| 2026-09-05 | De två `auth_rls_initplan`-performance-varningarna på `realtime.messages` (MSG-01/MSG-08) stängda med en ny migration som wrappar `auth.uid()` som `(select auth.uid())` i båda broadcast-policyerna, samma mönster som redan användes för `realtime.topic()`. Ingen ändring av åtkomstlogik. `supabase db advisors --type performance` ger nu "No issues found". 162/162 migrationer synkade. | Performance advisor helt ren |
| 2026-09-04 | AUTH-01 hosted-grind delvis stängd: direkta GoTrue REST-anrop mot `hgcshgunvooyudvrcpig` bekräftade oförändrad svagt-lösenord-avvisning (422/weak_password), identiskt neutralt recovery-svar (200/{}) för två okända adresser, aktiv domänvalidering mot reserverade testdomäner, en aktiv inbyggd mejl-rate-limit (429/over_email_send_rate_limit) och inga hemligheter i API-svaren. E-postleverans, dubblettbeteende för en verkligt existerande adress och serverloggar kräver fortfarande en läsbar inkorg eller fysisk enhet. Ingen Auth-konfiguration ändrades. | AUTH-01 hosted REST-nivå delvis verifierad |
| 2026-09-04 | Hosted migrationsbacklog stängd mot `hgcshgunvooyudvrcpig`: fem drivande versionsstämplar reparerades (bokföring endast) och 47 genuint väntande migrationer (`cal02`–`auth04_fix_membership_request_role_ambiguity`) pushades. Pushen hittade och migrationsfilerna rättades för två obalanserade parenteser (`cal02`, `cal03`), en `||`/`->>`-precedensbugg som fick Postgres att felaktigt tolka en textliteral som jsonb (`msg08`), samt idempotens mot redan hosted-applicerat tillstånd i `cal04/cal06/cal07/cal08` och fem funktioner (`cal07/cal08/msg02/msg06/msg08`), allt verifierat read-only mot `information_schema`/`pg_proc` innan ändring. `supabase migration list` visar nu 0 diff (161/161 synkade). Security Advisor: bara den redan kända leaked-password-varningen. Performance Advisor: två nya `auth_rls_initplan`-varningar på `realtime.messages` (MSG-01/08), kvarstår som separat uppföljning. SQL-runtime-delen av grinden är därmed stängd för CAL-02/03/04/06/07/08, PUB-02–06, MSG-01–08, HOME-01–05 och AC-01/03–08; fysisk/hosted enhetsgrind kvarstår separat och korten är inte individuellt omflaggade än. Se `docs/evidence/hosted_migration_backlog_2026-09-04.md`. | SQL-runtime stängd för ~25 kort; fysisk grind kvarstår |
| 2026-09-04 | Veckans ocommitterade arbete säkrades i git och REL-01 kördes fullständigt för första gången mot den sammanslagna koden (direkt Dart-anrop förbi den hängande Flutter-wrappern). 27 testfel spårades till sex distinkta orsaker (ny kontextetikett, ikonknapp i stället för textknapp, omdöpta SQL-variabler, en verklig saknad engelsk översättning, en knapp utanför testytan och testuppsättning utan locale-delegates) och rättades. Dart-format, statisk analys och hela Flutter-sviten (349/349) passerar rent; Flutter web/APK verifierades tidigare samma session. Publiksajtens npm-steg kördes därefter om mot veckans PUB-04-mediaworker/proxyändringar: 26/26 tester, ren typecheck och godkänd Next-produktionsbuild. REL-01 är grön i samtliga nio steg. Ingen liveändring gjordes. | REL-01 helt grön mot sammanslagen kod |
| 2026-09-01 | TEAM-02 kompletterat lokalt med capabilitystyrd redigering av lagtyp, åldersklass, kort presentation och HTTPS-lagbild. Separat läs-RPC hämtar aktuell revision; update har stale-skydd, idempotens, advisory lock och audit. Säker filuppladdning förblir explicit separat. TEAM-01/02 passerar 7/7 och riktad Dart-analys är ren. | TEAM-02 profilredigering lokalt implementerad; migration/live och fysisk grind återstår |
| 2026-09-01 | REL-02-fixturer städades i godkänd Supabase-testdatabas. Det tomma extralaget togs bort; tillfälliga player-/guardianrelationer avslutades historikbevarande eftersom kallelser, truppsnapshot och meddelanden nu refererar dem. Ordinarie ledar-/funktionärskontexter och testlag är intakta. | REL-02 cleanup godkänd |
| 2026-09-01 | REL-02 slutstängd efter 12/12 roll-/enhetsfall, 7/7 avbrottsfall, 5/5 tillgänglighetsområden och slutlig automatiserad grind 44/44. Verkliga fel-scope deep links och serveråterkallad testsession passerade fail-closed. REL-03:s enda öppna beroende stängdes. | REL-02 och REL-03 godkända |
| 2026-08-28 | AC-08 implementerat lokalt: varje specialistområde har maskinläsbart ansvar, förbjudna beslut och en gemensam mutationsregel där navigation är tillåten men domänmutation kräver preview, explicit bekräftelse, serverauktorisation, idempotens och audit. Rehabstöd har hård gräns mot diagnos, ordination, medicinsk riskrangordning och return-to-play-beslut. Appen beskriver Min assistent som digital funktion, och både områden samt generativ AI har separata fail-closed-grindar. AC-01–AC-08-regression 34/34, separat AC-08 6/6 och analys passerar. Ingen liveändring gjordes. | AC-08 policy/grind lokalt implementerad; obligatoriska runtime- och fysiska grindar återstår |
| 2026-08-28 | AC-07 implementerat lokalt: assistentkön binds till exakt assignment/context och filtreras på både målroll och capabilities. Aktiv klubb, lag, roll och verifierad guardian acting-as visas explicit. Mobil-FAB och integrerad bred panel delar samma kontext. Gemensam aktuell/historik-växling, områdesfilter och privata revisionerade leveranspreferenser har lagts till utan nya specialistinkorgar eller aktivering. Postkort visar område, källa, beräkningstid, freshness/stale, förklaring, kontext och säker navigation. AC-01–AC-07-regression 28/28, separat AC-07 6/6 och analys passerar. Ingen liveändring gjordes. | AC-07 lokalt implementerad; runtime och fysisk flerrolls-/enhetsgrind återstår |
| 2026-08-28 | AC-06 implementerat lokalt: alla assistentområden delar en canonical cross-area-kö, domänhändelser dedupliceras med deterministisk vinnare och global prioritet, och en gemensam budget stöder direkt, digest, endast i Min assistent och av. Överskjutande direkta poster degraderas till en gemensam digest. Alla effektiva leveranser förblir fail-closed och vanliga TeamZone-systemmeddelanden berörs inte. AC-01–AC-06-regression 21/21, separat AC-06 6/6 och analys passerar. Ingen liveändring gjordes. | AC-06 lokalt implementerad; runtime och faktisk leverans återstår |
| 2026-08-28 | AC-05 implementerat lokalt: sex versionshanterade specialistområden har stabila nycklar, etiketter, ikoner, separata design-tokens och explicita policyfält för källor, capabilities, roller, presentationsfält och actions. AC-01:s fem signaler binds till Lagplanering. Alla områden är fail-closed; badgepresentationen bär alltid text + ikon + färg och passerar automatisk kontrastkontroll i ljust/mörkt tema. AC-01–AC-05-regression 15/15 samt separat AC-05 5/5 passerar och analysen är grön. Ingen liveändring gjordes. | AC-05 lokalt implementerad; runtime och fysisk visuell grind återstår |
| 2026-08-28 | AC-04 implementerat lokalt: ny användarcopy använder **Min assistent**, användaren kan spara eller återställa ett privat kontosynkat personligt namn och får en tydlig varning vid namn som kan förväxlas med TeamZone, support eller vårdprofession. Preferensen är revisionerad, idempotent och isolerad från authorization/capabilities. Riktad AC-regression 8/8 och analys passerar. Ingen liveändring gjordes. | AC-04 lokalt implementerad; runtime, fysisk kontosynk och standardnamn återstår |
| 2026-08-28 | Produktbeslut dokumenterat: paraplyet heter **Min assistent**, får ett senare clearat sportigt standardnamn och kan namnges privat av varje användare. En gemensam kärna/kö kompletteras med tydliga specialistområden märkta med text, ikon och färg; prioritet visas separat. AC-04–AC-08 och en stegvis implementeringsguide skapades. Ingen runtime- eller liveändring gjordes. | Min assistent målmodell godkänd |
| 2026-08-28 | HOME-05 stabiliserat lokalt: Notification Center fail-stänger nu även i klienten pensionerade Watchpoint-payloads och förtida assistant-, workload-, high-load- och medical-poster från gammal cache/API samt tar bort dem ur badge-räknaren. AC-02/03:s statiska hållningsyta förblir tillåten utan AI- eller känslig signalaktivering. HOME/MSG/AC-regression 22/22 passerar och analysen är grön. Ingen liveändring gjordes. | HOME-05 stabiliserad lokalt |
| 2026-08-28 | HOME-04 stabiliserat lokalt: Hem och Notification Center använder nu en gemensam klientprioritetsfunktion; notifieringssvar omprioriteras och dedupliceras defensivt på kanonisk nyckel med senaste post som deterministisk vinnare. HOME/MSG-regression 25/25 passerar och analysen är grön. Ingen liveändring gjordes. | HOME-04 stabiliserad lokalt |
| 2026-08-28 | HOME-03 stabiliserat lokalt: guardian-cache isoleras per lag och valt barn, märks som inaktuell och spärrar både barnbyte och kallelsesvar tills relationen har verifierats igen. HOME-01–HOME-03-regression 15/15 passerar och analysen är grön. Ingen liveändring gjordes. | HOME-03 stabiliserad lokalt |
| 2026-08-28 | HOME-02 stabiliserat lokalt: kontextcache märks explicit som inaktuell med senaste servergenereringstid och gamla kallelser blir skrivskyddade tills färsk serverdata finns. HOME-02 plus guardian-regression 9/9 passerar och analysen är grön. Ingen liveändring gjordes. | HOME-02 stabiliserad lokalt |
| 2026-08-28 | HOME-01 stabiliserat lokalt: kontextbunden cache märks nu explicit som inaktuell med offlineindikering och senaste servergenereringstid, så gamla ledaråtgärder inte visas tyst som färska. HOME-01 5/5 och HOME-02/03-regression 8/8 passerar; analysen är grön. Ingen liveändring gjordes. | HOME-01 stabiliserad lokalt |
| 2026-08-28 | REL-03 read-only scopegrind passerar: gamla projektet är git-rent, produktion är ej provisionerad, förbjudna kataloger/deploykommandon saknas, runtime pekar endast på aktuella projekt och paketidentiteten är intakt. Evidence finns för implementerade kort; första git-revision och gröna REL-01/02 återstår. | REL-03 partiell |
| 2026-08-28 | REL-02 fick maskinläsbar 4×3 roll-/enhetsmatris, sju avbrottsfall, fem tillgänglighetsfall och en stegvis klarmarkeringsguide. Äldre FND/AUTH-bevis anges endast som regressionsunderlag; aktuell gemensam fysisk/webbkörning återstår och REL-01 är fortfarande ett öppet beroende. | REL-02 partiell |
| 2026-08-28 | REL-01 uppföljning: 16 klammer-lints rättades manuellt. Publiksajtens 22/22 tester och kompletta Next-build passerade utanför sandboxens child-processbegränsning. Flutter analyze hänger fortfarande efter start även utanför sandboxen, så Flutter-grindarna förblir öppna. | REL-01 partiell |
| 2026-08-27 | REL-01 automatiserad kvalitetsgrind skapad med nio timeout-skyddade steg, separata loggar och JSON-rapport. Publiksajtens typecheck passerar; Flutter/Dart låser sig och Node child-processer blockeras av `spawn EPERM`. Separat analys har inga produktfel men 16 klammer-lints återstår. Ingen live-/produktionsändring gjordes. | REL-01 partiell |
| 2026-08-27 | HOME-05 lokalt genomfört: Watchpoint-runtimeidentitet och separat previewyta pensionerades, gamla/förtida notifieringar fail-stängs och AC-preview-API/klientkod togs bort. Privat AC-01-gate blockerar AI/workload/medical medan HOME-01–04:s deterministiska uppgifter fortsätter. Ingen livepush gjordes. | HOME-05 partiell |
| 2026-08-27 | HOME-04 lokalt genomfört: gemensamma prioritetsnivåer och kanoniska domännycklar för rollhem/Notification Center, server- och klientdeduplicering samt read/dismiss över hela domänhändelsen. Mobil och större skärmar delar data/rättigheter men använder olika komposition. Ingen livepush gjordes. | HOME-04 partiell |
| 2026-08-27 | HOME-03 lokalt genomfört: guardian-isolerad hemsida med serververifierat barnval, relationstillåtna kallelser/event/meddelanderäknare och genomgående synlig/persisterad acting-as i revisions-/decline-reason-säkra svar. Ingen livepush gjordes. | HOME-03 partiell |
| 2026-08-27 | HOME-02 lokalt genomfört: player-isolerad hemsida med laginformation, nästa event, egna kallelser, säker oläst meddelanderäknare och revisions-/decline-reason-säkra snabbsvar. Leader- och guardianadministrativa actions exponeras inte. Ingen livepush gjordes. | HOME-02 partiell |
| 2026-08-27 | HOME-01 lokalt genomfört: serververifierad ledarhemsida med dagens arbete, nästa event, capability-styrda kort för obesvarade kallelser/saknad närvaro och responsiv mobil kontra planeringslayout. Det förtida AC-kortet avlägsnades från Hem; Watchpoints/AC-signaler visas inte. Ingen livepush gjordes. | HOME-01 partiell |
| 2026-08-27 | MSG-08 lokalt genomfört: gemensamt Notification Center med kontosynkad read/dismiss-status, badge, säker serverberäknad preview, tillåtna deep links och privat Realtime-invalidering. Watchpoints och förtida AC-signaler filtreras bort utan att vanliga domännotiser försvinner. Ingen livepush gjordes. | MSG-08 partiell |
| 2026-08-28 | MSG-08 stabiliserat lokalt: swipe-dismiss väntar nu på serverbekräftelse innan notisen tas bort; misslyckad skrivning behåller raden och visar säkert fel. Bottom-sheet-contexten livscykelkontrolleras efter async-gap. Riktade MSG-07/08/HOME-04-tester 14/14 och analys passerar. Ingen liveändring gjordes. | MSG-08 stabiliserad lokalt |
| 2026-08-27 | MSG-07 lokalt genomfört: personlig döljning och frivilligt utträde påverkar inte andras historik; behörig stängning bevarar läsbar historik. Global radering kräver initiativtagare plus separat behörig godkännare och service-only applicering, med TeamZone-review för cross-club/integritet. Neutral tombstone bevarar ordning, replies, read state och notifieringsreferenser. Ingen livepush gjordes. | MSG-07 partiell |
| 2026-08-28 | MSG-07 stabiliserat lokalt: vanlig global trådradering kräver exakt initiativtagare och separat godkännare; serviceappliceringen attribueras till godkännaren och är replay-safe. Endast cross-club/integritetsärenden kräver en tredje separat TeamZone-granskare. Riktade MSG-06–08-tester 14/14, SQL-strukturgrind och analys passerar. Ingen liveändring gjordes. | MSG-07 stabiliserad lokalt |
| 2026-08-23 | Fastställda paritetspunkter utbrutna till beroendesatta, verifieringsbara leveranskort och senare-register. | Arbetskort skapade |
| 2026-08-23 | FND-01 genomförd: appmonoliten uppdelad i shell/router och ytspecifika partfiler; analys ren och 72/72 tester passerar. | FND-01 verifierad |
| 2026-08-23 | FND-02 genomförd: gemensamt async/stale/offline-kontrakt, context-race-skydd och kalender-Realtime-resync; analys ren och 80/80 tester passerar. | FND-02 verifierad |
| 2026-08-23 | FND-03 genomförd: gemensamma formulär- och listkontroller, osparade-ändringar-skydd och centralt routekontrakt integrerade; analys ren och 89/89 tester passerar. | FND-03 implementerad |
| 2026-08-23 | Samlad verifiering av FND-01–FND-03: widgetmatris för phone/tablet/desktop, alla async-huvudstatusar, cold link/rebuild och system-back. Två upptäckta router/back-fel rättades; analys ren och 95/95 tester passerar. | FND-01–FND-03 verifierade |
| 2026-08-23 | Fysisk Android-smoke på Samsung SM-S931B: aktuell debug-APK installerad, cold start och fail-closed-layout godkända, inga Flutter/AndroidRuntime-fel och fysisk system-back lämnar roten korrekt. | Androidgrind godkänd |
| 2026-08-23 | FND-04 fastställt: roll-/situationskontrakt för Hem, Laget, Kalender och Inbox med positiva och negativa regler för leader, player, guardian och klubbfunktionär samt mobil/tablet/desktop; analys ren och 104/104 tester passerar. | FND-04 verifierad |
| 2026-08-23 | FND-05 genomfört: 48 px/semantik/fokus/reduced-motion/AA/lokalisering låsta; 200 % text verifierad på phone/tablet/desktop och fysisk Android. Två textskaleoverflow samt tre localeavvikelser rättades; analys ren och 113/113 tester passerar. | FND-05 verifierad |
| 2026-08-23 | AUTH-01 lokalt genomfört: separata login/signup-flöden, lösenord och e-postkod/länk, verifieringskrav, neutral recovery, recovery-event samt OTP cooldown/expiry. Analys ren och 121/121 tester passerar; hosted e-post/Auth och fysisk vy bakom låst telefon återstår. | AUTH-01 partiell |
| 2026-08-23 | AUTH-02 lokalt genomfört: fail-closed sessioner, lokal utloggning, återställning av endast fortsatt behörig kontext, context-race-reset samt webbval för delad enhet. Sandbox-/wrapperlåsning löst, testmiljöregression rättad, analys ren och 126/126 tester passerar; fysisk/hosted sessiongrind återstår. | AUTH-02 partiell |
| 2026-08-23 | AUTH-03 lokalt genomfört: invite-deep links före/efter auth, begränsad preview via servergräns, recipient-hash, atomisk v2-claim, replay/idempotency och neutral manuell konfliktgranskning. Analys ren, fullsvit 130/130 samt riktad slutkontroll och X-QA 4/4 + 4/4; lokal/hosted SQL- och Edge-grind återstår. | AUTH-03 partiell |
| 2026-08-24 | AUTH-04 lokalt genomfört: minimerad klubb-/lagsökning, officiell status, rollvald idempotent ansökan, sökandens väntelista/återkallelse och capabilitystyrt beslut med audit. Analys ren; AUTH-04 + FND-05 12/12 passerar. SQL-runtime samt fysisk och hosted grind återstår. | AUTH-04 partiell |
| 2026-08-24 | AUTH-04 reviewer färdig lokalt: Laget visar capabilitystyrd kö, minimerad sökandeprofil och bekräftat godkänn/avslag med pending-/retry-skydd. Analys ren, AUTH-04 3/3 och kombinerad AUTH-04/FND-05 12/12 passerar. | AUTH-04 klientklar |
| 2026-08-24 | AUTH-05 lokalt genomfört: verifierad användare kan atomiskt skapa inofficiell klubb, första lag, administrativ personrelation, assignment och capabilities med idempotent kontextresultat. Behörig administratör kan skapa ytterligare lag. Analys ren och kombinerad AUTH-04/AUTH-05/FND-05-svit 14/14 passerar. | AUTH-05 partiell |
| 2026-08-24 | AUTH-06 lokalt genomfört: namn normaliseras inklusive vanliga homoglyphs, skyddade namn blockeras före och vid skapande, behörig klubbansvarig kan begära verifiering och följa en text- och ikonmärkt status. Godkännande, avslag och återkallelse har endast service-role-gräns och auditspår. Analys ren och riktad AUTH/FND-svit 16/16 passerar. | AUTH-06 partiell |
| 2026-08-24 | AUTH-07 lokalt genomfört: blockerande versionsgrind före klubb-/lagdata, separata obligatoriska attesteringar för villkor och integritet, frivillig ej förvald marknadsföring med senare opt-out samt separat auditspår. Guardian- och publiceringssamtycken berörs inte. Analys ren och riktad AUTH/FND-svit 18/18 passerar. | AUTH-07 partiell |
| 2026-08-24 | TEAM-01 lokalt genomfört: Laget har exakt Översikt, Trupp och Kalender; kalenderfliken delar tidigare/kommande, filtrerar eventtyp och leder event till huvudkalenderns EventDetails. Flik och event-ID bevaras i canonical route query. Analys ren och riktad TEAM/FND-svit 20/20 passerar. | TEAM-01 partiell |
| 2026-08-24 | TEAM-02 lokalt genomfört: rollstyrd översikt visar lagbild/fallback, identitet, information, ledare och genvägar. Administrativa invite-/ansökningsräknare minimeras server-side och renderas endast bakom capability; negativt spelartest passerar. Analys ren och riktad TEAM/AUTH/FND-svit 18/18 passerar. | TEAM-02 partiell |
| 2026-08-24 | TEAM-03 lokalt genomfört: truppen har sök, aktiva/övriga-filter och pagination; rollminimerad medlemsdetalj visas i mobil bottom sheet eller desktop/tablet-panel. Guest/okänd roll stängs ute begripligt och administrativa fält kräver serververifierad capability. Analys ren och samlad TEAM-01–03-regressionssvit 9/9 passerar. | TEAM-03 partiell |
| 2026-08-26 | TEAM-04 lokalt genomfört: behörig ledare kan skapa och redigera klubbägda rosterprofiler med validering, pending-/double-submit-skydd och varning för osparade ändringar. Serverkommandon är atomiska, idempotenta, auditerade, tenantbundna, dubblettskyddade och revisionslåsta; global person/profil uppdateras aldrig. Analys ren, TEAM-04 5/5 och samlad roster/auth-regression 17/17 passerar före det tillagda redigeringstestet. | TEAM-04 partiell |
| 2026-08-27 | TEAM-05 lokalt genomfört: riktad mottagarbunden invite, guardianinvite och generell lagkod kan skapas, statusvisas och återkallas. Delad lagkod skapar alltid väntande medlemsansökan; verifierad guardianrelation kan avslutas av guardian eller safeguardingansvarig med explicit acting-as-audit. Analys ren, TEAM-05 4/4 och samlad TEAM-03–05/AUTH-03/S02-regression 21/21 passerar. | TEAM-05 partiell |
| 2026-08-27 | TEAM-06 lokalt genomfört: utvecklingsspel, dispens, lån och gästspel kan ges för säsong, valt slutdatum eller tillsvidare med obligatorisk granskningsdag. Överlapp serialiseras, status kan avslutas revisionssäkert och eventmotorn validerar perioden vid eventets starttid utan att ändra ordinarie lag eller historik. Analys ren, TEAM-05/06 7/7 och samlad TEAM-03–06/S04-regression 19/19 passerar. | TEAM-06 partiell |
| 2026-08-27 | TEAM-07 lokalt genomfört: behörig ledare kan flytta en spelare inom klubben från valt datum. Den gamla assignment-raden avslutas och en ny skapas atomiskt; advisory lock, revision, periodkontroll, idempotens och audit skyddar samtidighet och historik. Cross-club ligger kvar i separat flerpartsgodkännande. Analys ren; Flutter-testwrappen gav ingen output och testkörning återstår. | TEAM-07 partiell |
| 2026-08-27 | TEAM-08 lokalt genomfört: synlig arkivering till Tidigare, dual-control för klubbens PII-anonymisering och service-only TeamZone-granskning för global radering. Aktiva länkar avslutas, neutral tombstone bevarar historik och profilens Auth-FK frikopplas så att Auth Admin kan radera kontot utan att bryta auditreferenser. Analys ren; Flutter-testwrappen gav ingen output och runtime-/fysisk grind återstår. | TEAM-08 partiell |
| 2026-08-27 | CAL-01 lokalt genomfört: agenda, månad, vecka och dag delar samma paginerade eventprojektion, överlapps- och datumlogik samt lag-/eventtypfilter. Månad använder 6×7-rutnät, vecka prioriterar mobil lista eller desktopöversikt och alla event öppnar befintlig EventDetails. Analys ren; Flutter-testwrappen gav ingen output och fysisk responsiv grind återstår. | CAL-01 partiell |
| 2026-08-27 | CAL-02 lokalt genomfört: ett gemensamt formulär skapar och redigerar engångsevent/serier med titel, beskrivning, typ, utkast/publicerat, tid/heldag, tidszon, lag, audience och tenantbundna platsförslag. V2-revision flyttar serietider relativt ankaret för one/forward/all, bevarar framtida intervall, använder revision/advisory lock och rör inte kommande shared-team-audience. Analys ren; testwrappen gav ingen output och SQL-/fysisk grind återstår. | CAL-02 partiell |
| 2026-08-27 | CAL-03 lokalt genomfört: primärlaget behåller ägarskap och ensam rätt att administrera delning. Andra aktiva lag i samma klubb får explicit view, deltagarhantering eller samredigering; audience ger endast synlighet. EventDetails visar ägare/deltagande lag och har en responsiv delningsdialog. Granulära server-actions används även av trupp/närvaro. Analys ren; testwrappen fastnade utan output och SQL-/fysisk flerrollsgrind återstår. | CAL-03 partiell |
| 2026-08-27 | CAL-04 lokalt genomfört: endast opublicerade fristående draft-event utan följddata kan tas bort av primärlaget. Övriga event ställs in och kan arkiveras med orsak medan historiken bevaras. Cancel återkallar aktiva kallelser och svarstoken samt köar mottagarnotiser atomiskt. Permanent purge är service-role-only, minst 365 dagar och stoppas av skyddad historik. Analys ren; SQL-, testwrapper- och fysisk grind återstår. | CAL-04 partiell |
| 2026-08-27 | CAL-05 lokalt genomfört: EventDetails använder Info, Deltagare, Förberedelser och Uppföljning. Deltagare sammanfattar urval, kallelser/svar och närvaro; eventtyp och server-actions styr innehåll och åtgärder. Mobil använder rullbara fullständiga fliknamn och 90 % bottom sheet, tablet/desktop en 760×680-dialog. Analys ren; testwrapper och fysisk responsiv/flerrollsgrind återstår. | CAL-05 partiell |
| 2026-08-27 | CAL-06 lokalt genomfört: manuell, alla, eventtidsbaserad behörighetsgrupp och deterministisk balanced_v1-generator skriver samma revisionerade deltagardraft. Lock och send återvaliderar eligibility under aggregate advisory lock; dedupe sker före state/stale-kontroll för säkra retries. Sena draft/utskick är explicita och skapar endast nya callups utan att skriva över tidigare. Analys ren; SQL-, testwrapper- och fysisk grind återstår. | CAL-06 partiell |
| 2026-08-27 | CAL-07 lokalt genomfört: player och guardian använder samma v2-svarstransition; aktiv guardianrelation verifieras och acting-as auditeras. Decline reason har fem strukturerade koder och fritext endast för other. Reminder har sex timmars cooldown, idempotens och separat leveransstatus. Push-actiontoken binds till callup/mottagare/actions, gäller högst 15 minuter och konsumeras atomiskt. Analys ren; SQL-, testwrapper- och fysisk flerrollsgrind återstår. | CAL-07 partiell |
| 2026-08-27 | CAL-08 lokalt genomfört: unknown, present, late, partial och absent hålls separata. Mobilredigeraren samlar ändrade rader i en atomisk batch med expected revision per person; late/partial kräver minuter. Efter eventslut +24 h krävs event.attendance.correct_late och orsak, och varje ändring får immutable revisionsspår. Dedupe sker före state/stale-kontroll. Analys ren; SQL-, testwrapper- och fysisk mobilgrind återstår. | CAL-08 partiell |
| 2026-08-27 | CAL-09 lokalt genomfört: EventDetails renderar förberedelseåtgärder från en explicit allowlist med endast verkliga flöden (Match Space, deltagare och eventredigering). Uppskjuten import, anteckningar, bilagor och träningsworkspace exponeras inte. En stabil URL-kodad eventroute bevarar eventidentitet och ger senare planeringsfunktioner en utbyggbar navigationsgräns. Ingen databasändring gjordes. Flutter analyze stannade utan diagnos och avbröts kontrollerat; testwrapper och fysisk responsiv grind återstår. | CAL-09 partiell |
| 2026-08-27 | PUB-01 lokalt genomfört: klubbens route har professionell profilhero, verifieringsmarkör och navigation för om, nyheter, lag, händelser, partners och kontakt. Lagroute är officiell underkanal med klubbåterväg, nyheter och tidigare/kommande event. Publicerat namn styr metadata, canonical och Open Graph; runtime-off är noindex och okänd slug ger 404. TypeScript, 9/9 tester och Next-produktionsbuild passerar. Ingen driftsättning eller liveändring gjordes. | PUB-01 partiell |
| 2026-08-27 | PUB-02 lokalt genomfört: klubb/lag har private, listed och published med private som säker default. Endast officiell klubb och explicit publication.manage-grant kan publicera. Revisionerad fältallowlist binds till en auditerad policybekräftelse med högst 366 dagars giltighet; expiry stänger ytan och köar projection removal. Minderårig-/persondata saknar publik projektion som default. Minimal officiell katalog återanvänder service-only API, prefixlimit och rate limit. Riktat kontraktstest 3/3 passerar. Ingen livepush gjordes. | PUB-02 partiell |
| 2026-08-27 | PUB-03 lokalt genomfört: capabilitystyrda och revisionerade serverkommandon hanterar utkast, preview, schemaläggning, publicering och avpublicering till klubbkanal och valda lagkanaler. Publika artiklar använder strukturerade allowlistade block utan rå HTML. Avpublicering tar bort projektionen atomiskt och köar cacheinvalidation. Privata meddelandefiler återanvänds inte; publik bildvariant tillkommer i PUB-04. TypeScript, 12/12 tester och Next-produktionsbuild passerar. Ingen livepush gjordes. | PUB-03 partiell |
| 2026-08-27 | PUB-04 lokalt genomfört: revisionerad eventpublicering exponerar endast titel, tid, typ och uttryckligt vald plats. Partners har HTTPS-only länkar och logotyp kräver ren, servicegenererad publik mediavariant. Klubbsidan visar publicerade klubbhändelser och säkra partnerlänkar. Kontaktgränsen korrigerades för PUB-02:s published-läge och behåller same-origin, CAPTCHA, rate limit, maxlängd, neutral respons och retention. TypeScript, 15/15 tester och Next-produktionsbuild passerar. Ingen livepush gjordes. | PUB-04 partiell |
| 2026-08-28 | PUB-04:s autentiserade Flutter-panel tillagd lokalt: lagmandat styr eventlistning och publicering, klubbmandat styr partners, förhandsgranskningen visar exakt den publika eventgränsen och mediauppladdning förblir ärligt avstängd. Analys och 274/274 Flutter-tester passerar. Ingen migration applicerades och ingen livepush gjordes. | PUB-04 UX genomförd lokalt |
| 2026-08-27 | PUB-05 lokalt genomfört: globalt unik hostname-claim, hashad TXT-verifiering, separat kommersiell grind, TLS-/providerlivscykel, en canonical per klubb och datadriven rewrite/308-routing infördes. Canonical metadata följer verifierad egen domän. TeamZone-subdomäner är strukturellt avstängda tills wildcard DNS/TLS och automatisk routing öppnas tillsammans. Ingen DNS, TLS, hosting eller livekonfiguration ändrades. | PUB-05 partiell |
| 2026-08-28 | PUB-05:s autentiserade självbetjäning tillagd lokalt: kostnadsfri standardadress, custom-domain-begäran med engångs-TXT, status för entitlement/DNS/TLS och säkert canonical-val. Premiumsubdomänen förblir låst. Samtidigt rättades kommandogatewayens allowlist för PUB-03–PUB-05. Analys och 277/277 Flutter-tester passerar. Ingen liveändring gjordes. | PUB-05 UX genomförd lokalt |
| 2026-08-27 | PUB-06 lokalt genomfört: publik HTML får högst 60 sekunders CDN-cache med must-revalidate medan API/kontakt är no-store. Service-only invalidationsclaim, strikt bearer-skyddad Next-worker, pathvalidering, retry och timeoutåtertagning kopplar PUB-03/04-köerna till revalidatePath. Dynamisk canonical-medveten sitemap, robots, HSTS/COOP och syntetiskt smoke-script infördes. Live matchrapportering förblir explicit senare. TypeScript, 22/22 tester och Next-produktionsbuild passerar. Ingen hosted smoke eller liveändring gjordes. | PUB-06 partiell |
| 2026-08-28 | PUB-06-regression rättad: opaque publik media undantas från HTML-/tenantproxyn så att egna klubbdomäner inte skriver om bildrouten och immutable bildcache inte ersätts av 60-sekunders HTML-cache. TypeScript, 26/26 publiksajttester och komplett Next-build passerar. Ingen liveändring gjordes. | PUB-06 stabiliserad lokalt |
| 2026-08-27 | MSG-01 lokalt genomfört: Inbox fick sök, fem filter, senaste avsändare/tid, unread/mute och privat debouncad Realtime-resync. Varje aktivt lag får deterministisk lag- och ledarchatt; team-, assignment-, kontolänk- och capabilitytriggers reconcilerar deltagare från aktuella relationer. Ledarchatten återkontrollerar team.roster.view centralt vid läsning/send. Dart-format och statisk kontraktsgrind passerar; Flutter-wrapper/analysserver fastnade utan diagnostik och riktad flutter_test-körning återstår. Ingen livepush gjordes. | MSG-01 partiell |
| 2026-08-28 | MSG-01 stabiliserat lokalt: kontolänk- och capabilityflyttar reconcilerar nu både gammalt och nytt lag, vilket förhindrar kvarhängande deltagare i lag-/ledarchatt. Analys, riktade MSG-/säkerhetstester och hela Flutter-sviten 278/278 passerar. Ingen migration applicerades live. | MSG-01 stabiliserad lokalt |
| 2026-08-27 | MSG-02 lokalt genomfört: samma centrala relationsregel används av mottagarsökning, direkt-/gruppskapande, deltagartillägg och send. Player-to-player är av som standard. Cross-club-ledarkontakt behåller verifiering, dataminimering, 3/24 h- och 10/30 d-gränser samt mottagaracceptans. Klienten kan skapa direkt- och grupptrådar och lägga till servervaliderade gruppdeltagare. Dart-format och statiska kontraktskontroller passerar; Flutter-testwrappen fastnade utan output och avbröts kontrollerat. Ingen livepush gjordes. | MSG-02 partiell |
| 2026-08-28 | MSG-02 stabiliserat lokalt: acceptans av cross-club-förfrågan återvaliderar nu båda parters verifiering, tidsaktuella ledaruppdrag, fortsatt klubbseparation och blockstatus innan en tråd skapas. Riktade MSG-/idempotens-/livscykeltester 21/21 och analys passerar. Ingen migration applicerades live. | MSG-02 stabiliserad lokalt |
| 2026-08-27 | MSG-03 lokalt genomfört: aktiv ledare/klubbfunktionär kan skapa announcement till servervaliderade mottagare, medan endast skapare/moderator kan skriva. Announcements har separat per-deltagare-readmodell; listning och enskild läsmarkering routar efter trådtyp. Markera alla är atomiskt, idempotent och kontextbundet över både messages och announcements. Mottagaren får en tydlig read-only-yta. Dart-format och statisk SQL-kontraktsgrind passerar; runtime-, Flutter- och fysisk grind återstår. Ingen livepush gjordes. | MSG-03 partiell |
| 2026-08-28 | MSG-03 stabiliserat lokalt: announcement-skaparen och samtliga mottagare materialiseras nu från aktiva, tidsaktuella uppdrag i auktoriserad klubb-/lagkontext. Ändrad relation ger atomisk rollback i stället för en tom eller direkt otillgänglig tråd. Riktade MSG-01–04-tester 19/19 och analys passerar. Ingen migration applicerades live. | MSG-03 stabiliserad lokalt |
| 2026-08-27 | MSG-04 lokalt genomfört: historiken fick exklusiv revisionscursor, limit+1, explicit continuation och klientdeduplicering. Trådens privata Realtime-kanal resynkar första sidan deterministiskt vid subscribe/reconnect. Send visas optimistiskt med pending/failure och explicit retry som återanvänder idempotensnyckel och staged files; servern återkontrollerar aktiv participantaccess vid varje försök. Dart-format och statisk kontraktsgrind passerar; runtime-, Flutter- och fysisk tvåenhetsgrind återstår. Ingen livepush gjordes. | MSG-04 partiell |
| 2026-08-28 | MSG-04 stabiliserat lokalt: meddelandehämtningar generationsmärks så sena initial-/Realtime-svar inte kan skriva över nyare serverstatus och äldre pagination ignoreras när en resync har startat. Laddningsläget återställs även när resync avbryter pagination. Riktade MSG-03–05-tester 14/14 och analys passerar. Ingen liveändring gjordes. | MSG-04 stabiliserad lokalt |
| 2026-08-27 | MSG-05 lokalt genomfört: mute och frivillig push är fail-closed och kontosynkade; push kräver explicit opt-in och aktiv mute undertrycker workerclaim. Pin beslutades som kontosynkad, styr Inboxordning/filter och resynkas privat. En trigger reducerar varje message-push till thread/message-ID och generisk preview-nyckel; workern loggar ingen payload. Klienten fick pushinställning samt säkra mute-/pin-pendinglägen. Gatewayallowlisten kompletterades för MSG-02/03/05-kommandon. Dart-format och statisk kontraktsgrind passerar; runtime/provider-/Flutter-/Deno-/fysisk grind återstår. Ingen livepush gjordes. | MSG-05 partiell |
| 2026-08-28 | MSG-05 stabiliserat lokalt: pushinställningen kan inte öppnas/sparas parallellt, mute/pin låser sitt målvärde före nätverksanropet och mutad tråd visar den korrekta återställningsåtgärden. Riktade MSG-04–06-tester 14/14 och analys passerar. Ingen live-/providerändring gjordes. | MSG-05 stabiliserad lokalt |
| 2026-08-27 | MSG-06 lokalt genomfört: aktiv filprojektion exponerar inte object key; fil-ID måste serverauktoriseras före en 120-sekunders signerad URL och Storage-RLS återkontrollerar access. Recall behåller 15-minutersfönster, tombstone, audit/retention, withdrawn-filer och resynkar nu även vid update. Report fick strukturerad orsak, auto-block och säker stängning av klientvyn. Service-only moderation fick reviewer/reason/evidence-hash och immutable actions för dismiss, hide, close och legal hold. Dart-format och statisk kontraktsgrind passerar; runtime-, moderatoroperator-, Flutter- och fysisk grind återstår. Ingen livepush gjordes. | MSG-06 partiell |
| 2026-08-28 | MSG-06 stabiliserat lokalt: bilagesändning är replay-safe efter tappat svar, kräver exakt samma fillista och återlämnar kanoniskt resultat även sedan filerna aktiverats. En fil som ändras mellan kontroll och aktivering rullar tillbaka hela sändningen. Riktade MSG-05–07-tester 14/14, SQL-strukturgrind och analys passerar. Ingen live-/Storageändring gjordes. | MSG-06 stabiliserad lokalt |
