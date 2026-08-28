# CAL-06 – en revisionerad deltagardraft

Datum: 2026-08-27  
Status: lokalt genomförd, runtimegrindar återstår

## Levererat

- Manuell markering, alla behöriga, behörighetsgrupp och generator skriver till samma `core.squad_revisions` och `core.squad_members`.
- Grupp betyder aktuell eventtidsbehörighet: ordinarie assignment, development, dispensation, loan, guest eller cross-team. Permanenta rostergrupper och import är fortsatt uppskjutna.
- `balanced_v1` är deterministisk: ordinarie spelare prioriteras, därefter stabil namn-/id-ordning. Servern räknar om och avvisar manipulerat generatorurval.
- Varje revision sparar selection source, minimerad selection context och initial/late dispatch kind.
- Lock och send återvaliderar varje deltagares behörighet mot eventets starttid.
- Draft, lock och send serialiseras med samma transaktionslokala advisory lock per event.
- Idempotency lookup sker före state/stale-kontroll för att samma command-id tryggt ska kunna återspelas.
- En ny draft efter tidigare utskick blir explicit `late`; utskick skapar bara nya callups via konfliktsskydd och avvisas om ingen ny mottagare finns.
- Befintlig explicit återkallelse ändrar endast vald callup och tidigare utskick/svar bevaras.

## Klient

- Deltagardialogen erbjuder Manuell, Alla, Grupp och Generator.
- Manuell tillåter individuell markering.
- Alla och Grupp väljer hela den servervaliderade mängden.
- Generatorn väljer målantal och visar sin deterministiska princip.
- Utskickssteget visar `Skicka sena kallelser` för en late draft.

## Verifiering

- `flutter analyze`: godkänd utan problem.
- Kontraktstest tillagt i `test/cal06_revisioned_participant_draft_test.dart`.
- SQL-runtime återstår eftersom lokal Docker/PostgreSQL saknas och Supabase live inte får ändras utan separat godkännande.
- Flutter-testwrapper och fysisk draft/lock/send/late-callup-grind återstår.

## Ändrade huvudfiler

- `supabase/migrations/20260827073426_cal06_revisioned_participant_draft.sql`
- `lib/src/features/calendar/calendar_models.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/features/calendar/calendar_surface.dart`
- `test/cal06_revisioned_participant_draft_test.dart`

Ingen Supabase-liveändring, produktionsprovisionering, webtool eller workspace har genomförts. Paketidentiteten är fortsatt `com.teamzone.teamzone`.
