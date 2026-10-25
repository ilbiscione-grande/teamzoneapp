# TeamZone Webtools

A portal of standalone web apps for coaches, leaders and clubs: Tacticsboard,
Video Analyzer, Bokningshanterare and Turneringsplanerare to start with.

Status checked 2026-10-25: three tools have beta implementations; Video
Analyzer is planned. A clean local installation, typecheck, 54 tests, build
and dependency audit pass on Next.js 16.4.3. The repository
now has a separate `webtools` CI job for installation, typecheck, tests,
production build and dependency audit. The site jobs have also passed on the
GitHub Ubuntu runner; this does not certify all signed-in/device flows. The
[shared status](../docs/implementation/current_status.md) records remaining
release gates and the distinction between built, deployed and verified.
See [CI/security verification](../docs/evidence/webtools_ci_2026-10-25.md)
for the critical finding that prompted the version update and the
[audit release receipt](../docs/evidence/audit_release_2026-10-25.md) for deployment evidence.

## Tools currently built

| Tool | Routes and implemented scope | Remaining boundary |
|---|---|---|
| Tacticsboard | `/tacticsboard`, projects, board editor, formations/squad, animation/timeline, templates, sharing, export, live lessons with drawing/chat/questions, and `/tacticsboard/bibliotek`. | Training-session library import and the app viewer are not delivered; package 13 step 4 is explicitly waiting. |
| Bokningshanterare | `/bokningar`, organisations/resources, invitations, bookings, approvals, recurring series, availability and TeamZone activity links. | Full role/device acceptance and commercial activation remain separate. |
| Turneringsplanerare | `/turneringar`, registration, classes, organisers, groups, schedule, playoff/result contracts, TeamZone links and public `/turnering/[id]`. | Code presence and page delivery do not establish full tournament acceptance. |
| Video Analyzer | Catalog entry only. | Planned; no corresponding tool implementation identified. |

The catalog in `lib/apps.ts` still calls some implemented Tacticsboard and
tournament features upcoming. Its user-facing copy has not been changed as
part of the documentation sync; reconcile it with verified deployed behavior.

Tacticsboard has one library with community/club visibility, a curated club
list, own projects and favorites. See approved
[package 13](../docs/specification/source/28_tacticsboard_library_decision.md).
Steps 1–3 are built; the app connection is a later delivery, not a separate
exercise library to build in the Flutter app. `/tacticsboard/demo` is a
development route and intentionally returns 404 in production unless
`TACTICS_DEMO=1` is configured.

- **One account.** Every app signs in with the TeamZone account (the same
  Supabase project as the app). An account can be created here; the current
  terms are accepted on first sign-in, as in the app.
- **Standalone.** A club or team connection is optional. When the account has
  one, apps may use it (e.g. a squad in a line-up); `/konto` shows it.
- **Subscriptions (later).** Each app becomes a subscription, bought on its
  own, in a bundle, or through the club in TeamZone. `/konto` has the place
  for it; nothing is sold yet.

## Structure

- `lib/apps.ts` – the app catalog (status, copy) and safe return paths.
- `lib/account.ts` – shapes from TeamZone's API and pure helpers.
- `components/account.tsx` – the browser session, terms and connections.
- `components/tactics/`, `lib/tactics/` – editor, live lessons and library.
- `components/booking/`, `lib/booking.ts` – bookings and resources.
- `components/tournament/`, `lib/tournament*.ts` – tournaments and schedule.
- `app/` – portal/account pages, tool routes, public tournament and `/api/config`.

## Run and check

```
npm ci
npm run dev     # http://localhost:3100 (env: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY)
npm run lint
npm test
npm run build
npm audit
```

From the repo root, `.claude/launch.json` has a `webtools` entry with the test
environment's values.

## Deploy

Firebase App Hosting backend `teamzoneapp-webtools` (europe-west4), deployed
from local source like the public site:

```
npx -y firebase-tools deploy --only apphosting:teamzoneapp-webtools --project teamzoneapp-b02a2
```

It runs on `https://teamzoneapp-webtools--teamzoneapp-b02a2.europe-west4.hosted.app`
until `webtools.teamzoneapp.se` moves over from the old site (now on Vercel).
The public site links to it through `NEXT_PUBLIC_WEBTOOLS_URL`. The old domain
and the new Firebase origin are different deployments; do not use the old
domain as proof of a new Webtools release. Current backend uses the same
audit Supabase project as the app. Separate production is not provisioned.

Sign-up confirmation links return to `/logga-in?konto=bekraftat` on this
origin, so the origin must be in Supabase Auth's redirect allow list.

## Bokningshanterare (beta)

`/bokningar`. An organisation (club, association, company...) owns
resources: pitches, halls, locker rooms, rooms, vehicles, equipment. Bookings
of one resource never overlap; each resource either confirms at once or
needs an admin's approval. Members join through a 14-day, single-use
invitation link. Without TeamZone that is all.

Linked to a TeamZone club (by someone who administers both): the club's
leaders and functionaries book without an invitation, a booking can be for
one of their teams and attached to one of its activities, and the activity
lists its bookings in the TeamZone app. Database: migration
`20261115090000_booking_manager.sql`, test `supabase/tests/booking_manager.local.mjs`.
