# Steg 2 – spårbarhet och grind

**Status: produktgodkänt 2026-08-07. Teknisk/säkerhetsmässig review gav villkorat klartecken för sliceplanering 2026-08-07; implementationsgrindarna i `23_technical_security_review.md` återstår.**

## Leveranser

| Dokument | Omfattning |
|---|---|
| `17_domain_model_and_invariants.md` | Domängränser, source of truth, capabilities, states och transaktioner |
| `18_target_data_model.md` | Schemastrategi, logiska tabeller, nycklar, relationer och legacy mapping |
| `19_authorization_rls_storage_contract.md` | Authorizationordning, grants/RLS, Storage, Edge Functions, tokens och negativa tester |
| `20_api_command_query_event_contract.md` | Queries, commands, fel, idempotens, domain events, Realtime och versionering |
| `21_migration_compatibility_verification.md` | Expand/backfill/cutover/contract, rollback och evidensgrindar |

## Kravspårning

| Kravfamilj | Primärt specifikationsbevis |
|---|---|
| REQ-ID-01/02, REQ-MEM-01/02 | 17, 18, 20 |
| REQ-SEC-01–05 | 17, 19, 20 |
| REQ-DB-01/02 | 18, 21 |
| REQ-EVT/CAL/CALL/SQUAD | 17, 18, 20, 21 |
| REQ-MATCH-01 | 17, 18, 20, 21 |
| REQ-MSG-01–03 | 17–21 |
| REQ-SIG-01 | 17, 18, 20 |
| REQ-BILL-01/02, REQ-ECO-01 | 17, 18, 20, 21 |
| REQ-WEB-01–03 | 18–21 |
| REQ-CLI-01–04, REQ-OPS-01 | 19–21 och CRD-01–10 |

## Reviewgrind

Före implementation ska review bekräfta:

1. `club_person` är tenantägd representation och account link är separat.
2. Capability + objektscope, inte UI-roll, är enda authorizationmodell.
3. `core` är inte direkt klientskrivbar; commands är mutationsgräns.
4. Event→squad revision→callup är enda uttagningskedja.
5. Match v2 bevaras utan regressionsförsvagning.
6. Modul-entitlement gäller klubb men capability gäller fortfarande person/scope.
7. Publik data kommer endast från explicit `public_api`-projektion.
8. Migration sker additivt per slice och legacy avvecklas först efter observerad cutover.

## Kända, avsiktliga öppningar

De 25 posterna i `16_open_parameter_backlog.md` är inte bortglömda krav. P0-poster måste beslutas före berörd dataspec/API-freeze; P1/P2 håller berörd feature avstängd eller begränsad. Exakta DDL-, function signatures, index/partitionering och providerkonfiguration skrivs först i respektive implementationsslice och måste följa dessa kontrakt.

## Utfall

Steg 2 har nu en sammanhängande logisk specifikation som kan granskas utan att ändra implementation eller liveprojekt. Nästa grind efter godkännande är att omvandla specifikationen till en sliceplan med migrations-/API-/klienttasks och verifieringsbevis per slice.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | Steg 2:s domän-, data-, authorization-, API-, migrations- och verifieringskontrakt godkända som produktmålbild. | Produktägaren |
