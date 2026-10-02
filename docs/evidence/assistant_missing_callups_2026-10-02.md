# Min assistent – saknade kallelser inom 48 timmar

Produktbeslut: användaren godkände den föreslagna 48-timmarsregeln 2026-10-02.

## Regel och presentation

`missing_callups` ingår i den befintliga ledarprojektionen. Uppgiften visas för
ägarlagets behöriga ledare när aktiviteten är `scheduled`, inte arkiverad,
startar **efter nu och senast om 48 timmar**, har `callups_required=true`
och inte har någon utfärdad kallelse. Enbart ett deltagarutkast räknas inte
som utskick. UTC-tidsstämplar jämförs mot serverns statement-tid.

Alla kallelsestatusar räknas som tidigare utfärdade, även avböjda och återkallade.
Återutskick av tidigare återkallade kallelser är en annan uppgift och ingår inte
i denna regel. Leveransfel efter kölagt utskick skapar inte en ny saknad-kallelseuppgift.

Kortet **Kallelser har inte skickats** erbjuder **Förbered kallelser**, som
öppnar den vanliga deltagarfliken. Samma filtrering mellan **Här och nu** och
**Mina uppgifter** gäller som i föregående leverans. Regeln skickar inget själv.
Uppgifterna hämtas på nytt genom de befintliga uppdateringsvägarna; ingen ny
bakgrundspollning eller push har införts.

## Undantag för kallelsefria aktiviteter

Info-fliken har inställningen **Kallelse behövs**, på som standard för nya och
befintliga aktiviteter. Behöriga eventredigerare kan stänga av den för just
den aktuella förekomsten, även i en återkommande serie. Avstängning döljer
endast denna planeringsuppgift: den återkallar inga kallelser och hindrar inte
att man senare skickar en kallelse manuellt. Övriga förekomster behåller sitt värde.

Inställningen sparas genom ordinarie `revise_event_v3` → V2 med revision,
idempotensnyckel, audit, eventhistorik och behörighetskontroll. Återförsök efter
förlorat svar använder samma nyckel och revision. Endast JSON-boolean accepteras.
En gammal klient som utelämnar fältet lämnar inställningen oförändrad.

## Databas och säkerhet

Migration: `20261002121840_assistant_missing_callups.sql`.

- Ny kolumn på det redan behörighetsstyrda eventet och utökad event-snapshot.
- Befintliga `events_owner_time_idx` och `callups_event_club_idx` täcker sökningen.
- Inga nya rättigheter, tabeller, publiceringsfält eller AI-aktiveringar.
- Migrationen är applicerad på det godkända auditprojektet `hgcshgunvooyudvrcpig`.
- Hosted transaktionstest av skapa → uppgift → undanta → uppgift borta passerar;
  testdata och outboxposter rullades tillbaka.
- Advisors före/efter är oförändrade: 55 förväntade INFO om privata RLS-tabeller
  och den befintliga varningen om leaked-password protection. Inga nya fynd.

## Tester

- PGlite kör de verkliga V2/V3-kommandona, snapshot och ledarprojektionen.
  Täcker exakt 48-timmarsgräns, redan startat, draft/completed/cancelled/archived,
  undantag, andra lag/klubbar, utskickade och återkallade kallelser, nekad capability,
  ej inloggad, revisionskonflikt, idempotens, historik och audit.
- 45 fokuserade Flutter-tester passerar. Nya tester täcker uppgiftskortets
  åtgärd, capability/undantag, Info-inställningen, återförsök med samma kommando
  och läsbehörighet i delat lag.
- Slutlig analys är ren och full Flutter-testsvit passerar **547/547**.
- Webbens releasebygge mot auditprojektet passerar.
- Android debugbygge mot auditprojektet passerar (befintlig Kotlin-pluginvarning).

Hosting och S25 har inte uppdaterats i denna leverans.
