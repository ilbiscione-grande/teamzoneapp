# Produktvision och scope

## Vision

TeamZone Pro ska vara en tvåspråkig, rollanpassad fotbollsplattform för svenska föreningar. Grundappen ska göra vardagsarbetet kring lag, event, kallelser, meddelanden och närvaro enkelt. Mer avancerade behov ska aktiveras genom separata moduler och fristående web tools som integreras med samma klubb-, lag-, event- och personmodell.

## Grundprodukt

Grundappen har fem stabila huvudytor:

1. **Hem** – aktuellt event, nästa händelser och rollanpassade åtgärder.
2. **Laget** – lagidentitet, trupp, historik, kommande aktiviteter och tävlingar.
3. **Kalender** – alla event som personen berörs av, filtrerbara över roller och lag.
4. **Inbox** – lag-/ledarchattar, tillåtna grupper och direktmeddelanden.
5. **Statistik** – närvaro i basnivån och utökad match-/spelarstatistik genom moduler.

EventDetails och PlayerDetails är centrala sekundärytor. En publik klubb-/lagsajt är en separat webbyta men delar publiceringsmodell med appen.

## Rollprincip

En person kan samtidigt ha flera roller i flera lag och klubbar. Huvudrollerna i målbilden är:

- ledare;
- spelare;
- vårdnadshavare;
- klubbfunktionär/styrelse/administration.

Underroller beskriver funktion eller relation, exempelvis huvudtränare, lagledare, målvakt eller pappa. Platshållarprofiler ska kunna samla historik innan ett Auth-konto claimar rätt personkoppling.

## Produktlager

| Lager | Syfte | Exempel |
|---|---|---|
| Grundapp | Daglig lagverksamhet | hem, lag, kalender, inbox, närvaro, event/callup |
| Appmoduler/workspaces | Fördjupning inne i TeamZone | Match, Training, Season Plan, Team/Player Development, Economy/Board Room |
| Web tools | Fristående webbprodukter med valbar TeamZonekoppling | Tactics Board, Video Analyzer, Matchpoolen, bokning |
| Assistant Coach | Roll- och kontextmedvetet besluts-/åtgärdsstöd | påminnelser, trender, förslag och säkra actions |

## Affärsprincip

Spelare och vårdnadshavare ska inte betala. Grundnivån föreslås vara gratis för ett lag och högst 25 användare. Betalning skalar med lag/användare och kompletteras med moduler och web tools. Priserna i källdokumentet är hypoteser, inte fastställda krav.

## Icke-förhandlingsbara kvaliteter från auditen

- Authorization ska vara serverbaserad och tenantbunden.
- Svenska och engelska ska vara fullständiga från start.
- Minderårigdata och publik publicering kräver explicit policy/samtycke.
- Tokens, pushpayloads och persondata får inte läcka i loggar.
- Kritiska mutationer ska vara atomiska, idempotenta och auditerbara.
- Deep links, session, offline/reconnect och tillgänglighet ska ingå i releasegrinden.

