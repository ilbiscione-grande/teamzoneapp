# AC-08 – Specialistpolicy, ansvar och aktiveringsgrind

Datum: 2026-08-28  
Status: policy och fail-closed-grind lokalt implementerade och Flutter-verifierade; PostgreSQL-runtime/advisors, flerrollsmatris och fysisk enhetsgrind återstår.

## Specialistansvar

- Alla sex områden har ett versionerat, maskinläsbart ansvar och en explicit lista över förbjudna beslut.
- Alla områden är digitala funktioner, saknar generativ AI och får inte utföra autonoma domänmutationer.
- Navigation får ske direkt till en säker TeamZone-vy.
- En framtida domänmutation får endast fortsätta när preview, explicit användarbekräftelse, serverauktorisation, idempotens och audit samtliga är uppfyllda.
- Nuvarande specialist-actions är navigation; AC-08 inför ingen mutationsväg.

## Rehabgräns

- Rehabstöd får endast följa och påminna om en redan beslutad plan.
- Både klient- och databaskontrakt förbjuder diagnos, ordination, medicinsk riskrangordning och beslut om återgång till spel.
- Postkort för Rehabstöd visar gränsen synligt för användaren.
- Rehabstöd förblir blockerat i väntan på LATER-04 och separat hälso-/ansvarsgrind.

## Digital identitet

- Assistentytan säger uttryckligen att Min assistent är en digital funktion, inte en människa, vårdprofession eller legitimerad expert.
- Förslag beskrivs som baserade på verifierade TeamZone-data och kräver användarens beslut.
- Notisen är semantiskt märkt för skärmläsare.

## Aktiveringsgrind per område

Varje område kräver samtliga följande innan status kan bli `ready`:

- verifierad datakvalitet;
- godkänd dataägare;
- integritetsgodkännande;
- passerad PostgreSQL-runtime;
- passerade advisors;
- passerad flerrollsmatris;
- passerad fysisk mobil/tablet/desktop-grind;
- utsedd incidentägare;
- namngiven granskare och tidsstämplad review.

Aktivering kräver dessutom både `review.state = ready` och områdets separata `gate_state = active`. AC-05:s befintliga constraint förbjuder fortfarande `active`, så ingen aktiveringsväg öppnas av AC-08.

## Separat generativ AI-grind

- Generativ AI har egen grind med `state = blocked` och `enabled = false` som databaskonstraint.
- Produkt, integritet, leverantör, region, retention, minderårigdata, utvärdering, drift och incidentflöde måste godkännas separat.
- Inget AI-SDK, modell-anrop eller externt dataflöde har lagts till.

## Säkerhet och audit

- Policy-, review- och AI-grindtabeller ligger i `internal`, har RLS och saknar direkt åtkomst för `anon` och `authenticated`.
- Aktiveringshändelser har ett separat auditkontrakt som kan bevara evidens utan att ge klienten mutationsrätt.
- Den autentiserade läs-RPC:n exponerar endast ansvar, förbud och blockerad grindstatus.
- Ingen Supabase-liveändring har gjorts.

## Verifiering

- `dart analyze lib test`: inga problem.
- AC-01–AC-08 riktad regression: 34/34 passerade.
- Separat AC-08-svit: 6/6 passerade.
- Testerna täcker fullständigt mutationskontrakt, rehabförbud, digital identitet, samtliga aktiveringskrav, separat AI-grind och frånvaro av aktiverande SQL.
- PostgreSQL-runtime/advisors kunde inte köras eftersom lokal Docker-runtime saknas.

## Kvarvarande grindar

- Kör migration och policy-RPC i godkänd icke-live PostgreSQL-miljö och kör advisors.
- Genomför flerrollsmatris med verkliga leader/player/guardian/club_functionary-konton.
- Genomför fysisk mobil/tablet/desktop-verifiering och tillgänglighetskontroll.
- Inget område får aktiveras innan dess egen fullständiga review är dokumenterad och separat godkänd.
- Generativ AI kräver ett nytt uttryckligt produkt- och driftbeslut även efter övriga AC-grindar.
