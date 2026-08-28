# TeamZone grundapp – implementerbara arbetskort

**Status:** AKTIVT ARBETSDOKUMENT  
**Upprättat:** 2026-08-23  
**Källa:** fastställd paritetsmatris och fastställd arbetsplan  
**Livegräns:** inga Supabase-liveändringar utan separat uttryckligt godkännande

## 1. Så används dokumentet

Det här är genomförandelagret under:

- `docs/implementation/core_app_workplan.md`
- `docs/implementation/core_app_parity_matrix.md`

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
| 3 | Kalender och EventDetails | CAL-01–CAL-09 | TEAM-03–TEAM-06 |
| 4 | Publik klubbsajt | PUB-01–PUB-06 | TEAM-01, CAL-01, publiceringsgrindar |
| 5 | Inbox och notiser | MSG-01–MSG-08 | AUTH-06, TEAM-03 |
| 6 | Rollspecifikt Hem | HOME-01–HOME-05 | TEAM/CAL/MSG stabila läsmodeller |
| 7 | Assistant Coach-grund | AC-01–AC-03 | HOME-04 och stabila domänsignaler |
| 8 | Senare funktioner | LATER-01–LATER-04 | Separat prioriteringsbeslut |
| 9 | Samlad releasegrind | REL-01–REL-03 | Våg 0–6 klara |

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

**Verifiering:** phone/tablet/desktop widgetmatris samt navigationstest för cold link, refresh och back.

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

**Status:** `[~]` – lokalt implementerad och verifierad; hosted Auth/e-postgrind återstår  
**Paritet:** AUTH-01–AUTH-04  
**Beroenden:** FND-02, FND-03, FND-05

- [x] Separata begripliga ingångar för `Logga in` och `Skapa konto`.
- [x] Både lösenord och e-postkod/magic link erbjuds.
- [x] Kontoskapande kräver verifierad e-post utan dubblettidentitet.
- [x] Glömt lösenord visar neutralt svar och återupptar rätt vy via deep link.
- [x] OTP/resend har cooldown, expiry, pending och återhämtningsbar fel-UX.

**Verifiering:** widgettest, auth-emulator/hosted godkänd testmiljö, secret/log-redaction och deep-linktest. Live kräver separat godkännande.

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

**Status:** `[~]` – lokalt implementerad och klientverifierad; lokal/hosted SQL- och Edge-grind återstår  
**Paritet:** AUTH-06, AUTH-15, TEAM-07, TEAM-08  
**Beroenden:** AUTH-01, AUTH-02

- [x] Invitekod/-länk kan tas emot före eller efter auth och återupptas efter verifiering.
- [x] Preview visar klubb, lag, person/roll och giltighet före acceptans.
- [x] Acceptans är scopead, tidsbegränsad, single-use/idempotent och dubblettsäker.
- [x] Kontot binds till samma förskapade personpost; namnlikhet ensam får aldrig claima.
- [x] Konflikt går till manuell granskning utan dataexponering.

**Verifiering:** replay/race, fel mottagare, fel tenant, utgången invite och dubblettkonflikt.

### AUTH-04 – Sök klubb/lag och medlemsansökan

**Status:** `[~]`  
**Paritet:** AUTH-07, AUTH-10, AUTH-14  
**Beroenden:** AUTH-01, FND-03

- [x] Sökningen returnerar endast tillåten minimal information.
- [x] Officiell status visas med text och ikon.
- [x] Ansökan väljer klubb, lag och avsedd relation/roll.
- [x] Vänteläge visar status, återkallelse och nästa steg.
- [x] Behörig mottagare kan godkänna/avslå med audit i serverkontraktet och
  capabilityanpassad reviewer-UI; fysisk neutral sökande-UX återstår som grind.

**Verifiering:** enumerationsskydd, outsider/cross-club, dubblettansökan och avstängd relation.

### AUTH-05 – Skapa klubb och första lag

**Status:** `[~]` – lokalt implementerad och klientverifierad; SQL-runtime/fysisk grind återstår  
**Paritet:** AUTH-08, AUTH-09  
**Beroenden:** AUTH-01, AUTH-02

- [x] Verifierad ny användare kan skapa inofficiell klubb och första lag atomiskt.
- [x] Skaparen får beslutad administrativ relation och en användbar aktiv kontext.
- [x] Behörig klubbadministratör kan senare skapa ytterligare lag.
- [x] Delvis misslyckande lämnar inte en föräldralös klubb, relation eller lagpost.

**Verifiering:** idempotent retry, duplicate submit, rollback och omedelbart kontextbyte.

### AUTH-06 – Skyddade namn och officiell klubb

**Status:** `[~]` – lokalt implementerad och klientverifierad; SQL-runtime/fysisk grind återstår  
**Paritet:** AUTH-10, AUTH-11  
**Beroenden:** AUTH-04, AUTH-05

- [x] Normaliserat namn, kända varianter/förkortningar och förväxlingsrisk kontrolleras före skapande.
- [x] Utomstående kan inte skapa en förväxlingsbar officiell kopia.
- [x] Användaren kan begära verifiering och följa status.
- [x] Endast TeamZone kan godkänna, avslå eller återkalla officiell status.
- [x] Alla beslut och underlagshändelser auditloggas och klienten kan inte själv sätta status.

**Verifiering:** homoglyph/normalisering, reserverat namn, nekad klientmutation och tillgänglig statusvisning.

### AUTH-07 – Villkor, integritet och frivilliga samtycken

**Status:** `[~]` – lokalt implementerad och klientverifierad; juridiskt innehåll, SQL-runtime och fysisk/hosted grind återstår  
**Paritet:** beslut i arbetsplan steg 3A  
**Beroenden:** AUTH-01

- [x] Versionerad acceptans av användarvillkor och läst integritetspolicy.
- [x] Marknadsföring är separat, frivillig och aldrig förvald.
- [x] Väsentligt nya villkor kräver nytt uttryckligt godkännande.
- [x] Minderårig-/guardianbeslut blandas inte ihop med generella villkor.

