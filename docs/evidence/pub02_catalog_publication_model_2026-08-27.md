# PUB-02 – katalog och publiceringsmodell

Datum: 2026-08-27  
Omfattning: lokal migration och kontraktstest; ingen Supabase-liveändring.

## Genomfört

- Klubb och lag använder `private`, `listed` och `published`; tidigare S09-draft återgår säkert till private och kräver ett nytt aktivt beslut.
- `publication.manage` är en separat capability-grant. Befintliga klubbadministratörer får en explicit bootstrap-rad, men runtimekontrollen härleder aldrig rättigheten från rollnamn eller officiell status.
- Listed/published kräver att klubben är aktiv och `official`, en allowlistad fältmängd samt en revisionerad policybekräftelse som gäller högst 366 dagar.
- Bekräftelser är privata, RLS-skyddade och auditeras med actor, policyversion, fält, mode och expiry. En aktiv bekräftelse per aggregate tillåts.
- Expiry sätter ytan private och köar removal före cacheinvalidation. Projection-workern bygger endast när inställning, revision, mode, fält och aktiv bekräftelse matchar.
- Klubbkatalogen returnerar endast opaque public id, slug, namn, valfri ort och official-markör. Den behåller tre teckens prefixkrav, max tio träffar och befintlig pseudonymiserad rate limiting.
- Ingen personprojektion skapas. Fälten namn, bild, position och statistik kan därför inte läcka; framtida publik trupp kräver aktiva fältspecifika samtycken från S09-modellen.

## Säkerhetsgränser

- Alla nya tabeller har RLS och explicit revoke för `public`, `anon` och `authenticated`.
- Privilegierad kod ligger i `internal`, kontrollerar `auth.uid()`/capability och exponeras endast via en smal `api`-wrapper.
- Publiceringsruntime aktiveras inte av migrationen.

## Verifiering

- Statisk SQL-kontroll: 14 balanserade dollar-delimiters, inga felaktiga `end$$`-terminatorer och inga publika/anon-grants.
- `flutter test test/pub02_catalog_publication_model_test.dart --no-pub`: 3/3 godkända.
- PostgreSQL-runtime och advisors återstår eftersom lokal Docker/PostgreSQL-runtime saknas och tidigare CAL-02 blockerar den ordnade livekedjan.

## Reviderat produktbeslut 2026-09-25

Aktuell runtimeuppdatering: efter senare separat godkännande aktiverades
testprojektets publika runtime och riktiga klubb-/lagsidor verifierades.
Se [aktiveringsbevis](pub02_real_web_readiness_2026-09-25.md). Äldre uppgifter
nedan om avstängd runtime beskriver läget före detta godkännande.

Produktägaren har beslutat att varje klubb själv ska kunna aktivera en publik
klubbsida utan TeamZone-godkännande. Officiell verifiering ska enbart skilja
godkända klubbar från inofficiella; den ska inte vara en publiceringsgrind.
Klubben väljer vilka lag som får egna publika undersidor. Lagledare ska kunna
ansöka om en sådan sida och få beslut av klubben i appen. Produktägaren har
också uttryckligen beslutat att inofficiella klubbar ska kunna visas i den
publika klubbkatalogen när de själva valt `listed` eller `published`, med en
tydlig inofficiell markering. `private` ska förbli osynligt.

## Lokal implementation 2026-09-25

- Ny migration `20260925104508_pub02_self_service_club_team_pages.sql` tar bort
  officiell status som publiceringsgrind, men bevarar statusen som publik
  märkning. Den håller kvar fält-allowlist, årlig bekräftelse, revision,
  idempotens, projektion och rate limit.
- Endast klubbscopad `publication.manage` får aktivera klubb- eller lagsida.
  Lagledare med `team.roster.manage` får ansöka; klubbansvarig kan godkänna
  eller avslå och väljer därefter uttryckligen lagets synlighet. Ansökan
  publicerar aldrig automatiskt.
