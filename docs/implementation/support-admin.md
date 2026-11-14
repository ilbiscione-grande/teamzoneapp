# Adminsida för TeamZones support

**Status: del 1, 2 och 4 byggda 2026-11-14, och sidan är bruten loss från appen. Del 3 och 5 planerade.**

Sidan är för plattformens egna supportadministratörer (`internal.support_admins`, spärren `internal.actor_is_support_admin()`), inte för klubbadmin.

## En egen webbplats och ett eget konto (beslut 2026-11-14)

Produktägaren var både användare och supporttekniker på samma konto. Därför:

- **Eget supportkonto:** supporten sköts från ett konto utan roller i klubbar. Fliken Supportadmins visar om ett aktivt supportkonto har roller i klubbar.
- **Egen webbplats:** `https://support.teamzoneapp.se` (Firebase Hosting-webbplatsen `teamzoneapp-support`, target `support`, adressen `teamzoneapp-support.web.app` tills domänen är kopplad). Det är samma bygge som appen (`build/web`); `main.dart` känner igen adressen (`isSupportSiteHost`) och visar efter inloggning bara supportsidan (`_SupportSiteShell`). Ett konto som inte är supportadministratör får veta det och kan logga ut.
- **Appen:** `/support` visar att supporten har flyttat, och kortet Supportkö i Inkorgen öppnar supportwebbplatsen. Kortet visas fortfarande bara för supportadministratörer.
- **Inloggning:** `support.teamzoneapp.se` finns bland de godkända adresserna (`supabase/functions/_shared/sign_in_limits.ts`), och `teamzoneapp-support.web.app` bara på testprojektet.
- **Driftsättning:** bygg webben en gång och driftsätt både `hosting:test` och `hosting:support`.

Byta till supportkontot: skapa kontot, lägg till det under Supportadmins med det gamla kontot, logga in med det nya på supportwebbplatsen och ta bort det gamla kontots supporträtt där.

## Varför inte i Webtools

- Webtools i produktion använder ett annat Supabase-projekt än appen, så supporten skulle se fel data eller behöva två backends.
- Supportsidan är redan byggd i Flutter och återanvänds som den är.
- Undantag: granskningen av anmälda delade Tacticsboard-objekt ligger kvar i Webtools, eftersom Tacticsboard säljs fristående.

## Delar

| Del | Innehåll | Serverfunktioner | Status |
|---|---|---|---|
| 1. Klubbar (läsa) | Alla klubbar: status, verifiering, lag, personer, konton, klubbadmins med konto, styrelsemandat, styrelse under bildning, väntande styrelseändringar. De som behöver hjälp först. En klubb öppnas med namn på admins, styrelse, väntande ändringar och lag. | `api.list_clubs_for_support()`, `api.get_club_for_support(club)` (loggar `support.club_viewed`) | Byggd 2026-11-14 |
| 2. Statistik | Konton (totalt, typ, nya, kopplade till klubb), aktiva (i dag, 7 och 30 dagar, i perioden), aktiva konton per dag, appar (webben, Android, iPhone, Tacticsboard, Webtools), klubbar och lag, användning per område (aktiviteter, kallelsesvar, närvaro, meddelanden, Tacticsboard-projekt och livelektioner, bokningar), Tacticsboard-prenumerationer och enheter med push. Perioden 7, 30, 90 eller 365 dagar. Bara antal, inga namn. | `api.get_platform_usage_for_support(period_days)`, `api.record_app_activity(app)` och tabellen `core.profile_activity_apps` | Byggd 2026-11-14. Aktiva dagar finns sedan 2026-09-30, vilken app först från 2026-11-14. Kvar: Webtools och Tacticsboard anropar ännu inte `record_app_activity`, så de räknas inte som appar. |
| 3. Klubbar (åtgärder) | Utse klubbadmin bland personer med konto, verkställa eller avbryta en styrelseändring som fastnat, nödundantaget `teamzone.allow_no_club_admin` som loggad funktion med motivering. | `api.support_grant_club_admin`, `api.support_resolve_board_change`, `api.support_end_assignment_without_admin` | Planerad |
| 4. Supportadmins | Lista, lägga till (befintliga konton) och ta bort; den sista kan inte tas bort. | `api.list_support_admins`, `api.grant_support_admin(email, reason)`, `api.revoke_support_admin(profile, reason)` (loggar `support.admin_granted` och `support.admin_revoked`, felkod `last_support_admin`) | Byggd 2026-11-14 |
| 5. Logg | Supportens egna åtgärder ur `audit.command_events`. | `api.list_support_actions` | Planerad |

Alla funktioner kräver supportadmin, nekar andra med `insufficient_privilege` (`not_found`), och ändringar kräver motivering, loggas och använder PT409 vid konflikt. Vidgade rättigheter skrivs in i [permissions-review.md](permissions-review.md).

## Del 1 i appen

- `lib/src/features/support/support_club_services.dart`: tjänst och modeller (`SupportClubServices`, implementeras av `SupabaseMembershipServices`).
- `lib/src/features/support/support_clubs_tab.dart`: fliken Klubbar och klubbens detaljvy.
- `lib/src/core/localization/support_strings.dart`: texterna.
- `_SupportAdminSurface` har flikarna Ärenden och Klubbar.
- Test: `test/support_club_overview_test.dart`.

## Del 2 i appen

- `lib/src/features/support/support_usage_services.dart` och `support_usage_tab.dart`: fliken Statistik.
- `SupabaseProfileServices.recordActivity` anropar `record_app_activity` med `web`, `android` eller `ios` (skrivbordsbyggen använder det gamla anropet).
- Test: `test/support_platform_usage_test.dart`.
