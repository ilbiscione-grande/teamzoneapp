# AUTH-01 – Logga in och Skapa konto

**Datum:** 2026-08-23  
**Status:** LOKALT VERIFIERAD, HOSTED GRIND ÅTERSTÅR  
**Livepåverkan:** Ingen. Supabase-projekt, Auth-inställningar, redirectallowlist, användare och databas är oförändrade.

## Implementerat

- Separata, tydliga ingångar för `Logga in` och `Skapa konto`.
- Båda ingångarna erbjuder lösenord och e-postkod/säker länk.
- Password login behåller befintlig mätt `auth-password-sign-in`-gräns och läcker inte credentials till loggar.
- Lösenordsregistrering använder Supabase signup, kräver minst åtta tecken och visar verifieringskrav innan inloggning.
- Om signup oväntat ger en session innan e-post är verifierad loggas klienten ut och går inte vidare till produktskalet.
- E-postinloggning använder `shouldCreateUser: false`; e-postregistrering använder `shouldCreateUser: true`. Därmed kan loginflödet inte skapa en ny identitet av misstag.
- Kodverifiering använder aktuell `OtpType.email`; säker länk kan slutföra samma flöde via PKCE/deep link.
- Challengekontraktet har 60 sekunders resend-cooldown och tio minuters klientexpiry, pending/double-submit-skydd och explicit utgånget läge.
- Glömt lösenord visar samma neutrala svar oavsett backendresultat.
- `AuthChangeEvent.passwordRecovery` tar över appens bootstrap och öppnar en särskild vy för nytt lösenord.
- Redirects är explicit avgränsade till `teamzone://app/auth/callback` och `https://app.teamzoneapp.se/auth/callback`; inga wildcardredirects har införts.

## Filer

- `lib/src/core/identity/auth_entry_services.dart`
- `lib/src/core/supabase/supabase_bootstrap.dart`
- `lib/src/features/auth/auth_surfaces.dart`
- `lib/src/app/teamzone_app.dart`
- `lib/src/core/localization/app_strings.dart`
- `test/auth01_entry_flows_test.dart`

## Automatiserad verifiering

- Separata startlägen och båda authmetoderna renderas.
- Password signup validerar bekräftelse och visar verifieringsinstruktion.
- Email login skickar uttryckligen `signIn`, email signup skickar `signUp`.
- Kod kan verifieras och resend är disabled under cooldown.
- Neutral recoverytext visas även när fakebackend kastar fel.
- Recovery-event prioriteras över en befintlig authenticated session.
- Cooldown och expiry verifieras med injicerbar deterministisk klocka.
- SDK-kontrakt, exakta redirects och frånvaro av service-role i adaptern fryses med källtest.
- Riktad AUTH-01-svit: **8/8 passerar**.
- Full regressionssvit: **121/121 passerar**.
- `flutter analyze`: **No issues found**.

## Officiell SDK-kontroll

Supabases aktuella Flutter-dokumentation kontrollerades före implementation. Den bekräftar `signInWithOtp` med `shouldCreateUser`, `verifyOTP` med email-typen och att passwordless resend görs genom ett nytt `signInWithOtp`-anrop. Inga relevanta Flutter Auth-breaking changes identifierades i aktuell changelog.

## Kvarvarande verifieringsgrind

Följande kräver separat uttryckligt godkännande att använda en hosted testmiljö eller Supabase live:

1. faktisk leverans av signup-, OTP/magic-link- och recoverymejl;
2. redirectallowlist för exakt mobil- och webborigin;
3. verifierad e-post, befintlig e-post/dubblettbeteende och PKCE-retur på Android/web;
4. resend/rate-limit/expiry mot serverns faktiska policy;
5. kontroll av att e-post, lösenord, OTP och token saknas i hosted loggar.

## Fysisk Android-verifiering

En loopback-konfigurerad audit-APK byggdes och installerades på Samsung SM-S931B utan livekontakt. Följande kontrollerades på den upplåsta telefonen:

