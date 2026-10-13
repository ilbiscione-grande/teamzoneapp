# X-OBS-01 observability policy

- Structured records contain event, severity, release, environment, correlation
  ID and allowlisted low-cardinality dimensions only.
- Tokens, headers, request/response bodies, e-mail, free text, sports facts,
  health data, error messages and raw stack traces are prohibited.
- Crash stack traces (amended 2026-10-13, see PAR-OPS-05): a fatal, unhandled
  error may carry its stack reduced to code locations only — function name,
  `package:`/`dart:` URI or bare file name, line and column; at most 30
  frames. The error is sent as its type, never its message. Absolute paths
  are cut to the file name and any other line is dropped
  (`StackSanitizer`); the web sink re-validates every frame and rejects the
  whole record on a mismatch. Handled failures (`AppErrors.caught`) carry no
  stack. `--dart-define=TEAMZONE_CRASH_STACKS=false` turns stacks off.
  Source maps and symbol files are never published (hosting ignores `*.map`).
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
