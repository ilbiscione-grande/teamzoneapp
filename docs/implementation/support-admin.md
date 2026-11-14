# Adminsida för TeamZones support

**Status: del 1–4 byggda 2026-11-14, och sidan är bruten loss från appen. Del 5 planerad.**

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
| 3. Klubbar (åtgärder) | I klubbens vy: utse klubbadmin bland personer i klubben med konto, ta bort en klubbadmin (nödundantaget när klubben då står utan klubbadmin med konto), verkställa eller avbryta en styrelseändring som fastnat. Varje åtgärd kräver motivering (5–500 tecken) och loggas. | `api.support_grant_club_admin(club, person, reason)`, `api.support_remove_club_admin(club, person, reason)`, `api.support_resolve_board_change(change, apply\|cancel, reason)` (loggar `support.club_admin_granted`, `support.club_admin_removed`, `support.board_change_applied`, `support.board_change_cancelled`) | Byggd 2026-11-14 |
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
- **Mer om ett kort (2026-11-14):** varje kort i Statistik går att klicka på. Det visar vad som räknas, ett värde per dag i perioden (nya konton, aktiva, nya klubbar, antal i området och så vidare) och uppdelningar: kontotyp, kopplade till klubb, per app, verifiering, sport, typ av aktivitet, svar, status, betalperiod, och de 15 klubbar som har flest. Serverfunktion `api.get_usage_detail_for_support(metric, item, period_days)` (migration `20270321090000_support_usage_details.sql`); bara antal, och de enda namnen är klubbnamn. Appen: `support_usage_detail.dart` (`SupportUsageDetailSheet`, `UsageBars`), test `test/support_usage_detail_test.dart`.

## Del 3 i appen

- Migration `20270320090000_support_club_actions.sql`. Klubbens vy (`api.get_club_for_support`) har nu också id för admins och väntande ändringar, och personerna i klubben med konto.
- **Utse klubbadmin:** personen får Medlemmar och lag över klubben genom en klubbroll (`club_functionary`), som Klubbens roller gör. Rollen skapas om personen saknar den. Bara Medlemmar och lag ges; den nya admin kan sedan dela ut det den själv har.
- **Ta bort klubbadmin:** personens Medlemmar och lag avslutas, övriga roller finns kvar. Planen sa `support_end_assignment_without_admin`, men att ta bara rättigheten är snävare än att avsluta hela uppdraget. Om klubben då står utan klubbadmin med konto används nödundantaget: `teamzone.allow_no_club_admin` sätts, spärrens trigger kontrolleras direkt (`set constraints ... immediate`) och inställningen stängs av igen innan funktionen är klar. Loggen visar `left_without_admin`.
- **Styrelseändring som fastnat:** verkställs med samma kontroller som styrelsens egen (uppdraget aktivt, ingen överlappande post), men utan styrelsens godkännanden; loggen visar hur många godkännanden ändringen hade. Avbryta sätter den till avbruten.
- `lib/src/features/support/support_club_actions.dart`: tjänst (`SupportClubActionServices`, implementeras av `SupabaseMembershipServices`) och dialogerna. Knapparna sitter i `SupportClubDetailSheet`.
- Test: `test/support_club_actions_test.dart`. Provad mot databasen i en transaktion som rullades tillbaka (nekas för andra, motivering, utse, igen ger PT409, ta bort, nödundantaget, spärren håller för andra ändringar, verkställa och avbryta).
