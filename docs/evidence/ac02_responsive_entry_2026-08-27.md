# AC-02 – responsiv Assistant Coach-ingång (2026-08-27)

## Resultat

Produktskalet har nu en responsiv men inaktiv ingång till Assistant Coach:

- mobil visar en semantisk FAB nere till höger, 88 pixlar ovanför innehållets nederkant för att inte sammanfalla med sidornas primära FAB-zon;
- tablet och desktop visar en avgränsad sidopanel;
- `/assistant` är en canonical deep link;
- öppning använder router-push och back återgår till föregående sida, med `/home` som säker fallback vid kall deep link;
- hållytan förklarar uttryckligen att ingen analys eller automatisk åtgärd körs.

Ingen signaldata hämtas, Assistant Coach aktiveras inte och ingen generativ AI används.

## Ändrade kontrakt

- `lib/src/features/assistant_coach/assistant_coach_entry.dart`
- `lib/src/app/product_shell.dart`
- `lib/src/app/product_route_contract.dart`
- `test/ac02_responsive_entry_test.dart`

## Återstående verifiering

AC-02 står som delvis klar. Full widget-/fysisk verifiering av telefon, tablet och desktop samt verkligt fokusflöde skjuts upp tills AC-01 har verifierad data. Den lokala Flutter-runnern har tidigare hängt före testoutput; ingen livebackend behöver eller får ändras för denna verifiering.

## Utförda kontroller

- Statisk kontroll av mobil-FAB, sidopanel, canonical route, back-fallback, semantik och avsaknad av dataanrop: godkänd.
- `git diff --check`: godkänd.
- `flutter analyze`: AC-02 gav inga egna fel. Helhetsanalysen stoppas av ett redan befintligt dubblerat nyckelfel i `app_strings.dart`; därutöver rapporterades äldre lintanmärkningar i meddelande- och hemfiler.
- Isolerat `flutter test test/ac02_responsive_entry_test.dart`: gav ingen output inom 30 sekunder och avbröts enligt den kända lokala runner-begränsningen.
