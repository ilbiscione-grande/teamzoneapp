# Nulägesrapport TeamZone – 25 oktober 2026

> Dokumentationen har därefter statussynkats mot denna genomgång. Se
> [aktuell leveransstatus](../implementation/current_status.md) för den levande
> sammanställningen. Avsnitt 6 nedan bevarar dokumentationsavvikelserna som
> konstaterades vid granskningen; uppdateringen innebär inte att kod- eller
> driftfynd har åtgärdats.

> Senare samma dag rättades språkregressionen och träningsvyerna lokaliserades.
> Se [rättningens evidens och verifiering](localization_modules_2026-10-25.md).
> Testresultat och språkfynd i denna rapport beskriver granskningstillfället
> före rättningen; aktuell status förs i den levande sammanställningen.

> Även Webtools fick senare ett CI-jobb. Den rena verifieringen rapporterade
> då kritiska Next.js-advisories för 16.3.8, vilket ledde till en lokal
> uppdatering av båda sajterna till 16.4.3. Se
> [CI- och säkerhetsuppföljningen](webtools_ci_2026-10-25.md). Npm-resultaten
> nedan bevarar den tidigare kontrollen och är inte ett intyg om driftsatt patchstatus.

Underlag: repot `C:\Dev\TeamzoneApp` vid commit `760dbe0`, dokumentationen i
`docs/`, läsande kontroller av Supabase-projektet TeamzoneApp, HTTP-kontroller av
sajterna och nya lokala analys-, test- och byggkörningar. Rapporten ändrar inga
produktbeslut. Ingen applikationskod, databas eller driftsättning har ändrats.

## Samlad bedömning

TeamZone är en omfattande beta med en långt utvecklad grundapp, publik
webbplats och flera byggda webbverktyg. Produkten har vuxit betydligt sedan
rapporten den 11 oktober: arbetsytor, matchmodul, lagets utvecklingsplan,
träningsmodul, bokningar, turneringar, matchpool och Tacticsboard finns nu i
koden. Påståendet att alla arbetsytor/webbverktyg fortfarande är uppskjutna är
inte längre en användbar nulägesbeskrivning.

Den största övergripande risken är att **byggt, driftsatt, verifierat och
godkänt för produktion inte följs åt i samma statusbild**. Det finns fortfarande
ingen provisionerad produktionsdatabas enligt miljömanifestet och listningen
av tillgängliga Supabase-projekt. Publika adresser används för testmiljön.
Flera manuella releasegrindar kvarstår i leveranskorten, samtidigt som vissa
av deras uppgifter om väntande migreringar redan är överspelade.

En aktuell regression är också bekräftad: Flutter-suitens språkgrind hittar
**64 olika texter utan engelsk översättning, på 76 ställen i 13 filer**.
De finns i matchmodulen, klubb-Hem och modulnavigationen. Detta gör
testkörningen underkänd även om övriga tester går igenom.

Min bedömning är därför: **bra underlag för fortsatt beta och styrd pilot,
men underlaget räcker inte för att godkänna en bred produktionslansering.**
Det är en bedömning av verifierings- och driftläget, inte ett påstående att
grundfunktionerna saknas.

## 1. Omfattning och säkerhet i slutsatserna

Genomgången omfattar appens samtliga funktionsområden på inventeringsnivå,
de tre aktuella kodbaserna, backendens kataloger och driftstatus samt
jämförelse med produktbeslut, leveranskort, tidigare evidens och runbooks.
Fördjupad kodläsning har gjorts i modulnavigationen, match-, tränings- och
lagutvecklingstjänsterna, publicering, autentisering, webbverktygens katalog,
biblioteksmodell och driftkonfiguration.

Detta är inte en rad-för-rad-granskning av all källkod eller en fullständig
penetrationstestning. Ingen ny inloggad manuell genomgång för varje roll och
enhet har genomförts. HTTP 200 bekräftar leverans av en sida, inte att dess
inloggade funktioner fungerar. Webbläsarverktygets öppning av sajten timeoutade;
ny visuell granskning kan därför inte redovisas. iOS, fysisk tillgänglighet,
e-postleverans, betalningsflöden och Android-push har inte provats på nytt.
Historiska manuella resultat märks som dokumenterad evidens, inte nya tester.