- `Logga in` med lösenord visar e-post, lösenord, primär inloggningsåtgärd och `Glömt lösenord?`.
- `Skapa konto` med lösenord visar e-post, lösenord, lösenordsbekräftelse och separat registreringsåtgärd.
- `Skapa konto` med e-postkod/länk visar endast e-postfält och rätt utskicksåtgärd.
- Valda lägen framgår visuellt och alla kontroller ryms utan överlapp eller avklippt innehåll i porträttläge.
- Android-loggen innehöll inga Flutter-fel eller `AndroidRuntime`-krascher efter växlingarna.

Inga formulär skickades och ingen nätverks- eller liveverifiering utfördes. Den hosted verifieringsgrinden ovan kvarstår därför oförändrad.

## Hosted Auth REST-verifiering 2026-09-04

Efter att den hosted migrationsbacklogen stängdes (se
`docs/evidence/hosted_migration_backlog_2026-09-04.md`) återupptogs
AUTH-01:s hosted-grind genom direkta anrop mot GoTrue REST-API:t
(`https://hgcshgunvooyudvrcpig.supabase.co/auth/v1/...`) med projektets
publishable-nyckel. Ingen Flutter-app eller fysisk enhet användes; detta är
en ren API-nivåverifiering.

- **Svagt lösenord avvisas fortfarande korrekt:** `POST /auth/v1/signup` med
  ett 5-teckens lösenord gav `HTTP 422`, `error_code:"weak_password"` med
  samma policybeskrivning (12 tecken, alla fyra teckenklasser) som
  ursprungligen verifierades 2026-08-07 i `docs/security/s01_auth_policy.md`.
  Bekräftar att policyn överlevt hela veckans migrationsarbete oförändrad.
- **Neutralt svar på glömt lösenord bekräftat mot två olika icke-existerande
  adresser:** `POST /auth/v1/recover` gav `HTTP 200` och tomt `{}` för både
  en uppenbart påhittad adress och en syntaktiskt giltig men okänd adress —
  identiskt svar i båda fallen, vilket stödjer kravet att svaret inte får
  avslöja om ett konto finns.
- **Domänvalidering vid registrering är aktiv:** reserverade testdomäner
  (`example.com`, `example.org`, RFC 2606) avvisas med `HTTP 400`,
  `error_code:"email_address_invalid"` innan något mejl skickas. Positivt
  fynd, men det innebär att vidare live-signup-tester kräver en verkligt
  levererbar testdomän/inkorg som den här sessionen inte har tillgång till.
- **Inbyggd mejl-rate-limit är aktiv:** efter ett fåtal på varandra följande
  anrop (recover + signup-domänförsök) svarade servern `HTTP 429`,
  `error_code:"over_email_send_rate_limit"`. Bekräftar att rate limiting
  finns på plats, men blockerar vidare live-mejltester under resten av det
  aktuella fönstret (exakt tröskel/återställningstid inte karakteriserad).
- **Inga hemligheter i svarskropparna:** samtliga infångade API-svar
  genomsöktes efter `service_role`, `secret`, `access_token`, `refresh_token`
  och det testade lösenordet i klartext — inga träffar.

### Kvarstår öppet

Full leverans/mottagning av signup-, OTP- och recoverymejl, redirect-
allowlist på riktig mobil/web-origin, dubblettbeteende för en verkligt
existerande e-postadress samt kontroll av servrarnas egna loggar (till
skillnad från API-svaren) kunde inte verifieras i den här sessionen —
kräver antingen en inkorg denna miljö kan läsa eller fysisk
enhetsverifiering, plus att vänta ut den triggade rate-limiten. AUTH-01
kvarstår därför `[~]`, men med en betydligt smalare och mer specifik
återstående grind än tidigare. Ingen liveändring av Auth-konfigurationen
gjordes; endast läsande/skapande testanrop mot publika endpoints.
