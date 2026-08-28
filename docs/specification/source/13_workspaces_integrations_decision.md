# Beslutspaket 8 – workspaces och webtoolintegrationer

**Status: godkänt av produktägaren 2026-08-07. WID-01–WID-09 är beslutade; WID-09 återställdes till web tool efter förnyat produktbeslut.**

## Mål

Grundappen ska vara komplett för daglig lagverksamhet. Workspaces fördjupar appen och web tools kan fungera helt fristående. Integrationer ska höja kvaliteten utan att göra grundflöden beroende av en köpt produkt eller delad direktdatabas.

## Gemensam modulprincip

- Appmoduler köps per klubb enligt BED-06 och är tillgängliga för alla klubbens lag.
- Användaren behöver fortfarande rätt capability och lagrelation för att läsa eller ändra data.
- Varje workspace har ett tydligt kärnobjekt, revisionsmodell och export/read-only-läge efter downgrade.
- Grundappen visar en stabil projektion av moduldata men fungerar med tom/ingen modulprojektion.

## Match Space

- Det liveverifierade v2 command API:t och `match_commands` bevaras som serverkontrakt.
- Matchday roster fryses från skickade/accepted callups vid beslutad tidpunkt; sena ändringar är explicita revisioner.
- Score härleds från aktiva scoring events. Manuell korrigering är ett separat loggat adjustment, inte osynlig override.
- Matchtimeline är append-only i betydelsen att historik inte hard-deletas; fel rättas genom editrevision/void med actor och reason.
- Fulltime låser normala livekommandon. Unlock kräver särskild capability, reason och audit.
- Shared-match-rättigheter följer eventets explicita capabilities från ECD-01.
- Grundappens matchförberedelse kan läsa en förenklad projection men behöver inte Match Space.

## Training Space

- Grundappen behåller eventets enkla fokus, textplan, deltagarinfo och uppföljning.
- Training Space tillför versionerade sessionsplaner, media, enkel ritbräda, coachningspunkter, reflektion och valbar självskattning.
- Övningar från Tactics Board importeras som snapshots/referenser till en draft; externa ändringar skriver inte tyst över en sparad träning.
- Självskattning följer ACD-07 och får inte bli ranking eller automatiskt uttagningsunderlag.

## Season Plan och Team Development

- Season Plan har konfigurerbara perioder med datum, namn, mål/fokus och revision.
- En period kan projicera fokus till träningsdrafts men ändrar inte historiska events.
- Team Development äger lagmål, spelprinciper, KPI:er, initiativ och återkommande review.
- Workload-/attendance-signaler visas som referenser från signalmotorn; Team Development äger inte en parallell beräkning.

## Player Development

- Player Development äger IDP, mål, actions, check-ins och fleråriga projektioner.
- Statistikens facts ligger i gemensam statistikdomän; workspacet skapar inte kopior som egen source of truth.
- Spelare och behörig utvecklingsledare arbetar mot revisionerad plan med synlig actorhistorik.
- Health- och självskattningsdata visas endast enligt separata capabilities/policy.

## Webtoolintegration

- Web tools har egen tenant, auth och lagring när de körs fristående.
- Linking till TeamZone är en explicit, återkallelig integration mellan billing/tenantobjekt.
- Data delas genom versionerat API och events, aldrig genom att verktygen skriver direkt i varandras tabeller.
- Varje delat objekt har owner system, external ID, version, syncstatus och senaste fel.
- Importerade artifacts sparar provenance; write-back kräver separat capability och idempotent kommando.
- Unlink stoppar ny synk men raderar inte automatiskt lagligt bevarade snapshots/historik.

## Tactics Board och Video Analyzer

- Tactics Board äger avancerade boards, animationer, övningar och sessionsbibliotek.
- TeamZone kan bädda in/länka publicerade versioner och importera draft-snapshots till event/workspace.
- Video Analyzer äger originalvideo och annoteringsprojekt. Delning till TeamZone sker endast genom explicit publicerad clip/analysis projection.
- Media rights, samtycke, storage region, retention och export måste beslutas innan videointegration byggs.

## Matchpoolen

- Matchpoolen är ett fristående web tool med valbar TeamZonelänk.
- Verifierade ledare publicerar datumintervall, lag/nivå, geografi och kontaktväg.
- Kontakt kan använda den beslutade cross-club leader message request-modellen från MND-10.
- Publicering har expiry, rate limit, block/report och abuse moderation.
- Accepterad matchförfrågan kan föreslå ett eventdraft; den skapar inte event autonomt.

## Bokningssystem

Systemet är ett fristående, responsivt web tool som är lätt att nå direkt i webbläsaren. Det kan användas utan TeamZone och kan länkas till en TeamZoneklubb. EventDetails kan visa tillgänglighet, skapa bokningsrequest och läsa bekräftad bokning. Grundappen behåller fri text/plats och är därför fullt användbar utan verktyget.

Webverktyget äger resurs-, konflikt-, pris- och organisationslogik. TeamZoneintegrationen följer WID-06 med explicit linking, versionerade API/events, provenance och idempotenta kommandon; ingen direkt delad databasskrivning används.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| WID-01 | Grundappen är komplett; workspaceprojektioner är valfria förbättringar med tydlig tom fallback. | Beslutad |
| WID-02 | Match Space bevarar v2, härledd score, append-only historik och auditerad fulltime unlock. | Beslutad |
| WID-03 | Matchday roster fryses från callups och sena ändringar är explicita revisioner. | Beslutad |
| WID-04 | Training Space fördjupar grundeventet; externa övningar importeras som provenance-märkta drafts/snapshots. | Beslutad |
| WID-05 | Season Plan, Team Development och Player Development har separata kärnobjekt men delar facts/signaler. | Beslutad |
| WID-06 | Web tools har egen tenant/auth och integreras endast genom versionerade API/events med explicit linking. | Beslutad |
| WID-07 | Tactics Board äger avancerade artifacts; Video Analyzer delar endast explicit publicerade projections. | Beslutad |
| WID-08 | Matchpoolen använder verifierad ledarpublicering/message requests och skapar endast eventdraft efter accept. | Beslutad |
| WID-09 | Bokningssystemet är ett fristående web tool med valbar TeamZone-/EventDetails-integration; fri platsinfo finns kvar i grundappen. | Beslutad efter omprövning |

## Konsekvens

Paketet slutför PD-09 och ND-03–05/08:s produktgränser. Det gör att workspaces och web tools kan utvecklas oberoende utan att skapa parallella sources of truth i TeamZones kärna.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | WID-01–WID-09 godkända; WID-09 ändrad så att bokning är en klubbomfattande TeamZone-modul. | Produktägaren |
| 2026-08-07 | WID-09 omprövad och återställd: bokningssystemet ska vara ett fristående web tool för enkel webbläsaråtkomst. | Produktägaren |