Det äldre repot `C:\Dev\TeamZone` finns kvar. Det är inte källa för den nya
greenfield-databasen enligt README. Det har identifierats som äldre system;
ingen ändring eller full revision av dess separata produkt har gjorts.

## 2. Appens faktiska funktionella nuläge

"Byggt" nedan betyder att funktionskod och tillhörande kontrakt finns. Det
betyder inte automatiskt produktionsgodkänt eller manuellt slutverifierat.

| Område | Vad som finns nu | Kvarstående gräns eller osäkerhet |
|---|---|---|
| Identitet och anslutning | Inloggning, återställning, session, inbjudan, medlemsansökan, skapande av klubb/lag, skyddade namn och villkorsacceptans. Separat följarkonto på publika sajten och konto på Webtools. | Flerrolls-, sessions-, e-post- och fysisk slutverifiering är inte samlat stängd i leveranskorten. |
| Hem och navigation | Rollanpassad Hem, kommande aktivitet, svar på kallelser, klubbvy, valbar femte navigationsknapp, responsiv navigation och tema. | Manuell helhetskontroll för ledare, spelare, vårdnadshavare med flera barn och klubbfunktionärer kvarstår i dokumentationen. |
| Lag och person | Trupp, roller, titlar, positioner, profilbilder, kontaktuppgifter, medlemskort, representation, flytt, arkivering och raderingsflöden. | Behörighetsöversynen är uttryckligen planerad, inte genomförd. |
| Kalender och aktiviteter | Kalenderlägen, serier, delning mellan lag, målgruppssynlighet, förberedelser, kallelser, påminnelser, närvaro, efterhandsrättningar och statistik. | Reconnect, samtidiga ändringar och full enhetsmatris behöver fortsatt acceptansevidens. |
| Inbox och kontakter | Direkt- och grupptrådar, anslag, bilagor, notifieringar, supportärenden, publika kontakttrådar och profilbilder. | Manuella tvåenhets-, fil-, modererings- och gallringsgrindar är inte samlat stängda. |
| Push | FCM-worker, enhetsregistrering, skyddade token och Android-åtgärder för kallelser och meddelandesvar. | Android-åtgärder har fysisk evidens från oktober. iOS återstår. Ny fysisk pushprovning ingår inte här. |
| Min assistent | Deterministiska uppgifter, kallelser, konflikter, förberedelser, uppföljning, preferenser, feedback och centrala avstängningar. | Generativ AI är fortsatt avsiktligt grindad. Assistenten ska inte beskrivas som en färdig generativ tränare. |
| Matchpool | Publik sökyta, karta, bevakningar, kontakt, avbokning och modereringsspår. | Leveranskortens väntande driftstatus behöver stämmas av med faktisk miljö och manuell provning. |
| Domare | Tillsättning, föreningsdomare, ansvarig, arvodes-/utbetalningsunderlag och rapportering. | Flödenas fullständiga manuella och behörighetsmässiga acceptans är inte samlat dokumenterad. Förekomst av underlag bevisar inte en aktiverad betalningsintegration. |
| Statistik och laget.se | Lag-/personstatistik och avgränsad närvaroexport via lokal agent. | Tillfällig integration med separat lokal komponent; agentens eget repo och verklig överföring har inte testats i denna genomgång. |
| Publicering | Klubb-/lagsidor, teman, klubbmärke, nyheter/bilder, admin, följande, kontakt och publikt match-live. | Publiceringsbeslutet har ändrats genom beslutspaket 12. Äldre text om enbart slutresultat måste läsas tillsammans med detta. |
| Ekonomi och styrelse | Intern ekonomi, historik, export, godkännanden och styrelsemandat; abonnemangs-/entitlementgrund. | PAR-FIN-03 och kommersiell produktionsaktivering är separata grindar. Intern ekonomifunktion är inte samma sak som en färdig betalningsprodukt. |

