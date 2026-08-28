# AUTH-02 – Session, återkallelse och utloggning

**Datum:** 2026-08-23  
**Status:** LOKALT IMPLEMENTERAD OCH VERIFIERAD, FYSISK/HOSTED GRIND ÅTERSTÅR  
**Livepåverkan:** Ingen. Supabase-projekt, Auth-inställningar, användare och databas är oförändrade.

## Implementerat

- Supabase-session med saknad eller utgången token betraktas som unauthenticated; skyddade ytor visas inte.
- Fel i auth-state-strömmen hanteras fail-closed i stället för att bli ett ohanterat zonfel.
- Oväntat sessionsslut visar en neutral återhämtningsvy och kräver ny inloggning.
- Explicit utloggning använder `SignOutScope.local`, rensar lokalt aktivt kontextval och återbygger appträdet.
- Mobil använder SDK:ns beständiga sessionslagring.
- Webben visar ett explicit val `Delad enhet`. Valet tar bort befintlig beständig session och blockerar fortsatt tokenpersistens i webblagringen.
- Senast valda kontext sparas per profil och måste finnas i det färska, serverreturnerade kontextsvaret innan den återställs.
- Ett ogiltigt eller upphört kontextval faller begripligt tillbaka i ordningen leader, club functionary, guardian, player och guest.
- Kontextbyte nycklar om hela produktskalet, vilket avbryter/disponerar ytspecifik state och hindrar sena svar från föregående kontext.

## Filer

- `lib/src/core/identity/session_persistence.dart`
- `lib/src/core/identity/identity_services.dart`
- `lib/src/core/supabase/supabase_bootstrap.dart`
- `lib/src/app/teamzone_app.dart`
- `lib/src/app/product_shell.dart`
- `lib/src/features/auth/auth_surfaces.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/auth02_session_context_test.dart`

## Verifiering

- `flutter analyze`: **No issues found**.
- Ny testfil täcker giltig/återkallad kontext, profilseparerad persistence, delad-enhet-lagring, fail-closed UI samt adapterkontrakt.
- Testet rättades från ett oändligt `pumpAndSettle` mot inloggningssidans avsiktliga OTP-timer till avgränsade pumps.
- Testrunnerlåset spårades till övergivna `cmd.exe`-wrappers samt att sandboxen saknade åtkomst till Flutter-SDK:ns låsfil. Endast identifierade övergivna wrappers stoppades och `flutter test` fick ett avgränsat testundantag.
- Riktad AUTH-02-svit: **5/5 passerar**.
- Riktade tidigare felande smoke/FND-sviter: **5/5** respektive **15/15 passerar**.
- Full regressionssvit: **126/126 passerar**.
- En testmiljöregression upptäcktes och rättades: beständig `SharedPreferences`-lagring injiceras nu bara i verklig Supabase-bootstrap, medan fake/oanslutna tjänster använder en stateless säker standard.

## Kvarvarande grind

1. Cold-start med faktisk sparad och utgången testsession.
2. Återkallad session och avslutad relation i en uttryckligen godkänd hosted testmiljö.
3. Fysisk Android-verifiering av sessionsåterställning och utloggning.
4. Webbverifiering av beständig respektive delad enhet i en godkänd testmiljö.

Punkterna kräver hosted testdata eller motsvarande separat godkännande. Ingen sådan miljö användes i detta arbete.
