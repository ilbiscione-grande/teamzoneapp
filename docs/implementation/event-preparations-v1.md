# Förberedelser v1 och enkelt Matchläge

Förberedelser är ett litet arbetsutrymme per event, inte ett planerings- eller
projektverktyg. Det finns ingen samlad status, procent eller "färdigförberett".
Bara enskilda punkter (material, uppgifter, agenda) kan bockas av.

## 1. Audit (före ändring)

| Område | Befintligt | Filer |
| --- | --- | --- |
| Event, typer | `core.events.event_type` ∈ training/match/meeting/activity, typade textfält (`training_focus`, `match_notes`, `meeting_agenda` …) | `s03_event_calendar`, `cal02_typed_event_fields…`, `calendar_models.dart` |
| Eventsida, flikar | `_EventDetailsPage` med Info/Deltagare/Förberedelser/Uppföljning. Förberedelser var en platshållare med knappar | `event_details_page.dart` |
| Deltagare | Kompakt lista, kallelser, närvaro, walk-in | `event_participants.dart`, `cal06–cal08`, `20260928104134_…walk_in…` |
| State/services | `StatefulWidget` + tjänstegränssnitt per domän (`CalendarServices`, `MatchServices`), Supabase-RPC:er i `api`-schemat, kritiska kommandon via edge-funktionen `critical-flow-command` | `calendar_services.dart`, `match_services.dart`, `measured_rpc.dart` |
| Behörighet | Central i databasen: `actor_can_read_event`, `actor_can_manage_event`, `actor_can_manage_event_roster`; klienten begränsar dessutom efter aktivt lagkontext (`_contextCanCoManage`) | `s03`, `cal03_shared_event_access` |
| Filer | Privat bucket `message-files`, stage → upload → aktivera, RLS på `storage.objects`, 120 s signerad URL | `s06_private_files…`, `msg06…`, `messaging_services.dart` |
| Realtime | Privata broadcast-ämnen med enbart "invalidate", klienten hämtar om | kalender (`calendar:club:`), meddelanden |
| Matchdata | **Match Space v2**: workspace, frusen trupp, append-only kommandolog (kommando-id = idempotens), fakta med målskytt/assist, versionshistorik, härledd ställning, 2–8 perioder, serverbaserad klocka (`started_at`/`paused_seconds`), periodankare | `s07_*`, `match_models.dart`, `match_space_dialog.dart` |
| Resultat/rapport | Direktresultat med orsak vid rättelse, matchrapport | `match_direct_result…`, `match_written_reports…` |
| Anteckningar/checklistor/uppgifter | Saknades (endast fritextfält på eventet) | – |

## 2. Gap-analys

- **Återanvänt:** eventbehörigheter, Match Space v2 (klocka, perioder, mål,
  målskytt/assist, rättelser, void, idempotens, audit), deltagar-/närvarodata
  som trupp, filmönstret från meddelanden, realtime-mönstret.
- **Ändrat:** trupplåsning krävde accepterade kallelser — nu accepterade
  kallelser + registrerad närvaro, och tom trupp är tillåten (okänd målskytt).
  Perioder 1–8 i stället för 2–8. Snapshot innehåller nu trupp, namn och
  `can_manage`. Match Space-dialogen ersattes av Matchläge.
- **Skapat:** förberedelsepunkter, anteckning, eventfiler med synlighet per fil,
  period-/formatkommando, tidskorrigering, matchanteckning, rättelse av
  minut/målskytt/assist (även efter slutsignal), per-event realtime-ämne.

## 3. Datamodell

`20260928150000_event_preparations_v1.sql`

- `core.event_preparation_items` — `kind` ∈ focus/material/task/agenda,
  `label`, `done`, `assignee_club_person_id` (endast task), `position`,
  `source` (`manual`/`module`) + `source_ref` för framtida moduler, `revision`.
- `core.event_preparation_notes` — en anteckning per event, `revision`.
- `core.event_files` — id, event, uppladdare, `object_key`, namn, MIME,
  storlek, `visibility` ∈ participants/leaders/selected, `state`
  staged/active/deleted, `created_at`. `core.event_file_viewers` för valda personer.
- Bucket `event-files` (privat, 20 MB, PDF/bild/text/Office).

`20260928150100_match_mode_v1.sql` — inga nya matchtabeller; nya kommandon på
v2-kontraktet: `configure_match_periods_v2`, `adjust_match_clock_v2`,
`record_match_note_v2`, `correct_match_event_v2`, faktatyp `note`.