**Plattformar:** Flutter-webb är driftsatt. Android har separat test-app-id,
förberedd release-signering och dokumenterad fysisk pushprovning. Denna
genomgång har inte byggt ett nytt APK/AAB eller verifierat uppladdningsnyckeln.
iOS-runbooken anger fortfarande att appen aldrig byggts för iOS; Firebase-/APNs-
konfiguration, signering, TestFlight och fysisk iPhone-provning återstår.
Native desktop är inte ett v1-mål enligt README; desktopanvändning avser webb.

## 3. Moduler och arbetsytor jämfört med senaste beslut

| Modul/beslut | Verkligt läge | Bedömning mot dokumentationen |
|---|---|---|
| Gemensam modulgrund, paket 11 | Serverbaserad modulkatalog, åtkomstnivåer, beta och skrivskydd samt bilagemodell finns. Appen har en egen modulram med navigation och färgtema. | Byggt längre än README och slice-översikten anger. |
| Matchmodulen | Matchplan, delarnas synlighet/publicering, uppställning på plan, live, egna knappar och analysytor finns i `match_workspace/`. | Paket 11 har konkret implementation; full acceptans ska fortfarande skiljas från kodförekomst. |
| Publikt match-live, paket 12 | Publik live-route, klientvy och migreringar finns. Publicering har serverkontrakt. | Den äldre publiceringsgränsen är uttryckligen ändrad 24 oktober. Samtyckes- och skyddsregler behöver ingå i releaseprovningen. |
| Team Development Plan | Säsong, perioder, mål, spelprinciper, nyckeltal, avstämningar, delning och förslag till event/moduler finns. | Följer beslutet att bygga lagets plan före träning. |
| Träning | Versionerat pass med block, publicering, sammanhållen förberedelse, säsongsanknytning och ledarutvärdering finns. Senaste commit innehåller migreringen för mållistan. | Pass och utvärdering är byggda. Träningsbibliotekets ursprung har ändrats genom paket 13; ett eget nytt bibliotek i appen ska inte räknas som saknad beslutad funktion. |
| IDP | Äldre utvecklingsplansgrund finns. Arbetsytornas öppnare hanterar Match, Träning och Team Development Plan, men inte `module.player_development`. | Den nya fullständiga IDP-modulen är inte levererad. Ordningen ändrades i paket 13 så att Tacticsboard-kopplingen går före IDP. |
| Tacticsboard-bibliotek, paket 13 | Egna projekt, delat bibliotek, klubbdelning, klubbens lista, favoriter, metadata och versionsmodell finns. | Beslutshistoriken 25 oktober säger uttryckligen att steg 1–3 är byggda och steg 4 väntar. |
| Bibliotek → träningspass och appvisare | Ingen motsvarande biblioteksimport i `TrainingServices`; appkopplingen och visaren är inte redovisade som levererade. | Planerad fortsättning enligt paket 13, inte ett oavsiktligt regressionsfel. |

Modell för bilagor är inte detsamma som att alla fil-, bild- och taveltyper
har ett komplett användarflöde. Modulernas tjänster visar bland annat
länkhantering; full acceptans för alla bilagetyper är inte verifierad här.

## 4. Sajter, adresser och verklig driftsmiljö

Läsande HTTP-kontroller den 25 oktober gav följande:

| Adress | Resultat | Tolkning |
|---|---|---|
| `https://teamzoneapp.se` | 200, TeamZones nya startsida. | Kanonisk publik adress i nuvarande public-site-konfiguration. |
| `https://public.teamzoneapp.se` | 200, samma startsidetitel och storlek som huvuddomänen. | Fungerande alternativ adress; åtminstone `robots.txt` omdirigerar till kanonisk adress. |
| `https://app.teamzoneapp.se` | 200, Flutter-startdokument. | Reachable webbapp; miljömanifestet hänför adressen till audit. Ingen ny inloggad funktionskontroll. |
| `https://webtools.teamzoneapp.se` | 200, titel "Webtools". Saknar CSP och X-Frame-Options i svaret. | Äldre sajt, inte den nya Firebase-sajten enligt README och jämförelsen av HTTP-svaren. |
| Firebase-adressen för `teamzoneapp-webtools` | 200, titel "TeamZone Webtools", CSP och X-Frame-Options finns. | Den nya webbverktygssajten. Public-site är konfigurerad att länka hit. |

