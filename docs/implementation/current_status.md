# TeamZone – aktuellt leveransläge

Senast avstämt: **2026-10-25**, mot kod vid `760dbe0` och
[nulägesrapporten](../evidence/app_status_review_2026-10-25.md).
Senare lokal rättning samma dag: [modulöversättningar](../evidence/localization_modules_2026-10-25.md).
Den tidigare språkregressionen är rättad; aktuell Flutter-svit är grön.
Ytterligare uppföljning: [Webtools i CI och Next.js-säkerhetsuppdatering](../evidence/webtools_ci_2026-10-25.md).
Den rena CI-verifieringen hittade ett kritiskt Next.js-paketfynd; båda sajterna
har därför uppdaterats från 16.3.8 till 16.4.3. Appen och båda sajterna är
driftsatta till audit efter användarens godkännande; se
[releasekvittot](../evidence/audit_release_2026-10-25.md) för revision och verifiering.
Detta är den gemensamma ingången till aktuell status. Daterade rapporter och
äldre testantal är historisk evidens, inte ett löfte om dagens releasekvalitet.

Senare manuell uppföljning: [acceptansgenomgång 25 oktober](../evidence/manual_acceptance_2026-10-25.md).
Fem avvikelser är rättade och publicerade till audit. Svenska ledarvyer har granskats läsande
i P2012. Engelskt manuellt språkpass, app i 390-pixels bredd och skriv-/rollacceptans
återstår; genomgången stänger inte dessa grindar.

Efterföljande publicerad ändring: [språkval under Personligt](../evidence/language_setting_2026-10-25.md).
Svenska, engelska eller enhetens språk kan väljas och sparas på enheten.
Språkbyte och sparat val har provats i audit. Fullt engelskt språkpass återstår.
Se [releasekvittot](../evidence/language_release_2026-10-25.md).

Det ursprungliga manuella [engelska språkpasset](../evidence/english_acceptance_2026-10-25.md)
var **inte godkänt**: assistenten, gemensamma förberedelser, TDP och Matchs
detaljvyer innehåller kvarvarande svenska systemtexter. Språkvalets funktion
är verifierad, men hela appens engelska lokalisering är inte färdig.

Efter språkpasset har [översättningsrättningar för de fyra komponentgrupperna](../evidence/english_translation_fix_2026-10-25.md)
genomförts lokalt, med engelska widgetprov och bevarat användarinnehåll.
Rättningarna är nu publicerade till audit och granskade läsande i den engelska
ledarsessionen. Omprovets mindre rester är rättade i en komplettering. Se
[engelsk release och omprov](../evidence/english_release_2026-10-25.md) för
revisioner och avgränsning. Skriv-/rollacceptans och manuell mobilgranskning
återstod vid det omprovet. Språkputsen av singularformer och hörnresultatet Short följs upp i
[Matchs språkputs 26 oktober](../evidence/english_polish_2026-10-26.md).

Senare uppföljning: [390-pixelsvy och skrivprov 26 oktober](../evidence/mobile390_write_acceptance_2026-10-26.md).
Grundläggande skapa/redigera/spara/läsa tillbaka passerade för TDP-mål,
träningsutkast och matchplansutkast. Testposterna är märkta AUDIT; målet är
avbrutet och båda planerna opublicerade. De efterföljande fynden om för trång analysflik och svenska systemtexter
på Home är rättade, publicerade och manuellt omprovade i 390 pixlars bredd;
se [rättningskvittot](../evidence/mobile390_fixes_2026-10-26.md).
Fysisk telefon och andra roller återstår.

## Statusregler

- **Byggt:** implementation finns i repot.
- **Driftsatt:** miljön har verifierad deployment eller motsvarande objekt.
- **Verifierat:** angiven kontroll har passerat på angivet datum och inom sin omfattning.
- **Releaseklart:** även manuella, juridiska, säkerhets- och driftgrindar är stängda.

Ingen av de tre första statusarna innebär automatiskt den sista. Kryss i
[leveranskorten](core_app_delivery_cards.md) behåller sina acceptanskriterier;
en kodinventering eller HTTP 200 stänger inte en fysisk verifieringsgrind.

## Produkt och moduler