## 4. Säkerhet

- Läsning följer `actor_can_read_event`, skrivning `actor_can_manage_event`
  (arkiverade event är skrivskyddade). Klienten döljer dessutom redigering i
  delade lagkontext utan samredigering.
- Filsynlighet kontrolleras i databasen **och** i RLS på `storage.objects`:
  *Alla* = alla som får läsa eventet; *Ledare* = hanterare av event/trupp samt
  aktiva ledar-/funktionärsuppdrag i eventets lag; *Valda* = kopplad person
  eller aktiv vårdnadshavare till vald person (ledare ser alltid).
  Ett känt id eller objektnamn ger ingen åtkomst; URL:er är signerade i 120 s.
- Mottagarlistan för "valda" returneras bara till ledare.
- Realtime-ämnet `event:live:<event>` bär ingen data och kräver läsbehörighet.

## 5. Samtidighet och nätverksfel

- Nya punkter och filer får klient-genererade id:n; omförsök skapar inga dubbletter.
- Redigering av text/ansvarig/synlighet använder `expected_revision`; vid
  konflikt laddas senaste versionen (anteckningen öppnas igen med användarens text).
- Bocka av är målvärdes-idempotent: två ledare som bockar samma punkt krockar inte.
- Matchkommandon har fasta kommando-id:n. Ett mål visas först när servern
  bekräftat det; "Försök igen" skickar exakt samma kommando.
- Ställningen härleds alltid från aktiva mål. "−" tar bort senaste målet för
  laget (eller loggad justering om ställningen kom från direktresultat), så
  resultat och målhändelser kan inte glida isär.
- Klockan räknas fram från servertider inklusive klockskillnad mot enheten;
  lämna/återvänd, appåterupptagning och realtime hämtar ny snapshot.

## 6. UI

- `event_preparation.dart`: sektioner per typ — Träning: fokus, anteckningar,
  material, uppgifter, filer. Match: *Öppna matchläge*, matchförberedelse,
  material, uppgifter, filer. Möte: agenda (dra för att sortera), uppgifter,
  anteckningar, filer. Övriga: anteckningar, uppgifter, filer.
- Tomma sektioner är en rad med "+ Lägg till"; läsare ser inte tomma sektioner.
- `match_mode_page.dart`: resultat, klocka och period, start/paus/fortsätt,
  +/− per lag, målskytt → assist (tre tryck), motståndarmål med "Ångra",
  händelselista med redigera/ta bort, kompakt trupp som kan fällas ut,
  matchformat och tidskorrigering.
- Svenska texter direkt i widgetarna, som i den nya Deltagare-fliken.

## 7. Framtida utbyggnad (ej byggt)

- Träningsmodul: kan skriva fokus/pass som `source = 'module'` med
  `source_ref`, och visa ett "Träningspass"-kort i Förberedelser.
- Matchmodul: bygger vidare på samma workspace/fakta (byten, kort,
  uppställning, speltid, statistik finns redan som faktatyper/planfält).
- Motståndartrupp: `match_facts.club_person_id` är null för motståndarmål.
- Städning av filer som aldrig slutförts (staged) och storage-objekt efter
  borttagning sker bäst effort i klienten; ett schemalagt städjobb liknande
  meddelandefilernas kan läggas till.
- Gamla typade eventfält (`training_focus`, `match_notes`, `meeting_agenda`)
  visas fortfarande under Info och migreras inte automatiskt.

## 8. Verifiering

- `node supabase/tests/event_preparations.local.mjs` (PGlite, hela S07-kedjan
  + båda migrationerna): punkter, idempotens, konflikter, sortering, förslag,
  anteckning, läsbehörighet/utomstående/arkiverat, filstaging, synlighet i RPC
  och storage-RLS, vårdnadshavare, borttagning, realtime; matchformat,
  walk-in-trupp, idempotenta mål, truppvalidering, rättelser även efter
  slutsignal, tidskorrigering, anteckningar, void, perioder, behörighet.
- `flutter test test/prep01_event_preparation_test.dart` (390 × 844):
  träning, möte, match, filsynlighet, läsbehörighet, konflikt, klocka efter
  återkomst, perioder, tidskorrigering, format, misslyckat mål + omförsök.
- `flutter analyze`, hela `flutter test`.
