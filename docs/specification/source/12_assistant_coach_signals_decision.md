# Beslutspaket 7 – Assistant Coach, signaler och utvecklingsdata

**Status: godkänt av produktägaren 2026-08-07. ACD-01–ACD-09 är beslutade.**

## Mål

Assistant Coach (AC) ska hjälpa användaren att förstå vad som är viktigt just nu och erbjuda konkreta lösningar. Den ska inte vara en autonom aktör, medicinsk rådgivare eller genväg runt vanliga behörighetsregler.

## Assistant Coach v1

- V1 är en transparent signal- och actionmotor på Hem.
- Signaler beräknas deterministiskt från versionerade regler och visar varför de uppstod, tidsfönster och datakälla.
- AC kan formulera och prioritera signalerna, men får inte hitta på statistik eller dölja osäker input.
- Positiva signaler, exempelvis stabil närvaro, är lika viktiga som varningar.
- Mobil kan använda en floating entry; tablet/desktop kan visa en sidokolumn. Funktionens data- och actionkontrakt är samma.

## Actions

- En föreslagen action visas endast om användaren har vanlig capability för målobjektet.
- Action visar preview av mottagare, target context och konsekvens.
- Användaren måste bekräfta varje mutation eller utskick.
- Exekveringen går genom samma auditerade domänkommando som resten av appen.
- AC får inte autonomt skicka meddelanden, kalla spelare, ändra injury eller köpa något.

## Generativ AI

- En eventuell språkmodell får endast ett serverhärlett, allowlistat och dataminimerat context – aldrig fri databasaccess.
- Kunddata används inte för modellträning som default.
- Prompt/outputretention, leverantör, region, personuppgiftsbiträde och incidentflöde ska privacy/security-godkännas.
- Minderårig-, injury-, självskattnings- och utvecklingsdata hålls utanför generativ behandling tills en särskild policy och konsekvensbedömning är godkänd.
- Fallback utan språkmodell ska behålla kärnsignalerna och actions.

## Workload och attendance

- Nuvarande workload behandlas som **aktivitets-/deltagandeproxy**, inte fysiologisk eller medicinsk belastning.
- Låg attendance är en separat närvaro-/engagemangssignal och får inte sänka eller höja ett “belastningsvärde”.
- Om verklig workload införs senare krävs definierade dosinputs, metodval, validering och sportmedicinskt ägarskap.
- UI visar signaltyp, inputperiod, senast beräknad tid och kända dataluckor.

## Injury och suspension

- Injury har explicit status och behörig manuell clearance. `expected_return_at` skapar review/påminnelse men friskförklarar inte automatiskt.
- Vem som får se och ändra injurydata styrs av särskilda health capabilities och dataminimering.
- Suspension är en separat sportslig eligibilityregel.
- Matchbaserad suspension räknas ned endast av definierade, completed eligible matches och loggar vilka matcher som räknats.
- AC får påminna behörig användare om review men inte fatta clearance-/eligibilitybeslut.

## Självskattning och IDP

- Självskattning 1–5 är frivillig utvecklingsdata, inte objektivt prestationsbetyg.
- Spelaren ser sin egen data. Endast explicit behöriga utvecklingsledare får se individvärden.
- Guardianvisibility, minimiålder, retention och möjlighet att avstå beslutas innan funktionen aktiveras.
- Teamaggregat kräver minsta gruppstorlek och får inte återidentifiera en spelare.
- IDP har mål, actions, check-ins, actor och revision; AC kan sammanfatta men inte ändra mål utan bekräftelse.

## Tactics Board och förslag

- AC kan söka i en länkad, kuraterad övnings-/sessionkatalog genom versionerat integrations-API.
- Förslag visar källa, mål/fokus och varför övningen matchar signalen.
- En föreslagen session importeras som draft; ledaren granskar och sparar den.
- Ingen webtoolintegration får vara krav för att grundappens signaler ska fungera.

## Kvalitetsgrind

- Varje signal har fixtures för positivt, negativt, stale, missing och cross-tenant fall.
- Genererade formuleringar utvärderas för factuality, privacy, olämplig medicinsk slutsats och felaktig action.
- Feedback loggas utan rå känslig payload och kan kopplas till regel-/promptversion.
- Kill switch kan stänga generativ formulering eller en signal utan att stänga grundappen.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| ACD-01 | AC v1 är transparent, regel-/signalbaserad och read-only tills användaren bekräftar en vanlig domän action. | Beslutad |
| ACD-02 | AC får aldrig autonomt mutera/skicka och får ingen authorization utöver användarens capabilities. | Beslutad |
| ACD-03 | Generativ AI får endast allowlistat dataminimerat context; känslig minderårig-/healthdata är spärrad tills separat godkännande. | Beslutad |
| ACD-04 | Workload v1 benämns aktivitets-/deltagandeproxy; låg attendance är separat signal. | Beslutad |
| ACD-05 | Injury kräver manuell behörig clearance; expected return ger endast review. | Beslutad |
| ACD-06 | Suspension räknas mot explicit definierade completed eligible matches med revisionsspår. | Beslutad |
| ACD-07 | Självskattning är frivillig känslig utvecklingsdata med begränsad individaccess och skyddade aggregat. | Beslutad |
| ACD-08 | Tactics Board-förslag importeras som granskningsbar draft genom versionerat API. | Beslutad |
| ACD-09 | Signal-/AI-kvalitetsgrind, provenance, feedback och kill switch krävs före release. | Beslutad |

## Konsekvens

Paketet slutför PD-12 och PD-13 på produktnivå samt ND-01/02/09:s grundprinciper. Exakt AI-leverantör, legal basis, retention, ålderspolicy och medicinsk metod kräver separat verifiering innan känslig funktion aktiveras.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | ACD-01–ACD-09 godkända som bindande målbild för rebuildspecifikationen. | Produktägaren |