**Verifiering:** versionsbyte, nekad obligatorisk acceptans, frivillig opt-out och auditspår.

## 6. Våg 2 – Lagets fas 1

### TEAM-01 – Lagets tre grundflikar

**Status:** `[~]` – lokalt implementerad och klientverifierad; fysisk deep-link/navigation-grind återstår  
**Paritet:** TEAM-01, TEAM-17, TEAM-18  
**Beroenden:** FND-03, FND-04

- [x] Exakt `Översikt`, `Trupp`, `Kalender`.
- [x] Kalenderfliken är lista med tidigare/kommande och eventtypfilter.
- [x] Listpost öppnar samma EventDetails som huvudkalendern.
- [x] Deep link, refresh och mobilnavigation bevarar vald flik.

### TEAM-02 – Rollstyrd lagöversikt

**Status:** `[~]` – lokalt implementerad och klientverifierad; SQL-runtime och fysisk/hosted grind återstår  
**Paritet:** TEAM-02, HOME-06  
**Beroenden:** TEAM-01, AUTH-03, AUTH-04

- [x] Lagbild, grundinformation, ledare och relevanta genvägar visas.
- [x] Behöriga ledare ser aktiva invites, väntande ansökningar och åtgärdsbehov.
- [x] Player/guardian ser inte administrativa ärenden utan capability.
- [x] Tom lagbild/information har professionellt fallbackläge.

### TEAM-03 – Trupplista och medlemsdetalj

**Status:** `[~]`  
**Paritet:** TEAM-03, TEAM-06, TEAM-09  
**Beroenden:** TEAM-01, FND-02–FND-05

- [x] Sök/filter/status och pagination fungerar i stora trupper.
- [x] Detalj visar endast rolltillåtna lag- och spelaruppgifter; kontaktfält saknas i nuvarande schema och exponeras därför inte.
- [x] Guest/okänd roll får begriplig fail-closed upplevelse.
- [x] Telefon prioriterar snabb lookup; tablet/desktop ger administrativ överblick.

**Återstår:** lokal/hosted SQL-runtime samt fysisk phone/tablet/desktop-grind.

### TEAM-04 – Skapa och redigera rosterperson

**Status:** `[~]`  
**Paritet:** TEAM-04, TEAM-05  
**Beroenden:** TEAM-03

- [x] Person, klubbpost och lagrepresentation skapas atomiskt och dubblettsäkert.
- [x] Klubben redigerar endast sin tenantägda rosterinformation.
- [x] Global identitet skrivs inte över av lokal lagredigering.
- [x] Formulär har pending, safe validation och osparade ändringar.

**Återstår:** lokal/hosted SQL-runtime samt fysisk phone/tablet/desktop-grind.

### TEAM-05 – Guardian och riktad inbjudan

**Status:** `[~]`  
**Paritet:** TEAM-07, TEAM-08, AUTH-15  
**Beroenden:** AUTH-03, TEAM-04

- [x] Riktad invite och generell lagkod har tydlig status, expiry och revoke.
- [x] Guardianrelation verifieras och kan avslutas säkert.
- [x] Acting-as och barnets integritet bevaras i alla följdflöden.

**Återstår:** lokal/hosted SQL-runtime, Edge-/deep-link-grind samt fysisk phone/tablet/desktop-grind.

### TEAM-06 – Behörighet att representera andra lag

**Status:** `[~]`  
**Paritet:** TEAM-10  
**Beroenden:** TEAM-03, säsongskontrakt

- [x] Typ: utvecklingsspel, dispens, lån eller gästspel.
- [x] Giltighet: säsong, valt slutdatum eller tills vidare.
- [x] Säsongsbundna behörigheter upphör vid säsongsslut; tillsvidare granskas regelbundet.
- [x] Ordinarie lag och historiska fakta ändras inte.
- [x] Servern validerar representation vid eventtidpunkt.

**Återstår:** lokal/hosted SQL-runtime samt fysisk phone/tablet/desktop-grind.

### TEAM-07 – Flytta spelare med bevarad historik

**Status:** `[~]`  
**Paritet:** TEAM-11  
**Beroenden:** TEAM-03, TEAM-06

- [x] Flytt inom klubb avslutar tidigare assignment och skapar ny från valt datum.
- [x] Gamla event, närvaro och statistik ligger kvar på historisk representation.
- [x] Överlapp, bakdatering och samtidiga flyttar valideras atomiskt.
- [x] Cross-club använder separat source/target-/guardianflöde.

**Återstår:** lokal/hosted SQL-runtime, fysisk phone/tablet/desktop-grind och omkörning av Flutter-testsviten när den lokala testwrappen svarar.

### TEAM-08 – Arkivering, borttagning och anonymisering

**Status:** `[~]`  
**Paritet:** TEAM-12  
**Beroenden:** TEAM-03, retention-/integritetspolicy

- [x] Ledare kan arkivera eller avsluta aktiv lagrepresentation.
- [x] Arkiverade/tidigare spelare kan hittas i separat filtrerad vy.
- [x] Klubbens PII-radering kräver separat laginitiator och klubbapprover.
- [x] Global radering kräver TeamZone-granskning och initiator får inte själv godkänna.
- [x] Anonymiserad neutral representation bevarar nödvändiga verksamhetsfakta och obrutna referenser.
- [x] Raderad identitet kan inte oavsiktligt återkopplas eller återidentifieras.

**Återstår:** lokal/hosted SQL-runtime, Auth Admin-workerintegration, fysisk phone/tablet/desktop-grind och omkörning av Flutter-testsviten när testwrappen svarar.

**Verifiering:** hela appens relevanta historikvyer körs mot anonymiserad fixture utan fel eller identifierande data.

## 7. Våg 3 – Kalender och EventDetails

### CAL-01 – Kalenderns vyer och filter

**Status:** `[~]`  
**Paritet:** CAL-01, CAL-02  
**Beroenden:** FND-02–FND-05

