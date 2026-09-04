# HOME-05 – Avlägsna Watchpoints och håll AC avvaktande

## Lokalt genomfört

- Den gamla runtime-definitionen `workload.watchpoint` pensioneras och ersätts av den neutrala, inaktiva `workload.future_review` bakom AC-01.
- Gamla eller förtida Watchpoint-/assistant-/AC-notifieringar suppressas, tappar klientmottagare och kan inte komma in i Notification Center. Ett before-trigger fail-stänger även framtida felaktiga emissioner.
- Den tidigare publika Assistant Coach-preview-RPC:n tas bort. Preview-modeller, serviceanrop, utvecklingsyta och hemkort har avlägsnats från klienten. Den senare tillagda AC-02/03-ingången är endast en transparent hållningsyta och aktiverar varken AI eller känsliga signaler.
- Ett privat `AC-01`-gate-register skapas i läget `blocked`. Generativ AI, workload och medical är databaskonstraintade till `false`; senare aktivering kräver en uttrycklig ny migration efter datagrinden.
- HOME-01–04:s deterministiska uppgifter, kallelsesvar, närvarokort, prioritering och Notification Center fortsätter utan AC-beroende.
- Notification Center filtrerar även i klientens modell bort pensionerad Watchpoint-identitet och förtida assistant-, workload-, high-load- och medical-payloads samt korrigerar deras unika olästa poster ur badge-räknaren. Därmed kan inte en gammal cache eller äldre API-version kringgå serverspärren eller skapa en spökbadge.

## Verifierat lokalt

- HOME-05, HOME-04, MSG-08 och AC-01–03: 22/22 riktade tester passerar.
- Beteendetest verifierar att pensionerade/förtida notifieringspayloads filtreras medan ett vanligt meddelande behålls.
- `dart analyze lib test`: inga problem.
- Dart-format, beteendetest och statisk kontraktsgrind täcker runtime-pensionering, notifieringsspärr på server och klient, borttagen previewyta, AC-01-gate och fortsatt deterministiskt Hem.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Fysisk kontroll att inga gamla poster visas och att HOME-01–04 fungerar oförändrat.
