# CAL-05 – EventDetails informationsarkitektur

Datum: 2026-08-27  
Status: lokalt genomförd, fysisk verifiering återstår

## Levererat

- EventDetails har exakt flikarna `Info`, `Deltagare`, `Förberedelser` och `Uppföljning`.
- Info samlar tid, tidszon, plats, beskrivning, ägande/deltagande lag och eventets livscykelåtgärder.
- Deltagare sammanfattar samma auktoritativa squadprojektion för urval, kallelser, svar och närvaro och leder vidare till det fullständiga hanteringsflödet.
- Förberedelser anpassas efter eventtyp. Match visar Match Space; övriga event prioriterar deltagare och eventinformation.
- Uppföljning visar registrerad närvaro, Match Space för matcher och möjlighet att markera eventet genomfört.
- Ledaråtgärder visas endast när serverns `caller_actions` innehåller motsvarande capability.
- Saknad deltagaråtkomst visas som en begriplig låst status i stället för rått backendfel.

## Responsivitet

- Telefon: 90 procent högt bottom sheet med fullständiga horisontellt rullbara fliknamn.
- Tablet/desktop: centrerad dialog på 760 × 680 logiska pixlar.
- Inga otydliga förkortningar används för flikarna.
- Allt flikinnehåll kan rullas vertikalt och åtgärder använder `Wrap` där bredden varierar.

## Verifiering

- `flutter analyze`: godkänd utan problem.
- Kontraktstest tillagt i `test/cal05_event_details_information_architecture_test.dart`.
- Flutter-testkörning återstår eftersom testwrappen återkommande fastnar utan output i aktuell miljö.
- Fysisk phone/tablet/desktop- och flerrollsgrind återstår.

## Ändrade huvudfiler

- `lib/src/features/calendar/calendar_surface.dart`
- `test/cal05_event_details_information_architecture_test.dart`

Ingen Supabase-liveändring, produktionsprovisionering, webtool eller workspace har genomförts. Paketidentiteten är fortsatt `com.teamzone.teamzone`.
