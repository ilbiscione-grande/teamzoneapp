# Beslutspaket 11 – grunder för Match, Träning, IDP och Team Development Plan

**Status: godkänt av produktägaren 2026-10-23. MFD-01–MFD-16 är beslutade; MFD-14 ändrad så att Team Development Plan byggs före Träningsmodulen.**

## Mål

Bygga grunderna i appens fyra utvecklingsmoduler innan Tacticsboard kopplas till appen. Varje modul ska ha ett tydligt kärnobjekt som är användbart på egen hand och som Tacticsboard senare kan fästas vid, så att kopplingen inte behöver göras om när modulerna växer.

Paketet bygger på BED-06/07 (moduler per klubb, web tools med separat koppling), WID-01–07 (komplett grundapp, Match Space, Training Space, Development, web tools) och beslutet 2026-10-07 om att eventytan hålls enkel (`docs/implementation/event-kpis-followup.md`).

## Tre nivåer per område

Varje område i appen kan ha tre nivåer. Servern räknar ut vilken nivå en klubb har; appen visar den högsta och har alltid en fungerande nivå 1.

| Område | 1. Grundappen (alla klubbar) | 2. Appmodul (köps per klubb) | 3. Tacticsboard (web tool + koppling) |
|---|---|---|---|
| Uppställning | Lista: formation, startelva, avbytare, publiceringstid | Matchmodulen: spelarna på en enkel plan i appen | Uppställningen som tavla, ifylld från kallelsen och skriven tillbaka |
| Matchförberedelse | Text, filer, enkla mål per event | Matchmodulen: matchplan (spelidé, motståndare, fasta situationer) | Tavlor med animationer i matchplanen, livelektion med laget |
| Match live och efteråt | Enkelt matchläge, resultat | Matchmodulen: nyckeltalsräknare, händelser, spelartabell, rapport | Ingen roll |
| Träning | Tema, fokus och textplan per event | Träningsmodulen: pass med övningar, övningsbibliotek, utvärdering | Övningar ur tavelbiblioteket som kopior i passet |
| Individuell utveckling | Enkla utvecklingsplaner | IDP: mål, aktiviteter, avstämningar med historik | Tavla som illustration till ett mål |
| Lagets utveckling | – | Team Development Plan: säsongsmål, perioder, tillfälliga mål | Tavlor för spelprinciper och periodens fokus |

Tacticsboard ersätter det visuella och pedagogiska i en modul, aldrig modulens fakta. Vem som spelar, resultat, statistik, närvaro och planernas innehåll ligger kvar i TeamZones kärna.

## Gemensam modulgrund

- Rättigheter: `module.match_workspace`, `module.training`, `module.player_development` och `module.team_development`. Under betan är de öppna för alla klubbar genom samma rättighetsmodell som senare tar betalt (ingen separat betaväg i koden).
- Nivån räknas ut på servern per klubb och område, så att klienter bara frågar vad de ska visa. Rättigheten ersätter inte behörighet: lagrelation och capability avgör fortfarande vem som läser och ändrar.
- Modulernas kärnobjekt får **bilagor** genom en gemensam modell: typ (fil, bild, länk, senare tavla), titel, ordning, synlighet och ursprung. Tacticsboard blir då en ny bilagetyp utan nya tabeller per modul.
- Varje modul har revisionsnummer, visar vem som ändrat, och blir skrivskyddad (inte raderad) om klubben lämnar modulen (BED-05).
- Eventytan visar en kort projektion från modulen (t.ex. "Matchplan finns") men fungerar som idag utan den.

## Matchmodulen – grund

**Kärnobjekt: matchplanen**, en per matchevent.

- Spelidé, motståndaren, fasta situationer och nyckelpunkter i strukturerad text, med bilagor.
- Uppställningen visas på en enkel plan i appen (spelarna utplacerade enligt formationen, dragbara). Det är samma uppställning som i grundappen: en källa, aldrig två.
- Det som 2026-10-07 flyttades hit: live-räknarna för nyckeltal, de matchspecifika nyckeltalen och matchuppföljningen (resultat, händelser, spelartabell, rapport), ovanpå Match Space v2 (WID-02/03).
- Synlighet per del för spelare och vårdnadshavare, med publiceringstid som för uppställningen.

## Träningsmodulen – grund

**Kärnobjekt: träningspasset**, ett per träningsevent, versionerat.

- Pass med block i ordning: övningens namn, tid, organisation, coachpunkter och en plats för illustration.
- Övningsbibliotek per lag och per klubb. En övning läggs in i passet som en kopia med ursprung, så ändringar i biblioteket skriver inte över ett sparat pass (WID-04).
- Utvärdering efter passet. Valbar självskattning följer ACD-07 och blir aldrig ranking eller uttagningsunderlag.
- Grundappens tema, fokus och textplan finns kvar och kan bli passets utgångspunkt.

## IDP – grund

**Kärnobjekt: spelarens utvecklingsplan**, som byggs på dagens `development_plans` (spelare).