- [x] Agenda/lista, månad, vecka och dag använder samma datakälla och datumlogik.
- [x] Lag-/eventtypfilter är konsekventa och begripliga.
- [x] DST, nattpass, heldag och timezonegränser testas.
- [x] Mobil/tablet/desktop prioriterar om utan capabilityskillnad.

**Återstår:** omkörning av Flutter-testsviten när testwrappen svarar samt fysisk phone/tablet/desktop-grind.

### CAL-02 – Skapa och redigera event/serie

**Status:** `[~]`  
**Paritet:** CAL-03–CAL-05, CAL-08  
**Beroenden:** CAL-01, FND-03

- [x] Engångsevent och serie använder validerad typ, tid, plats, lag, audience och status.
- [x] Redigering väljer förekomst, framtida eller hela serien med revision/conflict-skydd.
- [x] Sparade platsförslag är tenantsäkra.

**Återstår:** lokal/hosted SQL-runtime, omkörning av Flutter-testsviten när testwrappen svarar samt fysisk phone/tablet/desktop-grind.

### CAL-03 – Delade event och audience

**Status:** `[~]`  
**Paritet:** CAL-06, CAL-07  
**Beroenden:** CAL-02, TEAM-06

- [x] Primärt lag äger eventet; deltagande lag får explicita capabilities.
- [x] Audience styr synlighet/mottagare men aldrig redigeringsrätt.
- [x] Sekundärlagsledare kan bara utföra uttryckligen tillåtna handlingar.

**Återstår:** lokal/hosted SQL-runtime, omkörning av den riktade Flutter-testfilen när testwrappen svarar samt fysisk flerrollsgrind.

### CAL-04 – Säker eventlivscykel och radering

**Status:** `[~]`  
**Paritet:** CAL-09  
**Beroenden:** CAL-02

- [x] Opublicerat utkast/oberoende event kan raderas efter konsekvenskontroll.
- [x] Event med publicering, callups, svar, närvaro eller historik ställs in/arkiveras.
- [x] Cancel återkallar relevanta callups och skapar notifieringshändelser atomiskt.
- [x] Permanent radering finns endast i skyddat admin-/retentionflöde.

**Återstår:** lokal/hosted SQL-runtime, riktad Flutter-testkörning när testwrappen svarar samt fysisk verifiering av delete/cancel/archive.

### CAL-05 – EventDetails informationsarkitektur

**Status:** `[~]`  
**Paritet:** CAL-10  
**Beroenden:** CAL-01, FND-04

- [x] Flikarna heter Info, Deltagare, Förberedelser och Uppföljning.
- [x] Deltagare omfattar urval, kallelser, svar och närvaro.
- [x] Innehåll/actions anpassas efter eventtyp och roll.
- [x] Mobil visar begripliga fulla namn via rullning/sekundär navigation, inte otydliga förkortningar.

**Återstår:** riktad Flutter-testkörning när testwrappen svarar samt fysisk phone/tablet/desktop- och flerrollsgrind.

### CAL-06 – En revisionerad deltagardraft

**Status:** `[~]`  
**Paritet:** CAL-11–CAL-13  
**Beroenden:** CAL-03, TEAM-06

- [x] Manuell, alla, grupp och generator fyller samma draft.
- [x] Lock/send validerar eligibility vid eventtidpunkten och fryser revision.
- [x] Late callup och cancel är explicita och skriver inte över tidigare utskick.
- [x] Retry/idempotens och stale revision testas.

**Återstår:** lokal/hosted SQL-runtime, riktad Flutter-testkörning när testwrappen svarar samt fysisk draft/lock/send/late-callup-grind.

### CAL-07 – Svar, guardian och påminnelse

**Status:** `[~]`  
**Paritet:** CAL-14–CAL-16, CAL-18  
**Beroenden:** CAL-06, TEAM-05

- [x] Player/guardian svarar via samma auktoritativa transition.
- [x] Guardian acting-as verifieras och auditloggas.
- [x] Decline reason skiljer strukturerad anledning från fritext.
- [x] Reminder har cooldown, dedupe och separat leveransstatus.
- [x] Push-actiontoken är scopead, kortlivad och single-use/idempotent.

**Återstår:** lokal/hosted SQL-runtime, riktad Flutter-testkörning när testwrappen svarar samt fysisk player/guardian/reminder/push-action-grind.

### CAL-08 – Närvaro

**Status:** `[~]`  
**Paritet:** CAL-17, HOME-06  
**Beroenden:** CAL-06

- [x] Unknown, present, late, partial och absent är separata tillstånd.
- [x] Unknown räknas aldrig som present eller frånvarande.
- [x] Batchmutation är atomisk; sen ändring kräver capability och revisionsspår.
- [x] Mobilregistrering under aktivitet är snabb och har säkert retrybeteende.

**Återstår:** lokal/hosted SQL-runtime, riktad Flutter-testkörning när testwrappen svarar samt fysisk mobil batch-/late-correction-grind.

### CAL-09 – Förbered gränser för senare planeringsfunktioner

**Status:** `[~]`  
**Paritet:** CAL-19–CAL-22  
**Beroenden:** CAL-05

- [x] Import, anteckningar, bilagor och fulla match-/träningsworkspaces ligger inte i första leveransen.
- [x] Nuvarande data- och navigationsgränser blockerar inte senare tillägg.
- [x] Inga tomma eller falskt aktiva funktioner visas i kärn-UX.

**Återstår:** riktad Flutter-testkörning när testwrappen svarar samt fysisk kontroll av EventDetails på mobil och tablet/desktop.

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

**Status:** `[~]`  
**Paritet:** PUB-01, PUB-08–PUB-10  
**Beroenden:** AUTH-06

- [x] Verifierad/listad klubb kan visas minimalt i skyddad katalog.
- [x] Teamstatus är private/listed/published, private som default.
- [x] Fältvis publicering och samtycke är audit- och expiryhanterade.
- [x] Minderårigdata är dold som default.
- [x] Publik data går via allowlistad projection/API med limits och rate limiting.

