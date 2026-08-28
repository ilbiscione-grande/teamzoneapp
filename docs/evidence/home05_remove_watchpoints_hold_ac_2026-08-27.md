# HOME-05 – Avlägsna Watchpoints och håll AC avvaktande

## Lokalt genomfört

- Den gamla runtime-definitionen `workload.watchpoint` pensioneras och ersätts av den neutrala, inaktiva `workload.future_review` bakom AC-01.
- Gamla eller förtida Watchpoint-/assistant-/AC-notifieringar suppressas, tappar klientmottagare och kan inte komma in i Notification Center. Ett before-trigger fail-stänger även framtida felaktiga emissioner.
- Den tidigare publika Assistant Coach-preview-RPC:n tas bort. Preview-modeller, serviceanrop, utvecklingsyta, hemkort, test och oanvända översättningssträngar har avlägsnats från klienten.
- Ett privat `AC-01`-gate-register skapas i läget `blocked`. Generativ AI, workload och medical är databaskonstraintade till `false`; senare aktivering kräver en uttrycklig ny migration efter datagrinden.
- HOME-01–04:s deterministiska uppgifter, kallelsesvar, närvarokort, prioritering och Notification Center fortsätter utan AC-beroende.

## Verifierat lokalt

- Dart-format och statisk kontraktsgrind täcker runtime-pensionering, notifieringsspärr, borttagen previewyta, AC-01-gate och fortsatt deterministiskt Hem.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Flutter test/analyze när wrappern kan slutföra utan låsning.
- Fysisk kontroll att inga gamla poster visas och att HOME-01–04 fungerar oförändrat.
