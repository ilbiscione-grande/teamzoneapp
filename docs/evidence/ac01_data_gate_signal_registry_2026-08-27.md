# AC-01 – datagrind och signalregister (2026-08-27)

## Resultat

AC-01 är lokalt implementerad men endast delvis verifierad. Ett privat register beskriver fem deterministiska signaler med källtabeller, freshness, ägande och kapabilitet. Den autentiserade diagnostiken returnerar källa, observationstid, förklaring och säker route, och filtrerar signaler efter faktisk lagbehörighet.

Assistant Coach, AC-yta och generativ AI är inte aktiverade. `internal.assistant_activation_gate` står kvar i `blocked`, och workload-, medicinska och andra känsliga signaler ingår inte.

## Omfattning

- Migration: `20260827195852_ac01_data_gate_signal_registry.sql`
- Kontraktstest: `test/ac01_data_gate_signal_registry_test.dart`
- Källor: `core.events`, `core.squad_revisions`, `core.callups`, `core.attendance_facts`
- Behörigheter: `event.manage`, `event.squad.manage`, `event.attendance.manage`; `development.manage` ger tillgång till grinddiagnostiken men inte till obehöriga signaler.

## Återstående verifiering

Docker/PostgreSQL kan inte köras i nuvarande miljö. Migreringen har därför inte exekverats lokalt, och Supabase live har inte ändrats. Innan AC-01 kan klarmarkeras måste migreringen köras i godkänd databas, representativa färskhets-/datakvalitetsfall verifieras och säkerhetsmatrisen provas med separata roller.

## Utförda kontroller

- Statisk kontroll av samtliga fem signalnycklar och transparensfält: godkänd.
- Kontroll att ingen `ready`-transition finns och att `activationAllowed` är falsk: godkänd.
- Kontroll av wrapper-/internfunktionsbehörighet och `git diff --check`: godkänd.
- Isolerat Flutter-test startades men gav ingen output inom 30 sekunder och avbröts, i linje med det redan dokumenterade lokala Flutter-hänget.