**Återstår:** PostgreSQL-runtime/advisors och separat godkänd liveutrullning; publiceringsruntime förblir strukturellt avstängd.

### PUB-03 – Nyheter och redaktionellt flöde

**Status:** `[~]`  
**Paritet:** PUB-04  
**Beroenden:** PUB-01, PUB-02

- [x] Rollstyrt utkast, preview, schemaläggning, publicera och avpublicera finns som revisionerade serverkommandon; publik artikel-preview renderar endast strukturerade, allowlistade block.
- [x] Klubbkanal och valda lagkanaler är explicita, publiceringsstatus ingår i redaktörsvyn och bildstatus är tydligt `not_configured` tills PUB-04 inför säker publik mediavariant.
- [x] Avpublicering tar atomiskt bort API-projektionen och köar invalidation för klubb- och artikelväg.

**Återstår:** autentiserad redaktörsyta i Flutter, publik bildvariant i PUB-04, PostgreSQL-runtime, mätning av cache-SLA och separat godkänd liveutrullning.

### PUB-04 – Publika event, partners och kontakt

**Status:** `[~]`  
**Paritet:** PUB-05–PUB-07  
**Beroenden:** PUB-01, PUB-02, CAL-03

- [x] Event publiceras separat och revisionerat; endast titel, starttid, typ och uttryckligt vald plats förs till publik projektion och klubb-/laglistor.
- [x] Partners kräver HTTPS-länk och eventuell logotyp måste vara skannad samt ha servicegenererad publik variant innan publicering.
- [x] Kontaktformuläret har same-origin, CAPTCHA, 5 försök/timme, maxlängder, neutral respons för okänd/otillgänglig klubb samt 30 dagars innehållsretention.

**Återstår:** autentiserad publicerings-UX, faktisk mediaworker/leveransväg, PostgreSQL-runtime/advisors, fysisk visuell fixture och separat godkänd liveutrullning.

### PUB-05 – Domänförberedelse utan manuell klubbdrift

**Status:** `[~]`  
**Paritet:** PUB-12, PUB-13  
**Beroenden:** PUB-01, separat driftgodkännande

- [x] Egen premiumdomän har unik claim, hashad ägarverifiering, entitlementgrind, DNS-guide, TLS-livscykel, en canonical och permanenta 308-redirects.
- [x] Premiumsubdomän är strukturellt blockerad tills wildcard DNS, wildcard TLS och automatisk tenantrouting öppnas tillsammans genom en senare migration.
- [x] Hostname→klubb-routing och fallback till path-adress är datadriven; normalflödet kräver ingen manuell kod-, route- eller hostingändring per klubb.

**Återstår:** fastställd premium-entitlement, provideradapter/worker, faktisk wildcard- och TLS-provisionering, hosted redirect/certifikat-smoke samt separat driftgodkännande.

### PUB-06 – Webbkvalitet och framtida livegräns

**Status:** `[~]`  
**Paritet:** PUB-14, PUB-15  
**Beroenden:** PUB-01–PUB-04

- [x] Publik HTML har högst 60 sekunders CDN-cache med `must-revalidate`; API/kontakt förblir `no-store` och köad path-invalidation har autentiserad worker, retry och timeoutåtertagning.
- [x] Security headers, canonical SEO, dynamisk sitemap, robots och repeterbart synthetic smoke-script ingår i grinden.
- [x] Live matchrapportering ligger endast i LATER-03 och kontraktstest blockerar live-/matchklocka-/realtimebegrepp i PUB-06-leveransen.

**Återstår:** hosted synthetic smoke, cache-hit/invalidation-SLA med publicerad fixture, PostgreSQL-runtime/advisors, workerhemlighet/schemaläggning och separat driftgodkännande.

## 9. Våg 5 – Inbox och notiser

### MSG-01 – Inbox och automatisk team-/ledarchat

**Status:** `[~]`  
**Paritet:** MSG-01–MSG-03  
**Beroenden:** TEAM-03, FND-02–FND-04

- [x] Inbox har sök, Alla/Olästa/Lag/Ledare/Tystade-filter, senaste avsändare/aktivitet, unread, mute, manuell refresh och debouncad privat Realtime-resync.
- [x] Lagchat och ledarchat binds deterministiskt till laget; triggers skapar/reconcilerar deltagare från aktiva assignment- och kontorelationer samt stänger trådarna med laget.
- [x] Ledarchatt kräver aktivt deltagande och aktuell `team.roster.view`-capability vid varje central accesskontroll för både läsning och send.

**Återstår:** PostgreSQL-runtime/advisors, körbar Flutter-test-/analysgrind när den lokala verktygslåsningen lösts samt fysisk tvårollsverifiering av join/leave, unread, mute och reconnect.

### MSG-02 – Group, direct och relationsstyrd kontakt

**Status:** `[~]`  
**Paritet:** MSG-04–MSG-06  
**Beroenden:** MSG-01, TEAM-05

- [x] Samma centrala relationsregel styr mottagarsökning, skapande, tillägg och send; grupp- och direktflödena använder endast serverns tillåtna mottagare.
- [x] Player-to-player är av som default; spelare kan kontakta ledare/vårdnadshavare medan ledare kan kontakta relevanta roller i aktuell klubb-/lagkontext.
- [x] Cross-club leader request förblir dataminimerad, rate-limitad till 3/24 timmar och 10/30 dagar samt skapar ingen tråd före mottagarens acceptans.

**Återstår:** PostgreSQL-runtime/advisors, körbar Flutter-test-/analysgrind när den lokala verktygslåsningen lösts samt fysisk flerrollsverifiering av tillåten/nekad direktkontakt, gruppskapande, deltagartillägg och accepterad cross-club-förfrågan. Ingen livepush är gjord.

### MSG-03 – Announcement och lässtatus

**Status:** `[~]`  
**Paritet:** MSG-07, MSG-10  
**Beroenden:** MSG-01

