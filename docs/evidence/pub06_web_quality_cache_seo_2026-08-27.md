# PUB-06 – webbkvalitet, cache och SEO

Datum: 2026-08-27  
Status: lokalt genomfört, hosted verifiering återstår

## Levererat

- Publik HTML annonserar `public, max-age=0, s-maxage=60, must-revalidate`; `stale-while-revalidate` används inte.
- Alla `/api/*`-svar behåller `no-store` och fail-closed 404 använder `no-store`.
- Service-only SQL claimar endast invalidationsjobb. Claims äldre än tio minuter återtas och retry använder befintlig backoff.
- Intern Next-worker kräver minst 32 teckens bearer-hemlighet, jämför konstant-tid, validerar högst 20 paths och avslutar varje jobb explicit som success/failure.
- Sitemap byggs endast från publicerade klubb-, lag- och nyhetsprojektioner och använder aktiv canonical premiumdomän när sådan finns.
- `robots.txt`, HSTS, COOP, befintlig CSP/frame/content/referrer/permissions-policy och ett repeterbart syntetiskt smoke-script ingår.
- Ett negativt kontraktstest säkerställer att live matchrapportering, matchklocka och realtimekanal inte införts.

Supabase-skillens säkerhetsgräns påverkade workerdesignen: claim/sitemap är endast `service_role`, inga tabeller exponeras, serverhemligheten går aldrig till klienten och databasjobbet är återtagbart efter avbrott.

## Lokal verifiering

- `npm run lint`: godkänd.
- `npm test`: 22/22 godkända.
- `npm run build`: godkänd.
- Buildmanifestet innehåller Proxy, `/robots.txt`, `/sitemap.xml` med en minuts revalidate och `/api/internal/cache-invalidation`.
- SQL har jämnt antal dollar-quotes och service-only grants kontrolleras statiskt.

## Återstår

- PostgreSQL-runtime och Security/Performance Advisors.
- Serverhemlighet och schemaläggning i en separat godkänd miljö.
- Hosted synthetic smoke samt uppmätt cache-hit och invalidation inom 60 sekunder med publicerad fixture.
- Separat godkännande före Supabase-live- eller hostingändring.

Ingen liveändring, driftsättning, webtools eller workspace utfördes.
