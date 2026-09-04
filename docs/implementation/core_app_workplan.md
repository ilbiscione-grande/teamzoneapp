# TeamZone grundapp – fastställd arbetsplan

Status: **FASTSTÄLLD – uppdateras och klarmarkeras löpande**  
Skapad: 2026-08-23  
Omfattning: Inloggning/Skapa konto, Hem, Laget, Kalender, Inbox och publik klubbsajt med lagkanaler

## 1. Så använder vi dokumentet

Det här är det levande arbetsdokumentet för nästa fas av TeamZone-rebuilden.
Vi uppdaterar status direkt här när en punkt har verifierats.

- `[ ]` Inte påbörjad.
- `[~]` Pågår eller finns delvis men är inte paritetsgranskad/verifierad.
- `[x]` Färdig och verifierad mot punktens acceptanskriterier.
- `[!]` Blockerad av beslut, behörighet eller extern förutsättning.
- `[n/a]` Gemensamt beslutad att inte ingå.

En punkt får klarmarkeras först när implementation, relevanta tester och
användarupplevelsen är verifierade. Att en funktion fanns i den gamla appen
betyder inte automatiskt att dess gamla tekniska lösning eller risker ska
återskapas.

## 2. Mål och arbetsprinciper

Målet är att de fem prioriterade ytorna ska ge i stort sett samma praktiska
nytta som den tidigare appen, men byggas på rebuildens beslutade gröna
datamodell, capabilitystyrning och säkra API-gräns.

- Gamla `C:\Dev\TeamZone` är en skrivskyddad beteende- och UX-referens.
- Gamla databaser, gamla Supabase-projekt och gammal implementation ändras inte.
- Funktioner kopieras inte blint när gamla auditfynd visar säkerhets-, privacy-,
  data- eller synkproblem.
- Varje skrivning ska visa och skicka explicit klubb-/lag-/eventmål.
- Hem, Kalender och Inbox ska kunna aggregera behöriga kontexter.
- Alla ytor ska ha tydliga loading-, empty-, stale-, error- och retry-lägen.
- Svenska och engelska, tillgänglighet, telefon/tablet/web och reduced motion
  ingår i definitionen av färdig.
- Supabase live ändras endast efter separat uttryckligt godkännande.
- Webtools, workspaces och separat produktionsprovisionering ingår inte här.
- Appidentiteten `com.teamzone.teamzone` behålls.

### Roll- och situationsanpassad produktdesign

De prioriterade ytorna ska inte vara samma informationsmängd med olika behörighetsknappar.
Varje huvudroll ska få en egen prioriterad upplevelse ovanpå samma säkra data-
och actionkontrakt:

- **Ledare:** planering, uppgifter som kräver åtgärd, lagöverblick, kallelser,
  närvaro och kommunikation.
- **Spelare:** eget schema, egna kallelser/svar, relevant laginformation,
  personlig utveckling och säkra kontaktvägar.
- **Vårdnadshavare:** barnets/barnens schema och kallelser, acting-as-svar,
  praktisk information och kontakt med behöriga ledare.
- **Klubbfunktionär:** klubbövergripande sammanfattning och endast de
  klubbåtgärder som personens capabilities tillåter.

Enhet och situation är också en del av kravbilden:

- **Mobil:** snabb användning på språng eller under aktivitet, stora touchmål,
  få steg, primära actions nära tummen och robust hantering av avbrott.
- **Tablet:** planering, överblick och visuella arbetsytor, exempelvis att rita
  och planera en träning, samtidigt som touch är primär input.
- **Desktop/web:** tätare informationsöverblick, tangentbord, mus, sidopaneler
  och effektiva administrations-/planeringsflöden.

Responsiv design får därför ändra informationshierarki och arbetsflöde, inte
bara bredden på samma layout. Funktionens behörighet och resultat ska däremot
vara konsekventa mellan enheter.

### Min assistent ersätter Watchpoints

Gamla Watchpoints ska inte flyttas över som produkt eller namn. **Min assistent**
är det fasta funktionsnamnet för den nya sammanhållna assistenten. Den får ett
senare beslutat sportigt, internationellt standardnamn och varje användare kan
välja ett eget personligt namn. Namnet påverkar endast presentation. Assistenten
kan på sikt få en godkänd generativ AI-del, men kärnan ska fungera utan
språkmodell. Full målmodell finns i
`docs/implementation/min_assistent_concept.md`.

- Första versionen är transparent och deterministisk: verifierbara signaler,
  datakälla, tidsfönster, osäkerhet och förklaring.
- Positiva signaler är lika viktiga som risker eller saker att följa upp.
- Förslag visas endast när användaren redan har vanlig capability för målet.
- Varje mutation kräver preview och uttrycklig bekräftelse och går genom samma
  auditerade domänkommando som resten av appen.
- Min assistent får aldrig autonomt skicka, kalla, ändra data eller fatta
  medicinska/eligibilitybeslut.
- På mobil nås Min assistent från en flytande FAB längst ned till höger
  ovanpå Hem. På tablet/desktop ska Min assistent i första hand utnyttja det
  större utrymmet som en synlig, integrerad eller beständig panel; en FAB behövs
  där endast om den senare UX-genomgången visar ett tydligt värde.
- En gemensam kö kompletteras med specialistområden. Varje post visar område
  med textetikett, ikon och färg; status och prioritet visas separat.
- Alla områden delar historik, deduplicering, prioritering och notifieringsbudget
  och får inte skapa konkurrerande specialistinkorgar.
- Gamla Watchpoint-trösklar kopieras inte. Varje ny signal ska definieras,
  versionshanteras och verifieras på nytt.

## 3. Källor som ligger till grund för arbetsplanen

### Tidigare app