- [x] Announcement skapas av aktiv ledare/klubbfunktionär, är envägs för mottagare och använder en separat per-deltagare-readmodell.
- [x] Markera läst routas till rätt readmodell; Markera alla är ett idempotent, kontextbundet serverkommando som omfattar både vanliga trådar och announcements.

**Återstår:** PostgreSQL-runtime/advisors, körbar Flutter-test-/analysgrind när den lokala verktygslåsningen lösts samt fysisk flerrollsverifiering av publicering, mottagarens read-only-yta, unread och Markera alla. Ingen livepush är gjord.

### MSG-04 – Historik, send och Realtime-resync

**Status:** `[~]`  
**Paritet:** MSG-08, MSG-09  
**Beroenden:** MSG-01, FND-02

- [x] Historiken använder en exklusiv revisionscursor med explicit `has_more`/nästa cursor; klienten deduplicerar på meddelande-ID och sorterar på revision.
- [x] Send är optimistisk men idempotent med synligt pending, failure och explicit retry som återanvänder samma idempotensnyckel och staged files.
- [x] Aktiv participantaccess verifieras centralt vid varje send, inklusive announcement-skrivbehörighet.
- [x] Privat tråd-Realtime triggar debouncad ersättning av första sidan både vid subscribe och reconnect; serverhistoriken är fortsatt källa till sanning.

**Återstår:** PostgreSQL-runtime/advisors, körbar Flutter-test-/analysgrind när den lokala verktygslåsningen lösts samt fysisk tvåenhetsverifiering av lång historik, offline failure/retry och reconnect. Ingen livepush är gjord.

### MSG-05 – Mute, pin och pushpreferenser

**Status:** `[~]`  
**Paritet:** MSG-11, MSG-12, MSG-20  
**Beroenden:** MSG-01

- [x] Mute och frivillig push är fail-closed och kontosynkade; push är av tills användaren uttryckligen aktiverar den och aktiv mute undertrycker workerclaim.
- [x] Pin är beslutad och implementerad som kontosynkad per profil/tråd, visas och sorteras i Inbox samt resynkas via den privata inbox-kanalen.
- [x] Push/outbox använder endast tråd-ID, meddelande-ID och generisk preview-nyckel; en databastrigger redigerar automatiskt bort övrigt och workern loggar aldrig payload.

**Återstår:** PostgreSQL-runtime/advisors, provider-/endpointaktivering under separat driftgodkännande, körbar Flutter-/Deno-testgrind samt fysisk tvåenhetsverifiering av mute, pin och push opt-in/out. Ingen livepush är gjord.

### MSG-06 – Bilagor, återkallelse och moderation

**Status:** `[~]`  
**Paritet:** MSG-13, MSG-14, MSG-17  
**Beroenden:** MSG-02, MSG-04

- [x] Objektidentitet lagras privat; listprojektionen exponerar endast fil-ID/visningsmetadata och en 120-sekunders signerad URL skapas först efter separat serverauktorisering och Storage-RLS.
- [x] Återkallelsefönstret är 15 minuter och ger tombstone, ny trådrevision, auditversion, withdrawn-bilagor och privat Realtime-/inbox-resync.
- [x] Report kräver strukturerad orsak, blockerar avsändaren och är idempotent; service-only moderation kan dismiss, dölja med tombstone, stänga eller legal-hold med reviewer, reason, evidence hash och immutable auditspår.

**Återstår:** PostgreSQL/Storage-runtime och advisors, faktisk service-moderatoroperator/arbetskö under separat driftgodkännande, körbar Flutter-test-/analysgrind samt fysisk tvårollsverifiering av filåtkomst, recall och report/block. Ingen livepush är gjord.

### MSG-07 – Trådlivscykel och global radering

**Status:** `[~]`  
**Paritet:** MSG-15, MSG-16  
**Beroenden:** MSG-04, MSG-06, retentionpolicy

- [x] Deltagare kan dölja/lämna utan att påverka andras historik.
- [x] Behörig ansvarig kan arkivera/stänga för nya meddelanden.
- [x] Global radering kräver två separata behöriga användare.
- [x] Cross-club/integritetsärende kräver TeamZone-granskning.
- [x] Tombstones bevarar ordning, replies, read state och notifieringsreferenser.

**Återstår:** PostgreSQL-runtime/advisors, Flutter-grind och fysisk flerrolls-/serviceoperatorverifiering. Ingen livepush är gjord.

### MSG-08 – Notification center utan Watchpoints

**Status:** `[~]`  
**Paritet:** MSG-18–MSG-20, HOME-10  
**Beroenden:** MSG-03–MSG-05

- [x] Samlar handlingsbara domännotiser med säker preview och deep link.
- [x] Watchpoint-items avlägsnas utan att vanliga notifieringar försvinner.
- [x] AC-signaler introduceras inte här före AC-vågen.

**Återstår:** PostgreSQL-runtime/advisors, Flutter-grind och fysisk tvåenhetsverifiering av badge/read/deep links. Ingen livepush är gjord.

## 10. Våg 6 – rollspecifikt Hem

### HOME-01 – Ledarens Hem

**Status:** `[~]`  
**Paritet:** HOME-01, HOME-04, HOME-06  
**Beroenden:** TEAM-02, CAL-07, CAL-08, MSG-08

- [x] Prioriterar dagens lagarbete, nästa event och deterministiska åtgärder.
- [x] Visar obesvarade callups/saknad närvaro endast för behörig kontext.
- [x] Tablet/desktop kan ge planeringsöverblick; mobil ger snabb handling.

**Återstår:** PostgreSQL-runtime/advisors, Flutter-grind och fysisk verifiering med flera ledarkontexter/skärmstorlekar. Ingen livepush är gjord.

### HOME-02 – Spelarens Hem

**Status:** `[~]`  
**Paritet:** HOME-02, HOME-04, HOME-05  
**Beroenden:** CAL-07, MSG-08

- [x] Egna kallelser, nästa aktivitet, laginformation och meddelanden.
- [x] Snabbt svar bevarar korrekt callupstatus och decline reason.
- [x] Inga leader-/guardianadministrativa actions exponeras.

