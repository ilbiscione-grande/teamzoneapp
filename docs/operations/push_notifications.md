# Push notifications (Firebase Cloud Messaging)

Decided 2026-10-13: push through FCM (Android now, iOS via APNs once the iOS
app exists), lock-screen text **type + activity** without names or free text,
and the app asks for permission the first time there is something unread.

## How it works

1. The app asks once, with an explanation, when the notification center first
   has something unread (`ProductShell._maybeOfferPush`). "Inte nu" is
   remembered; the user can still turn push on in the inbox settings.
2. After the user allows it, the app registers its FCM token
   (`api.register_push_endpoint`). The token is stored encrypted (pgcrypto,
   key `push_token_key` in Vault) in `internal.push_endpoint_tokens`; only the
   worker can read it. A token registered for a new account is removed from
   the previous one (shared phones). Signing out unregisters the device.
3. pg_cron starts `notification-worker` every minute. For each queued
   notification it asks `api.push_message_for_outbox` for the text and
   tokens and sends through FCM HTTP v1:
   - callups: "Ny kallelse" / "Påminnelse: svara på kallelsen" /
     "Kallelsen är inställd" with "Träning · P2012 · lör 17 okt 18:00";
   - messages: "Nytt meddelande" with the team name.
   Event titles, thread titles and message text are never used. English
   profiles get English text; the time is in the recipient's time zone.
4. A tap opens the event or the thread (only those in-app routes are
   followed). FCM tokens that no longer exist are disabled.
5. Notifications older than six hours are recorded as `stale` and never sent,
   so a backlog cannot reach phones when push is switched on.

Message pushes also follow the inbox setting (`notification_preferences`);
accepting the permission dialog turns it on.

## Activation (product owner)

Nothing is sent until steps 2–4 are done; until then every notification is
recorded as `suppressed / provider_not_configured`, as before.

1. Run `supabase/migrations/20261023090000_push_delivery.sql` and record it:
   ```sql
   insert into supabase_migrations.schema_migrations(version,name) values ('20261023090000','push_delivery') on conflict (version) do nothing;
   ```
2. **Worker token.** Create a long random value (for example from a password
   manager) and store it in both places:
   ```sql
   select vault.create_secret('<random value>', 'notification_worker_token');
   ```
   ```powershell
   npx supabase secrets set NOTIFICATION_WORKER_TOKEN=<random value> --project-ref hgcshgunvooyudvrcpig
   ```
3. **FCM service account.** In the Firebase console for `teamzoneapp-b02a2`
   (Project settings → Service accounts) generate a private key, or create a
   dedicated service account with the role *Firebase Cloud Messaging API
   Admin*. Check that *Firebase Cloud Messaging API (V1)* is enabled. Then set
   it from a file: passing the JSON on the command line loses its quotes
   (`npx` runs through cmd.exe), and the worker then reports
   `fcm_service_account_invalid`.
   ```powershell
   $json = Get-Content -Raw .\service-account.json | ConvertFrom-Json | ConvertTo-Json -Compress
   Set-Content -Path .\fcm.env -Value ("FCM_SERVICE_ACCOUNT_JSON='" + $json + "'") -Encoding ascii
   npx supabase secrets set --env-file ./fcm.env --project-ref hgcshgunvooyudvrcpig
   Remove-Item .\fcm.env, .\service-account.json
   ```
   The JSON file must never be committed.
4. **Switch on** (the fail-closed kill switch; set `false` to stop at once):
   ```powershell
   npx supabase secrets set NOTIFICATION_PUSH_ENABLED=true --project-ref hgcshgunvooyudvrcpig
   ```
5. Deploy the worker (it now authenticates with the worker token, not a JWT):
   ```powershell
   npx supabase functions deploy notification-worker --project-ref hgcshgunvooyudvrcpig
   ```
6. Build and install the Android app; sign in, wait for something unread and
   accept the dialog.

## iOS

Needs the iOS app in Firebase, the Push Notifications capability and an APNs
key uploaded to Firebase (see `ios_release.md`). The worker and server need no
changes.
