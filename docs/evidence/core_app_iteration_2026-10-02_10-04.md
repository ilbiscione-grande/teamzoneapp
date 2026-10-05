# Core app iteration 2026-10-02–2026-10-04

## Scope and baseline

This document consolidates the product changes made after the broad documentation
sync in commit `88e2e8c` (`docs: wave 10 through 2026-10-02`) through commit
`ef39c93` (`feat: move support conversations into inbox`). Feature-specific
evidence remains authoritative for exact test runs and database checks; this page
records the current combined product state.

## Min assistent

The assistant is still deterministic. No generative AI has been enabled. It now
collects concrete tasks from existing, capability-filtered TeamZone projections:

- activities within 48 hours that still lack sent callups;
- callup reminders, including recipient review before sending;
- finished matches from the last seven days that lack a result or report;
- overlapping visible activities in the same team;
- personal calendar conflicts across the teams and clubs in which the signed-in
  account participates;
- unfinished preparation items before an activity.

Cross-team conflict detection is deliberately account-private. It only uses the
account's own pending or accepted callups, does not combine a guardian's children,
does not infer travel time and does not expose one team's event details to another
team.

The presentation has also been revised:

- warnings belonging to the same activity are grouped into one card;
- cards start compact and expose details on expansion;
- `Åtgärda`, `Skjut upp` and `Arkivera` are available directly on a card;
- postponed and archived state is private, revision protected and can be restored;
- the `Här och nu` section follows the current page and activity context;
- category chips separate important items, preparations, matches, training and
  other tasks;
- the FAB shows the number of active tasks the account may see;
- desktop uses a wider assistant column, while phone and tablet retain the FAB;
- the header contains the chosen assistant identity, refresh and settings;
- the welcome message can be dismissed permanently and enabled again in settings.

Each account can choose which task types are shown, whether the assistant should
show only the current team or all authorized teams, a personal assistant name and
one of six bundled profile images. These preferences are account-scoped and do not
change authorization.

Detailed evidence:

- [context-aware tasks](assistant_context_tasks_2026-10-02.md)
- [missing callups](assistant_missing_callups_2026-10-02.md)
- [reminders and match follow-up](assistant_reminders_match_followup_2026-10-02.md)
- [same-team conflicts and preparations](assistant_conflicts_preparation_2026-10-02.md)
- [compact task UI and dispositions](assistant_compact_ui_2026-10-02.md)
- [personal cross-team conflicts](assistant_personal_conflicts_2026-10-02.md)
- [categories and team scope](assistant_categories_team_scope_2026-10-03.md)
- [settings](assistant_settings_2026-10-03.md)
- [name and bundled profile images](assistant_profile_avatar_2026-10-03.md)

## Account data, addresses and profile editing

Contact information linked to an account is treated as the person's shared account
data rather than as independent copies owned by individual teams. A submitted
contact update for a linked account is not applied immediately: the account holder,
or an authorized guardian, must approve it first. Approval rechecks the submitted
snapshot and guardian authority, then updates the shared profile and relevant club
records transactionally. Notifications to other authorized contexts do not include
the contact values themselves.

The address model now supports:

- more than one address for a person;
- a selected contact address per club relationship;
- restricted identity mode with a separate display name;
- restoration of the previous ordinary display name when restricted mode is
  disabled.

Profile editing is opened from the edit icon in the app bar. The editor separates
profile, contact information, role/title and settings. Addresses are under contact
information. Personal, team and club settings are shown according to the account's
capabilities. A club functionary may update their own role/title in a team.

Profile-image selection now requests a maximum dimension of 1024 pixels and uses
compressed image output, allowing the user to select source images larger than
2 MB. The final upload still respects the server limit and gives a clear error if
the selected image cannot be reduced sufficiently.

The review also centralized team-wide publication controls for match results and
training times, corrected replay protection and reset Turnstile after failed public
submissions. See [review fixes](review_fixes_2026-10-02.md) and
[address privacy](../implementation/address-privacy.md).