**Återstår:** PostgreSQL-runtime/advisors, Flutter-grind och fysisk spelarverifiering av svar/stale revision/deep links. Ingen livepush är gjord.

### HOME-03 – Vårdnadshavarens Hem

**Status:** `[~]`  
**Paritet:** HOME-03, HOME-05  
**Beroenden:** TEAM-05, CAL-07, MSG-08

- [x] Välj barn och visa endast relationstillåtna kallelser/event/meddelanden.
- [x] Acting-as är synligt och bevaras genom hela svarsmutationen.

**Återstår:** PostgreSQL-runtime/advisors, Flutter-grind och fysisk guardianverifiering med flera barn/lag samt avslutad relation. Ingen livepush är gjord.

### HOME-04 – Gemensam uppmärksamhetsmodell

**Status:** `[~]`  
**Paritet:** HOME-06, HOME-10, HOME-12  
**Beroenden:** HOME-01–HOME-03

- [x] Rollstyrda åtgärdskort och notification center använder en konsekvent prioritering.
- [x] Samma domänhändelse dupliceras inte som flera oberoende uppgifter.
- [x] Mobil och större skärmar prioriterar olika layout men samma rättigheter/data.

**Återstår:** PostgreSQL-runtime/advisors, Flutter-grind och fysisk cross-device-/responsivitetsverifiering. Ingen livepush är gjord.

### HOME-05 – Avlägsna Watchpoints och håll AC avvaktande

**Status:** `[~]`  
**Paritet:** HOME-07–HOME-09, HOME-11  
**Beroenden:** HOME-04

- [x] Watchpoints-namn, separat UI och notification-items avlägsnas.
- [x] Deterministiska uppgifter fortsätter fungera utan AC.
- [x] AC-prototypen byggs inte vidare förrän AC-01:s datagrind passerar.
- [x] Belastning/skada/high-load förblir senare och fail-closed.

**Återstår:** PostgreSQL-runtime/advisors, Flutter-grind och fysisk kontroll av gamla poster samt HOME-01–04-regression. Ingen livepush är gjord.

## 11. Våg 7 – Assistant Coach-grund

### AC-01 – Datagrind och signalregister

**Status:** `[~]`  
**Paritet:** HOME-08, HOME-11  
**Beroenden:** CAL-06–CAL-08, HOME-04

- [~] Datakvalitet, ägande, freshness och behörighet har ett privat, fail-closed register; runtime-verifiering återstår eftersom lokal PostgreSQL-miljö saknas.
- [x] Första deterministiska signaler: obesvarade callups; nära event utan deltagardraft/callup; avslutat event utan närvaro; positiva planerings-/svarssignaler; framtida planeringsluckor.
- [x] Varje signal visar källa, tidpunkt, förklaring och möjlig säker handling.
- [x] Ingen generativ AI aktiveras utan separat parameter-/integritetsbeslut; AC-grinden förblir blockerad.

### AC-02 – Responsiv AC-ingång

**Status:** `[~]`  
**Paritet:** HOME-09  
**Beroenden:** AC-01

- [x] Mobil använder FAB nere till höger, placerad ovanför sidornas primära FAB-zon och navigation.
- [x] Tablet/desktop använder en integrerad, inaktiv sidopanel där utrymme finns.
- [~] Fokus, semantik, back och deep link har strukturella kontrakt; fysisk responsiv verifiering och dataflöde återstår tills AC har verifierad data.

### AC-03 – Transparent assistent, inte Watchpoints i ny kostym

**Status:** `[~]`  
**Paritet:** HOME-07, HOME-08, MSG-19  
**Beroenden:** AC-01, AC-02

- [x] AC-kontraktet sammanfattar deterministiskt och navigerar till säker vy; domänkommandon kräver fortfarande explicit användarhandling.
- [x] Presentationen förbjuder dolda riskpoäng, medicinska slutsatser, otillåtna personjämförelser och generativ AI.
- [~] Signal har privat, idempotent och auditerad avfärda/återställ-livscykel utan koppling till notifieringshistorik; SQL-runtime och verkligt dataflöde återstår.

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

- [x] Dart-formatkontrollen passerar för samtliga 125 filer under `lib` och `test`.
- [x] Statisk Dart-analys passerar utan anmärkningar.
- [x] Hela Flutter-sviten passerar: 256 tester.
- [x] Flutter-webbbygget passerar och skapar `build/web`.
- [x] Android-debugbygget passerar och skapar `build/app/outputs/flutter-apk/app-debug.apk`.
- [x] Publiksajtens typecheck, 22/22 tester och full Next-produktionsbuild passerar i lokal miljö som tillåter child-processer.
- [x] Secret-, loggredaction-, ACL/RLS- och kontraktskontroller ingår i den gröna Flutter-sviten.

### REL-02 – Roll-, enhets- och avbrottsmatris

**Status:** `[~]`  
**Beroenden:** REL-01

- [~] Leader, player, guardian och klubbfunktionär passerar aktuell automatiserad 4 × 3-baslinje över alla fyra grundytor; hosted behörighetskörning med separata konton återstår.
- [~] Telefon, tablet och desktop/web passerar aktuell automatiserad viewport-/navigationsregression; fysisk/webbläsarbaserad slutkörning återstår.
- [~] Cold start, deep link, back/forward, kontextbyte, offline, reconnect och session expiry har separata fall; äldre strukturbevis finns men aktuell releasekörning återstår.
- [~] Skärmläsare, tangentbord/fokus, textskalning, kontrast och reduced motion har separata fall; aktuell assistiv/fysisk regression återstår.

### REL-03 – Scope- och säkerhetsgrind

**Status:** `[~]`  
**Beroenden:** REL-01, REL-02