På huvuddomänen svarade `/klubbar`, `/matchpool`, `/integritet`, `/villkor`,
`/robots.txt`, `/sitemap.xml`, kontokonfiguration och katalogsökning efter demo
med 200. På nya Webtools svarade startsidan, inloggning, konto, bokningar,
turneringar, Tacticsboard, bibliotek, live och `/api/config` med 200.
`/tacticsboard/demo` gav **404**, vilket är avsiktligt: routens kod stänger
utvecklingsdemon i produktionsläge om inte `TACTICS_DEMO=1` är satt. Detta är
inte ett konstaterat driftsfel.

**Miljögränsen:** `ops/environments.json` har fortfarande produktion som
`not_provisioned` och saknar produktionsprojektref. Supabase-listningen visar
TeamzoneApp i `eu-west-1`, men inget TeamzoneApp Production i Stockholm.
Den publika sajtens CSP och konfiguration använder audit-projektet. Sajten är
alltså internetåtkomlig utan att en separat produktionsmiljö är färdig.

### Webbverktygens innehåll

- **Tacticsboard:** editor med objekt, formationer/trupp, tavlor/projekt,
  animation/tidslinje, mallar, delning, exportkod, livelektioner med ritning,
  chatt och frågor samt det nya biblioteket. Produktkatalogens formulering
  "Animationer, delning och export kommer härnäst" ligger efter koden.
- **Bokningshanterare:** organisationer, resurser, medlemsinbjudningar,
  bokningar, godkännande, serier, tillgänglighet och TeamZone-eventkopplingar.
- **Turneringsplanerare:** anmälan, klasser, organisatörer, grupper,
  schemaläggning, slutspel/resultatkontrakt och publik turneringssida.
  Katalogtexten säger fortfarande att grupper och schema kommer härnäst.
- **Video Analyzer:** planerad i katalogen, ingen motsvarande produkt-route
  eller implementation identifierad.

Webtools README beskriver framför allt portalgrunden och bokningsbetan;
den fungerar inte som full aktuell funktionsbeskrivning av verktygen.

## 5. Backend, dataskydd och drift

### Bekräftat med nya läsfrågor

- 173 tabeller i `core`, samtliga med RLS.
- 54 tabeller i `internal`, 10 i `audit` och 6 i `attendance_export`.
- Inga direkta SELECT-rättigheter för `anon` eller `authenticated` på dessa
  tabeller. Katalogkontrollen bekräftar åtkomstgränsen, men bevisar inte ensam
  att varje API-funktion gör korrekt individuell behörighetsprövning.
- 936 SECURITY DEFINER-funktioner i de kontrollerade applikationsschemana;
  ingen saknar inställd `search_path`.
- Åtta Storage-buckets, samtliga privata.
- 15 Edge Functions listades som ACTIVE. Det bekräftar deploymentstatus,
  inte att deras driftsatta källkod är identisk med varje lokal fil.
- Publiceringens runtime är aktiverad i audit.
- Notifieringskön innehåller 27 poster i `delivered` och 367 i `suppressed`.
  Senaste leveransen var 24 oktober. Det är backendens registrerade resultat,
  inte ny bekräftelse på mottagning på telefon. Suppression är inte i sig fel.
- Sju schemalagda jobb finns. Ingen körning var markerad som misslyckad i
  cron-loggens senaste 24 timmar. En lyckad cron-körning bevisar inte att
  varje efterföljande extern HTTP-leverans lyckades.

Automatisk gallring av Inbox-material är inte därmed bevisad:
`message-retention-worker` är driftsatt, men finns inte bland de sju
databasjobben. En eventuell extern schemaläggare har inte verifierats.
Kontrollera anrop, senaste verkliga gallringskörning och felövervakning inför
release; förekomst av worker-kod räcker inte som driftbevis.

