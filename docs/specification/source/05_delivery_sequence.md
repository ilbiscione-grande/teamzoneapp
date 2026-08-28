# Rekommenderad specifikations- och leveransordning

## Fas A – Produktkontrakt

1. Bekräfta `01_product_delta.md`.
2. Besluta roll/capability, context och person/roster (PD-01–03).
3. Besluta shared event/cross-team/squad/callup (PD-05–08).
4. Besluta messaging, publicering och minderårigpolicy (PD-10/11/16/20).
5. Besluta entitlementmodell och kommersiella kvoter (PD-04/15, ND-10).
6. Avgränsa Assistant Coach v1 (ND-01/02).

## Fas B – Rebuildspecifikation

Skriv därefter, i ordning:

1. identity/capability/context;
2. temporal person-, roster- och representationmodell;
3. event/callup/attendance och gemensam notification delivery;
4. navigation, fem huvudytor och URL-/statekontrakt;
5. messaging;
6. matchintegration ovanpå v2;
7. statistics/signals/Assistant Coach;
8. public web/publication;
9. subscription/entitlement;
10. workspaces och versionerat webtool-API;
11. migration, compatibility, release och rollback.

## Fas C – Vertikala implementationsdelar

| Slice | Leverans | Varför först/senare |
|---|---|---|
| 1 | Auth, väntrum, context och femsidigt tomt shell | Alla andra flöden behöver korrekt identitet/navigation. |
| 2 | Club/team/roster/invite/claim | Skapar säkra aktörer och målobjekt. |
| 3 | Event + Kalender + EventDetails Info | Bas för callup, booking, träning och match. |
| 4 | Squad/callup/push/attendance | Produktens centrala dagliga loop. |
| 5 | Hem + rollanpassade actions | Kan nu drivas av riktiga domäntillstånd. |
| 6 | Inbox och notification center | Byggs på beslutad recipientmodell. |
| 7 | Match Space integration | Återanvänd verifierat backendkontrakt. |
| 8 | Statistik och Assistant Coach v1 | Kräver tillförlitlig historik/provenance. |
| 9 | Publik webb | Kräver beslutad publicerings-/samtyckesmodell. |
| 10 | Billing/entitlements | Aktiveras när produktpaketeringen är beslutad. |
| 11 | Övriga workspaces/web tools | Versionerade integrationer, inte kärnberoenden. |

## Definition of done per slice

- Produktbeslut och målflöde godkända.
- Schema/RLS/RPC och negativa tenanttester.
- Klientens loading/empty/error/retry/offline.
- Locale svenska/engelska och accessibility.
- Realtime/resync där relevant.
- Migration från faktisk liveform och rollbackplan.
- Sanerad observability och signerad releaseartefakt.

