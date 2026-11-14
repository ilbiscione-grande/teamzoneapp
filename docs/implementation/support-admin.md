# Adminsida för TeamZones support

**Status: del 1 byggd 2026-11-14. Övriga delar planerade.**

Sidan är för plattformens egna supportadministratörer (`internal.support_admins`, spärren `internal.actor_is_support_admin()`), inte för klubbadmin. Den ligger i appen på `/support` och nås från kortet Supportkö i Inkorgen.

## Varför i appen och inte i Webtools

- Spärren, rutten, köerna och kortet i Inkorgen finns redan i appen, även i mobilen.
- Webtools har egna miljöer (test och produktion) med var sin backend och används för de fristående produkterna (Tacticsboard, bokning). Supporten skulle få ännu ett ställe att logga in och driftsätta.
- Undantag: granskningen av anmälda delade Tacticsboard-objekt ligger kvar i Webtools, eftersom Tacticsboard säljs fristående.

## Delar

| Del | Innehåll | Serverfunktioner | Status |
|---|---|---|---|
| 1. Klubbar (läsa) | Alla klubbar: status, verifiering, lag, personer, konton, klubbadmins med konto, styrelsemandat, styrelse under bildning, väntande styrelseändringar. De som behöver hjälp först. En klubb öppnas med namn på admins, styrelse, väntande ändringar och lag. | `api.list_clubs_for_support()`, `api.get_club_for_support(club)` (loggar `support.club_viewed`) | Byggd 2026-11-14 |
| 2. Statistik | Hur apparna används: antal användare och konton, aktiva per dag/vecka/månad, nya konton, klubbar och lag över tid, fördelning webb/Android, användning per område (kalender, närvaro, meddelanden, Tacticsboard, bokning). Bara antal, inga namn. | Planeras, t.ex. `api.get_platform_usage_for_support(from, to)` | Önskad av produktägaren 2026-11-14, ska kartläggas: vilken aktivitet som redan sparas (t.ex. `recordActivity` i profilen) och vad som saknas |
| 3. Klubbar (åtgärder) | Utse klubbadmin bland personer med konto, verkställa eller avbryta en styrelseändring som fastnat, nödundantaget `teamzone.allow_no_club_admin` som loggad funktion med motivering. | `api.support_grant_club_admin`, `api.support_resolve_board_change`, `api.support_end_assignment_without_admin` | Planerad |
| 4. Supportadmins | Lista, lägga till (befintliga konton) och ta bort; den sista kan inte tas bort. | `api.list_support_admins`, `api.grant_support_admin`, `api.revoke_support_admin` | Planerad |
| 5. Logg | Supportens egna åtgärder ur `audit.command_events`. | `api.list_support_actions` | Planerad |

Alla funktioner kräver supportadmin, nekar andra med `insufficient_privilege` (`not_found`), och ändringar kräver motivering, loggas och använder PT409 vid konflikt. Vidgade rättigheter skrivs in i [permissions-review.md](permissions-review.md).

## Del 1 i appen

- `lib/src/features/support/support_club_services.dart`: tjänst och modeller (`SupportClubServices`, implementeras av `SupabaseMembershipServices`).
- `lib/src/features/support/support_clubs_tab.dart`: fliken Klubbar och klubbens detaljvy.
- `lib/src/core/localization/support_strings.dart`: texterna.
- `_SupportAdminSurface` har flikarna Ärenden och Klubbar.
- Test: `test/support_club_overview_test.dart`.