### Avvikelser

**Migreringsloggen är åter ofullständig.** Repot har 389 SQL-migreringar,
databasloggen 387. Inga extra versioner finns i loggen, men dessa två saknas:

| Version | Innehåll | Nya kontroller |
|---|---|---|
| `20261022090000` | Begränsning av misslyckade lösenordsinloggningar. | Tabellen `internal.sign_in_failures` och funktionen `sign_in_attempt_allowed(bytea,bytea)` finns. |
| `20261128090000` | Avslut av inaktiv Tacticsboard-livelektion. | Kolumnen `last_activity_at` finns på `core.tactics_live_sessions`. |

Detta visar att viktiga objekt finns, men är **inte en fullständig
källkods-/trigger-/rättighetsjämförelse av hela de två migreringarna**.
Loggen får inte rättas eller migreringarna köras om blint. Kontrollera alla
objekt och funktionernas innehåll innan rättning. Denna rapport har inte
ändrat loggen.

Senaste loggade version är `20261218090000`. Migreringsnummer i november och
december förekommer redan i nuvarande kod och databas; de ska inte tolkas
som framtida leveransdatum.

**Supabase security advisors:**

- WARN: skydd mot läckta lösenord är avstängt. Detta behöver lösas inför
  produktion enligt befintlig authpolicy.
- WARN: `pg_net` ligger i `public`. Bedöm schemaflytt tillsammans med
  beroendena; varningen är inte bevis för en aktuell exploatering.
- INFO: 126 tabeller har RLS utan policy. Med denna API-baserade arkitektur
  och borttagna direkta tabellrättigheter är det inte automatiskt en brist.
  Lägg inte till breda policyer för att bara få bort informationsnotiserna.

**Performance advisors:** 245 foreign keys utan täckande index och 246
index utan registrerad användning. Detta är informationsfynd, inte uppmätta
prestandafel. Prioritera med realistiska datamängder och query plans;
skapa eller radera inte alla index mekaniskt.

## 6. Dokumentationen jämfört med verkligheten

| Dokument/uppgift | Avvikelse | Konsekvens |
|---|---|---|
| README och `slice_status.md`: S11/arbetsytor/webtools uppskjutet, Arbetsytor platshållare. | Tre moduler och flera separata webbverktyg har implementation nu. | Huvudstatus underskattar det som faktiskt är byggt. |
| Statusrapport 11 oktober: ingen CI. | `.github/workflows/ci.yml` finns med Flutter, SQL, Edge, public-site och Firebase. | Den gamla rapporten ska läsas som historisk. |
| Samma rapport: push skickas inte, enbart Android-felrapportering, debugsignering utan minifiering. | Push är dokumenterad och har leveransposter; webbfelkanal finns; releasekonfigurationen har upload key, minifiering och spärr för Play-bundle utan nyckel/produktionsmiljö. | Dessa äldre brister får inte kopieras till en ny åtgärdslista utan omprövning. Att signering är förberedd bevisar inte ett publicerat Play-bygge. |
| Samma rapport: kritiska npm-beroenden. | Nu låsta patchversioner och nya audits med noll fynd för båda sajterna samt Firebase-funktionernas produktionsberoenden. | De ursprungliga npm-fynden är inte aktuella i de granskade låsfilerna. |
| Leveranskortens sammanfattning och vissa POOL/REF-statusar. | Anger väntande migrationer som nu finns i databasloggen. | Skilj deployment från kvarvarande manuell provning och uppdatera status med datum. |
| Beslutspaket 11 respektive 13. | Paket 13 ändrar bibliotekets ursprung och ordning före IDP. | Den senaste uttryckliga ändringen gäller; detta är inte två samtidiga krav på olika bibliotek. |
| Webtools produktkatalog. | Funktioner presenteras som kommande trots att kod för dem finns. | Risk för fel förväntningar; verifiera driftsatt funktion och synka sedan texterna. |
| Produktionsrunbook. | Tomdatabasreplay gäller 320 migrationer den 13 oktober; repot har nu 389. | Den tidigare replayen är värdefull historisk evidens, men bevisar inte att alla 389 går att köra på en ny databas. |
| Service- och miljöinventering. | Webbverktygens nya hosting och alla faktiska publika adresser framgår inte samlat. | Svårare att avgöra vilket system en länk eller felrapport gäller. |

