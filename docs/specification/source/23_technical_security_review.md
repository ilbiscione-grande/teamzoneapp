# Teknisk och säkerhetsmässig review av steg 2

**Status: slutförd 2026-08-07. Villkorat klartecken för sliceplanering; inget implementations- eller deploygodkännande.**

## Omfattning och metod

Dokument 17–22 granskades mot auditens krav/fynd, aktuell Supabase-dokumentation och skrivskyddad livekatalog för Teamzone6. Inga SQL-writes, migrationer, konfigurationsändringar eller deployer utfördes.

Officiellt underlag:

- [Securing your API](https://supabase.com/docs/guides/api/securing-your-api)
- [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Storage Access Control](https://supabase.com/docs/guides/storage/security/access-control)
- [Securing Edge Functions](https://supabase.com/docs/guides/functions/auth)
- [Realtime Authorization](https://supabase.com/docs/guides/realtime/authorization)
- [Database Migrations](https://supabase.com/docs/guides/deployment/database-migrations)
- [2026 OpenAPI breaking change](https://supabase.com/changelog/42949-breaking-change-removing-access-to-openapi-spec-via-the-anon-key)

## Skrivskyddad livebaseline

| Kontroll | Resultat 2026-08-07 | Betydelse |
|---|---|---|
| PostgreSQL | 17.6 | `security_invoker` stöds; faktisk version låses per release |
| Publika tabeller | 65/65 med RLS | Coverage är bra men bevisar inte semantisk authorization |
| Målschemas `core/api/public_api` | Finns inte ännu | Specs är additiv målbild, ingen dold livecutover |
| `public` SECURITY DEFINER | 179 totalt; 12 anon- och 165 authenticated-körbara | Bekräftar behovet av explicit API-yta och privilegeavveckling |
| Security Advisor | Bland annat mutable search path, anon/auth definer-exponering, extension i `public`, RLS utan policy och avstängt leaked-password-skydd | Registreras som baseline; löses/undantagshanteras per slice |
| Migration history | Genom `20260914020000_secure_database_webhooks` | Matchar auditens postdeploybas |

## Reviewfynd och korrigeringar

| ID | Pri | Fynd | Åtgärd i specifikationen | Status |
|---|---:|---|---|---|
| TSR-01 | P0 | Security-invoker-view över privat core fungerar inte utan invoker SELECT/RLS. | 18/19 kräver minimal SELECT endast för querykällor, core ej exponerat och RLS defense in depth. | Löst i spec |
| TSR-02 | P0 | “Security-invoker/materialiserad” blandade två olika säkerhetsmodeller. | 18 kräver separat public projection table eller invoker-view över anon-säkra källor; ingen privilegierad matview över PII. | Löst i spec |
| TSR-03 | P0 | Commandgränsen behövde ett konkret definer-/wrappermönster. | 19 låser exposed invoker wrapper → snäv internal definer med fixerad search path, explicit grants och full auth. | Löst i spec |
| TSR-04 | P0 | Default grants kunde återexponera nya objekt. | 19 kräver revoke default privileges och explicit grantverifiering i varje migration. | Löst i spec |
| TSR-05 | P0 | Realtime-resync var beskriven men kanalauthorization saknades. | 19 kräver private channels, `realtime.messages`-RLS och topic/objectbinding. | Löst i spec |
| TSR-06 | P1 | Data API pre-request skyddar inte Storage/Realtime/Functions. | 19 kräver separat rate-/abusekontroll per produktyta. | Löst i spec |
| TSR-07 | P1 | Nya publishable/secret keys är inte JWT och har särskilda Function-regler. | 19 separerar user JWT från namngiven `apikey` secret-auth. | Löst i spec |
| TSR-08 | P1 | Anonåtkomst till Data API OpenAPI har tagits bort 2026. | 20 kräver lokal/auditerad eller autentiserad kontraktgenerering. | Löst i spec |

## Kvarvarande implementationsgrindar

1. Första identity-slicen måste prototypa och negativtesta wrapper → internal command-mönstret i auditprojektet.
2. Varje slice ska ha ett maskinläsbart privilege manifest och diff mot `pg_default_acl`, grants, RLS, policies och function ACL.
3. Security Advisor-varningar ska bli lösta eller individuellt hotmodellsgodkända; särskilt de 179 befintliga definerfunktionerna får inte följa med som odifferentierad API-yta.
4. `public_api` endpoint-/fältallowlist förblir blockerad av PAR-API-01 före public API-freeze.
5. Realtime private-channel-policy, Storage ownerbinding och Edge auth ska testas med säkra JWT-identiteter i auditprojekt före live.
6. Leaked-password-skydd och eventuell MFA/step-up för super-admin/högriskekonomi ska få operations-/produktbeslut innan authrelease.
7. Berörda P0-parametrar i dokument 16 måste vara beslutade före respektive dataspec/cutover.

## Reviewbeslut

Steg 2 är tekniskt sammanhängande efter korrigeringarna och får gå vidare till sliceplanering. Det är inte ett klartecken att skapa DDL, ändra klienten eller deploya. Varje slice behöver separat implementationstillstånd, auditprojekttest och livegodkännande.

