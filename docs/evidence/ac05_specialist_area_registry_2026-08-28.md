# AC-05 – Versionshanterat specialistområdesregister

Datum: 2026-08-28  
Status: lokalt implementerad och Flutter-verifierad; PostgreSQL-runtime och fysisk visuell/tillgänglighetsverifiering återstår.

## Levererat

- Sex stabila områdesnycklar: `team_planning`, `training_support`, `individual_development`, `rehab_support`, `club_administration` och `communication`.
- Ett typat klientregister, version 1, med etikett, ikon-token, design-token, datakällor, capabilities, målroller, presentationsfält, tillåtna navigationer och grindstatus.
- Ett privat serverregister med samma kontrakt och explicit registerversion.
- De fem befintliga AC-01-signalerna har `team_planning` som primärt område.
- En återanvändbar badge visar alltid områdets textetikett, ikon och färg samt en separat semantisk etikett för skärmläsare.
- Min assistent-ytan visar samtliga registrerade områden och markerar separat att de väntar på verifiering.

## Fail-closed och säkerhet

- Samtliga områden är inaktiva. Databaskontraktet förbjuder `active` i denna migration och kräver en senare explicit migration för aktivering.
- Registret ligger i `internal`, har RLS aktiverat och saknar direkt tabellåtkomst för `anon` och `authenticated`.
- En smal autentiserad läs-RPC kan returnera presentations- och policykontraktet men ger ingen ny capability.
- Områdesnyckel eller design-token används inte som authorization.
- Rehabstöd är blockerat i väntan på LATER-04 och separat hälso-/ansvarsgrind; inga medicinska beslut aktiveras.
- Ingen Supabase-liveändring har gjorts.

## Tillgänglighet och design

- Områdesfärg är separerad från prioritet och status.
- Betydelsen bärs alltid av text och ikon, aldrig av färg ensam.
- Alla sex badges passerar automatiserat kontrastkrav 4,5:1 i både ljust och mörkt tema.
- Fysisk färgblindhets-, textskalnings- och enhetsverifiering återstår.

## Verifiering

- `dart analyze lib test`: inga problem.
- AC-01–AC-05 riktad regression: 15/15 passerade.
- Separat AC-05-svit inklusive tolv ljus-/mörkerkontrastfall: 5/5 passerade.
- PostgreSQL-runtime/advisors kunde inte köras eftersom lokal Docker-runtime saknas.

## Kvarvarande grindar

- Kör migrationen och RPC-kontraktet i godkänd icke-live PostgreSQL-miljö.
- Verifiera färgblindhet, textskalning, skärmläsare och faktisk mobil/tablet/desktop-layout.
- Rendera samma badge i skarpa kort, historik och detaljvy när dataposter senare aktiveras.