Grundspecifikationernas ursprungliga snapshot bör bevaras. Lägg aktuell
leveransstatus i en daterad spårbar matris och länka till senare ändringsbeslut,
i stället för att skriva om historiska beslut till påståenden om dagens drift.

## 7. Kvalitet, verifiering och underhåll

Inventeringen räknar cirka 95 700 icke-tomma Dart-rader i `lib/`, 120
Dart-testfiler och 389 SQL-migreringar. Detta är inventeringsmått, inte
produktivitets- eller kvalitetsmått. UI-delar använder fortfarande ett stort
gemensamt `part`-bibliotek, samtidigt som modeller och tjänster är uppdelade i
egna bibliotek. Den äldre rapportens formulering att hela appen är ett enda
bibliotek är därför för grov.

Konkreta underhållsrisker:

1. **CI saknar Webtools-jobb.** Den nya sajten täcks inte av de typkontroller,
   tester, byggen och audits som CI kör för public-site. Den behöver samma
   grundläggande skydd.
2. **Språkkravet är inte uppfyllt i alla nya moduler.** Hela testkörningens
   språkgrind misslyckas på 64 olika saknade engelska översättningar (76
   förekomster i 13 filer) i matchmodulen, klubb-Hem och modulnavigationen,
   bland annat "Välj spelare", "Lägg till avbytare" och uppställningens
   spara-/konfliktmeddelanden. Nya modulvyer innehåller också hårdkodad svenska,
   exempelvis träningens
   Kommande/Tidigare, tomlägen och felmeddelanden. Att testet för
   `AppStrings.feature()` går igenom bevisar inte att dessa texter är
   översatta. Språkkravet behöver kontrolleras för de nya modulerna.
   `AppStrings.feature()` faller tillbaka till svenska i release och har en
   assert i debug; fyndet innebär därför inte att dessa texter automatiskt
   kraschar produktionsappen, men engelska gränssnittet är ofullständigt.
3. **Manuella godkännanden är utspridda.** Behörigheter, flera konton,
   tillgänglighet, samtidiga ändringar och mobil/tablet kräver en gemensam
   acceptansmatris med tydligt resultat och senaste kördatum.
4. **Migreringskedjan växer och loggningen släpar igen.** En ny replay från
   tom databas och schemadiff behövs för aktuell version inför produktion.
5. **Katalog-, status- och driftinformation ligger efter kodutvecklingen.**
   Det ökar risken att arbete dubbelbyggs eller att en otestad funktion
   uppfattas som färdig.

### Nya verifieringsresultat

Resultaten avser nya körningar för denna rapport, om inget annat anges.

| Kontroll | Resultat |
|---|---|
| Flutter statisk analys | Godkänd: inga analysfynd. |
| Flutter hela testsuiten | 808 godkända, 1 underkänt: språkgrinden i `fnd05_accessibility_localization_test.dart`. |
| Public-site typkontroll | Godkänd, inga TypeScript-fel. |
| Public-site tester | 94/94 godkända. |
| Public-site produktionsbygge | Godkänt. |
| Webtools typkontroll | Godkänd, inga TypeScript-fel. |
| Webtools tester | 54/54 godkända. |
| Webtools produktionsbygge | Godkänt. |
| Isolerade SQL-testfiler | Alla 84 `*.local.mjs` avslutades utan fel. De tre extra lägena för direktresultat, matchrapporter och följarnotiser passerade också. Vissa filer är hjälprunners; antalet är inte 84 enskilda assertions. |
| Firebase Functions tester | 8/8 godkända. |
| npm audit, public-site och Webtools | 0 kända sårbarheter i respektive kontroll. |
| npm audit, Firebase Functions | 0 i kontrollerade produktionsberoenden (`--omit=dev`). |
| PUB-06 smoke, `teamzoneapp.se` | Godkänd. |
| PUB-06 smoke, `public.teamzoneapp.se` | Avbryts på 308 från `/robots.txt`; testet kräver 200. Huvudadressens test passerar. Anpassa test eller dokumentera kanonisk adress, inte automatiskt ett sajtavbrott. |