- Mål, aktiviteter och avstämningar med datum, historik och synlig aktör.
- Spelaren och ansvarig ledare arbetar i samma plan; vårdnadshavares insyn styrs av ålder och samtyckespolicy.
- Varje mål har plats för bilagor (senare tavlor).
- Hälsa och sanktioner ingår inte (deras specifikationsgrindar är öppna).
- Ett mål kan valfritt kopplas till ett mål i lagets Team Development Plan ("bidrar till").

## Team Development Plan – grund

**Kärnobjekt: lagets utvecklingsplan för en säsong**, byggd på `development_plans` (lag).

- **Säsongsmål**, långsiktiga för laget.
- **Perioder** inom säsongen med namn, datum och fas (t.ex. försäsong, tävling del 1, uppehåll). Varje period har **tillfälliga utvecklingsmål** och ett fokus.
- **Kortsiktiga mål** som inte hör till en period, t.ex. inför en viss match eller ett block av träningar.
- Spelprinciper och nyckeltal för laget, med återkommande avstämning.
- En periods fokus kan föreslås som utgångspunkt för träningspass och matchplaner i perioden. Förslaget ändrar aldrig redan genomförda event.
- Ersätter de tidigare separata begreppen Season Plan och Team Development i WID-05 med ett gemensamt kärnobjekt.

## Tacticsboard senare

Kopplingen av Tacticsboard till appen beslutas i ett eget paket när grunderna finns. Utgångspunkten är förslaget från 2026-10-22:

- TeamZones kärna äger fakta; Tacticsboard läser och skriver tillbaka via kommandon.
- Spelare ser publicerade, låsta versioner av tavlor, inte utkast.
- En gemensam koppling (modulernas bilagor) i stället för en integration per modul.
- Visning i appen via Webtools visare med förhandsbild och kortlivad visningsnyckel.
- Rättigheterna `webtool.tacticsboard` och `webtool.tacticsboard_link` (BED-07).

## Ordning

1. Gemensam modulgrund: rättigheter, nivåberäkning, bilagor.
2. Matchmodulen.
3. Team Development Plan (före Träning, så att perioderna kan föreslå fokus till passen från början).
4. Träningsmodulen.
5. IDP.
6. Beslutspaket och byggande för Tacticsboard-kopplingen.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| MFD-01 | Modulgrunderna byggs före Tacticsboard-kopplingen. | Beslutad |
| MFD-02 | Tre nivåer per område (grundapp, appmodul, Tacticsboard); servern räknar ut nivån per klubb och grundappen fungerar alltid. | Beslutad |
| MFD-03 | Fyra modulrättigheter: `module.match_workspace`, `module.training`, `module.player_development`, `module.team_development`; öppna under betan. | Beslutad |
| MFD-04 | Gemensam bilagemodell på modulernas kärnobjekt; Tacticsboard blir en bilagetyp. | Beslutad |
| MFD-05 | Matchmodulens kärnobjekt är matchplanen per matchevent. | Beslutad |
| MFD-06 | Uppställningen har en källa i kärnan; Matchmodulen och Tacticsboard visar och ändrar samma uppställning. | Beslutad |
| MFD-07 | Live-räknare, matchspecifika nyckeltal och matchuppföljning flyttas från eventytan till Matchmodulen. | Beslutad |
| MFD-08 | Träningsmodulens kärnobjekt är det versionerade träningspasset med block och övningsbibliotek; övningar kopieras in med ursprung. | Beslutad |
| MFD-09 | IDP byggs på dagens utvecklingsplaner med mål, aktiviteter och avstämningar; hälsa och sanktioner ingår inte. | Beslutad |
| MFD-10 | Team Development Plan är en ny modul: säsongsmål, perioder med tillfälliga utvecklingsmål, kortsiktiga mål, spelprinciper och avstämning. | Beslutad |
| MFD-11 | Team Development Plan ersätter de separata begreppen Season Plan och Team Development i WID-05. | Beslutad |
| MFD-12 | En periods fokus kan föreslås till träningspass och matchplaner men ändrar aldrig genomförda event. | Beslutad |
| MFD-13 | Ett IDP-mål kan valfritt kopplas till ett mål i lagets plan. | Beslutad |
| MFD-14 | Ordningen är modulgrund, Match, Team Development Plan, Träning, IDP, därefter Tacticsboard-kopplingen. | Beslutad med ändring |
| MFD-15 | Team Development Plan är en egen köpbar modul med rättigheten `module.team_development`. | Beslutad |
| MFD-16 | Team Development Plan byggs före Träningsmodulen. | Beslutad |

## Öppna frågor

- Vårdnadshavares insyn i IDP per ålder följer samtyckespolicyn; exakta åldersgränser är en parameter i `16_open_parameter_backlog.md`.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-10-23 | Förslag skrivet efter produktägarens önskan om modulgrunder före Tacticsboard-kopplingen, ordning Match, Träning, IDP och en ny modul Team Development Plan. | – |
| 2026-10-23 | MFD-01–MFD-16 godkända; Team Development Plan är egen modul och byggs före Träningsmodulen (MFD-14 ändrad). | Produktägaren |
