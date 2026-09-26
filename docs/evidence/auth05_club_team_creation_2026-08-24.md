# AUTH-05 – Skapa klubb och första lag

**Datum:** 2026-08-24  
**Status:** IMPLEMENTERAD OCH VERIFIERAD MOT HOSTED TESTDATABAS SAMT FYSISK ANDROID  
**Livepåverkan:** Migrationerna är applicerade mot det uttryckligen godkända Supabase-testprojektet `hgcshgunvooyudvrcpig`.

## Implementerat

- Endast autentiserad användare med verifierad e-post får skapa klubb.
- Klubb och första lag skapas i ett atomiskt kommando tillsammans med person, aktiv kontolänk, `club_functionary`-assignment och administrativa capabilities.
- Klubben skapas alltid som `unofficial`; skyddade namn och TeamZone-verifiering hör till AUTH-06.
- Resultatet innehåller klubb-, lag- och context-ID så att klienten omedelbart kan ladda den nya kontexten.
- Kommandot använder command-deduplication; samma idempotency key skapar inte dubbla organisationer.
- Slug genereras serverstyrt med ett UUID-suffix och kan inte väljas av klienten.
- Behörig användare med `club.memberships.manage` kan skapa ytterligare lag via ett separat idempotent kommando.
- Ett ytterligare lag får omedelbart en aktiv `club_functionary`-kontext för skaparen och dennes aktiva klubbscopade capabilities kopieras till kontexten.
- Efter skapandet laddar klienten om kontexterna, väljer det nya laget via returnerat lag-ID och öppnar dess hemsida.
- Vänteläget har ett validerat, lokaliserat formulär med pending-, timeout-, double-submit- och neutral felhantering.
- Laget-vyn erbjuder `Skapa ytterligare lag` endast bakom befintlig capabilitygrind.
- Dialogen håller inget lokalt `TextEditingController`-objekt som kan disponeras medan stängningsanimationen fortfarande har beroenden; detta åtgärdar den fysiskt observerade `_dependents.isEmpty`-rödskärmen.

## Verifiering

- Riktad Flutter-analys: **No issues found**.
- Riktad AUTH-04/AUTH-05/AUTH-06-svit: **12/12 passerar**.
- Källkontrakt verifierar e-postgrind, inofficiell status, atomiskt relationspaket, idempotens, aktivt context-ID, capability och avsaknad av anon-grant.
- Hosted rollback-test verifierade idempotent återspelning, exakt en aktiv skaparkontext och fyra kopierade klubbcapabilities; hela testtransaktionen rullades tillbaka.
- Fysisk Xiaomi Mi9 verifierade skapande av ytterligare lag utan rödskärm samt automatiskt byte till det nya lagets hemsida.

## Uppföljning

- Samtidig duplicate submit och unik lagnamnskonflikt bevakas vidare i den breda regressionsgrinden.
- iOS verifieras när en iOS-miljö finns.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
