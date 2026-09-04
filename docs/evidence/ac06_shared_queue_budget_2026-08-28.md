# AC-06 – Gemensam kö, prioritering och notifieringsbudget

Datum: 2026-08-28  
Status: lokalt implementerad och Flutter-verifierad; PostgreSQL-runtime, faktisk leverans och fysisk cross-area-verifiering återstår.

## Levererat

- En gemensam kömodell för samtliga specialistområden; inga separata specialistinkorgar eller pushköer.
- Varje kandidat får `primaryAreaKey`, domänstabil `canonicalKey`, global prioritet och leveransklass.
- Eventrelaterade signaler använder samma `event:<id>` oavsett signal eller framtida specialisttolkning. Lagets planeringslucka använder `planning_gap:<team-id>`.
- En deterministisk vinnare väljs per canonical key i ordningen prioritet, senaste observation, signalnyckel och käll-id.
- Obehöriga och avfärdade kandidater filtreras före klientkön.
- Positiva poster har lägre avbrottsprioritet och standardklass `digest`.

## Gemensam budget

- Stödda lägen är `direct`, `digest`, `in_assistant` och `off`.
- Grundbudgeten är högst tre direkta assistentposter och en gemensam digest per 24 timmar.
- Överskjutande direkta poster degraderas till digest; om digest saknar budget degraderas de till endast Min assistent.
- Samma budget används över områdesgränser.
- Alla effektiva leveranslägen blir fortsatt `off` när områdets aktiveringsgrind inte är `active`.

## Säkerhets- och systemgräns

- Budgetpolicyn ligger i `internal`, har RLS och saknar direkt åtkomst för `anon` och `authenticated`.
- Kö-RPC:n kräver autentiserad användare och återanvänder AC-01:s capabilityverifierade datagrind.
- Områdesklassificering och canonical key ger ingen ny behörighet.
- Migreringen läser eller skriver inte `internal.notification_outbox` eller `core.notification_receipts`.
- System-, säkerhets-, juridik- och driftmeddelanden ligger uttryckligen utanför assistentbudgeten och fortsätter ha TeamZone som avsändare.
- Ingen Supabase-liveändring har gjorts.

## Verifiering

- `dart analyze lib test`: inga problem.
- AC-01–AC-06 riktad regression: 21/21 passerade.
- Separat AC-06-svit: 6/6 passerade.
- Testerna täcker cross-area-deduplicering, prioritetsvinnare, tids-/nyckel-tiebreak, obehörig/avfärdad filtrering, fyra leveranslägen och budgetdegradering.
- PostgreSQL-runtime/advisors kunde inte köras eftersom lokal Docker-runtime saknas.

## Kvarvarande grindar

- Kör migrationen och kö-RPC:n i godkänd icke-live PostgreSQL-miljö.
- Verifiera canonical deduplicering med verkliga event som samtidigt matchar flera signaler och senare flera områden.
- Implementera faktisk leverans först när områdesgrind, notifieringsägarskap och fysisk testmatris godkänts.
- Kontosynkade områdespreferenser och historikfilter hanteras i AC-07.
