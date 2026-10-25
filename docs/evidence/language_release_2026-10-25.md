# Publicering av språkval – 25 oktober 2026

Användaren godkände publicering av språkvalet samt acceptansrättningarna.
Kodrevision: `0313cce78f09def28f2f13f66c6df2f900e26525`, pushad till `main`.

[GitHub CI](https://github.com/ilbiscione-grande/teamzoneapp/actions/runs/40224862204)
verifierar revision `ec8d6d5c1ed4b5c333f9470c7c865db033712ef6`.
Den skiljer sig endast genom ett profiltest som rullar fram Laget före klick.
Första CI-körningen hade 812 godkända app-tester och detta enda felande test;
samtliga 17 profiltester passerade lokalt efter justeringen.
App- och Webtools-koden är identisk med `0313cce`.
**Samtliga sex CI-jobb passerade.** Flutter-jobbet passerade full analys och
**813 tester**. SQL/PGlite, Webtools, public-site, Edge Functions och Firebase
Functions passerade också. Efterföljande dokumentationscommit ändrar inte kod.

## Omfattning

- Språkval under Inställningar → Personligt: enhetens språk, svenska och engelska.
- Tillgänglig sidomeny och förbättrad textbrytning i navigeringen.
- Matchlistans kommande intervall börjar i dag, så gårdagens match inte dubbleras.
- Korrigerade beskrivningar av Träning och Webtools betafunktioner.

Mål: auditmiljön i Firebase-projekt `teamzoneapp-b02a2`.
App: `hosting:test`, `https://app.teamzoneapp.se`.
Webtools: `apphosting:teamzoneapp-webtools`, befintlig Firebase-origin.
Publiksajten och Functions ingår inte i denna uppdatering.
Inga databasändringar, DNS-ändringar eller produktionsprovisionering ingår.

Flutter byggs i release-läge med samma auditanslutning, publika nyckel,
`TEAMZONE_ENV=audit` och `PUBLIC_SITE_URL=https://public.teamzoneapp.se`
som föregående release. Övriga feature-flaggor använder befintliga standardvärden.

## Efterkontroller

Firebase rapporterade release complete för `hosting:test` och rollout
complete för Webtools. Miljögrinden `node ops/check_web_build.mjs audit`
passerade. Bygget gav samma CupertinoIcons-fontvarning som föregående
release; releasebygge och wasm-dry-run passerade.

Lokalt och publicerat `main.dart.js` har identisk SHA-256:
`DFDE5977B52E65FCBEF461401CBD985E0130EC744A0F6F43B23B3FC2D5F5E2DD`.

I den befintliga auditsessionen verifierades:

- Inställningar → Personligt visar Språk med enhetens språk, Svenska och English.
- English ändrar Inställningar och navigeringen direkt utan utloggning.
- Efter omladdning ligger English kvar och Settings/Personal visas på engelska.
- Device language återställer svenska. Det ursprungliga valet återställdes
  efter provningen, och inställningssidan lämnades öppen.
- Webtools `/appar/tacticsboard` och `/appar/turneringsplanerare` ger HTTP 200,
  visar ”Det här finns i betan” och saknar det gamla löftet ”kommer härnäst”.
- Match för P2012 visar inte Aneby-matchen 24 oktober under Kommande,
  men behåller den under Spelade. Träningskortet har korrigerad beskrivning.

Detta är ett avgränsat manuellt språkvalstest. Full engelsk roll-/modulacceptans
är fortfarande öppen; bland annat assistentens knapptext observerades på svenska.
