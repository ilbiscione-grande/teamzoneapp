# CAL-09 – gränser för senare planeringsfunktioner

Datum: 2026-08-27, slutverifierad 2026-09-20  
Status: genomförd och verifierad

## Genomfört

- EventDetails använder `EventPreparationAction` som explicit allowlist för de fullt fungerande flöden som får visas: Match Space för match, deltagarhantering när rollen har `manage_roster` och eventredigering när rollen har `revise`.
- Import, anteckningar, bilagor och träningsworkspace har inga knappar eller tomma destinationsytor i kärn-UX.
- `ProductRouteContract.calendarEvent` skapar en URL-kodad, kanonisk djuplänk där event-id förblir den stabila identiteten. Senare planeringsvyer kan därför läggas till som en underdestination/query utan att kalenderns eventkontrakt byts ut.
- Befintligt Match Space behålls eftersom det är ett verkligt, redan implementerat matchflöde; CAL-09 skapar inget nytt fullskaligt match- eller träningsworkspace.

## Verifiering

- `test/cal09_deferred_planning_boundaries_test.dart` verifierar action-allowlist, behörighetsstyrning, opaque event-id i route och frånvaro av uppskjutna affordances i kalenderytan.
- Senare samlad Flutter-analys och riktade EventDetails-/kalendertester är gröna.
- Fysisk telefon-, tabletresponsiv och desktop/webb-kontroll är dokumenterad i REL-02-matrisen och senare CAL-01/CAL-05-genomgångar. EventDetails, fliknavigation, rollgränser och responsiv layout fungerade utan att uppskjutna import-/antecknings-/bilage-/workspaceytor exponerades.

## Avgränsning

Ingen migration skapades och inget skrevs till Supabase live. Import, anteckningar, bilagor och ytterligare workspaces förblir uttryckligen senare arbete.
