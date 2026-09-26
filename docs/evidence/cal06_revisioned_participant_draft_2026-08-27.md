# CAL-06 – en revisionerad deltagardraft

Datum: 2026-08-27, slutverifierad 2026-09-20  
Status: genomförd och verifierad

## Levererat

- Manuell markering, alla behöriga, behörighetsgrupp och generator skriver till samma `core.squad_revisions` och `core.squad_members`.
- Grupp betyder aktuell eventtidsbehörighet: ordinarie assignment, development, dispensation, loan, guest eller cross-team. Permanenta rostergrupper och import är fortsatt uppskjutna.
- `balanced_v1` är deterministisk: ordinarie spelare prioriteras, därefter stabil namn-/id-ordning. Servern räknar om och avvisar manipulerat generatorurval.
- Varje revision sparar selection source, minimerad selection context och initial/late dispatch kind.
- Send låser aktuell draft automatiskt och både lock och send återvaliderar varje deltagares behörighet mot eventets starttid. Någon separat låsknapp exponeras inte.
- Draft, lock och send serialiseras med samma transaktionslokala advisory lock per event.
- Idempotency lookup sker före state/stale-kontroll för att samma command-id tryggt ska kunna återspelas.
- En ny draft efter tidigare utskick blir explicit `late`; utskick skapar bara nya callups via konfliktsskydd och avvisas om ingen ny mottagare finns.
- Explicit återkallelse ändrar endast vald callup och tidigare utskick/svar bevaras. En person vars enda kallelse har återkallats räknas inte som aktivt vald i nästa arbetsutkast.

## Klient

- Deltagarflikens meny erbjuder Manuell, Alla behöriga, Behörighetsgrupp och Generator i samma revisionerade utkast.
- Manuell tillåter individuell markering.
- Ett manuellt utkast kan tömmas helt; automatiska urvalsmetoder måste fortsatt ge ett giltigt, icke-tomt urval.
- Alla och Grupp väljer hela den servervaliderade mängden.
- Generatorn väljer målantal och visar sin deterministiska princip.
- Utskickssteget visar `Skicka sena kallelser` för en late draft.
- Kallelsesvar ligger kompakt på samma rad som namnet. Bred vy visar ikon + `Acceptera`/`Avböj`, smal vy visar ikoner med tooltip och valt svar markeras direkt i knappen.

## Verifiering

- `flutter analyze`: godkänd utan problem.
- 14/14 riktade CAL-06/CAL-11-tester passerar, inklusive regressioner för tomt manuellt utkast och återkallad kallelse som inte återväljs.
- Migration `20260920094411_cal06_allow_empty_manual_draft.sql` applicerades efter separat godkännande på testprojektet `hgcshgunvooyudvrcpig`; lokal och remote migrationshistorik matchar.
- Fysisk webbgrind 2026-09-20 godkände alla fyra urvalsmetoder, full avmarkering, automatisk låsning + första utskick, sena kallelser, kompakt svarshantering och återkallning utan påverkan på övriga kallelser.

## Ändrade huvudfiler

- `supabase/migrations/20260827073426_cal06_revisioned_participant_draft.sql`
- `supabase/migrations/20260920094411_cal06_allow_empty_manual_draft.sql`
- `lib/src/features/calendar/calendar_models.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/features/calendar/event_details_page.dart`
- `lib/src/features/overview/overview_surface.dart`
- `test/cal06_revisioned_participant_draft_test.dart`
- `test/cal11_event_details_page_test.dart`

Endast den uttryckligt godkända migrationen ovan ändrades i Supabase-testprojektet. Ingen produktionsprovisionering, webtool eller workspace har genomförts. Paketidentiteten är fortsatt `com.teamzone.teamzone`.