- `C:\Dev\TeamZone\docs\audit_phase_1\02_functional_inventory.md`
- `C:\Dev\TeamZone\docs\audit_phase_1\03_runtime_navigation_and_state.md`
- `C:\Dev\TeamZone\docs\audit_deep_dives\01_identity_and_context\`
- `C:\Dev\TeamZone\docs\audit_deep_dives\04_member_roster_and_organization_lifecycle\`
- `C:\Dev\TeamZone\docs\audit_deep_dives\05_calendar_events_and_recurrence\`
- `C:\Dev\TeamZone\docs\audit_deep_dives\06_callups_responses_and_attendance\`
- `C:\Dev\TeamZone\docs\audit_deep_dives\09_messages_and_notifications\`
- `C:\Dev\TeamZone\docs\audit_deep_dives\13_cross_cutting_client_quality\`
- `C:\Dev\TeamZone\docs\rebuild_spec\06_identity_role_context_decision.md`
- `C:\Dev\TeamZone\docs\rebuild_spec\07_person_roster_transfer_decision.md`
- `C:\Dev\TeamZone\docs\rebuild_spec\08_event_squad_callup_decision.md`
- `C:\Dev\TeamZone\docs\rebuild_spec\09_messaging_notifications_decision.md`

### Rebuildens nuläge

- `README.md`
- `docs/implementation/slice_status.md`
- Evidens för S01–S06 samt X-QA, X-UX och X-OBS under `docs/evidence/`.
- Aktuell Flutterimplementation under `lib/src/` och kontrakt under `test/`.

## 4. Nulägesbild

| Yta | Rebuildens grund finns | Viktiga sannolika paritetsluckor |
|---|---|---|
| Inloggning/Skapa konto | `[~]` Password login, session, väntrum, contextval, claim och guardian invite | Skapa konto med både lösenord och e-postkod/magic link, verifiering, glömt lösenord, invite under onboarding, ansök/skapa klubb och lag, skyddade/officiella klubbnamn, villkor/privacy |
| Hem | `[~]` Multi-context projection, nästa innehåll, actions, cache/felläge | Separata rollprioriteringar, situations-/enhetsanpassning och Min assistent som ersätter Watchpoints |
| Laget | `[~]` Rosterlista, detaljgrund, claim och guardian invite | Skapa/redigera person, import, invite, medlemsdetaljflikar, historik, statistik och grupper |
| Kalender | `[~]` Lista, details, create/edit/cancel/complete, recurrence, squad/callup/attendance och Match Space | Månad/vecka/dag, filter, import, personal notes, attachments, full EventDetails-struktur |
| Inbox | `[~]` Trådar, create/send/read/mute, filer, recall/report, requests, notifications och realtimegrund | Automatiska team-/ledarchattar, broadcast/announcement, pagination, reconnect-resync, komplett notification center |
| Publik klubbsajt | `[~]` Fail-closed public API, consent/projection, Next.js-routes, abuse-skydd och hostinggrund finns men publicering är strukturellt avstängd | Professionell klubbsajt, redaktionellt nyhetsflöde, lagkanaler, media, navigation, SEO/cache, avpublicering och separat godkänd aktivering |

Tabellen är en hypotes från dokument- och källinventeringen. Steg 1 nedan ska
göra den till en verifierad paritetsmatris innan större implementation fortsätter.

## 5. Steg-för-steg-plan

### Steg 0 – Gemensamt fastställa planen

- [x] Skapa första arbetsplansutkastet.
- [x] Gå igenom och godkänn produktbesluten tillsammans.
- [x] Varje användarsynlig funktion i de fem gamla ytorna ska finnas i
  paritetsmatrisen och märkas `Behåll`, `Förbättra`, `Senare` eller `Ta bort`.
- [x] `Behåll` och `Förbättra` måste vara färdiga för att respektive beslutad
  fas ska stängas. `Senare` måste ha ett uttryckligt framtida steg och `Ta bort`
  kräver dokumenterat produktbeslut.
- [x] Gamla osäkra eller felaktiga beteenden är aldrig paritetskrav. Samma
  praktiska användarnytta väger tyngre än identisk skärm eller implementation.
- [ ] Märk varje identifierad gammal funktion som `Behåll`, `Förbättra`,
  `Senare` eller `Ta bort`.
- [x] Fastställ ordning och acceptanskriterier.
- [x] Byt dokumentstatus från `UTKAST` till `FASTSTÄLLD`.

Godkänd när: produktägaren har godkänt omfattning, prioritet och öppna
avgränsningar. Ingen funktionslucka ska döljas bakom formuleringen "samma som
gamla appen".

### Steg 1 – Verifierad funktions- och UX-paritetsmatris

- [ ] Inventera den gamla onboardingytan skärm för skärm: start, login,
  invitekod, klubb-/lagsökning, ansökan, skapa klubb/lag, e-post och verifiering.
- [ ] Inventera gamla Hem för ledare, spelare och guardian: kort, sortering,
  handlingar, badges, varningar och tomlägen.
- [ ] Inventera gamla Laget: lista, sök/filter, detaljflikar, skapa/redigera,
  invite, import, grupper, statistik, historik och statusmarkeringar.
- [ ] Inventera gamla Kalender/EventDetails: vyer, filter, recurrence, import,
  info, trupp, förberedelser, uppföljning, notes, attachments och Match Space.
- [ ] Inventera gamla Inbox/Notification center: trådtyper, compose,
  deltagarval, broadcast, filer, read/mute, moderation, badges och pushinställningar.
- [ ] Kör motsvarande flöden lokalt i rebuilden där fixtures/mocks tillåter.
- [ ] Skapa en rad per funktion med gammal referens, rebuildstatus,
  målbeslut, beroende och verifieringsmetod.
- [ ] Granska gamla auditfynd och markera beteenden som uttryckligen inte får
  återinföras, exempelvis oscopeade medlemsändringar, stale cache utan resync,
  läckande feltexter och bilagor utan gemensam retention.

Godkänd när: varje användarsynlig funktion på de fem gamla ytorna har ett
spårbart målbeslut och det finns inga okända "övrigt"-områden.

### Steg 2 – Gemensam grund för de prioriterade ytorna

- [x] Dela upp den stora appfilen i ytspecifika widgets/controllers utan att
  ändra beteende i samma steg.
- [x] Inför gemensam modell för initial load, refresh, stale cache, offline,
  säkert fel och retry.
- [x] Säkerställ att kontextbyte avbryter/ignorerar gamla svar och aldrig visar
  data från föregående klubb eller lag.
- [ ] Bevara deep links och Android back för alla ytor och detaljvyer.
- [ ] Definiera gemensam formvalidering, pending/double-submit-skydd och
  osparade-ändringar-varning.
- [ ] Definiera gemensam lista: sök, filter, sortering, pagination och refresh.
- [ ] Verifiera tangentbord, skärmläsarsemantik, textskalning, 48 px touchmål,
  kontrast och reduced motion.
- [ ] Lägg widgettester för telefon, tablet och web/desktop per huvudstatus.
- [ ] Dokumentera en behovsmatris per yta för ledare, spelare, guardian och
  klubbfunktionär: mål, viktigaste information, primära actions och sådant som
  uttryckligen inte ska visas.
- [ ] Dokumentera en situationsmatris per yta för mobil under aktivitet,
  tabletbaserad planering och desktop/web-administration.
- [ ] Verifiera att responsiva layouter prioriterar om innehåll och actions utan
  att ändra capability- eller datakontraktet.

Godkänd när: ytorna använder samma robusthetskontrakt och inga kända
cross-context-, async- eller navigationrace återstår i de prioriterade flödena.

### Steg 3 – Inloggning och Skapa konto

#### 3A. Beslut och flödeskarta

- [x] Erbjud både lösenord och e-postkod/magic link.
- [x] "Skapa konto" ska stödja fristående konto, inbjudan, ansökan till
  befintlig klubb/lag samt skapande av ny klubb och första lag.
- [x] En ny användare ska kunna skapa en ny klubb och dess första lag direkt.
- [x] Nya klubbar skapas som inofficiella. Användaren kan begära verifiering
  och lämna underlag som visar kopplingen till klubben.
- [x] Endast TeamZone får godkänna, avslå eller återkalla officiell status;
  klienten får aldrig själv sätta verifieringsstatus.
- [x] Skyddade klubbnamn omfattar normaliserat namn samt kända namnvarianter och
  förkortningar och kräver TeamZone-godkännande vid saknad verifierad koppling.
- [x] Officiell status visas med text och ikon, inte enbart färg.
- [x] Ett avslag tar inte automatiskt bort den inofficiella klubben, men ett
  förväxlingsbart namn kan behöva bytas.
- [x] Ansökan, underlagets hantering, beslut och statusändringar auditloggas.
- [x] Lösenordsregistrering kräver verifierad e-post innan användaren får skapa
  eller ansluta sig till en klubb; e-postkod/magic link verifierar adressen i
  själva autentiseringsflödet.
- [x] Glömt lösenord använder e-postbaserad återställning och visar alltid ett
  neutralt svar oavsett om adressen tillhör ett konto.
- [x] Mobil behåller sessionen säkert tills användaren loggar ut eller sessionen
  återkallas. Web erbjuder ett tydligt val att inte behålla inloggningen på en
  delad enhet.
- [x] Vid kontoskapande måste användaren acceptera aktuella användarvillkor och
  bekräfta att integritetspolicyn har lästs; version, tidpunkt och metod sparas.
- [x] Marknadsföring och frivilliga utskick använder separata, frivilliga val
  som aldrig är förkryssade.
- [x] Väsentligt ändrade villkor kräver ett nytt uttryckligt godkännande.
- [x] Minderårigs- och vårdnadshavarsamtycken hanteras separat per funktion och
  blandas inte ihop med allmänna villkor eller marknadsföringsval.

#### 3B. Grundflöden

- [ ] Bygg tydlig start med `Logga in` och `Skapa konto`.
- [ ] Implementera skapa-konto med säkra, lokaliserade valideringsfel.
- [ ] Implementera e-postverifiering och resend/cooldown.
- [ ] Implementera glömt/återställ lösenord med neutral kontouppräkning.
- [ ] Implementera invitekod före eller efter auth och återuppta rätt flöde.
- [ ] Implementera väntrum med claim, guardian invite och tydliga nästa steg.
- [ ] Implementera inbjudningskod/-länk som återupptas säkert efter verifierad auth.
- [ ] Implementera sökning efter tillåtna befintliga klubbar/lag och en
  medlemsansökan som måste godkännas av behörig ledare eller klubbfunktionär.
- [ ] Implementera skapande av ny klubb och första lag direkt efter verifierad auth.
- [ ] Officiella/skyddade klubbar får visas i sökningen men en utomstående får
  varken skapa en förväxlingsbar kopia eller ansluta utan godkännande.
- [ ] Kontrollera namn mot normaliserad skyddslista, reserverade varianter och
  förväxlingsrisk innan skapande; visa neutral väg för att begära godkännande.
- [ ] Visa officiell/godkänd status med tillgänglig text + ikon, aldrig enbart färg.
- [ ] Auditlogga ansökan, godkännande, avslag och ändrad officiell status.
- [ ] Återställ och validera senast använda context efter appstart.
- [ ] Hantera avstängd, avslutad eller borttagen relation fail-closed.
- [ ] Lägg explicit logga ut från alla relevanta lägen.

#### 3C. Verifiering

- [ ] Widgettesta validering, pending, timeout, retry och avmonterad vy.
- [ ] Testa ny användare, återkommande användare, invite, väntrum och flera contexts.
- [ ] Testa web deep link, Android cold start/back och session restore.
- [ ] Verifiera att loggar aldrig innehåller e-post, lösenord, OTP eller token.

Godkänd när: en ny respektive återkommande användare kan nå korrekt kontext
utan blindväg och alla misslyckanden är begripliga, säkra och återhämtningsbara.

### Steg 4 – Hem

#### 4A. Informationsarkitektur

- [x] Bygg alla rollanpassade Home/Today-varianter med gemensam grund och
  vertikal kvalitetssäkring i ordningen ledare → spelare → guardian;
  klubbfunktionär hanteras capabilityanpassat där klubböversikt behövs.
- [x] Hem prioriterar: (1) saker som kräver åtgärd nu, (2) dagens aktiviteter,
  (3) Min assistent-poster via dess FAB, (4) nästa kommande event,
  (5) olästa meddelanden/notiser och (6) övrig överblick/genvägar.
- [x] "Kräver åtgärd" är rollanpassat: spelare/guardian ser främst obesvarade
  kallelser, medan ledare även kan se ofärdig trupp, ej utskickad kallelse och
  oregistrerad närvaro.
- [x] Gamla Watchpoints ersätts av Min assistent och flyttas inte över som
  separat funktion eller genom okritisk återanvändning av gamla trösklar.

#### 4B. Funktioner

- [ ] Visa tydlig datum-/Today-rubrik och aktiv/aggregerad kontext.
- [ ] Visa nästa relevanta event med tid, plats, lag och status.
- [ ] Visa obesvarade kallelser och rollanpassad svarsväg.
- [ ] Visa uppgifter som kräver ledaråtgärd, exempelvis närvaro eller callup.
- [ ] Visa Inbox-/notification-sammanfattning utan känslig låsskärmspayload.
- [ ] Ge tydliga genvägar till Calendar, EventDetails, Team och Inbox.
- [ ] Visa neutral tom dag i stället för en tom teknisk lista.
- [ ] Visa timestamp på stale data och erbjud retry/refresh.
- [ ] Säkerställ deterministisk deduplicering över flera contexts.
- [ ] Placera Min assistent som en flytande FAB längst ned till höger ovanpå
  Hem på mobil; FAB:en öppnar en kompakt assistentyta.
- [ ] Visa Min assistent som en integrerad eller beständig panel på
  tablet/desktop där skärmutrymmet tillåter, i stället för att kräva en FAB.
- [ ] Låt Min assistent formulera rollrelevant prioritering utan att visa
  ledardata för spelare/guardian eller annan otillåten kontext.

#### 4C. Verifiering

- [ ] Testa tom, laddar, delvis data, stale, fel och retry.
- [ ] Testa flera klubbar/lag samt varje beslutat rollpaket.
- [ ] Testa att varje action öppnar rätt explicit target.
- [ ] Genomför fysisk/hostad UX-genomgång efter lokal verifiering.

Godkänd när: Hem besvarar "Vad händer nu och vad behöver jag göra?" inom en
skärm för varje huvudroll.

### Steg 4D – Min assistent, datadrivet implementationsspår

- [x] Behåll den befintliga fail-closed grunden med deterministiska råfakta och
  avstängd generativ AI/känslig signalbehandling.
- [~] En lokal teknisk Assistant Coach-grund finns med rollanpassad copy,
  verifierbara råfakta och säkra loading/empty/error/retry-lägen. Den ska senare
  anpassas till den beslutade Min assistent-identiteten och områdesmodellen.
- [ ] Definiera signalmodell: ID/version, typ, prioritet, positiv/neutral/action,
  förklaring, datakällor, tidsfönster, beräknad tid, stale/missing och confidence.
- [ ] Definiera roll- och capabilityfilter per signal och föreslagen action.
- [ ] Definiera användarfeedback: hjälpsam/inte hjälpsam, dismiss/snooze och
  varför, utan rå känslig payload.
- [ ] Definiera första signalpaketet tillsammans innan trösklar implementeras.
- [x] Min assistent v1 ska under området Lagplanering prioritera följande första signalpaket:
  1. obesvarade kallelser;
  2. event som snart börjar men saknar färdig trupp eller utskickad kallelse;
  3. genomförda event där närvaro inte registrerats;
  4. positiva signaler, exempelvis komplett planering eller god svarsfrekvens;
  5. luckor i kommande planering, exempelvis en period utan aktiviteter.
- [ ] Definiera och godkänn transparent regel, tidsfönster, prioritet,
  datakällor, missing/stale-beteende och målroll för var och en av de fem signalerna.
- [ ] Implementera signal-fixtures för positivt, negativt, stale, missing,
  cross-context och nekad capability.
- [ ] Implementera action preview och uttrycklig bekräftelse genom vanliga
  domänkommandon; ingen autonom mutation.
- [ ] Skapa kill switch per signal och separat för framtida generativ formulering.
- [ ] Håll generativ AI blockerad tills leverantör, region, dataminimering,
  retention, minderårigdata, utvärdering och incidentflöde har godkänts separat.
- [x] Full datadriven Min assistent-implementation ska inte starta innan identitet,
  klubb/lag, roster och eventlivscykeln producerar stabil, verifierad data.
- [ ] Före dess får endast dataoberoende förberedelser göras: signal-/actionkontrakt,
  capabilitygränser, responsiv AC-ingång, testfixtures och kill-switchdesign.
- [ ] Aktivera ingen signal mot verklig produktdata förrän dess källdata,
  semantik, freshness och cross-context-isolering har klarat respektive domängrind.

Godkänd när: Min assistent ger transparent, rollrelevant och verifierbar
hjälp på Hem utan att Watchpoints gamla semantik eller autonoma actions återinförs.

### Steg 5 – Laget

#### 5A. Lagets grundsida och navigation

- [x] Lagets grundsida ska ha tre huvudflikar: `Översikt`, `Trupp` och
  `Händelser/Kalender`.
- [ ] Bevara vald lagflik vid responsiv ombyggnad och relevant navigation.
- [ ] Anpassa fliknavigationen för mobil, tablet och desktop utan att ändra
  flikarnas informationsansvar.
- [x] `Översikt` ska innehålla lagbild, lagets identitet/grundinformation,
  nästa aktivitet, rollanpassade saker som kräver åtgärd, kort
  truppsammanfattning, viktig laginformation och genvägar till Trupp,
  Händelser/Kalender, kallelser och Inbox.
- [ ] Visa en tillgänglig och responsivt beskuren lagbild med neutral fallback
  när bild saknas. Behörighet för uppladdning/byte/borttagning ska vara explicit.
- [ ] `Trupp` är ingången till rosterlistan och enskilda medlemsdetaljer.
- [x] `Händelser/Kalender` är en lista över lagets matcher, träningar, möten och
  andra event – inte en fullständig kalenderkomponent.
- [ ] Dela listan tydligt i kommande och tidigare händelser.
- [ ] Låt användaren filtrera på minst alla, matcher och träningar; övriga
  eventtyper ska kunna visas utan att en ny parallell typmodell skapas.
- [ ] Återanvänd samma kanoniska eventdata, statusregler, behörigheter och
  EventDetails som huvudkalendern.
- [ ] Använd stabil pagination och bevara valt filter/läge vid detaljnavigation.

#### 5B. Trupp och rosterlista

- [ ] Visa aktiva personer med roll, tydlig status och dataminimerade fält.
- [ ] Lägg sök, filter och sortering enligt fastställd paritetsmatris.
- [ ] Visa separata, begripliga tomlägen för tom trupp och saknad behörighet.
- [ ] Behåll explicit lagkontext och återladda säkert vid contextbyte.

#### 5C. Fas 1 – medlemsdetaljer och inbjudningar

- [x] Den enskilda medlemsdetaljen i fas 1 innehåller:
  - `Översikt`: bild, namn, roll, lagstatus och viktigaste tillåtna åtgärder;
  - `Kontakt och relationer`: tillåtna kontaktuppgifter, guardians och
    inbjudnings-/kontostatus;
  - `Lagbehörighet`: aktuell assignment, eventuella spelbara lag och
    giltighetsperioder.
- [x] Närvaro, matcher, statistik och historik tillkommer i fas 2 och blockerar
  inte medlemsdetaljens första leverans.
- [ ] Visa endast fält som aktuell capability och relation tillåter.
- [ ] Visa aktuell assignment/eligibility utan att skriva om gamla facts.
- [ ] Implementera skapa och redigera rosterperson med atomiskt kommando.
- [ ] Implementera avsluta assignment i stället för global destruktiv arkivering.
- [ ] Implementera invite/claim och guardianrelation med tydlig status.
- [ ] Placera skada/suspension och känsliga fält bakom separat beslutad grind.

Godkänd när: behörig användare kan läsa och underhålla grundrostern, öppna
medlemsdetaljer och hantera inbjudan/claim säkert. Import, statistik/historik
och grupper blockerar inte fas 1.

#### 5D. Fas 2 – import, statistik/historik och grupper

- [x] Import, statistik/historik och grupper genomförs efter fas 1.
- [ ] Implementera medlemsdetaljflikar för närvaro, matcher/statistik och historik.
- [ ] Visa historik utan att räkna om eller flytta gamla facts vid lag-/klubbbyte.
- [ ] Implementera återanvändbara roster-/squadgrupper enligt den nya datamodellen.
- [ ] Implementera CSV/XLSX-import med preview, kolumnmappning, radvalidering, dubblettkontroll,
  partiellt resultat och återkörningssäkerhet.
- [ ] Verifiera att import aldrig auto-mergar personer på namn/e-post.
- [ ] Verifiera cross-club-isolering, transfer, lån/gäst och guardianregler.

Godkänd när: en behörig ledare kan underhålla lagets roster utan att påverka
andra klubbars representation eller historiska facts.

### Steg 6 – Kalender och allt kring EventDetails

#### 6A. Kalenderyta

- [x] Kalenderns första fullständiga version ska innehålla agenda-, månads-,
  vecko- och dagsvy; ingen av vyerna skjuts till en senare fas.
- [ ] Implementera konsekvent vyväxling mellan agenda, månad, vecka och dag
  med bevarat valt datum, filter och context.
- [ ] Implementera periodnavigation, "Idag", filter och tydlig contextindikering.
- [ ] Visa flera contexts med dedupe och begriplig färg-/etikettkodning.
- [ ] Behåll stabil cursor/pagination och full resync efter reconnect.
- [x] Kalender-/filimport skjuts till en senare kalenderfas och blockerar inte
  den första fullständiga kalenderleveransen.

#### 6B. Skapa och redigera event

- [ ] Komplett formulär för typ, titel, start/slut, heldag, plats, lag och audience.
- [ ] Recurrence med begripligt scope: denna, denna och framåt, alla.
- [ ] Delade lag med serververifierade relationer/capabilities.
- [ ] Draft/scheduled/cancelled/completed med tydliga konsekvenser.
- [ ] Validera DST, övernattning, heldag och stale revision.
- [ ] Skydda osparade ändringar och double submit.

#### 6C. EventDetails

- [ ] Info: sammanfattning, plats, deltagande lag, audience och status.
- [ ] Trupp: draft, kandidater, grupper/alla/generator, lock och late callups.
- [ ] Kallelser: send, cancel, reminder, accepted/declined/pending och leveransstatus.
- [ ] Svar: player/guardian acting-as, decline reason och säker retry.
- [ ] Närvaro: unknown/present/late/partial/absent och revisionshistorik.
- [ ] Förberedelser: besluta vilka gamla planeringsfunktioner som ingår.
- [ ] Uppföljning: resultat/reflektion och länk till Match Space där relevant.
- [x] Personliga eventanteckningar och taktiska bilagor skjuts till en senare
  kalenderfas och blockerar inte den första fullständiga kalenderleveransen.

#### 6D. Verifiering

- [ ] Testa två samtidiga ledare, stale revision och idempotent retry.
- [ ] Testa delade lag, guardian, cross-team eligibility och nekad capability.
- [ ] Testa realtime, reconnect, background/resume och full resync.
- [ ] Genomför fysisk kalender→event→callup→attendance-genomgång.

Godkänd när: hela livscykeln planera → kalla → svara → närvaro → följa upp
fungerar utan parallella källor eller otydlig status.

#### 6E. Senare kalenderfas – import, anteckningar och taktiska bilagor

- [ ] Implementera kalender-/filimport med preview, fältmappning, validering,
  dubblettskydd, partiellt resultat och återkörningssäkerhet.
- [ ] Implementera personliga eventanteckningar med explicit ägare och visibility.
- [ ] Implementera taktiska bilagor med beslutad behörighets- och delningsmodell.
- [ ] Använd privat storage, kort signerad URL, förnyelse, orphan cleanup och retention.
- [ ] Testa återkallad access, avslutad relation, raderat event och cross-context-isolering.

### Steg 7 – Publik klubbsajt och lagens officiella kanaler

Den publika produkten ska fungera som klubbens professionella officiella ansikte
utåt och kunna ersätta behovet av en separat klubbhemsida. Klubben är sajtens
rot, varumärke och avsändare. Varje lag får en sida under klubbsajten som lagets
officiella kanal. Ytan byggs ovanpå verifierad klubb-, lag-, event-,
publicerings- och samtyckesdata. Den publika Next.js-ytan är separat från den
inloggade Flutterappen men hör till samma produkt- och redaktionsflöde.

#### 7A. Publiceringsmodell

- [x] En professionell publik klubbsajt med underliggande lagkanaler ingår i
  den grundläggande delen av TeamZone.
- [ ] Behåll nivåerna `private`, `listed` och `published`; nytt lag är private
  tills en behörig publicist gör ett aktivt val.
- [ ] Definiera separat publiceringsstatus för klubbens sajt och varje lagkanal;
  en publicerad klubbsajt får inte automatiskt publicera alla lag eller fält.
- [ ] Visa exakt vilka fält som blir publika före publicering och kräv
  revisionerad, auditerad bekräftelse.
- [ ] Publiceringsrätt styrs av explicit capability och får inte härledas från
  enbart rollnamn eller officiell klubbstatus.
- [ ] Avpublicering ska ta bort projektion/media och invalidatera cache inom en
  dokumenterad och testad tidsgräns.
- [ ] Den strukturellt avstängda publiceringsruntime aktiveras endast genom en
  separat uttryckligt godkänd releaseåtgärd.

#### 7B. Professionell klubbstruktur och navigation

- [x] Klubbens huvudnavigation ska innehålla `Start`, `Nyheter`, `Lag`,
  `Kalender/Händelser`, `Om klubben` och `Kontakt`.
- [x] Sponsorer/partners visas på startsidan och kan få en egen sektion när
  klubbens innehåll motiverar det.
- [ ] Ge klubben ett professionellt men kontrollerat visuellt uttryck med logotyp,
  klubbfärger, typografi, bildytor och responsiva redaktionella komponenter utan
  att tillåta osäker fri HTML/CSS.
- [ ] Skapa tydlig global klubbnavigation, breadcrumbs och vägar mellan klubb,
  nyhetsartikel och lagkanal på mobil och desktop.
- [x] Skalbar standardadress är `teamzoneapp.se/{klubbslug}` med lagkanaler
  under `teamzoneapp.se/{klubbslug}/lag/{lagslug}`.
- [x] Egen klubbdomän, exempelvis `www.klubbnamn.se`, är det första
  premiumalternativet och kräver verifierat domänägarskap.
- [x] `{klubbslug}.teamzoneapp.se` är ett senare premiumalternativ och får inte
  lanseras genom manuell per-klubbanslutning i nuvarande hostingmodell.
- [ ] Inför TeamZone-subdomäner först efter verifierad wildcard-DNS/TLS,
  automatisk hostname→klubb-routing, skydd mot slug-/hostövertagande,
  automatiserad aktivering/rollback samt kapacitets- och kostnadsgrind.
- [ ] Endast en adress är kanonisk för SEO; alla andra godkända adresser
  omdirigerar permanent till den kanoniska.
- [ ] Pris, paketnivå och exakt entitlement för premiumdomäner beslutas senare
  och får inte hårdkodas i publiceringsmodellen.
- [x] Varje lag får en sida under klubbsidan som lagets officiella kanal med
  översikt/lagbild, lagets nyheter, kommande/tidigare publika händelser,
  valfri publik trupp och kontaktväg.
- [ ] Visa endast allowlistad public projection med publik slug/opaque ID;
  interna ID:n eller privata relationer exponeras inte.
- [ ] Använd lagbild och annan media endast när en explicit publik variant har
  publicerats; privat signed URL får aldrig bli permanent publik.
- [ ] Händelser återanvänder kanonisk eventdata men visar endast fält och
  eventtyper som lagets publiceringsinställning uttryckligen tillåter.
- [ ] Minderårigs namn, bild, position och individuell statistik är separata
  samtyckes-/policyfält och dolda som standard.
- [ ] Officiell/inofficiell klubbstatus visas tydligt och får inte förväxlas med
  att en viss lagsida eller personuppgift är godkänd för publicering.

#### 7C. Nyheter och redaktionellt arbetsflöde

- [ ] Behöriga klubbpublicister ska enkelt kunna skapa, förhandsgranska,
  schemalägga, publicera, uppdatera och avpublicera nyheter.
- [ ] Nyheter får explicit scope: hela klubben eller en/flera valda lagkanaler.
- [ ] Editor ska stödja rubrik, ingress, strukturerat brödtextinnehåll,
  huvudbild, bildtext, alt-text, publiceringstid och författar-/avsändarvisning.
- [ ] Autospara utkast, skydda osparade ändringar och bevara revisioner samt
  auditspår för publicering och avpublicering.
- [ ] Tillåt endast säkra, strukturerade innehållsblock och allowlistade länkar;
  fri osanerad HTML eller script får aldrig publiceras.
- [ ] Skapa professionella nyhetslistor och artikelsidor med pagination,
  relaterat lag/klubb, delningsmetadata och tillgänglig bildhantering.
- [ ] Avpublicerad eller framtidsschemalagd nyhet ska omedelbart försvinna ur
  publika projections, sök, sitemap och cache enligt den beslutade SLA:n.

#### 7D. Publik säkerhet, kvalitet och drift

- [ ] Dedikerat allowlistat server-API med limits, prefix-/enumerationsskydd,
  rate limiting och neutrala fel; inga breda anon-grants på privata tabeller.
- [ ] Kontaktformulär, om det ingår efter innehållsbeslut, kräver CAPTCHA,
  exakt origin, abuse-skydd, leveransstatus och fast retention.
- [ ] Implementera kontrollerad cache och exakt invalidation vid publicering,
  samtyckesåterkallelse och avpublicering.
- [ ] Verifiera professionell visuell kvalitet samt responsivitet, tangentbord,
  skärmläsare, SEO metadata, sitemap/robots, social preview och security headers.
- [ ] Testa hidden/private/listed/published, återkallat samtycke, borttagen
  media, wildcard enumeration, scrapinggränser och okänd slug.
- [ ] Verifiera publika lagsidor på mobil och desktop/web före separat aktivering.

#### 7E. Senare publik fas – liverapportering från match

- [x] Publik liverapportering ska i en senare fas kunna öppnas från respektive
  lagkanal och från klubbens match-/Kalender/Händelser-ingång.
- [ ] Skapa en separat, dataminimerad och read-only publik matchprojektion;
  den interna Match Space-kommandoytan eller dess privata data exponeras aldrig.
- [ ] Definiera vilka matchfakta som får visas live: status, klocka/period,
  ställning, publika händelser, laguppställning och spelarnamn kräver separata
  publicerings-/samtyckesbeslut där det är relevant.
- [ ] Definiera fördröjning, rättelser/void, reconnect, stale-indikering,
  avslutad match, cache/invalidation och trafik-/scrapingskydd.
- [ ] Ge publicist/matchledare en explicit kill switch som omedelbart stoppar
  publik livefeed utan att påverka den interna matchrapporteringen.
- [ ] Testa minderårigdata, återkallat samtycke, felaktig händelse, hög trafik,
  tappad anslutning och avpublicerad match.

Godkänd när: en klubb kan använda TeamZone som sin professionella officiella
webbplats, publicera nyheter enkelt och ge varje lag en tydlig officiell kanal,
utan att privata fält, minderårigdata, interna identifierare eller privat media
kan exponeras genom klient, API, cache eller sökmotor.

### Steg 8 – Inbox och notification center

#### 8A. Trådmodell och inboxlista

- [ ] Bekräfta trådtyper: team chat, leader chat, group, direct och announcement.
- [x] Team chat och leader chat ska skapas automatiskt när ett lag skapas.
- [ ] Gör det automatiska skapandet atomiskt/idempotent så att varje lag får
  exakt en aktiv team chat och en aktiv leader chat utan dubbletter.
- [ ] Härled deltagande dynamiskt från aktiva, tillåtna relationer och
  capabilities; avslutad relation ska stoppa fortsatt sendaccess.
- [ ] Definiera beslutad historikaccess separat från rätten att skicka nya meddelanden.
- [ ] Visa titel, senaste säkra preview, tid, unread, mute och requeststatus.
- [ ] Implementera cursorpagination/infinite scroll för trådar och meddelanden.
- [ ] Implementera sök/filter om det prioriteras i paritetsmatrisen.
- [ ] Full resync vid reconnect, app resume och contextbyte.

#### 8B. Skapa och använda tråd

- [ ] Compose väljer explicit trådtyp och target scope.
- [ ] Recipient search, create, participant add och send använder samma serverregel.
- [ ] Implementera group participantval med safeguardinggränser.
- [x] Announcement/broadcast och samlat notification center ingår direkt i
  samma Inbox-etapp, inte som ett senare delsteg.
- [ ] Implementera announcement/broadcast som envägsinformation med separat
  readmodell; mottagarsvar får inte skapa implicit massdistribution.
- [ ] Implementera send, pending, retry med samma idempotency key och säker feltext.
- [ ] Implementera read state, markera alla och synk mellan enheter.
- [ ] Implementera mute/opt-out fail-closed.
- [ ] Implementera recall/version, report, block och modereringsstatus.
- [ ] Behåll rate-limitad cross-club leader request med accept/reject/block.

#### 8C. Bilagor och notifications

- [ ] Visa uploadprogress, tillåtna typer/storlek, cancel och säkert retry.
- [ ] Bind fil till tråd/meddelande och hantera orphan/withdrawn/retention.
- [ ] Skapa samlat notification center för messages, announcements, callups och events.
- [ ] Implementera korrekt readmodell per notificationtyp och "markera alla".
- [ ] Definiera badgekontrakt och minimal pushpreview.
- [ ] Ge användaren tydliga notification-/muteinställningar.

#### 8D. Verifiering

- [ ] Testa leader, player och guardian recipientregler.
- [ ] Testa avslutad relation, leave/hide, mute, block och report.
- [ ] Testa offline/reconnect, pagination utan dubbletter och missed-event resync.
- [ ] Testa bilaga efter recall/retention samt att signerad URL kan förnyas.
- [ ] Genomför fysisk två-/flerkontogenomgång.

Godkänd när: meddelanden är snabba och begripliga men ingen gammal tråd,
godtycklig profilidentifierare eller stale klient ger utökad access.

### Steg 9 – Samlad kvalitets- och releasegrind för grundappen

- [ ] Kör formattering, statisk analys och full Fluttertestsuite.
- [ ] Kör kontrakt för localization, a11y, navigation, privacy och capabilities.
- [ ] Bygg web och Android debug/audit utan att produktionsprovisionera.
- [ ] Testa hela resan: konto/login → context → Hem → Laget → Kalender → Inbox.
- [ ] Testa svenska/engelska, light/dark/system och större text.
- [ ] Testa telefon, tablet och web/desktop.
- [ ] Testa nätverksavbrott, timeout, retry, resume och session expiry.
- [ ] Dokumentera kvarvarande avvikelser och länka verifieringsevidens.
- [ ] Produktägaren godkänner eller återöppnar varje huvudsteg.

Godkänd när: de prioriterade ytorna fungerar som en sammanhängande grundapp och alla
öppna avvikelser är uttryckligt beslutade, inte bara okända.

## 6. Fastställda produktbeslut

Följande frågor har gåtts igenom och beslutats tillsammans:

1. `[x]` Konton ska erbjuda både lösenord och e-postkod/magic link.
2. `[x]` En ny användare ska kunna skapa klubb/första lag direkt, med skyddade
   namn och TeamZone-godkänd officiell status.
3. `[x]` Alla Home-varianter ska byggas; gemensam grund och vertikal ordning
   ledare → spelare → guardian rekommenderas för bäst kvalitet och återbruk.
4. `[x]` Laget delas i två faser. Fas 1 omfattar roster, medlemsdetaljens grund
   och inbjudningar. Fas 2 omfattar import, statistik/historik och grupper.
5. `[x]` Kalender ska ha agenda-, månads-, vecko- och dagsvy direkt.
6. `[x]` Personliga eventanteckningar och taktiska bilagor läggs till i en
   senare kalenderfas.
7. `[x]` Team chat och leader chat skapas automatiskt när laget skapas.
8. `[x]` Announcement/broadcast och samlat notification center ingår direkt i
   samma Inbox-etapp.
9. `[x]` Watchpoints ersätts av Min assistent. Första signalpaketet under Lagplanering omfattar
   obesvarade kallelser, ofullständig trupp/kallelse inför nära event,
   oregistrerad närvaro efter event, positiva planerings-/svarssignaler och
   luckor i kommande planering.
10. `[x]` Både web och Android verifieras efter varje färdig huvudyta.

## 7. Fastställd arbetsordning

1. Fastställ planen och slutför den verifierade paritetsmatrisen.
2. Gemensam klientgrund och uppdelning av appytorna.
3. Inloggning/Skapa konto, officiella klubbar, klubb-/lagskapande och anslutning.
4. Laget fas 1: grundsida, roster, medlemsdetaljer och inbjudningar.
5. Kalender/EventDetails: events, trupp, kallelser, svar och närvaro.
6. Publik klubbsajt och lagkanaler ovanpå stabil klubb-/lag-/eventdata och publiceringssamtycken.
7. Inbox, automatiska chattar, announcement/broadcast och notification center.
8. Rollanpassat Hem ovanpå de stabila domänflödena.
9. Min assistent: identitet/personligt namn, specialistområden, mobil-FAB, tablet/desktop-panel och de fem första Lagplanering-signalerna.
10. Laget fas 2 samt senare kalenderfunktioner/import.
11. Samlad grundappsgrind på web och Android.

Motivet är att identitet/context först måste styra all behörighet och att Laget,
Kalender måste därefter skapa stabil, korrekt och tidsmärkt data. Den publika
klubbsajten och lagkanalerna byggs på dessa kanoniska källor innan Inbox
färdigställs. Hem kan sedan
prioritera verkliga användarbehov. Min assistent byggs efter dessa
dataproducerande flöden så att signalerna reagerar på verifierad produktdata i
stället för konstruerade antaganden. Endast dess dataoberoende kontrakt och
säkerhetsgränser får förberedas tidigare.

## 8. Ändringslogg

| Datum | Ändring | Beslutad av |
|---|---|---|
| 2026-08-28 | Paraplynamnet fastställdes till Min assistent. Ett sportigt internationellt standardnamn väljs senare och användaren får välja eget privat namn. En gemensam kärna/kö får specialistområden märkta med text, ikon och färg enligt separat målmodell. | Produktägaren |
| 2026-08-23 | Första utkast skapat från gammal dokumentation och rebuildens nuläge. | Ej fastställd |
| 2026-08-23 | Båda authmetoderna, direkt klubb-/lagskapande med namnskydd, roll-/situationsanpassning och Assistant Coach som ersättare för Watchpoints införda i arbetsplanen. | Produktägaren |
| 2026-08-23 | Första lokala Assistant Coach-modulen på Hem implementerad och verifierad; signalmodell/actions återstår. | Pågående implementation |
| 2026-08-23 | Laget delades i två faser; import, statistik/historik och grupper flyttades till fas 2. | Produktägaren |
| 2026-08-23 | Kalenderns första fullständiga version ska omfatta agenda-, månads-, vecko- och dagsvy. | Produktägaren |
| 2026-08-23 | Personliga eventanteckningar och taktiska bilagor flyttades till en senare kalenderfas. | Produktägaren |
| 2026-08-23 | Team chat och leader chat ska skapas automatiskt och följa aktiva relationer dynamiskt. | Produktägaren |
| 2026-08-23 | Announcement/broadcast och samlat notification center lades direkt i Inbox-etappen. | Produktägaren |
| 2026-08-23 | Första signalpaketet för Assistant Coach fastställdes på produktnivå; exakta regler återstår. | Produktägaren |
| 2026-08-23 | Både web och Android ska verifieras efter varje färdig huvudyta. | Produktägaren |
| 2026-08-23 | E-postverifiering, neutral lösenordsåterställning och plattformsanpassad sessionspolicy godkändes. | Produktägaren |
| 2026-08-23 | Versionerade villkor/integritetsbekräftelse och separata frivilliga samtycken godkändes. | Produktägaren |
| 2026-08-23 | Hem-prioriteringen godkändes; AC ska vara FAB på mobil och integrerad panel på tablet/desktop. | Produktägaren |
| 2026-08-23 | Lagets grundsida fick huvudflikarna Översikt, Trupp och Händelser/Kalender. | Produktägaren |
| 2026-08-23 | Lagöversikten kompletterades med lagbild; Händelser/Kalender definierades som filtrerbar lista med kommande/tidigare event. | Produktägaren |
| 2026-08-23 | Medlemsdetaljens fas 1 fastställdes till Översikt, Kontakt och relationer samt Lagbehörighet. | Produktägaren |
| 2026-08-23 | Kalender-/filimport flyttades till en senare kalenderfas. | Produktägaren |
| 2026-08-23 | Inbjudan och godkänd medlemsansökan fastställdes som vägar till befintlig klubb/lag. | Produktägaren |
| 2026-08-23 | TeamZone-styrd officiell klubbstatus, verifieringsansökan och normaliserat namnskydd godkändes. | Produktägaren |
| 2026-08-23 | Paritet definierades som spårbar praktisk användarnytta med Behåll/Förbättra/Senare/Ta bort. | Produktägaren |
| 2026-08-23 | Tidig AC-implementation avvisades; AC placeras efter stabil identitet, lag, roster, events och kommunikationsdata. | Produktägaren |
| 2026-08-23 | Publika lagsidor lades till som egen grundappsetapp efter stabil lag-/eventdata. | Produktägaren |
| 2026-08-23 | Målbilden utökades till en professionell publik klubbsajt som kan ersätta extern hemsida, med lagens officiella undersidor och redaktionellt nyhetsflöde. | Produktägaren |
| 2026-08-23 | Klubb-/lagstrukturen godkändes och publik matchliverapportering lades till som senare fas. | Produktägaren |
| 2026-08-23 | Domänmodell fastställd: path som standard, egen domän som första premium och TeamZone-subdomän senare bakom wildcardgrind. | Produktägaren |
| 2026-08-23 | Den uppdaterade arbetsordningen med publik klubbsajt godkändes och arbetsplanen fastställdes. | Produktägaren |
