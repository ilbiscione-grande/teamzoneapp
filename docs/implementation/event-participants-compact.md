# Kompakt deltagarlista

Implementerad i `lib/src/features/calendar/event_participants.dart`, som del av
befintliga `teamzone_app.dart`. Eventsidan skickar befintliga kalender- och
rostertjänster samt aktivt lags behörighetsgräns till vyn.

- 38 px normalrad, 28 px avatar, separat spelare/ledare och fast actionzon.
  Raden växer vid större textskalning.
- Sökning och åtgärdsmeny ligger över den scrollande listan. Alla spelare,
  alla behöriga, behörighetsgrupp, generator och samlad påminnelse finns kvar.
- Rad- och gruppval är lokala. Kalla-knappen sparar, låser och skickar genom
  befintliga revisionerade kommandon. Samma kommandonycklar används vid retry.
  Påbörjad sändning fryser urvalet för att inte ändra innehållet vid retry.
- Långtryck eller pil visar en inline-expansion åt gången. Profil och
  närvarosummering hämtas först då och cachas under vyns livstid.
- Efter sluttid/genomförande blir närvaro primär. Normala ändringar sparas
  direkt. Sena korrigeringar kräver befintlig extra behörighet och orsak.
  Bulkfrånvaro omfattar bara okända markeringar, med ursprungliga revisioner.
- Assistentknappens plats hålls fri från den nedre åtgärdsknappen.

## Närvaro utan kallelse

Migration `20260928104134_event_participants_walk_in_attendance.sql` ändrar
befintlig närvarofunktion. En person inom eventets klubb får registreras om
personen har en aktiv kallelse, är behörig enligt befintlig eventbehörighet
(lagmedlemskap/spelbehörighet), eller redan har närvarohistorik för eventet.
Aktörens befintliga mandat, sena korrigeringsgräns, revisioner, atomisk bulk,
idempotens och audit behålls. Inget kallelseutskick skapas.

Närvaroprojektionen inkluderar även personer utan kallelse. Summeringen
räknar unionen av kallelser och registrerad närvaro en gång per event.
Ingen anonym åtkomst eller ny tabellbehörighet tillkommer.

Migrationen aktiverades 2026-09-28 efter användarens godkännande i
TeamzoneApp-testmiljön (`hgcshgunvooyudvrcpig`). Utöver PGlite-testet
verifierades ett authenticated-anrop för en behörig deltagare utan kallelse:
närvaron sparades och syntes i eventprojektionen. Verifieringstransaktionen
rullades tillbaka. Inga kallelser skapades. Säkerhetsrådgivarens befintliga
anmärkningar var oförändrade efter migreringen.

Webbappen publicerades 2026-09-28 på `https://teamzoneapp-b02a2.web.app`
med Firebase Hosting, efter ett godkänt Flutter releasebygge mot samma
audit/testdatabas. Publicerad `main.dart.js` returnerade HTTP 200 och
matchade det lokala byggets SHA-256:
`88a4ba9a1cc1cf2d8562fc75aae415086ea8c60d01a208411e7ec64ae678ee08`.

## Datagränser

Visad statistik är befintlig total tränings-/matchnärvaro för laget,
inte senaste fem tillfällen. Senaste fem, position, tröjnummer och foton
saknas i de aktuella svaren och visas därför inte som exempeldata.
För dessa behövs ett behörighetsfiltrerat, helst batchat profil-/historiksvar.
Profil och statistik visas bara om deras befintliga backendbehörigheter medger det.
En attendance-only gäst utan rosterprofil har ingen verifierad lagroll i
nuvarande projektion och använder den befintliga gästspelarrepresentationen.

## Verifiering

- `flutter analyze --no-pub`
- `flutter test --no-pub test/cal11_event_details_page_test.dart test/cal08_atomic_attendance_test.dart test/cal07_callup_response_guardian_reminder_test.dart test/cal06_revisioned_participant_draft_test.dart`
- `node supabase/tests/event_participants_walk_in.local.mjs`

Widgettesterna omfattar mobilmått, meny, lokalt urval, samlat utskick,
knapp/radgesturer, cachead expansion, vårdnadshavare, påminnelser och närvaro.
SQL-testet verifierar även authenticated-anrop, nekad klubb-/aktörsgräns,
behörighet, atomisk konflikt, idempotens, statistik och sena korrigeringar.
