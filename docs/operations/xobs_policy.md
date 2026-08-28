# X-OBS-01 observability policy

- Structured records contain event, severity, release, environment, correlation
  ID and allowlisted low-cardinality dimensions only.
- Tokens, headers, request/response bodies, e-mail, free text, sports facts,
  health data and raw stack traces are prohibited.
- User-facing errors remain neutral and may show only a safe correlation ID.
- Critical integrations are fail-closed and require explicit environment flags.
- PAR-OPS-05 uses Supabase Logs, Firebase Crashlytics for Android/iOS and Google
  Cloud Logging/Error Reporting for web. Google Analytics remains disabled.
- Error/crash retention is 30 days and performance retention is 14 days.
- P0 alerts are immediate. Critical Auth, checkout, messaging and command flows
  alert at 5 percent failures over five minutes.
- The product owner is primary on-call until a named operations owner exists.
- Supabase Management API automation must use the current `logs` endpoint;
  `logs.all` is not permitted because it is removed on 2026-09-23.
