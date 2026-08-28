# AUTH-05 – Skapa klubb och första lag

**Datum:** 2026-08-24  
**Status:** LOKALT IMPLEMENTERAD OCH KLIENTVERIFIERAD, SQL-RUNTIME/FYSISK GRIND ÅTERSTÅR  
**Livepåverkan:** Ingen. Migrationen har inte applicerats mot Supabase live.

## Implementerat

- Endast autentiserad användare med verifierad e-post får skapa klubb.
- Klubb och första lag skapas i ett atomiskt kommando tillsammans med person, aktiv kontolänk, `club_functionary`-assignment och administrativa capabilities.
- Klubben skapas alltid som `unofficial`; skyddade namn och TeamZone-verifiering hör till AUTH-06.
- Resultatet innehåller klubb-, lag- och context-ID så att klienten omedelbart kan ladda den nya kontexten.
- Kommandot använder command-deduplication; samma idempotency key skapar inte dubbla organisationer.
- Slug genereras serverstyrt med ett UUID-suffix och kan inte väljas av klienten.
- Behörig användare med `club.memberships.manage` kan skapa ytterligare lag via ett separat idempotent kommando.
- Vänteläget har ett validerat, lokaliserat formulär med pending-, timeout-, double-submit- och neutral felhantering.
- Laget-vyn erbjuder `Skapa ytterligare lag` endast bakom befintlig capabilitygrind.

## Verifiering

- Direkt Dart-analys: **No issues found**.
- Kombinerad AUTH-04/AUTH-05/FND-05-svit: **14/14 passerar**.
- Källkontrakt verifierar e-postgrind, inofficiell status, atomiskt relationspaket, idempotens, aktivt context-ID, capability och avsaknad av anon-grant.
- Ingen åtkomst till eller ändring av Supabase live gjordes.

## Kvarvarande grind

1. Exekvera migration och rollback-fixtures i lokal eller separat uttryckligen godkänd testdatabas.
2. Verifiera idempotent retry, samtidig duplicate submit, unik lagnamnskonflikt och full rollback utan föräldralösa poster.
3. Fysisk Android-genomgång av skapa klubb, automatiskt kontextbyte och skapa ytterligare lag.
4. Köra full regressionssvit.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