- [x] Gamla `C:\Dev\TeamZone` är git-ren och ingen produktkod refererar till dess sökväg eller en gammal databas; read-only scopegrind passerar.
- [x] Dokumenterade Supabase-liveändringar ligger i tidigare separat godkända rolloutbevis; aktuellt arbete är lokalt och releaseverktygen innehåller inga push/deploykommandon.
- [x] Produktion är fortsatt `not_provisioned` utan Supabase-/Firebaseprojekt; inga `webtools`- eller `workspaces`-kataloger finns eller har startats.
- [x] Android namespace/applicationId och iOS bundle identifier är fortsatt `com.teamzone.teamzone`.
- [~] Alla implementerade arbetskort har evidence, REL-01 är grön och första återställningspunkten `bef10fb` finns; endast REL-02:s uppskjutna hosted/fysiska slutkontroller återstår.

## 14. Rekommenderat nästa konkreta arbete

1. [x] Genomför **FND-01** som en ren extraktion utan produktbeteendeändring.
2. [x] Genomför **FND-02** ovanpå de extraherade ytorna.
3. [x] Genomför **FND-03–FND-05** och frys klientgrundens kontrakt.
4. [~] **AUTH-01** lokalt genomförd; hosted e-post/Auth-verifiering kräver separat livegodkännande.
5. [~] **AUTH-02** lokalt genomförd; fysisk och hosted sessionsverifiering återstår.
6. [~] **AUTH-03** lokalt genomförd; SQL/Edge-integration och hosted replay/race-grind återstår.
7. [~] **AUTH-04** lokalt genomförd; SQL-runtime och fysisk/hosted grind återstår.
8. [~] **AUTH-05** lokalt genomförd; SQL-runtime och fysisk/hosted grind återstår.
9. [~] **AUTH-06** lokalt genomförd; SQL-runtime och fysisk/hosted grind återstår.
10. [~] **AUTH-07** lokalt genomförd; juridiskt innehåll, SQL-runtime och fysisk/hosted grind återstår.
11. [~] **TEAM-01** lokalt genomförd; fysisk deep-link/navigation-grind återstår.
12. [~] **TEAM-02** lokalt genomförd; SQL-runtime och fysisk/hosted grind återstår.
13. [~] **TEAM-03** lokalt genomförd; SQL-runtime och fysisk/hosted grind återstår.
14. [~] **TEAM-04** lokalt genomförd; SQL-runtime och fysisk/hosted grind återstår.
15. [~] **TEAM-05** lokalt genomförd; SQL/Edge-runtime och fysisk/hosted grind återstår.
16. [~] **TEAM-06** lokalt genomförd; SQL-runtime och fysisk/hosted grind återstår.
17. [~] **TEAM-07** lokalt genomförd; SQL-runtime, fysisk grind och Flutter-testkörning återstår.
18. [~] **TEAM-08** lokalt genomförd; SQL/Auth-worker-runtime, fysisk grind och Flutter-testkörning återstår.
19. [~] **CAL-01** lokalt genomförd; Flutter-testkörning och fysisk responsiv grind återstår.
20. [~] **CAL-02** lokalt genomförd; SQL-runtime, Flutter-testkörning och fysisk grind återstår.
21. [~] **CAL-03** lokalt genomförd; SQL-runtime, Flutter-testkörning och fysisk flerrollsgrind återstår.
22. [~] **CAL-04** lokalt genomförd; SQL-runtime, Flutter-testkörning och fysisk livscykelgrind återstår.
23. [~] **CAL-05** lokalt genomförd; Flutter-testkörning och fysisk responsiv/flerrollsgrind återstår.
24. [~] **CAL-06** lokalt genomförd; SQL-runtime, Flutter-testkörning och fysisk deltagardraftgrind återstår.
25. [~] **CAL-07** lokalt genomförd; SQL-runtime, Flutter-testkörning och fysisk svar/påminnelsegrind återstår.
26. [~] **CAL-08** lokalt genomförd; SQL-runtime, Flutter-testkörning och fysisk mobil närvarogrind återstår.
27. [~] **CAL-09** lokalt genomförd; Flutter-testkörning och fysisk responsiv kontroll återstår.
28. [~] **PUB-01** lokalt genomförd; publicerad fixture, fysisk visuell kontroll och PUB-02/PUB-04-projektioner återstår.
29. [~] **PUB-02** lokalt genomförd; PostgreSQL-runtime/advisors och separat livegodkännande återstår.
30. [~] **PUB-03** lokalt genomförd; redaktörsyta, PUB-04-media, PostgreSQL-runtime/cache-SLA och separat livegodkännande återstår.
31. [~] **PUB-04** lokalt genomförd; publicerings-UX, mediaworker, PostgreSQL-runtime, fysisk fixture och separat livegodkännande återstår.
32. [~] **PUB-05** lokalt genomförd; entitlement, providerworker, PostgreSQL-runtime och separat DNS/TLS-/driftgodkännande återstår.
33. [~] **PUB-06** lokalt genomförd; hosted synthetic/cache-SLA, PostgreSQL-runtime, workerschemaläggning och separat driftgodkännande återstår.
34. [~] **MSG-01** lokalt genomförd; PostgreSQL-runtime, Flutter-test/analys och fysisk tvårolls-/reconnectgrind återstår.
35. [~] **MSG-02** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk flerrollsgrind återstår.
36. [~] **MSG-03** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk announcement-/lässtatusgrind återstår.
37. [~] **MSG-04** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk pagination-/retry-/reconnectgrind återstår.
38. [~] **MSG-05** lokalt genomförd; PostgreSQL-runtime/advisors, providergrind, Flutter-/Deno-test och fysisk tvåenhetspreferencegrind återstår.
39. [~] **MSG-06** lokalt genomförd; PostgreSQL/Storage-runtime, moderatoroperator, Flutter-test/analys och fysisk fil-/safeguardinggrind återstår.
40. [~] **MSG-07** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk flerrolls-/serviceoperatorgrind återstår.
41. [~] **MSG-08** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk tvåenhetsgrind återstår.
42. [~] **HOME-01** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk fler-kontext-/responsivitetsgrind återstår.
43. [~] **HOME-02** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk spelar-/svarsgrind återstår.
44. [~] **HOME-03** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk flerbarns-/acting-as-grind återstår.
45. [~] **HOME-04** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk dedupe-/cross-device-/responsivitetsgrind återstår.
46. [~] **HOME-05** lokalt genomförd; PostgreSQL-runtime/advisors, Flutter-test/analys och fysisk legacy-/HOME-regressionsgrind återstår.

