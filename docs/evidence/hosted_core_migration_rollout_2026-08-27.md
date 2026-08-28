# Hosted core migration rollout – 2026-08-27

Projekt: `hgcshgunvooyudvrcpig`  
Godkännande: produktägaren godkände uttryckligen Supabase-liveutrullningen i uppgiften.

## Orsak

Android-appen blockerades fail-closed med `Villkor kunde inte kontrolleras` eftersom klienten anropade `api.get_legal_status()` medan AUTH-07-migrationen endast fanns lokalt.

## Applicerat

Följande migrationsintervall applicerades och registrerades av `supabase db push`:

- AUTH-03–AUTH-07
- TEAM-02–TEAM-08

AUTH-07:s villkors-RPC finns därmed i liveprojektet. Utrullningen använde projektets publishable klientkontrakt; ingen service-nyckel placerades i appen.

## Korrigering under utrullning

TEAM-06 avvisades först eftersom inputparametern och en `RETURNS TABLE`-kolumn båda hette `target_team_id`. Den ännu ej applicerade migrationen korrigerades till outputnamnet `eligibility_team_id`; klientmodellen accepterar både det nya och tidigare namnet. Migrationen applicerades därefter.

## Ej applicerat

CAL-02–CAL-08 är fortfarande lokala. CAL-02 avvisas vid PostgreSQL-kompilering av `internal.revise_event_v2_for_actor`; transaktionen rullas tillbaka och stoppar efterföljande kalenderfiler. Ingen migrationshistorik har markerat kalenderfilerna som applicerade och ingen manuell history-repair har gjorts.

## Verifieringsläge

- Den auktoritativa `db push --dry-run`-listan visar efter utrullningen endast CAL-02, CAL-03, CAL-04, CAL-06, CAL-07 och CAL-08 som väntande.
- Telefonens ADB-session blev offline före fysisk retry-verifiering. Användaren behöver trycka `Försök igen` när telefonen är online/upplåst.