- Klubbkatalogen inkluderar även inofficiella klubbar som själva valt
  `listed` eller `published`. Katalogpost utan publicerad sida är inte länkad.
  Publika klubb- och lagsidor märks efter verklig verifieringsstatus.
- Flutter har sidan **Publika sidor** i navigationen för berörda roller.
  `private` förblir standard, och publicering kräver en aktiv bekräftelse.
- Flutter-analys och PUB-02/PUB-03-tester är gröna; public-site TypeScript och
  30/30 tester är gröna. Produktägaren gav separat godkännande till
  Supabase-testprojektet `hgcshgunvooyudvrcpig`. Migrationerna
  `20260925104508_pub02_self_service_club_team_pages` och
  `20260925105116_pub02_reproject_verification_status` samt
  `20260925105653_pub02_hide_listed_team_pages` är tillämpade där,
  och `critical-flow-command` version 8 är driftsatt med JWT-verifiering.
  Skrivskyddad kontroll bekräftar ny tabell, klubbscopad publiceringsgrind och
  katalog utan officiellfilter. Direkta lagsidelänkar kräver nu att både lag
  och klubb faktiskt är `published`; `listed` räcker inte. Muterande rolltest
  och fysisk appkontroll återstår.
  Publik runtime är fortfarande avstängd; externa klubbsidor öppnas inte av
  denna ändring. Webbplats/app är inte driftsatta externt.

Historiken ovan beskriver den ursprungliga PUB-02-leveransen; dess gamla
`official`-grind ersätts av denna nya migration när den väl driftsätts.

## Fysisk kontroll av klubbpublicering 2026-09-25

- En första lagpublicering nekades korrekt med `club_page_required` medan
  klubbsidan var privat. Appen visar nu klubb och lag i tydlig ordning och
  erbjuder inte publik lagsida förrän klubbsidan publicerats.
- Vid nästa försök svarade `configure_publication_v2` med HTTP 200 och
  skrivskyddad kontroll visade **Thomas klubb** som `published`, revision 1,
  med aktiv bekräftelse. Appen visade ändå ett generiskt sparfel. Någon ny
  skrivning eller ompublicering gjordes inte under felsökningen.
- Appflödet läser nu tillbaka publiceringsinställningen vid osäkert
  kommandosvar och jämför aggregate, revision, mode, slug och publicerade
  fält innan det visar utfall. Ett oklart läge presenteras inte längre som
  ett säkert misslyckande. Lokal hot reload, Dart-analys och HTTP 200 på
  testservern är verifierade; användarens nya visuella kontroll återstår.
- Produktägaren bekräftade att klubben visas som `published`; den tekniska
  statusen översätts nu i gränssnittet till **Publicerad**. Även lagens
  synlighet och ansökningarnas status har svenska etiketter. Dart-analys och
  lokal hot reload är verifierade. Produktägaren har därefter bekräftat att
  den svenska statusen visas korrekt.
- Produktägaren publicerade också **Thomas lag** via appen och bekräftade att
  det fungerade. Detta verifierar klubb-först-ordningen och ett lyckat
  publiceringsval för ett lag i testprojektet. Avpublicering, ansökan/beslut,
  katalog och publik webbvisning ingår inte i denna kontroll.

## Lokal robusthet och förberedelse för fysisk kontroll 2026-09-25

- Lagledarens menyval **Publika sidor** låg bakom en yttre kontroll som
  saknade `team.roster.manage`. Den kontrollen omfattar nu även lagledaren.
- Uppdatering efter kommandon returnerar inte längre en Future från
  `setState`; det tidigare beteendet gav ett Flutter-fel i debugläge.
- Ett lag med sparat `published` visas som dolt när klubben inte är
  publicerad. Klubbens dialog förklarar att lagens val sparas och att
  tidigare publicerade lag kan återkomma vid återpublicering, förutsatt
  giltig bekräftelse. Privata lag förblir privata.