## Official clubs and support operations

The support queue at `/support` is the operational desktop/web surface for official
club verification, protected club names, account erasure and login-email cases.
Access is controlled by the platform support-admin role and every transition is
revision protected and audited.

Approving a protected-name request can now complete the registration in one
transaction: it creates or links the official club and first team, activates the
requester as a club functionary and initializes the public publication context.
The operation is idempotent, so a retry does not create duplicate clubs, teams or
memberships.

Support and the requester can have a case-bound conversation. Requester cases now
live in Inbox rather than in the main navigation. The Inbox shows an unread-count
badge backed by a per-account read cursor and refreshes on resume and periodically.
The support queue likewise distinguishes new requester messages.

Both sides can attach up to five private files to a message, with a maximum of
10 MB per file. Accepted formats are JPEG, PNG, WebP, PDF, plain text, CSV,
Microsoft Word/Excel/PowerPoint and OpenDocument text/spreadsheets. Files are stored
in the private `support-case-files` bucket and opened through short-lived signed
URLs after server-side case membership or support-admin checks. The waiting-room
entry remains available for accounts that have no product context and therefore no
Inbox.

New support cases are queued privately in Supabase and delivered through the
`support-email-worker` Edge Function. The scheduled worker uses Supabase Cron and
`pg_net`; Resend sends outbound email. Netlify hosts DNS for `teamzoneapp.se`, and
ImprovMX forwards incoming mail for `support@teamzoneapp.se` to the operational
mailbox. The notification-recipient registry is the only source of outbound support
recipients; support administrators' private account addresses are not recipients.

Operational details are in the
[support email runbook](../operations/support_email_runbook.md), the machine-readable
[service inventory](../../ops/service_inventory.json) and the
[support queue evidence](support_club_verification_queue_2026-10-03.md).

## Database changes

The following migrations belong to this iteration:

| Area | Migrations |
|---|---|
| Review and account data | `20261002084222_review_fixes_team_publication_and_profile`, `20261002120001_intake_contact_approval`, `20261002120002_address_privacy_controls`, `20261002120003_restore_name_after_privacy`, `20261003090342_club_functionary_self_team_role` |
| Assistant | `20261002121840_assistant_missing_callups`, `20261002132339_assistant_match_followup`, `20261002135847_assistant_conflicts_preparation`, `20261002142418_assistant_task_disposition`, `20261002185842_assistant_personal_calendar_conflicts`, `20261003063110_assistant_task_visibility_preferences`, `20261003064829_assistant_task_team_scope`, `20261003070703_assistant_profile_avatar`, `20261003072031_expand_assistant_profile_avatars`, `20261003083806_assistant_welcome_message_visibility` |
| Support | `20261003094810_support_club_verification_queue`, `20261003100000_support_email_open_case_backfill`, `20261003101010_support_email_trigger_revision_fix`, `20261003110959_support_notification_recipient`, `20261003134430_schedule_support_email_worker`, `20261003135312_restrict_support_email_to_notification_recipients`, `20261003171000_complete_protected_name_registration`, `20261003180000_protected_name_support_conversation`, `20261004133943_support_inbox_unread_attachments` |

The linked evidence pages contain the exact isolated SQL, hosted transaction,
Flutter widget and analyzer results for each delivery. The final support delivery
was verified with 23 focused Flutter tests, clean focused analysis and a hosted
role/attachment transaction test. The support and assistant flows remain subject to
normal physical-device regression when their UI changes again.

## Current boundaries

- Generative assistant behavior remains disabled.
- Support attachments are private support-case files; they are separate from the
  ordinary team-message attachment model.
- Email notification is an alert and deep link. The support conversation and
  decision remain inside TeamZone.
- The operational support mailbox is a forwarding destination, while `/support` is
  the source of truth for status, messages and decisions.
