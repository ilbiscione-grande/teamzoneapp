# Core app iteration 2026-10-07 – 2026-10-08

## Scope and baseline

This page records the product changes of 2026-10-07 and 2026-10-08, from
commit `757e4bc` (`feat: page administration on the public site and news
images`) through `6436989` (`feat: Hem follows the day for every role; clear
callup answers`). It follows the [2026-10-05 iteration](core_app_iteration_2026-10-05.md).
All migrations below have been run in the test project by the product owner;
SQL changes were dry-run against it in rolled-back transactions first.

| Migration | Purpose |
|---|---|
| `20261007090000_editorial_hero_image` | One hero image per news article |
| `20261008090000_event_kpis_followup` | KPI goals and the follow-up tab |
| `20261009090000_match_kpi_counters` | Live KPI counters in Matchläge |
| `20261010090000_callup_quiet_period_and_expected_absence` | Quiet period for new callups; absence only when expected |
| `20261011090000_messaging_reply_to_club_functionaries` | Players and guardians can answer the board/office |
| `20261012090000_leader_home_day_and_upcoming` | Leader Hem: own callup on today's events, upcoming events |
| `20261012100000_player_guardian_home_day_and_upcoming` | Player/guardian Hem: team events today and upcoming |
| `20261012110000_event_visibility_by_audience` | Events visible to their audience |
| `20261012120000_home_callup_decline_reason` | Decline reason on the leader's own callups |

`20260926154246_team_follow_notifications` had never been run in the test
project (the public site showed "Notiserna kunde inte hämtas"); it was run
unchanged on 2026-10-07. A spot check of the other migrations from that
period found nothing else missing.

## Public site

- **Page administration at `/<club>/admin`.** Signed-in administrators manage
  news, page settings, team pages and requests, public matches, results and
  training times, club colours, badge and partners without the app. Every
  command uses the same capability-checked `api` RPCs as the app; the page is
  never indexed. "Hantera sidan" is shown on club and team pages only to
  permitted accounts.
- **News images.** One hero image with a description per article, uploaded
  privately and published only as a new WebP by `public-media-worker`
  (ImageMagick in WebAssembly: signature check, header size guard,
  auto-orient, metadata stripped, at most 2048 px). The worker answers the
  browser's CORS preflight, and pending images are picked up again while the
  newsroom is open, in the web admin and in the app.
- **Team page leads with news.** From tablet width the next match, latest
  result and coming events sit in a narrower right column; on phones they
  follow the news.

## Event follow-up and KPIs

Described in [`event-kpis-followup.md`](../implementation/event-kpis-followup.md).

- **Goals in Förberedelser.** A built-in catalogue per event type and sport
  (attendance, answers, late arrivals, goals for/against, clean sheet, shots,
  corners, save rate, intensity …) or a custom goal, with "minst/högst" and an
  optional "visible to players".
- **Uppföljning tab.** To-dos for leaders after the event (attendance, KPI
  values, match result, report), attendance against the team average,
  answers, late arrivals, decline reasons, an attendance trend over six events
  and goals against outcome with manual entry and per-goal trends.
- **Live counters in Matchläge.** Counted goals get +/− during a live match as
  idempotent match commands (`kpi` facts); once counting starts, untouched
  counters mean zero. Other manual values are entered after full time.
- **Module boundary.** Match statistics and analysis belong to the coming
  match module, development and evaluation to the coming training module. The
  event pages keep per-event basics.

## Event details

- The result sits under the title, large on Info and small on the other tabs,
  and is hidden until the match has one.
- Edit, result, report, sharing, "Kallelse behövs", cancel, delete and archive
  moved to a "⋮" menu in the app bar. "Publicera event" and "Återställ från
  arkiv" stay on Info as the main action in those states.

## Callups and attendance

- **Quiet period.** An unanswered callup is not shown in Min assistent for its
  first 6 hours, unless the event starts within 18 hours.
- **Expected absence.** Absence counts only for someone who was called (or
  when the event used no callups). Uncalled people show as "Ej kallad" after
  the event, "Markera återstående som frånvarande" only marks called people,
  and profile statistics, main-surface statistics and the follow-up summary
  ignore uncalled absences.

## Hem

- **One card that follows the day, for every role.** It shows "PÅGÅR NU ·
  SLUTAR …", "SENARE IDAG", "IMORGON" or "NÄSTA", followed by "Resten av idag"
  (finished events dimmed) and "Kommande". Each event appears once, so "today"
  and "next" no longer contradict each other. Players and guardians keep
  "Fler kallelser" for callups further ahead, then the team and unread
  messages.
- **Callups answered in place.** The card and every row carry the own (or the
  child's) callup with Acceptera/Avböj. Unanswered: two neutral outlines;
  accepted: green filled "✓ Accepterat"; declined: red filled "✓ Avböjt". The
  status reads "Obesvarat – svara gärna", "Accepterat" or "Avböjt – Sjukdom"
  (with the own text for "Annat").
- **Audience.** Events are shown to their audience in the calendar, event
  details and Hem: leaders and functionaries see all team events, players
  events for players, guardians events for guardians or players, club-wide
  events everyone; a callup always makes the event visible, also to the
  child's guardian.

## Min assistent, messages and app shell

- Filter buttons Uppgifter, Uppskjutna and Arkiverade are centred with a label.
  On phones the assistant opens full screen without the shell bar and bottom
  navigation.
- A player or guardian can answer anyone who may write to them (chair, board,
  treasurer, office) in an existing conversation, or a group started by such
  a person. Starting conversations is unchanged.
- The app is locked to portrait; a view that needs landscape can enable it.

## Demo club

Seeds in `supabase/seeds/` create Demoklubben IF for demos and
troubleshooting: teams, people, guardians and a board (`demo_club.sql`), demo
logins `tre60grader+<roll>@gmail.com` (`demo_club_logins.sql`), activities
with callups and attendance (`demo_club_events.sql`), conversations and
announcements sent through the app's own messaging functions without
notifications (`demo_club_messages.sql`), and results with real match facts
and reports for most played matches (`demo_club_match_results.sql`). Each
seed runs once in the SQL editor as one atomic block and leaves deliberate
gaps for the assistant to show.

## Verification

- `flutter analyze`: no issues. Full test suite: 601 tests pass.
- PGlite tests: `supabase/tests/event_kpis_followup.local.mjs` and
  `supabase/tests/match_kpi_counters.local.mjs`.
- New widget tests cover the day card for leaders and players, answering
  callups on Hem, KPI goals and follow-up, KPI counters in Matchläge and the
  event "⋮" menu.
- Messaging reply rules, audience visibility and the Hem projections were
  checked against the test project as the demo logins in rolled-back
  transactions.
