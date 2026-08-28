# S09 publication parameter decisions

Approved by product owner: 2026-08-15  
Scope: TeamzoneApp v1, Sweden-first greenfield release

## PAR-PRIV-02 – public minor data

- Through age 15, individual publication requires both the subject's approval
  and approval from a verified active guardian.
- From age 16, the subject's own approval is sufficient.
- Missing account link, unknown age, protected identity or uncertain guardian
  relation blocks individual publication.
- Consent is separate for name, profile image/media, position and individual
  statistics. Nothing is preselected or bundled.
- Consent lasts at most one season or 12 months, whichever ends first.
- Withdrawal removes the corresponding projection/media and triggers cache
  invalidation. Team statistics must not expose identifiable small cohorts.
- V1 uses explicit consent for individual minor data and does not substitute an
  interest-balancing decision.

## PAR-API-01 – public allowlist and abuse limits

Allowed v1 reads:

- `search_clubs`: minimum query length 3, maximum 10 results;
- `get_club`: name, locality, public profile image and published description;
- `get_team`: club, team name, age class and explicitly published fields;
- `list_team_events`: published events, maximum 20 per page;
- `list_publications`: published news/media, maximum 20 per page.

Only opaque public identifiers and normalized slugs are returned. Internal UUIDs,
membership relations, private contact details and Storage keys are forbidden.
Wildcard search is forbidden; prefix search begins at three characters.

- general reads: 60 requests/minute/IP;
- search: 20 requests/minute/IP;
- contact: 5 attempts/hour/IP/club plus CAPTCHA;
- contact submission runs through a server/Edge Function, never direct anon DB
  write access;
- errors are neutral and do not disclose accounts or internal recipients.

## PAR-OPS-01 – origins and hosting

- Canonical public origin: `https://teamzoneapp.se`.
- Public team route: `/{club_slug}/{team_slug}`.
- `https://www.teamzoneapp.se` permanently redirects to the apex origin.
- Flutter web origin: `https://app.teamzoneapp.se`.
- Production auth callback: `https://app.teamzoneapp.se/auth/callback`.
- Public API base: `https://teamzoneapp.se/api/public/v1`.
- No wildcard origins or redirects. Preview origins are non-indexed and cannot be
  production auth callbacks.
- A new Firebase project belongs to the rebuild. Firebase App Hosting owns the
  public Next.js site; classic Firebase Hosting owns the Flutter SPA.
- Blaze budget alerts are mandatory. The old TeamZone Firebase project is not
  changed by this decision.

## PAR-OPS-02 – cache and withdrawal SLA

- Club pages without person data: CDN maximum 5 minutes.
- Team/event/news pages: CDN maximum 60 seconds, `must-revalidate`, no
  `stale-while-revalidate`.
- Individual person pages/media: CDN and browser maximum 60 seconds; no direct
  permanent Storage URLs.
- Public API/search/contact: `no-store`.
- Content-hashed CSS/JS: immutable up to one year.
- Consent withdrawal/publication withdrawal atomically removes the projection,
  invalidates affected paths/tags and removes public media.
- Withdrawal target: 60 seconds; verified absolute maximum: 5 minutes across
  CDN regions. Global kill switch maximum: 60 seconds.
- No offline/service-worker cache for HTML, API data or person media.
- Failed invalidation keeps publication disabled and emits an operations alert.

These are product and technical policies, not a substitute for final legal or
operational release review.

## CAPTCHA provider

- Cloudflare Turnstile is selected for the public contact form.
- The managed widget is bound to `teamzoneapp.se` and action `contact`.
- Every token is verified server-side through Turnstile Siteverify; a successful
  provider response with another hostname or action fails closed.
- Production and non-production use separate widgets and secrets. Secret keys
  are server-only and never committed or exposed to the browser.
- Missing configuration keeps contact submission disabled.