## 15. Ändringslogg

| Datum | Ändring | Status |
|---|---|---|
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
| 2026-08-27 | MSG-07 lokalt genomfört: personlig döljning och frivilligt utträde påverkar inte andras historik; behörig stängning bevarar läsbar historik. Global radering kräver initiativtagare plus separat behörig godkännare och service-only applicering, med TeamZone-review för cross-club/integritet. Neutral tombstone bevarar ordning, replies, read state och notifieringsreferenser. Ingen livepush gjordes. | MSG-07 partiell |
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
| 2026-08-27 | PUB-05 lokalt genomfört: globalt unik hostname-claim, hashad TXT-verifiering, separat kommersiell grind, TLS-/providerlivscykel, en canonical per klubb och datadriven rewrite/308-routing infördes. Canonical metadata följer verifierad egen domän. TeamZone-subdomäner är strukturellt avstängda tills wildcard DNS/TLS och automatisk routing öppnas tillsammans. Ingen DNS, TLS, hosting eller livekonfiguration ändrades. | PUB-05 partiell |
| 2026-08-27 | PUB-06 lokalt genomfört: publik HTML får högst 60 sekunders CDN-cache med must-revalidate medan API/kontakt är no-store. Service-only invalidationsclaim, strikt bearer-skyddad Next-worker, pathvalidering, retry och timeoutåtertagning kopplar PUB-03/04-köerna till revalidatePath. Dynamisk canonical-medveten sitemap, robots, HSTS/COOP och syntetiskt smoke-script infördes. Live matchrapportering förblir explicit senare. TypeScript, 22/22 tester och Next-produktionsbuild passerar. Ingen hosted smoke eller liveändring gjordes. | PUB-06 partiell |
| 2026-08-27 | MSG-01 lokalt genomfört: Inbox fick sök, fem filter, senaste avsändare/tid, unread/mute och privat debouncad Realtime-resync. Varje aktivt lag får deterministisk lag- och ledarchatt; team-, assignment-, kontolänk- och capabilitytriggers reconcilerar deltagare från aktuella relationer. Ledarchatten återkontrollerar team.roster.view centralt vid läsning/send. Dart-format och statisk kontraktsgrind passerar; Flutter-wrapper/analysserver fastnade utan diagnostik och riktad flutter_test-körning återstår. Ingen livepush gjordes. | MSG-01 partiell |
| 2026-08-27 | MSG-02 lokalt genomfört: samma centrala relationsregel används av mottagarsökning, direkt-/gruppskapande, deltagartillägg och send. Player-to-player är av som standard. Cross-club-ledarkontakt behåller verifiering, dataminimering, 3/24 h- och 10/30 d-gränser samt mottagaracceptans. Klienten kan skapa direkt- och grupptrådar och lägga till servervaliderade gruppdeltagare. Dart-format och statiska kontraktskontroller passerar; Flutter-testwrappen fastnade utan output och avbröts kontrollerat. Ingen livepush gjordes. | MSG-02 partiell |
| 2026-08-27 | MSG-03 lokalt genomfört: aktiv ledare/klubbfunktionär kan skapa announcement till servervaliderade mottagare, medan endast skapare/moderator kan skriva. Announcements har separat per-deltagare-readmodell; listning och enskild läsmarkering routar efter trådtyp. Markera alla är atomiskt, idempotent och kontextbundet över både messages och announcements. Mottagaren får en tydlig read-only-yta. Dart-format och statisk SQL-kontraktsgrind passerar; runtime-, Flutter- och fysisk grind återstår. Ingen livepush gjordes. | MSG-03 partiell |
| 2026-08-27 | MSG-04 lokalt genomfört: historiken fick exklusiv revisionscursor, limit+1, explicit continuation och klientdeduplicering. Trådens privata Realtime-kanal resynkar första sidan deterministiskt vid subscribe/reconnect. Send visas optimistiskt med pending/failure och explicit retry som återanvänder idempotensnyckel och staged files; servern återkontrollerar aktiv participantaccess vid varje försök. Dart-format och statisk kontraktsgrind passerar; runtime-, Flutter- och fysisk tvåenhetsgrind återstår. Ingen livepush gjordes. | MSG-04 partiell |
| 2026-08-27 | MSG-05 lokalt genomfört: mute och frivillig push är fail-closed och kontosynkade; push kräver explicit opt-in och aktiv mute undertrycker workerclaim. Pin beslutades som kontosynkad, styr Inboxordning/filter och resynkas privat. En trigger reducerar varje message-push till thread/message-ID och generisk preview-nyckel; workern loggar ingen payload. Klienten fick pushinställning samt säkra mute-/pin-pendinglägen. Gatewayallowlisten kompletterades för MSG-02/03/05-kommandon. Dart-format och statisk kontraktsgrind passerar; runtime/provider-/Flutter-/Deno-/fysisk grind återstår. Ingen livepush gjordes. | MSG-05 partiell |
| 2026-08-27 | MSG-06 lokalt genomfört: aktiv filprojektion exponerar inte object key; fil-ID måste serverauktoriseras före en 120-sekunders signerad URL och Storage-RLS återkontrollerar access. Recall behåller 15-minutersfönster, tombstone, audit/retention, withdrawn-filer och resynkar nu även vid update. Report fick strukturerad orsak, auto-block och säker stängning av klientvyn. Service-only moderation fick reviewer/reason/evidence-hash och immutable actions för dismiss, hide, close och legal hold. Dart-format och statisk kontraktsgrind passerar; runtime-, moderatoroperator-, Flutter- och fysisk grind återstår. Ingen livepush gjordes. | MSG-06 partiell |
