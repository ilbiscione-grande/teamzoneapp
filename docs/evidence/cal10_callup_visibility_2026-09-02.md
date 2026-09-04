# CAL-10 – ledarstyrd synlighet för kallelser

Datum: 2026-09-02  
Status: genomförd och fysiskt flerrollsverifierad

## Levererat

- Privat standardläge per event i `core.event_callup_visibility`.
- Revisions- och idempotensskyddat ledarkommando med audit-event.
- Serverfiltrering av trupp och kallelser till egen spelare/eget barn när delning är av.
- Delade namn och kallelsesvar när ledaren aktiverar inställningen.
- Närvaro, leveransstatus och påminnelsemetadata exponeras inte för deltagare.
- Ledarstyrning i EventDetails deltagarhantering.

## Verifiering

- Migration `20260902104510_cal10_callup_roster_visibility.sql` applicerad på testprojekt `hgcshgunvooyudvrcpig`.
- Korrigering `20260902115000_cal10_restore_callup_response_context_dependency.sql` gör CAL-07-hjälpfunktionen explicit efter upptäckt schema-drift i live-testdatabasen.
- Korrigering `20260902120500_cal10_restore_callup_reminder_columns.sql` återställer motsvarande CAL-07-kolumner idempotent.
- Tabellen och RPC-behörigheten verifierades efter applicering; inga event hade ändrat standardvärde.
- Modell- och migrationskontrakt täcks av `test/cal10_callup_visibility_test.dart`.
- `flutter analyze` gav ingen diagnostik men analysprocessen svarade inte inom den avgränsade kontrolltiden och avbröts.

## Fysisk flerrollsverifiering

Verifierad 2026-09-03 i webbappen mot testprojektet med eventet `Tranås Borta`:

1. Leader såg inställningen och kunde slå av och på den.
2. Player såg endast sin egen kallelse i privat läge och samtliga fyra kallade i delat läge.
3. Guardian såg endast valt barns kallelse i privat läge och samtliga fyra kallade i delat läge.
4. Player och guardian såg endast tillåten egen/barnets närvaroinformation och inga administrativa åtgärder.
5. Serverprojektionen verifierades separat i guardian-kontext: fyra kallade, fyra deltagare, en tillåten närvaropost och noll ledaråtgärder i delat läge.
6. Testeventet återställdes efter kontrollen till rekommenderat privat läge, revision 4.
