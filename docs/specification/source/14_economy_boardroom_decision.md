# Beslutspaket 9 – Economy, Board Room och klubbadministration

**Status: godkänt av produktägaren 2026-08-07. EBD-01–EBD-09 är beslutade.**

## Mål

Klubben behöver säker administration även utan betalmodul. Ekonomisk uppföljning och formell governance ska kunna fördjupas i klubbomfattande moduler med revisionsspår och separerade capabilities.

## Produktgränser

### Grundapp: Club Administration

Följande är grundläggande säker drift och ska inte paywallas:

- klubb-/lagmedlemskap och capabilities;
- invite, request, claim och removal;
- guardianrelationer och verifierade ändringar;
- lån/övergång enligt PRD-05–07;
- klubb-/lagsuppgifter och publiceringsansvar;
- club sanction, block eller removal med reason/audit.

Plattformsavstängning från hela TeamZone är separat från en klubbs lokala sanction och kräver plattformsadministration.

### Board Room-modul

- styrelseposter och mandatperioder;
- möten, agenda, deltagare, protokoll, beslut och actions;
- begränsade dokument och visibility;
- revisionshistorik och export.

En styrelsepost ger inte automatiskt tekniska superrättigheter. Varje funktion härleds till explicita club capabilities.

### Economy-modul

- klubb- och lagkassor;
- medlemsavgifter och reminders;
- sponsoravtal och kampanjer;
- privatpersoners pledges/lagsponsring;
- rapporter, export och audit.

Lagkassa och lagsponsring hör till Economy-modulen, inte grundappen. Eftersom modulen köps per klubb kan samtliga lag använda egna scopeade kassor/kampanjer.

## Ekonomisk datamodell

- Pengar lagras i minor units med explicit valuta.
- En bokförd ledgerpost hard-editeras inte; rättelse sker genom reversering/justering med referens.
- Actor, timestamp, source, target account, kategori och underlag ingår i audit.
- Konton kan vara klubb- eller lagbundna men ägs alltid av klubben som tenant.
- Balans är härledd från poster, inte ett fritt redigerbart fält.

TeamZone ska inte beskrivas som juridiskt bokföringssystem innan legal-/redovisningskraven har verifierats. Första nivån kan vara intern kassauppföljning med export.

## Medlemsavgifter

- En avgiftsomgång skapar individuella obligations med belopp, valuta, due date och status.
- Reminder skapar deliveryjobb; status “påmind” sätts först när jobbet accepterats och leveransresultat sparas separat.
- Betalstatus kan initialt registreras manuellt eller importeras. Faktisk betalningsprovider är ett separat idempotent integrationsflöde.
- Ändring/eftergift krediterar eller justerar obligationen och bevarar originalhistorik.

## Sponsring och pledges

- Sponsoravtal har giltighetstid, rätt klubb/lag och beslutade publiceringsfält.
- En kampanj binder event/lag genom servervaliderad relation.
- Pledgevillkor snapshotas när utfästelsen görs, exempelvis belopp per mål och maxbelopp.
- Settlement använder verifierade facts, är idempotent och skapar ekonomiposter – inte omskrivna kampanjvärden.
- Sponsorers/personers publika namn och belopp kräver separat visibility/samtycke.

## Governance och känsliga administrationer

- Ändring av guardianrelation, transfer, sanction och höga ekonomiska belopp kan kräva dual control enligt konfigurerad risknivå.
- Alla privilegierade ändringar kräver reason och immutable audit metadata.
- Board/Economy-data har dataklassning och export-/retentionpolicy.
- Club admin kan inte ge en profil capability utanför klubbens aktiva personrelation utan verifierat invite/claim.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| EBD-01 | Säker Club Administration ingår i grundappen och paywallas inte. | Beslutad |
| EBD-02 | Board Room och Economy är separata klubbomfattande moduler med egna capabilities. | Beslutad |
| EBD-03 | Lagkassa och lagsponsring ligger i Economy-modulen; varje lag får scopead yta när klubben köpt modulen. | Beslutad |
| EBD-04 | Ekonomiska facts är append-only ledgerposter med reversering/justering och härledd balans. | Beslutad |
| EBD-05 | TeamZone v1 är intern kassauppföljning/export, inte juridiskt bokföringssystem utan separat legal verifiering. | Beslutad |
| EBD-06 | Avgiftsobligation, reminder delivery och betalstatus är separata tillstånd med audit. | Beslutad |
| EBD-07 | Sponsor-/pledgevillkor snapshotas och settlement är servervaliderad/idempotent. | Beslutad |
| EBD-08 | Styrelsepost ger inte automatisk superaccess; capabilities och mandatperiod styr. | Beslutad |
| EBD-09 | Guardian/transfer/sanction/högriskekonomi kan kräva dual control och alltid reason/audit. | Beslutad |

## Konsekvens

Paketet slutför PD-14 på produktnivå och svarar på målbildens fråga om lagkassa/lagsponsring. Exakta beloppsgränser, dual-control-policy, retention och juridisk redovisningsnivå kräver finance/legalbeslut.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | EBD-01–EBD-09 godkända som bindande målbild för rebuildspecifikationen. | Produktägaren |
