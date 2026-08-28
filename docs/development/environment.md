# Development environment

## Verified S00 baseline

- Windows 10 Pro 22H2
- Flutter 3.44.8 / Dart 3.12.2
- Java 17.0.20
- Android SDK 36.0.0; licenses accepted
- Chrome available for Flutter web
- Node 24.19.0 / npm 11.17.0
- Supabase CLI 2.111.0
- Git 2.55.0.windows.3

Visual Studio is intentionally absent because native Windows desktop is not a v1 target. Android and web are buildable on this host. iOS project files are maintained here, while building/signing requires macOS or suitable CI.

No Docker-compatible runtime or local PostgreSQL server is required for S00. Future database migrations are tested in the hosted audit project until an explicitly approved isolated runtime exists.

## Environment contract

`TEAMZONE_ENV` accepts `local`, `audit`, `staging` or `production`. Unknown values parse fail-safe to `local`. S00 does not wire a Supabase project.

Secrets are supplied outside Git. Flutter/web/mobile clients may only receive a Supabase publishable key; secret/service-role keys remain server-side.