De första Node-testförsöken stoppades av sandlådans processbegränsning
(`EPERM`). Ovanstående testresultat kommer från omkörning med rätt
processåtkomst. Flutter krävde åtkomst till SDK-cache. Inget har driftsatts
som del av verifieringen. En ny Flutter releasebyggnad, Android AAB,
iOS-byggnad eller full Edge/Deno-testkörning ingår inte i redovisade resultat.
npm-audits omfattar inte automatiskt Deno-funktionernas separata importer.

## 8. Rekommenderad ordning framåt

| Prioritet | Arbete | Klart när |
|---|---|---|
| 1 – före release | Rätta den bekräftade språkregressionen och granska hårdkodad svenska i de nya modulerna. | Hela Flutter-suiten passerar och nya modulvyer är verifierade på svenska och engelska. |
| 1 – före produktionsbeslut | Fastställ och genomför miljödelningen; slå på läckta-lösenordsskydd enligt policyn. | Produktionsprojekt, Auth, domäner, hemligheter, monitorering och återställning är verifierade enligt runbook. |
| 1 – före ny databasrelease | Jämför och rätta de två saknade migreringsposterna; gör en ny tomdatabasreplay av aktuell kedja. | Alla objekt är jämförda, loggen stämmer och en ny installation kan reproduceras. |
| 1 – före bred pilot | Slutför en samlad roll-/enhetsmatris och den beslutade behörighetsöversynen. | Ledare, spelare, vårdnadshavare, klubbadmin, ekonomi/styrelse och support har verifierade tillåtna och nekade flöden. |
| 2 – kvalitetsskydd | Ta in Webtools i CI och gör de nya modulerna förenliga med språkkravet. | Samma kvalitetsgrindar som public-site och verifierade svenska/engelska vyer. |
| 2 – drift och begriplighet | Synka README, slice-status, leveranskort och verktygskatalog; besluta om gamla Webtools-domänen. | En användare och en utvecklare kan entydigt hitta aktuell sajt och aktuell leveransstatus. |
| 2 – produktfortsättning | Fortsätt enligt paket 13 med biblioteksimport och visare, därefter IDP enligt beslutad ordning. | Versionerade kopior och publicerad läsning fungerar över app och Webtools utan att lagets fakta dubbleras. |
| 3 – kapacitet och förvaltning | Mät databasprestanda och minska stora UI-bibliotek stegvis när de berörs. | Mätbara flaskhalsar hanteras utan en stor ogrundad omskrivning. |

## 9. Viktigaste källorna i repot

- `README.md`, `ops/environments.json`, `ops/service_inventory.json`.
- `docs/implementation/slice_status.md`, `core_app_delivery_cards.md`,
  `core_app_parity_matrix.md` och `permissions-review.md`.
- Beslutspaket 11–13: `docs/specification/source/26_module_foundations_decision.md`,
  `27_public_live_match_decision.md`, `28_tacticsboard_library_decision.md`.
- `docs/operations/production_provisioning.md`, `push_notifications.md`,
  `android_release.md`, `ios_release.md` och `xops_release_runbook.md`.
- `docs/evidence/app_status_review_2026-10-11.md` och senare iterationsevidens.
- `lib/src/features/`, `public-site/app/`, `webtools/app/`,
  `webtools/lib/apps.ts`, `.github/workflows/ci.yml`,
  `firebase.json`, respektive sajts App Hosting- och Next-konfiguration.

Supabase-fyndens åtgärdsreferenser:
[lösenordsskydd](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection),
[extension i public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public),
[RLS utan policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
[foreign key-index](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys)
och [oanvända index](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).
