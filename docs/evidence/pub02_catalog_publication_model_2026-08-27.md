# PUB-02 – katalog och publiceringsmodell

Datum: 2026-08-27  
Omfattning: lokal migration och kontraktstest; ingen Supabase-liveändring.

## Genomfört

- Klubb och lag använder `private`, `listed` och `published`; tidigare S09-draft återgår säkert till private och kräver ett nytt aktivt beslut.
- `publication.manage` är en separat capability-grant. Befintliga klubbadministratörer får en explicit bootstrap-rad, men runtimekontrollen härleder aldrig rättigheten från rollnamn eller officiell status.
- Listed/published kräver att klubben är aktiv och `official`, en allowlistad fältmängd samt en revisionerad policybekräftelse som gäller högst 366 dagar.
- Bekräftelser är privata, RLS-skyddade och auditeras med actor, policyversion, fält, mode och expiry. En aktiv bekräftelse per aggregate tillåts.
- Expiry sätter ytan private och köar removal före cacheinvalidation. Projection-workern bygger endast när inställning, revision, mode, fält och aktiv bekräftelse matchar.
- Klubbkatalogen returnerar endast opaque public id, slug, namn, valfri ort och official-markör. Den behåller tre teckens prefixkrav, max tio träffar och befintlig pseudonymiserad rate limiting.
- Ingen personprojektion skapas. Fälten namn, bild, position och statistik kan därför inte läcka; framtida publik trupp kräver aktiva fältspecifika samtycken från S09-modellen.

## Säkerhetsgränser

- Alla nya tabeller har RLS och explicit revoke för `public`, `anon` och `authenticated`.
- Privilegierad kod ligger i `internal`, kontrollerar `auth.uid()`/capability och exponeras endast via en smal `api`-wrapper.
- Publiceringsruntime aktiveras inte av migrationen.

## Verifiering

- Statisk SQL-kontroll: 14 balanserade dollar-delimiters, inga felaktiga `end$$`-terminatorer och inga publika/anon-grants.
- `flutter test test/pub02_catalog_publication_model_test.dart --no-pub`: 3/3 godkända.
- PostgreSQL-runtime och advisors återstår eftersom lokal Docker/PostgreSQL-runtime saknas och tidigare CAL-02 blockerar den ordnade livekedjan.