- Ansökan och beslut har återläsning vid osäkert kommandosvar och egna
  resultattexter. Godkännande förklarar att klubben därefter måste välja
  publik synlighet. Dubblettansökan erbjuds inte vid väntande eller godkänd
  ansökan eller redan publicerat lag.
- Publiceringsvyn visar antalet väntande ansökningar för klubbansvarig.
  Detta är en upplysning i vyn, inte en levererad notis i notiscentralen.
- Synlighetsväljaren anpassas till dialogbredden. Klientens adressvalidering
  har samma maxlängd 80 som befintlig servervalidering.
- `flutter test test/pub02_self_service_surface_test.dart
  test/pub02_catalog_publication_model_test.dart --no-pub`: 9/9 godkända
  (5 widgettester och 4 befintliga SQL-kontraktstester). Widgettesterna
  verifierar klubbens av-/återpublicering med ny bekräftelse, dold lagstatus,
  ansökan och beslut efter förlorat svar samt godkänd lagledarstatus utan
  dubblettansökan. Tjänstelagret är fejkat; detta är inte databasrolltest.
  `flutter analyze --no-pub`: inga problem.
- Inga databasändringar, driftsättningar eller ändringar av publik runtime
  har gjorts i denna uppföljning. Ingen server lyssnade på port 5000 vid
  inventeringen. Befintliga lokala ändringar har bevarats.

### Fysisk kontroll på localhost:5000 – pågående

- Den uppdaterade Flutter-webbappen startades på localhost port 5000 mot
  testprojektet; HTTP 200 verifierades.
- Produktägaren bekräftade efter testinstruktionen för Thomas lag:
  ”Sidan är nu privat utan problem”. Lagets avpublicering är därmed
  användarverifierad i appen.
- Produktägaren bekräftade därefter att Thomas lag kunde återpubliceras
  enligt teststeget med ny publiceringsbekräftelse, sparande och uppdatering:
  ”funkar”. Lagets avpublicering och återpublicering är därmed fysiskt
  verifierade i appen.
- Produktägaren bekräftade även teststeget där Thomas klubb görs privat:
  klubben visar Privat och Thomas lag visas som dolt eftersom klubbsidan
  inte är publicerad, med lagets publiceringsval sparat.
- Produktägaren bekräftade därefter ”ja, funkar” på kontrollen att Thomas
  klubb återpubliceras med ny bekräftelse och att både klubb och lag visar
  Publicerad efter sparande och uppdatering. Klubbens av-/återpublicering
  och det tidigare publicerade lagets statusövergång är därmed fysiskt
  verifierade i appen. Ett separat privat lags oförändrade status,
  lagledaransökan och klubbens beslut återstår att kontrollera.

### Fysisk testordning – återstående steg verifieras separat

1. Som klubbansvarig: gör Thomas lag privat och kontrollera status efter
   uppdatering. Publicera sedan laget igen med ny aktiv bekräftelse.
2. Gör Thomas klubb privat. Kontrollera klubbens privata status och att
   Thomas lag anges som dolt med sparat publiceringsval.
3. Återpublicera klubben med ny bekräftelse. Kontrollera sparade statusar
   efter uppdatering. Ett separat privat lag ska förbli privat.
4. Som lagledare med `team.roster.manage`: öppna **Publika sidor** och ansök
   för ett privat lag. Kontrollera väntande status och att publicerings-
   och beslutsknappar inte erbjuds.
5. Som klubbansvarig: granska ansökan och avslå. Som lagledare: uppdatera,
   kontrollera avslaget och ansök på nytt. Godkänn den nya ansökan som
   klubbansvarig och kontrollera att laget fortfarande är privat tills
   klubben uttryckligen väljer publik synlighet.

Den avstängda publika runtimen innebär att dessa appsteg inte verifierar
extern webbvisning, katalog eller projektionsarbetarens hela livscykel.
