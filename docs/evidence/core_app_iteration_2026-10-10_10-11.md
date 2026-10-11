# Core app iteration 2026-10-10 – 2026-10-11

## Scope and baseline

This page records the product changes of 2026-10-10 and 2026-10-11, on top
of `78d66d1` (`docs: document the 2026-10-08 – 2026-10-09 iteration`):

- an attendance rate that counts only expected people, callup corrections
  after an event and adding people afterwards
- fixes to the event details: the status circles and the participant details
- team and place in the calendar's week and day views
- a simpler event editor: type details moved to Förberedelser, sharing when
  creating, monthly and biweekly series, default lengths per type, a compact
  När section and compact match fields
- a match format per team and per match, with periods for match mode

It follows the [2026-10-08 – 2026-10-09 iteration](core_app_iteration_2026-10-08_10-09.md).

The product owner ran all migrations below in the test project. After each
run, read-only catalog queries checked tables, functions and grants: anonymous
users have no access, authenticated users can call the `api` functions but
cannot read the new table. These SQL changes were not dry-run in rolled-back
transactions first. Each one has a PGlite test that runs the real migration
against fixture tables.

| Migration | Purpose |
|---|---|
| `20261017090000_attendance_rate_expected_and_callup_corrections` | Rates count only expected people, walk-ins reported as extra; `api.correct_callup` |
| `20261018090000_share_event_at_creation` | `api.list_shareable_teams`, `api.share_new_event` |
| `20261019090000_monthly_event_series` | `monthly` recurrence in `internal.create_event_for_actor` |
| `20261020090000_team_match_format` | `core.teams.match_format`, `api.get/set_team_match_format`, format periods for new match workspaces |
| `20261021090000_event_match_settings` | `core.event_match_settings`, `api.get/set_event_match_settings` |

## Attendance rate and callups after the event

- **Expected people only.** `internal.attendance_is_expected` (called, or
  everyone when the event used no callups) now decides who counts. The rate is
  attended ÷ registered among the expected, in the event follow-up, the
  profile statistics and Laget → Statistik.
- **Walk-ins.** Attendance without a callup no longer lifts the rate. It is
  shown separately as "utan kallelse": a part of the follow-up bar, "+N utan
  kallelse" on the profile and per person, and a team tile.
- **Correcting callups.** After an event, the expanded participant row has
  "Kallelse (rättelse i efterhand)". It can mark someone as called, set
  accepted, declined (with a reason) or not answered, or remove the callup.
  `api.correct_callup` adds a forgotten person to the latest sent squad
  revision, writes an audit row and sends no notifications. Events without
  callups refuse it, so nobody else becomes "not called".
- **Adding people afterwards.** The club search works after the event, so
  someone outside the roster can be added and registered.
- **Fix.** Saving attendance or a correction with a row expanded left its
  details loading forever. The expanded row now reloads them.

## Event details

- **Utkast circle.** It counted everyone in the latest squad revision,
  including those already called. It now counts only those selected but not
  called, and is hidden after the event when that is zero.
- **Type details.** Training theme, focus and plan, match notes and meeting
  purpose and agenda are no longer on Info and no longer in the editor.
  Förberedelser already has agenda, goals, focus and notes. Values already
  saved are kept and shown read-only under "Detaljer" on Förberedelser.

## Calendar week and day views

- The week grid's event previews show "team · place" on a third line.
- Day view cards of about an hour or more show team and place on their own
  line. Shorter cards add them after the time.

## Event editor

- **Sharing when creating.** The editor lists the club's other active teams.
  Chosen teams get "Kan se" and the owning team's recipients, on every
  occurrence of a new series. Rights are changed later under Dela event.
  Sharing goes through the existing CAL-03 command.
- **Places.** Saved places are one horizontally scrolling row.
- **Date.** A new event starts on the day selected in the calendar, at 18:00.
- **Series.** "Upprepas": Dagligen, Varje vecka, Varannan vecka (weekly,
  interval 2) or Varje månad. Monthly keeps the day of the month, clamped to
  the month's last day. The free "Varje N" field is gone. Matches have no
  series option.
- **Removed.** "Fler inställningar" with the time zone (the event's own zone
  or Europe/Stockholm is used), and the draft switch: **Utkast** is a button
  next to **Skapa**.
- **Default length.** Training and meetings 90 minutes, activities 120, and
  matches the length of their format. A new start time resets the end to the
  default. A new event's end follows a type change.
- **När.** Two rows: date with an all-day chip, then start, end and assembly
  (with its clock time). All-day shows the end date instead.
- **Match fields.** Opponent and home/away (home preselected) share a row.
  Format and periods sit in a collapsed "Matchformat" row that shows the
  current choice, for example "9v9 · 3×25 min".

## Match format and periods

- **Per team.** Laget → Redigera lagprofil has a match format: 3v3, 5v5, 7v7,
  9v9 or 11v11. Unset means 11v11. The people who may edit the team profile
  may change it.
- **Per match.** The editor chooses format, 1–4 periods and minutes per period,
  when creating and when editing. A new match saves its choice (every
  occurrence of a series). An edit saves it only when changed, for the chosen
  scope. A match still being planned in match mode follows. A started match
  shows its periods locked; they are changed in match mode.
- **Match mode.** A new workspace starts with the match's periods, else the
  team format's, else 2×45. Existing workspaces keep theirs.

These defaults per format are assumptions and live in
`internal.match_format_period_minutes` and `MatchFormat`:

| Format | Periods | Match event length |
|---|---|---|
| 3v3 | 3×10 | 60 min |
| 5v5 | 3×15 | 60 min |
| 7v7 | 3×20 | 90 min |
| 9v9 | 2×35 | 105 min |
| 11v11 | 2×45 | 120 min |

The editor always writes equal periods. Unequal periods set in match mode are
only replaced when the periods are changed in the editor.

## Verification

- `flutter analyze`: no issues. Full test suite: 676 tests pass.
- PGlite tests, each running the real migration:
  - `attendance_rate_and_callup_corrections.local.mjs`: expected-only rates,
    extras, callup corrections and their refusals.
  - `share_event_at_creation.local.mjs`: shareable teams, every occurrence of a
    series, recipients, permission and grants (the CAL-03 command is stubbed).
  - `monthly_event_series.local.mjs`: monthly dates clamped at month end,
    biweekly, unknown frequencies refused.
  - `team_match_format.local.mjs`: default 11v11, permission, idempotency,
    the check constraint, workspace periods and rerunning the migration.
  - `event_match_settings.local.mjs`: team fallback, per-match choice, a
    planned workspace following, a started one locked, scopes, refusals and
    grants.
- New widget tests cover the callup corrections, adding people after the
  event, the reloaded participant details, the Utkast circle, team and place
  in the week and day views, the details on Förberedelser, sharing when
  creating, the series options, the preselected date, the draft button, the
  default lengths per type and format, the match settings when creating and
  editing, the compact När and match rows on a 390 px wide phone, and the match
  format in the team profile.
- A live catalog query before the migrations confirmed that the deployed
  `internal.create_event_for_actor` and `internal.ensure_match_workspace` were
  identical to the versions the migrations replace.
- Installed on Android (Samsung S25) as a debug build with the attendance and
  callup changes. The later changes were checked in the local web build; the
  flows were not run by hand in the signed-in app.
