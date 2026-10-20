# TeamZone Webtools

A portal of standalone web apps for coaches, leaders and clubs: Tacticsboard,
Video Analyzer, Bokningshanterare and Turneringsplanerare to start with.

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
- `app/` – start page, `/appar/[slug]`, `/logga-in`, `/konto`, `/api/config`.

## Run and check

```
npm install
npm run dev     # http://localhost:3100 (env: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY)
npm run lint
npm test
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
The public site links to it through `NEXT_PUBLIC_WEBTOOLS_URL`.

Sign-up confirmation links return to `/logga-in?konto=bekraftat` on this
origin, so the origin must be in Supabase Auth's redirect allow list.
