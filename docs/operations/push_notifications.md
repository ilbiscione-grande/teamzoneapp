# Push notifications (Firebase Cloud Messaging)

Status checked 2026-10-25: push is implemented and has delivery records in
audit (latest observed 24 October); Android callup/reply actions have physical
evidence from 13–15 October below. This is not a new device test. iOS setup and
device verification remain open. See [current status](../implementation/current_status.md).

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

## Answering a callup from the notification (Android)

Decided 2026-10-13: callups first, "Kan inte…" opens the app (a decline
needs a reason), and Android asks for unlock before an answer is sent.

1. For a new callup, a late callup or a reminder that still waits for an
   answer, `push_message_for_outbox` (migration `20261024090000`) issues a
   single-use response token. Only its SHA-256 hash is stored
   (`internal.push_response_tokens`). It is valid for two days (or until the
   callup expires, if sooner) and can only answer "accepted" for that callup
   and person. A
   guardian's token answers for the called child.
2. On Android the worker sends such a push as a data message. The app draws
   it itself (`packages/teamzone_notifications`, also when it is closed,
   through the FCM background handler) on the channel "Kallelser och
   meddelanden" (`teamzone_push`), with two buttons:
   - **Kommer:** Android 12+ asks for unlock first; older versions answer only
     on an unlocked phone. The token goes to the Edge Function
     `push-callup-response` (no JWT; the token is the credential). It answers
     through `internal.respond_callup_from_push` as the recipient, with the
     app's own rules (`respond_callup_for_actor`). The notification is then
     replaced by "Svar skickat: kommer" (which removes itself after five
     seconds), "Kallelsen kan inte besvaras här längre" (cancelled, expired
     or already answered; 410) or "Svaret skickades inte" (a tap opens the
     callup).
   - **Kan inte…:** opens the event's participants with the reason dialog
     (`?tab=participants&decline=<callup>`).
3. Tokens are issued only to recipients with a device. Two days is enough:
   a notification nobody has answered by then has most likely been swiped
   away (decided 2026-10-15, migration `20261029090000`).
4. A second tap, or a retry after a lost reply, answers nothing new. Neither
   the token nor the payload is logged.
5. iOS still gets the plain notification without buttons, and no token.

## Replying to a message from the notification (Android)

Like answering a callup (migration `20261025090000`): the push for a
message in an active thread one can write in (not announcements) carries a
single-use reply token, hash only, valid for one reply in that thread for
two days. The app draws it with **Svara** and a text field; Android 12+
asks for unlock before it is sent. `push-message-reply` (no JWT) passes the
token and text to `internal.reply_from_push`, which sends it as the
recipient through `internal.send_message_for_actor` (access, 1–4000
characters, closed announcements). The notification then says "Svar
skickat" (removed after five seconds) without the text; lock screens never
show message text. A newer message in the same thread replaces the earlier
notification. Neither the token nor the text is logged.

A tapped message notification opens its thread. When that thread belongs
to a team that is not selected in the inbox, the inbox widens to every
connection once so the thread can open.

While the app is open, pushes are shown by the app (FCM shows nothing then).

## Activation (product owner)

The following is the activation procedure for an unconfigured environment,
not a claim that audit is still inactive. Nothing is sent there until steps
2–4 are done; before configuration notifications are recorded as
`suppressed / provider_not_configured`. In an existing environment, inspect
migration/object and secret configuration before applying any step; do not
rerun migrations or overwrite secrets merely to follow this historical checklist.

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
7. **Answering from the notification:** run
   `supabase/migrations/20261024090000_push_callup_response.sql` and record it,
   then deploy the response function and the worker again:
   ```sql
   insert into supabase_migrations.schema_migrations(version,name) values ('20261024090000','push_callup_response') on conflict (version) do nothing;
   ```
   ```powershell
   npx supabase functions deploy push-callup-response --project-ref hgcshgunvooyudvrcpig
   npx supabase functions deploy notification-worker --project-ref hgcshgunvooyudvrcpig
   ```
   Verified on the test project 2026-10-14 (Android 16): unlock was asked
   for, the callup became `accepted` and the notification said so.
8. **Replying from the notification:** run
   `supabase/migrations/20261025090000_push_message_reply.sql` (check that it
   ran: `internal.push_reply_tokens` exists; logging it is not enough) and
   record it, then deploy:
   ```sql
   insert into supabase_migrations.schema_migrations(version,name) values ('20261025090000','push_message_reply') on conflict (version) do nothing;
   ```
   ```powershell
   npx supabase functions deploy push-message-reply --project-ref hgcshgunvooyudvrcpig
   npx supabase functions deploy notification-worker --project-ref hgcshgunvooyudvrcpig
   ```
   Verified on the test project 2026-10-14: the reply was sent as the
   recipient into the direct thread and the token was consumed.

## iOS

Needs the iOS app in Firebase, the Push Notifications capability and an APNs
key uploaded to Firebase (see `ios_release.md`). Plain notifications need no
server changes; answering from the notification on iOS needs notification
categories with actions and the response token in the APNs payload.
