# Core app iteration 2026-10-05

## Scope and baseline

This page records the product changes of 2026-10-05, from commit `8a33b82`
(`feat: Teamzone 2027 worklist and leaner navigation menu`) through `a683578`
(`feat: reminders quiet unanswered callups; scrolling shortcut row`). It follows
the [2026-10-02–2026-10-04 iteration](core_app_iteration_2026-10-02_10-04.md).
The work comes from the product owner's "Teamzone 2027" worklist and from a
review of the navigation menu on a signed-in coach account.

## Navigation menu

The drawer/side panel no longer carries Nyhetsredaktion, Publika sidor or
Supportärenden.

- **Support queue in Inbox.** Support administrators get a "Supportkö" card at
  the top of Inbox with the number of new user messages, opening `/support`.
  As before, it is shown on web and desktop at desktop width only, and access
  is still enforced by the server. Requesters keep "Mina supportärenden" in
  Inbox.
- **Settings tab "Publika sidor".** Shown to accounts that may publish or
  manage a team. One card per club holds the public club and team pages,
  each team's public matches/results/training times, and the newsroom
  ("Nyheter", only with `publication.manage`). These rows moved out of the
  Lag and Klubb tabs; Klubb keeps badge, colours and verification.

## Fixes

- **Archiving an event crashed (`_dependents.isEmpty`).** Dialog text
  controllers were disposed while the dialog was still animating out. A shared
  `disposeAfterDialog` helper now disposes them after the transition; the same
  pattern was fixed in board, economy, preparations, domains and "Avsluta i
  laget".
- **Delete a mistakenly booked event.** "Ta bort event" is offered for draft,
  scheduled and cancelled one-off events while no callup has been sent and the
  event has no sent squad, attendance, match workspace, sponsor pledge,
  explicit public publication or sharing with other teams. Otherwise the event
  is cancelled and archived as before. Series occurrences are still archived.
  Unsent squad drafts, preparations, files and revisions are removed by the
  existing cascades and public team projections by the existing delete
  triggers. The command stays revision checked, idempotent and audited, now
  with title and start time in the audit metadata.
- **Home flashed periodically.** The notification stream also emitted a
  45-second poll for followed-team updates, and Home reloaded everything on
  each tick while showing a loading indicator. Home now opts out of that poll
  (`includeTeamUpdatePoll: false`) and keeps its content while refreshing; a
  failed background refresh keeps the shown projection. This also removes a
  full Home reload every 45 seconds from database egress.
- **Club verification could not be closed.** The full-height sheet now always
  has a close button, also while loading and after sending, plus "Stäng" once
  the request is pending.

## Calendar

- The app bar takes its scrolled-under colour only when the page itself
  scrolls beneath it. Lists under a fixed header (calendar grid, day
  timeline) no longer recolour it. This is a shell-wide rule.
- The date navigation spans the title row with the period centred between the
  arrows; "Idag" sits after the right arrow. Phones use shorter week and day
  labels.
- A horizontal swipe changes month, week, day or agenda start, like the
  arrows.
- The month grid shows events on the leading and trailing days from the
  neighbouring months. The loaded window used to be fixed around today (one
  month back, eleven ahead); it now follows the selected date and reloads,
  keeping shown events, once a visible day falls outside it.
- The day view opens at 15:00. On a phone the end of the day limits the
  offset, so part of 14:00 shows above it. The position is kept while swiping
  between days.

## Appearance

- Personal settings offer System, Ljust and Mörkt. The choice is stored on
  the device next to the colour theme.

## Quick actions sheet

The swipe-up sheet from the Home button now depends on the current page.

- **Gör nu** leads with the page's own actions: on Laget Bjud in spelare,
  Ledare och roller, Kontaktuppdatering and Medlemsansökningar (club
  administrators); in Inbox Skicka meddelande and Nytt informationsmeddelande;
  in the calendar Skapa nytt event, Ny träning and Ny match. Elsewhere each
  page's main action leads.
- **Fler genvägar** holds every other action as one horizontally scrolling
  row of chips.
- **Gå till** holds the destinations as one horizontally scrolling row.
- New deep links: `/team?action=roles`, `/team?action=intake`,
  `/inbox?action=announce` and `/calendar?action=create&type=…`. Team links
  wait for the roster before opening its sheets. The announcement link falls
  back to an ordinary message when the account may not announce.

## Assistant

- After a reminder, an unanswered callup no longer counts towards
  "Obesvarade kallelser" for 6 hours, matching the reminder cooldown. If it is
  still unanswered after that, the warning returns. Sending reminders reloads
  the assistant through the existing participants refresh.

## Database changes

| Migration | Purpose |
|---|---|
| `20261005090000_event_delete_without_sent_callups` | Delete rule and command for events without sent callups |
| `20261005140000_assistant_pending_callups_reminder_quiet` | Reminded callups quiet the unanswered-callups task for 6 hours |

Both are applied to the audit project.

## Verification

- `flutter analyze`: no issues.
- Full Flutter suite: 594 tests green before the final commit; the focused
  quick-actions suite (15 tests) after it.
- New widget tests: support queue in Inbox for admins only, the Publika sidor
  tab and newsroom, theme mode selection and persistence, neighbouring-month
  events, swipe and window reload, day view at 15:00, app bar colour under a
  fixed header (fails without the fix), page-aware quick actions, horizontal
  rows and "Ny match" with match preselected.
- Isolated PGlite SQL: `event_delete_without_sent_callups.local.mjs` (allowed
  and blocked states, cascade, revision, idempotency, audit) and the extended
  `assistant_missing_callups.local.mjs` (reminder quiet window).
- Installed as a debug build on a Galaxy S25 against the audit project. The
  product owner reviewed the calendar and quick actions on the device; a
  complete physical walkthrough of every change remains part of the wave 10
  device gate.

## Boundaries

- Series occurrences are not deleted; they are cancelled and archived.
- The followed-team poll still runs for Inbox and notifications; only Home
  opts out. A realtime broadcast for team updates would let it be removed.
- The Inbox support queue counts unread messages only for protected-name
  cases, the only case type with a read cursor.
