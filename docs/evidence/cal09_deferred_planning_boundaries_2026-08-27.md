# CAL-09 – gränser för senare planeringsfunktioner

Datum: 2026-08-27  
Omfattning: lokal app och kontrakt; ingen Supabase-liveändring.

## Genomfört

- EventDetails använder `EventPreparationAction` som explicit allowlist för de fullt fungerande flöden som får visas: Match Space för match, deltagarhantering när rollen har `manage_roster` och eventredigering när rollen har `revise`.
- Import, anteckningar, bilagor och träningsworkspace har inga knappar eller tomma destinationsytor i kärn-UX.
- `ProductRouteContract.calendarEvent` skapar en URL-kodad, kanonisk djuplänk där event-id förblir den stabila identiteten. Senare planeringsvyer kan därför läggas till som en underdestination/query utan att kalenderns eventkontrakt byts ut.
- Befintligt Match Space behålls eftersom det är ett verkligt, redan implementerat matchflöde; CAL-09 skapar inget nytt fullskaligt match- eller träningsworkspace.

## Verifiering

- `test/cal09_deferred_planning_boundaries_test.dart` verifierar action-allowlist, behörighetsstyrning, opaque event-id i route och frånvaro av uppskjutna affordances i kalenderytan.
- `flutter analyze --no-pub` startade men stannade efter `Analyzing TeamzoneApp...` utan diagnos och avbröts kontrollerat; analysresultat är därför inte godkänt för detta kort.
- Riktad Flutter-testkörning och fysisk responsiv kontroll kvarstår på grund av den observerade Flutter-verktygsblockeringen.

## Avgränsning

Ingen migration skapades och inget skrevs till Supabase live. Import, anteckningar, bilagor och ytterligare workspaces förblir uttryckligen senare arbete.
