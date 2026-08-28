# Beslutspaket 5 – publik webb, privacy och hosting

**Status: godkänt av produktägaren 2026-08-07. PWD-01–PWD-09 är beslutade.**

## Mål

Den publika sajten ska vara klubbens och lagens ansikte utåt, men bara visa uttryckligen publicerad data. Sökbarhet, minderårigdata, media, kontaktformulär och anon-API måste vara en sammanhängande publiceringsmodell.

## Katalog och publiceringsnivåer

- Verifierade klubbar kan finnas i en minimal sökbar katalog med namn, ort och beslutad profilbild.
- Ett lag kan vara `private`, `listed` eller `published`.
  - `private`: inte sökbart eller publikt.
  - `listed`: namn/klubb/åldersklass kan hittas, men ingen innehållssida.
  - `published`: har publik sida med fältvis publicerad information.
- Ny klubb och nytt lag är private som default tills behörig publicist gör ett aktivt val.
- Club-/teaminställningar styr tillåtna innehållstyper, men kan aldrig kringgå centrala privacyregler.

## Minderåriga och trupp

- Minderåriga är dolda i publik trupp som default.
- Publicering av namn, bild, position och individuell statistik är separata samtyckes-/policyfält.
- Guardian/personsamtycke, lagets policy, giltighetstid och källa ska kunna auditeras.
- Återkallat samtycke avpublicerar projektion och media samt invalidaterar cache.
- Grupp-/lagstatistik får publiceras utan att möjliggöra återidentifiering genom små urval.

Den juridiska grunden och åldersreglerna ska privacy/legal-verifieras före implementation; produktbeslutet här är privacy-by-default.

## Public projection och anon-API

- Publik data exponeras genom ett dedikerat allowlistat public API/projectionlager, inte genom breda anon-grants på interna tabeller.
- Varje endpoint har maxlimit, minsta söklängd där relevant, rate limit och stabilt svarskontrakt.
- Wildcard- och prefixenumerering begränsas; katalogsökning returnerar endast publiceringsnivåns fält.
- Servern filtrerar alltid status, tidsgränser, consent och publication state.
- Interna ID:n och privata relationer exponeras inte om ett publikt opaque ID/slug räcker.

## Media och externa länkar

- Endast explicit publicerade mediaobjekt finns i publik bucket/projektion.
- Privata original kopieras/deriveras till public variant; en privat signed URL blir aldrig permanent publik.
- Avpublicering tar bort public access enligt dokumenterad cache-/CDN-SLA.
- Externa länkar tillåter endast säkra schemes och renderas med CSP/rel-policy.

## Kontaktformulär

- CAPTCHA/bot-skydd, IP-/identity-rate-limit och maxlängder krävs.
- Bekräftelse till besökaren får inte avslöja interna mottagare.
- Meddelandet får explicit routing, leveransstatus och retention; det är inte en permanent inbox som default.
- Abuse/report och blockering ska kunna hanteras av klubb och plattformsadministration.

## Hosting

- Flutterappen och den publika Next.js-sajten får varsin kanonisk origin/domainroll.
- En enda pipeline per yta äger build, preview, production, environment secrets och rollback.
- Publiksajten använder kontrollerad cache med tag/path-invalidation vid publiceringsändring istället för global `no-store`.
- Security headers, SEO metadata, sitemap/robots och synthetic smoke test ingår i releasegrinden.
- Exakta domännamn beslutas i operationsspecifikationen; flera konkurrerande produktionsspår är inte tillåtna.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| PWD-01 | Klubbar har minimal verifierad katalogpost; lag väljer private/listed/published och är private som default. | Beslutad |
| PWD-02 | Minderårig truppdata är dold som default och varje fältklass kräver beslutad policy/samtycke. | Beslutad |
| PWD-03 | Consent/publication är auditerat, tidsbundet där relevant och avpublicering invalidaterar data/media/cache. | Beslutad |
| PWD-04 | Publik data går genom dedikerade allowlistade projections/API:er; interna tabeller har inga breda anon-grants. | Beslutad |
| PWD-05 | Public API har limits, rate limiting och enumerationsskydd. | Beslutad |
| PWD-06 | Endast explicit publicerade mediaobjekt får ligga i publik bucket/projektion. | Beslutad |
| PWD-07 | Kontaktformulär får abuse-skydd, leveransstatus och fast retention. | Beslutad |
| PWD-08 | Flutter och Next.js får separata kanoniska origins och varsin enda reproducerbar pipeline. | Beslutad |
| PWD-09 | Publiksajten använder kontrollerad cache/invalidation och obligatoriska security-/SEO-/smoke-grindar. | Beslutad |

## Konsekvens

Paketet slutför målbilden för PD-16, PD-17 och PD-20. Exakta samtyckesåldrar, legal basis, retentionstider och domännamn behöver därefter signeras av privacy/legal respektive operations.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | PWD-01–PWD-09 godkända som bindande målbild för rebuildspecifikationen. | Produktägaren |
