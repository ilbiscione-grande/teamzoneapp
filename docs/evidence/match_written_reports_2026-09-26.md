# Skrivna matchrapporter

Status: aktiverat efter användarens godkännande. Migrationen är applicerad i testprojektet, critical-flow-command version 10 är aktiv med JWT-verifiering och Flutter har laddats om. App Hosting-driftsättningen är klar på `public.teamzoneapp.se`.

Kalender → avslutad match → Info → Skriv matchrapport. Text upp till 10 000 tecken sparas som internt utkast som standard. Användare med `publication.manage` kan publicera eller återta rapporten. Servern kräver också behörighet att hantera matchen. Ändring av redan publicerad text kräver publiceringsbehörighet. Matchanteckningar används inte som offentlig rapport.

Rapporten visas på publik lagsida och bland följda lags resultat i dashboarden endast om slutresultatet redan är offentligt. Egna lags behöriga användare kan läsa utkast i dashboardens rapportvy. Rapporttext renderas som vanlig React-text med bevarade radbrytningar, aldrig HTML. Publiceringsgränser för runtime, lag/klubb, resultatvisning, återöppning och arkivering består.

Ny tabell `core.match_reports` har RLS och inga direkta klienträttigheter. `api.get_match_report` kontrollerar läsbehörighet. `api.save_match_report` har revisionskontroll, kommandolås, idempotens och auditerad text i befintlig kommandologg. Den publika resultatprojektionen innehåller enbart uttryckligen publicerad text; ett triggersteg fyller denna även efter resultatkorrigering. Befintliga läsfunktioner behåller sina åtkomst- och rate-limit-gränser.

Verifierat:

- Flutter: 16 detaljsidetester, inklusive utkast, publicering, tom publicering och delad läsbehörighet. Alla godkända.
- Flutter analyze: inga anmärkningar.
- Isolerad PostgreSQL: `node supabase/tests/pub07_personal_home.local.mjs --direct-result --written-reports` godkänd. Utkast, publicering/återtagning, retry, revision, textgräns, saknad publiceringsbehörighet, arkiv, återöppnad match, runtime, lagvisning och båda publika läsvägarna täcks.
- Webb: 48 tester godkända; TypeScript godkänd; produktionsbygge med webpack godkänt.
- Hosted rollback-test med autentiserad roll: internt utkast, idempotens, publicering, publik läsning, återtagning och direktåtkomstspärrar verifierade. Alla teständringar återställdes med rollback.
- Hosted säkerhetskontroll: oförändrat 41 INFO för RLS utan policy och en befintlig varning för lösenordsskydd; inga nya fynd.
- Extern webb: driftsättningen lyckades, startsidan svarar HTTP 200 och levererad dashboardkod innehåller `get_match_report`. PUB-06 synthetic smoke passerar på den externa domänen.

Aktiveringspaket: `20260926150243_match_written_reports.sql`, endast nya `save_match_report`-operationen i `critical-flow-command` med befintlig JWT-verifiering, Flutter-omladdning och förberedd App Hosting-version för `teamzoneapp-public`. Testprojekt: `hgcshgunvooyudvrcpig`. Inga befintliga rapporter eller inställningar ändras vid aktivering.
