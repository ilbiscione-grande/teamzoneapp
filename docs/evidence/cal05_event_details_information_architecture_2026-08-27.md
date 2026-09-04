# CAL-05 – EventDetails informationsarkitektur

Datum: 2026-08-27  
Status: lokalt genomförd; grundlayout och lokaliserad tid fysiskt telefonverifierade, tablet/desktop och flerroll återstår

## Levererat

- EventDetails har exakt flikarna `Info`, `Deltagare`, `Förberedelser` och `Uppföljning`.
- Info samlar tid, tidszon, plats, beskrivning, ägande/deltagande lag och eventets livscykelåtgärder.
- Deltagare sammanfattar samma auktoritativa squadprojektion för urval, kallelser, svar och närvaro och leder vidare till det fullständiga hanteringsflödet.
- Förberedelser anpassas efter eventtyp. Match visar Match Space; övriga event prioriterar deltagare och eventinformation.
- Uppföljning visar registrerad närvaro, Match Space för matcher och möjlighet att markera eventet genomfört.
- Ledaråtgärder visas endast när serverns `caller_actions` innehåller motsvarande capability.
- Saknad deltagaråtkomst visas som en begriplig låst status i stället för rått backendfel.
- Info formaterar datum och tid med aktiv lokal: samma dag visas som fullständigt datum + tidsintervall, flerdagsevent visar båda datumen och heldag utelämnar klockslag.

## Responsivitet

- Telefon: 90 procent högt bottom sheet med fullständiga horisontellt rullbara fliknamn.
- Tablet/desktop: centrerad dialog på 760 × 680 logiska pixlar.
- Inga otydliga förkortningar används för flikarna.
- Allt flikinnehåll kan rullas vertikalt och åtgärder använder `Wrap` där bredden varierar.

## Verifiering

- `flutter analyze`: godkänd utan problem.
- Kontraktstest tillagt i `test/cal05_event_details_information_architecture_test.dart`.
- Riktat CAL-05-test passerar 2/2 och analysen av ändrade filer är ren.
- Audit-debugbuild `7D1D867FB7622EBA99846738D08D7CB2E5C84967A93CDC3C8D5B69D4450A2EA2` installerades på Xiaomi Mi 9.
- EventDetails för en svensk träning visade `lördag 29 augusti 2026 · 18:00–20:00` samt `Europe/Stockholm`, utan rå Dart-timestamp eller millisekunder.
- Telefonens Info-layout och fullständiga fliknamn är fysiskt godkända. Tablet/desktop, heldag/flerdag och fysisk flerrollsgrind återstår.
- EventDetails-flikar, ägarmarkering, deltagar-/kallelsesammanfattningar, förberedelsecopy och uppföljning flyttades därefter helt bakom localegränsen. Kombinerad CAL-05/FND-05-körning passerade 11/11 och analysen var ren.
- Samlad efterföljande audit-debugbuild `A8C081E47E8409B4B72E22882FA5964C1439E941BFB53555C5D3767A42C8B92F` installerades; svensk Kalender kallstartade med status, navigation och åtgärder intakta.

## Ändrade huvudfiler

- `lib/src/features/calendar/calendar_surface.dart`
- `test/cal05_event_details_information_architecture_test.dart`

Ingen Supabase-liveändring, produktionsprovisionering, webtool eller workspace har genomförts. Paketidentiteten är fortsatt `com.teamzone.teamzone`.