| Område | Nuläge | Kvarstående gräns |
|---|---|---|
| Grundapp, S00–S10 | Historiskt stängda inom godkänd scope: identitet, trupp, kalender, kallelser/närvaro, Inbox, Hem, Match Space, utveckling, publicering, ekonomi/styrelse och entitlements. Senare utbyggnad omfattar profiler, kontaktflöden, statistik, matchpool och domare. | Senare ändringar har egna acceptansgrindar; hela nuvarande appen är inte slutgodkänd. PAR-FIN-03 är fortsatt stängd. |
| Min assistent | Deterministiska uppgifter, konflikter, förberedelser, uppföljning, inställningar och feedback. | Generativ aktivering är fortsatt separat grindad. |
| Push | Worker och Android-åtgärder finns. Fysisk Android-evidens 13–15 oktober och leveransposter i audit 24 oktober. | Ingen ny fysisk pushprovning 25 oktober. iOS återstår. |
| Arbetsytor | Nav till tre byggda moduler med egen navigation: Match, Team Development Plan och Träning. | Inte längre enbart platshållare. Det äldre S11-paketet ska inte klarmarkeras i sin helhet. |
| Match | Matchplan, uppställning, Live, nyckeltalsknappar och analysytor finns. Publikt match-live har eget server- och webbkontrakt. | Manuell roll-/enhetsacceptans kvarstår. Språkgrindens fynd är rättade lokalt. |
| Team Development Plan | Säsong, perioder, mål, spelprinciper, nyckeltal, avstämningar, delning och förslag till event. | Samlad slutacceptans är inte styrkt av nulägesgenomgången. |
| Träning | Versionerade pass med block, publicering, sammanhållna förberedelser, säsongsanknytning och ledarutvärdering. | Biblioteksimport och tavelvisare i appen väntar. |
| IDP | Äldre utvecklingsplansgrund finns. | Ny full IDP-modul är inte levererad; saknar öppnare i Arbetsytor. |
| Webtools | Tacticsboard, Bokningshanterare och Turneringsplanerare finns som beta; Video Analyzer är planerad. | Kommersiell aktivering och gemensam slutacceptans återstår. Se [Webtools README](../../webtools/README.md). |
| Tacticsboard-bibliotek | Egna projekt, delning med community/klubb, klubbens lista, favoriter och versionsmodell finns. | Paket 13 steg 4 (kopplingen till träningspass) väntar enligt beslut 25 oktober; appvisaren är inte redovisad som levererad. |

Senare beslut gäller framför ändrade delar av tidigare målbild:
[paket 11 – modulgrunder](../specification/source/26_module_foundations_decision.md),
[paket 12 – publikt match-live](../specification/source/27_public_live_match_decision.md),
[paket 13 – Tacticsboard-bibliotek](../specification/source/28_tacticsboard_library_decision.md).
Paket 13 ersätter planeringen av ett eget övningsbibliotek i appen och lägger
Tacticsboard-kopplingen före IDP. Ursprungliga beslut ändras inte för att bokföra framdrift.

## Sajter och miljöer

| Yta | Aktuell adress | Miljö/status 25 oktober |
|---|---|---|
| Flutter-webb | `https://app.teamzoneapp.se` | Audit/test enligt miljömanifestet; HTTP 200. |
| Publik sajt | `https://teamzoneapp.se` | Kanonisk origin i `public-site/apphosting.yaml`, använder audit-projektet. |
| Publik aliasadress | `https://public.teamzoneapp.se` | Fungerar; kan omdirigera till huvuddomänen. |
| Nya Webtools | `https://teamzoneapp-webtools--teamzoneapp-b02a2.europe-west4.hosted.app` | Firebase App Hosting, audit; huvudwebbplatsen är konfigurerad att länka hit. |
| Äldre Webtools | `https://webtools.teamzoneapp.se` | Visar fortfarande den äldre sajten. Domänflytten är inte genomförd. |
| Planerad testseparering | `test.teamzoneapp.se`, `test-public.teamzoneapp.se` | Planerade adresser; inte verifierade som färdig flytt. |
| Produktion | Planerad separat databas i Stockholm | `not_provisioned`, projektref saknas i miljömanifestet. |

Internetåtkomlig är inte samma sak som produktionsgodkänd. Det aktiva nya
Supabase-projektet är TeamzoneApp i `eu-west-1`; Teamzone6 är en separat äldre
referens och inget deploymentmål. Se [miljöbeskrivning](../development/environment.md)
och [produktionsrunbook](../operations/production_provisioning.md).

