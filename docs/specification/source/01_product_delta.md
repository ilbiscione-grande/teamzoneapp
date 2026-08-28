# Produktdelta: målbild mot verifierat nuläge

**Status: godkänd av produktägaren 2026-08-07.** Godkännandet låser förändringskatalogen som planeringsbas, men inte teknisk lösning, pris eller öppna PD-/ND-beslut.

## Klassificering

- **Behåll:** verifierat beteende som ska föras vidare.
- **Förbättra:** samma produktförmåga men nytt kontrakt eller UX.
- **Ersätt:** nuvarande modell ska inte vara framtida source of truth.
- **Ta bort:** uttryckligen utanför målbilden; inga säkra borttagningar är beslutade ännu.
- **Nytt:** saknas eller är endast embryonalt idag.

| CHG-ID | Område | Klass | Målbild | Auditkoppling |
|---|---|---|---|---|
| CHG-NAV-01 | Huvudnavigation | Ersätt | En stabil femsidig IA: Hem, Laget, Kalender, Inbox, Statistik för alla roller, med rollanpassat innehåll. | Steg 1/13, NAV-01/02 |
| CHG-HOME-01 | Hem | Förbättra | Gemensamt aktuellt-kort och nästa vecka, men prioriterade actions per roll/context. | Steg 13 state/navigation |
| CHG-AI-01 | Assistant Coach | Nytt | Personlig assistent som förklarar signaler och erbjuder behöriga, bekräftade actions. | Steg 10/13, REQ-SIG-01 |
| CHG-TEAM-01 | Laget | Förbättra | Samlad lagpresentation med trupp, aktivitet, tävlingar och publik koppling. | Steg 4/5/12 |
| CHG-CAL-01 | Kalender | Förbättra | Personcentrerad kalender över flera roller/lag med sparade filter. | Steg 1/5, REQ-CAL-01 |
| CHG-MSG-01 | Inbox | Ersätt | Automatiska lag-/ledarchattar och explicit capabilitybaserad kontaktmodell. | Steg 9, PD-10, REQ-MSG-01–03 |
| CHG-STAT-01 | Statistik | Förbättra | Grundnivå för närvaro; modulstyrd match-/spelarstatistik med lag- och totalprojektion. | Steg 6/8/10 |
| CHG-EVT-01 | EventDetails | Förbättra | Gemensamma Info/Trupp/Förberedelser/Uppföljning med eventtypsspecifika fält och visibility. | Steg 5–8 |
| CHG-CALL-01 | Kallelseutkast | Förbättra | Individ, alla, grupp eller lag kan läggas i revisionerat utkast före atomisk send. | Steg 6/7, REQ-CALL/SQUAD |
| CHG-CALL-02 | Kallelsesvar | Behåll/förtydliga | Draft, pending, accepted, declined; decline reason valfri. | CRA-09, PD-08 |
| CHG-ATT-01 | Närvaro | Förbättra | Present, late, partial och not-present/unknown ska vara separata tillstånd. | Steg 6 |
| CHG-PUSH-01 | Pushactions | Förbättra | Svar direkt från notis, fail-closed preferences och verifierad actor/tokenexpiry. | CRA/MSG, REQ-SEC-05 |
| CHG-SMS-01 | SMS | Nytt/senare | Valbar fallback för svårnådda användare med samtycke, kostnad och deliverylogg. | Nytt beslut ND-06 |
| CHG-ID-01 | Person/roller | Ersätt | En person kan ha flera huvudsakliga capabilities per klubb/lag utan att tvingas till ett enda shell. | PD-01–03, REQ-ID-01 |
| CHG-ID-02 | Platshållare/claim | Förbättra | Rosterperson utan konto claimas atomiskt av Auth-profil och all historik behålls. | Steg 4, REQ-MEM-01 |
| CHG-ONB-01 | Vänteläge | Nytt/förtydliga | Konto utan godkänt medlemskap får ett säkert väntrum, inte felaktigt lagcontext. | PD-02 |
| CHG-CLUB-01 | Officiell klubb | Förbättra | Ny klubb kan skapas endast efter namn-/claimregel; skyddad klubb kräver verifieringsprocess. | Steg 4/12 |
| CHG-ROSTER-01 | Hemlag/playable teams | Förbättra | Ett hemlag och explicita spelbara lag; statistik projekteras per representation. | Steg 1/4/7 |
| CHG-ROSTER-02 | Lån/övergång | Nytt/förbättra | Gäst/lån och permanent klubbövergång bevarar historisk attribution utan att flytta gamla fakta. | PD-03/07 |
| CHG-PUBLIC-01 | Publik webb | Ersätt/förbättra | Snygg klubbportal med lagnavigation och explicit fältvis publiceringskontroll. | Steg 12, PD-16/17/20 |
| CHG-MATCH-01 | Match Space | Behåll/förbättra | Bevara verifierat v2-commandbackend; bygg målbildens plan/live/analys ovanpå det. | Steg 8, REQ-MATCH-01 |
| CHG-TRAIN-01 | Training Space | Nytt/fördjupa | Sessionsplan, fokus, media, enkel ritbräda, reflektion och eventuell självskattning. | Steg 5/10 |
| CHG-SEASON-01 | Season Plan | Förbättra | Konfigurerbara säsongsdelar med detaljplan och koppling till events/träning. | Steg 10 |
| CHG-TEAMDEV-01 | Team Development | Nytt/fördjupa | Lagmål, spelprinciper, KPI:er, initiativ och uppföljning; workload endast om semantiken beslutas. | PD-12, REQ-SIG-01 |
| CHG-PLAYERDEV-01 | Player Development | Nytt/fördjupa | Flerårig statistik och gemensam IDP mellan spelare och behörig ledare. | Steg 10 |
| CHG-ECO-01 | Economy/Board Room | Ersätt/fördjupa | Separera finansiella capabilities från person-/klubbadministration; auditnivå beslutas. | Steg 11, PD-14 |
| CHG-WEBTOOL-01 | Tactics Board | Förbättra/ny integration | Fristående verktyg med egen local team mode och valbar TeamZonekoppling. | ND-03/04 |
| CHG-WEBTOOL-02 | Video Analyzer | Nytt | Fristående annotering/telemetry med explicit media-, storage- och integritetsscope. | ND-08 |
| CHG-WEBTOOL-03 | Matchpoolen | Nytt | Publicerbara matchförfrågningar med kontakt- och abusekontroll. | REQ-WEB-02 |
| CHG-WEBTOOL-04 | Bokningssystem | Nytt | Fristående web tool för resursbokning med valbar TeamZone-/EventDetails-integration. | ND-05, WID-09 |
| CHG-BILL-01 | Basplan | Ersätt | En kanonisk klubbsubscription med kvoter för lag/användare. | PD-04/15, REQ-BILL-02 |
| CHG-BILL-02 | Modul-/webtoolaccess | Ersätt | Appmoduler köps per klubb och gäller alla klubbens lag; web tools stöder fristående och bundled lägen. Entitlements härleds server-side. | Steg 11, BED-06/07 |
| CHG-ANALYTICS-01 | Produktanalys | Nytt | Samtyckes- och privacydesignad usage analytics, separerad från spelarprestation. | ND-07 |

## Ingen beslutad borttagning ännu

Målbilden nämner inte alla nuvarande funktioner, men frånvaro är inte ett borttagningsbeslut. Legacyfunktioner klassas först som **Ta bort** när produktägaren bekräftat detta och datamigration/retention är definierad.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | CHG-katalogen godkänd som korrekt produktdelta mot auditens nuläge. | Produktägaren |
