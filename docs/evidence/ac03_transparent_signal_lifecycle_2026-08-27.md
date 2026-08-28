# AC-03 – transparent signalhantering (2026-08-27)

## Resultat

AC-03 är lokalt implementerad som ett fail-closed kontrakt ovanpå AC-01:

- signaler presenteras som deterministiska sammanfattningar med källa och tidpunkt;
- en säker handling är alltid navigation, aldrig en direkt domänmutation;
- dolda riskpoäng, medicinska slutsatser, personjämförelser och generativ AI anges explicit som avstängda;
- användaren kan avfärda och återställa en aktuell signal med idempotenta kommandon;
- avfärdandestatus lagras privat per användare, klubb, lag, signal och källobjekt;
- varje avfärdande/återställning auditeras separat;
- `notification_outbox` och `notification_receipts` berörs inte.

Klientens inaktiva AC-yta beskriver samma gränser men hämtar fortfarande ingen signaldata eftersom AC-01-grinden inte är runtime-verifierad.

## Ändrade kontrakt

- Migration: `20260827203154_ac03_transparent_signal_lifecycle.sql`
- Klient: `lib/src/features/assistant_coach/assistant_coach_entry.dart`
- Test: `test/ac03_transparent_signal_lifecycle_test.dart`

## Återstående verifiering

Docker/PostgreSQL saknas lokalt och Supabase live har inte ändrats. SQL-runtime, rollmatris, återställning med verkliga signaler och responsiv fysisk genomgång ska verifieras tillsammans med AC-01/02 när representativ lag- och eventdata finns. AC-03 står därför som `[~]`.

## Utförda kontroller

- Statisk kontroll av behörighetsgrind, idempotens, explicit handling, transparensflaggor samt avsaknad av notifieringskoppling: godkänd.
- `flutter analyze test/ac03_transparent_signal_lifecycle_test.dart`: godkänd utan anmärkningar.
- `git diff --check`: godkänd.
- Isolerat Flutter-test gav ingen output inom 30 sekunder och avbröts enligt den kända lokala runner-begränsningen.