Android skiljer på `com.teamzone.teamzone.test` för local/audit och
`com.teamzone.teamzone` för produktion. iOS har ännu ingen dokumenterad bygg-
eller TestFlight-verifiering. Native desktop är inte v1-mål.

## Senaste verifiering, 25 oktober

| Kontroll | Resultat |
|---|---|
| Flutter analys | Inga analysfynd. |
| Flutter test | **810/810 godkända** efter språkfixen, inklusive ett nytt engelskt träningsflöde. Ursprunglig granskning hade 808 godkända och en underkänd språkgrind; de 64 saknade översättningarna är nu rättade. |
| Public-site | Ren installation, typkontroll, 94 tester, produktionsbygge och audit godkända efter lokal uppdatering till Next.js 16.4.3. |
| Webtools | Ren installation, typkontroll, 54 tester, produktionsbygge och audit godkända efter lokal uppdatering till Next.js 16.4.3. Eget CI-jobb tillagt. |
| SQL/PGlite | 84 lokala testfiler avslutade utan fel, plus tre extra testlägen för direktresultat, matchrapporter och följarnotiser. Filantal är inte antal assertions. |
| Firebase Functions | 8 tester och audit godkända lokalt och i GitHub. Senare body-parser-fynd rättat och driftsatt till tre befintliga auditfunktioner. |
| npm audit | Noll fynd för båda sajterna och Firebase Functions efter Next.js- respektive body-parser-patch. Kontrollerna passerar även i GitHub. Omfattar inte Deno-importerna; driftsättningen styrks separat i releasekvittot. |
| Publik smoke | Huvuddomänen godkänd. Aliasdomänens test avbryts på förväntad kanonisk 308, eftersom scriptet kräver 200. |

Kod-, databas- och HTTP-granskning ersätter inte inloggad visuell provning.
Ingen ny full roll-/enhetsmatris, iOS-körning eller APK/AAB gjordes.
Efterföljande Flutter-webbrelease och full Edge/Deno-testkörning redovisas
i releasekvittot.

## Öppna kvalitets- och releasepunkter

1. **Driftsatt till audit:** språkgrindens 64 saknade översättningar och träningsvyerna
   är rättade. Engelskt mobilflöde, hela sviten, analys och format passerar.
   Rättningen finns i publicerad Flutter-webb men stänger inte full
   fysisk språk-/enhetsacceptans för alla andra moduler.
2. Avstäm migreringsloggen: **389 lokala versioner, 387 loggade**.
   `20261022090000` (inloggningsbegränsning) och `20261128090000`
   (inaktiv livelektion) saknas i loggen. Centrala objekt finns, men hela
   migreringarnas innehåll har inte jämförts. Kör inte om eller logga dem blint.
3. Gör ny tomdatabasreplay av aktuell kedja. Replayen 13 oktober omfattade
   320 migreringar och verifierar inte dagens 389.
4. Provisionera produktion enligt runbook; skydd mot läckta lösenord är
   fortfarande avstängt i audit. Bedöm också advisor-varningen om `pg_net` i `public`.
5. Genomför [behörighetsöversynen](permissions-review.md) och stäng återstående
   roll-, tvåenhets-, tillgänglighets-, juridik- och releasegrindar med egen evidens.
6. **CI-jobb pushat och verifierat:** `.github/workflows/ci.yml` omfattar nu även
   Webtools med ren installation, typkontroll, test, bygge och audit.
   Det utökar befintlig CI för Flutter, SQL, Edge, public-site och Firebase
   Functions. Samtliga steg har passerat i rena lokala kopior utan
   tjänstekonfiguration. Samtliga sex jobb har även passerat på GitHub,
   inklusive Flutter och SQL. Revision och körning finns i releasekvittot.
7. Verifiera verklig automatisk meddelandegallring. Workern finns, men inget
   motsvarande databas-cronjobb identifierades; extern schemaläggning är okontrollerad.
8. Bestäm flytten av gamla Webtools-domänen och synka produktkatalogens texter
   efter verifierad funktion. Den beskriver fortfarande vissa byggda funktioner som kommande.
9. **Next.js-säkerhetsrelease genomförd i audit:** båda App Hosting-utrullningarna
   är klara och läsande efterkontroller passerar. Se releasekvittot.

Detaljer, säkerhetskontrollens omfattning och historiska källor finns i
[rapporten 25 oktober](../evidence/app_status_review_2026-10-25.md).
