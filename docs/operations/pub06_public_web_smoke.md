# PUB-06 – publik webbkvalitetsgrind

Detta körkort får användas först efter separat godkänd driftsättning och med en uttryckligen vald URL.

## Förkrav

1. Publikationsmigrationerna är runtime-verifierade och publiceringsruntime är godkänd för miljön.
2. `CACHE_INVALIDATION_SECRET` är minst 32 tecken, lagras endast server-side och används av en skyddad scheduler.
3. Minst en icke-personlig klubbfixture är publicerad med klubb, lag, nyhet och event.
4. Rollback/kill switch och ansvarig operatör är utsedda.

## Automatisk smoke

Kör från `public-site`:

```powershell
npm run smoke -- https://VALD-HOST
```

Scriptet verifierar security headers, robots→sitemap, begränsad sitemapcache, API `no-store`, riktig 404 och frånvaro av privata fel-/hemlighetsmarkörer.

## Cache- och invalidations-SLA

1. Läs publicerad klubb-, lag- och artikelväg två gånger och verifiera `s-maxage=60, must-revalidate` utan `stale-while-revalidate`.
2. Avpublicera fixturen genom godkänt redaktionsflöde.
3. Kör den autentiserade invalidationsworkern; logga endast jobb-ID, antal paths, utfall och latens.
4. Verifiera att alla berörda vägar saknar innehållet senast 60 sekunder efter commit.
5. Simulera ett workerfel och verifiera retry. Lämna ett claim i tio minuter och verifiera timeoutåtertagning.
6. Bekräfta att API-, kontakt-, fel- och okänd-host-svar alltid är `no-store`.

## SEO

- `robots.txt` länkar till `sitemap.xml`.
- Sitemap innehåller endast publicerade projektioner.
- Egen canonical domän använder extern root-/lag-/nyhetspath; path-adressen omdirigerar 308.
- Opublicerad/okänd sida är 404 eller `noindex` och förekommer inte i sitemap.

## Scopegrind

Ingen publik matchklocka, score-feed, realtimekanal eller moderation för liverapportering får införas under PUB-06. Det kräver LATER-03:s separata specifikation och godkännande.
