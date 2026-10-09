# Core app iteration 2026-10-08 – 2026-10-09

## Scope and baseline

This page records the product changes of 2026-10-08 and 2026-10-09:

- the temporary laget.se attendance export, commit `973caeb` (`feat: temporary
  attendance export to laget.se`) on top of `b64d310`
- team statistics under Laget, a role-aware fifth bottom-bar button and the
  Arbetsytor placeholder
- fixes to attendance recording, the event status circles and the calendar
  filter sheet

The companion sync tool is commit `e8e3c62` in the separate private repository
[`laget-playwright`](https://github.com/ilbiscione-grande/laget-playwright).
This iteration follows the [2026-10-07 – 2026-10-08 iteration](core_app_iteration_2026-10-07_10-08.md).

The product owner ran all migrations below in the test project. After each
run, read-only catalog queries checked tables, functions and grants: anonymous
users have no access, authenticated users can call the `api` functions but
cannot read the tables. These SQL changes were not dry-run in rolled-back
transactions first.

| Migration | Purpose |
|---|---|
| `20261013090000_attendance_export_laget_se` | Schema `attendance_export`: team integration settings, member links, activity links, export log |
| `20261014090000_attendance_export_sync_agent` | Sync queue and agent heartbeat for the local sync agent |
| `20261015090000_attendance_export_locate_activity` | Sync without an activity link; the agent locates the laget.se activity |
| `20261016090000_team_statistics` | `api.get_team_statistics`: team attendance over a period (Laget → Statistik) |

## A temporary, removable feature

The export is meant to be removed from Teamzone over time, so it is isolated:

- All app code lives in `lib/src/features/attendance_export/` as its own
  library, not as a `part of` the app.
- Existing code has four hooks marked `attendance-export:hook`: two imports,
  one line in the Supabase bootstrap, the event "⋮" menu entry and the team
  settings entry. Calendar, attendance and roster models are unchanged.
- All database objects live in schema `attendance_export` plus thin
  `api.attendance_export_*` wrappers. Core attendance (`core.attendance_facts`)
  is only read.
- `supabase/removal/attendance_export_remove.sql` drops everything.
  [`attendance_export_laget_se.md`](../implementation/attendance_export_laget_se.md)
  lists every hook to delete.
- The build flag `TEAMZONE_ATTENDANCE_EXPORT` hides every entry point. It
  defaults to on.
- Teamzone never stores laget.se credentials.

## Export to a file

- **Architecture.** A provider-neutral export basis is built from the existing
  `get_event_details` and `get_event_squad` projections. The laget.se adapter
  matches people by Teamzone person id, never by name. It validates in a
  separate step and writes the verified JSON contract
  (`activityId`, `participants[{name, role, present, id}]`). The UI shows the
  result.
- **Attendance.** `present`, `late` and `partial` become `present: true`, as in
  Teamzone's own statistics, and `absent` becomes `false`. Unknown attendance is
  never exported as absent. Callup answers are not used.
- **Completeness.** Teamzone has no "attendance completed" status. The minimal
  solution is an explicit confirmation in the export view, stored on the export
  record.
- **Validation** blocks the file when any of these is found: the event has not
  ended, the activity id is missing or invalid, a member link is missing,
  duplicated, conflicting or belongs to another team, a field is invalid, or the
  basis is not confirmed. A message reads, for example, "Kan inte exportera:
  2 spelare saknar laget.se-ID." Guests without a link must be linked or
  explicitly left out. Members of other teams sharing the event are not
  affected.
- **File.** `laget_se_<eventId>.json` in UTF-8 is saved with the existing
  `file_picker`: a browser download on web, the system "save as" sheet on
  Android and iOS. Teamzone writes no temporary copy.
- **Status.** The log keeps counts and a SHA-256 of the file, never names. The
  view shows "Inte exporterad", "Exportfil skapad (ej bekräftad i laget.se)",
  "Export misslyckades" or "Verifierad i laget.se". Repeated exports are
  allowed. An unchanged basis gives an identical file.

## Member links

- **Integrationer → laget.se** in the settings' team tab, for
  `team.roster.manage`. It holds an enable switch, the team's name in the
  laget.se address, and member links per team with laget.se id, name and role.
- **Import from laget.se.** The sync tool's `members` command writes the
  team's players and leaders (name, role and id, no attendance). Teamzone
  proposes links:
  - **Safe:** a unique exact name on both sides.
  - **Changed:** the same id with a new name or role.
  - **Choose yourself:** duplicates or similar names.
  - **No match:** listed in both directions.

  Nothing is saved without approval. The import also fills in the team's
  laget.se address name.

## Direct sync through the local sync agent

**Skicka till laget.se** in the export view queues the basis in
`attendance_export.sync_jobs`. The sync agent runs on the administrator's
computer, started from a desktop shortcut that opens a local page. It works as
the signed-in Teamzone user:

1. It reads the laget.se activity with all writes blocked and reports a
   preview, for example "Anna (spelare): ? → ✓".
2. The administrator approves exactly that preview (`preview_sha256`).
3. The agent reads the page again and requires a new approval if anything
   changed. Otherwise it applies the changes, reads the page back and reports
   "Verifierad i laget.se" or the cause of failure.

The export view shows whether the agent is running and whether it needs a new
laget.se login. Jobs wait in the queue meanwhile. The server accepts only
people linked in the team, and empties the queued basis when the job ends.
A line under the disabled button says what is missing, for example "koppla
aktiviteten i laget.se".

## Locating the laget.se activity

Without an activity link the agent searches the team's laget.se calendar for
the same date and start time in the team's time zone. A snapshot of the real
calendar page was taken with names and long ids masked but dates and times
kept, and the selectors are based on it.

- **Exactly one activity at that time:** linked.
- **Several at that time:** the type decides (training, match or other).
- **Times differ between the systems:** exactly one training, or exactly one
  match, that day is linked. For example 17:30 in Teamzone and 18:00 in
  laget.se. This does not apply to "other".
- **Otherwise:** the job ends as `needs_activity`, and the app lists that day's
  activities with **Välj**. Choosing one links it and sends the sync again.

The link is reused by later exports. A file always needs the link. Creating
activities in laget.se is deferred.

## Team statistics under Laget

The former Statistik destination showed five all-time counters, which no one
could act on. Personal figures already live on each member's profile, so
Statistik is now a team view for the people who manage the team
(`event.attendance.manage`, `event.manage` or `team.roster.manage`).

- **Laget → Statistik** is a fourth tab next to Översikt, Trupp and Kalender.
  It is hidden for other roles.
- **Period:** 30 days, 90 days or this year.
- **Headline numbers:** attendance, training and match attendance, callup
  answers and late arrivals. Team rates are about the players; leaders are
  listed separately.
- **Attendance per month:** one series as thin bars, the latest value
  labelled, a tooltip on every bar.
- **Lowest attendance:** players with at least three counted activities.
- **Every player and leader** with attended of counted, trainings, matches and
  late arrivals. A tap opens the member's own statistics.
- **Same rules as the rest of the app:** present, late and partial count as
  attended; an absence only counts for someone who was called (or when the
  event had no callups); unregistered attendance is not counted. Only events
  that have started, are not cancelled and belong to the team are included.
- `/statistics` redirects to `/team?tab=statistics`, so old links keep working.

## A role-aware fifth bottom-bar button

Laget, Kalender, Hem and Inkorg are the same for everyone. The fifth button
follows the active context:

| Active context | Fifth button |
|---|---|
| Leader in a team | Arbetsytor |
| Club functionary with economy capabilities | Ekonomi |
| Club functionary with board capabilities | Styrelse |
| Player, guardian, everyone else | Inställningar |

- **Own choice.** Inställningar → Personligt → "Femte knappen i menyn" offers
  "Automatiskt (efter roll)" plus the destinations the user may open. The
  choice is stored on the device, like the theme. A choice the active context
  does not allow falls back to the role default.
- **Arbetsytor** is a placeholder for the coming modules. It opens Utveckling
  and lists Träning, Match and Planering as coming. Leaders also find it in
  the navigation drawer.
- **Own profile.** Inställningar → Personligt starts with "Min profil och
  statistik", which opens the user's own team profile. It is not shown to
  someone who is only a guardian.

## Attendance and event details

- **A tap cycles through three states** when recording attendance after an
  event: Ej registrerad → Närvarande → Frånvarande → Ej registrerad. A
  mistaken tap can always be undone. A walk-in without a callup goes straight
  back to unregistered. Late and partial are still reached by long-pressing
  the row.
- **Late corrections that are undone** are no longer staged. A person set back
  to their saved status no longer counts as a change, so the reason field and
  the change counter disappear when nothing is left to save.
- **The status circles explain themselves.** Each has a tooltip on hover and
  on tap, for example "Kallade: 12 har fått kallelse" or "Deltog: 9
  registrerade som närvarande (även sena och delvis)".
- **A constant gap to the tab row.** The circles shrink on every tab except
  Info. The layout now shrinks with them, so the tab row moves up instead of
  leaving a growing gap.

## Calendar

- The view and filter sheet closes with an ✕ in its title row instead of a
  "Klar" button at the bottom. Filter changes still apply immediately.

## Verification

- `flutter analyze`: no issues. Full test suite: 659 tests pass.
- New tests:
  - JSON contract, players and leaders, present and absent, unknown
    attendance, missing links, invalid ids, duplicates, members of several
    teams, an empty participant list, repeated export and conflicting data.
  - Member import parsing and proposals.
  - Widget tests for the export view, the import approval and the sync flow:
    preview, approval and choosing a candidate activity.
- Sync tool: `tsc --noEmit` and `npm run selftest` pass against fixture pages
  built after the real activity and calendar structure. The local server's
  host, origin and JSON guards were smoke-tested.
- End to end against laget.se on 2026-10-09, run by the product owner:
  - `members` and the import created 7 links.
  - A JSON file was exported.
  - A sync where laget.se already matched was verified with 0 changes.
  - A sync where a start time differed was linked by choosing the candidate
    activity.
  - An approved sync made 2 changes, read them back and was verified with 0
    remaining.
  - The same-type rule for differing times was reported working after the
    change.
- Team statistics: the PGlite test `supabase/tests/team_statistics.local.mjs`
  runs the real migration against fixture tables. It covers permission, the
  period, player-only team rates, the expected-absence rule, unknown
  attendance, and which events are excluded (cancelled, future, other teams,
  outside the period).
- New widget and unit tests cover the fifth button per role and the fallback
  for a disallowed choice, the Laget → Statistik tab and its redirect, the
  attendance tap cycle, undone late corrections, the status circle tooltips
  and the tab row moving up with the circles.
- `20261016090000_team_statistics` was checked after the run with read-only
  queries (authenticated may execute, anonymous may not).
- Installed on Android (Samsung S25) as a debug build.
