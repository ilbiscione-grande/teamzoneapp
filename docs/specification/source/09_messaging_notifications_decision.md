# Beslutspaket 4 – Inbox, meddelanden och notifieringar

**Status: godkänt med ändring av produktägaren 2026-08-07. MND-01–MND-10 är beslutade.**

## Mål

Inbox ska erbjuda enkel lagkommunikation utan att skapa en fri social plattform för minderåriga. Samma serverregel ska styra vem som kan hittas, läggas till, läsa, skriva och få push.

## Trådtyper och scope

- **Team chat:** skapas automatiskt med laget och har dynamiskt deltagande från aktiva, tillåtna teamrelationer.
- **Leader chat:** skapas automatiskt och är endast tillgänglig för aktiva leader-capabilities.
- **Group:** explicit klubb-/lagscope, titel, skapare och participantlista.
- **Direct:** exakt två profiler och ett dokumenterat connection-scope som motiverar kontakten.
- **Announcement:** envägsinformation med separat readmodell; svar skapar inte implicit massdistribution.

Alla trådar har ägande klubb och valfritt lag. “Global direct” utan relation är inte tillåten i första versionen.

## Kontaktregler

### Ledare

Ledare får kontakta spelare och guardians inom klubben när capability/legitim relation täcker målpersonen. De får även kontakta verifierade, aktiva ledare i andra klubbar genom en dataminimerad ledarkatalog. Första cross-club-kontakten är en rate-limitad message request; mottagaren kan acceptera, avvisa eller blockera. Full profilkatalog eller fri masskontakt är inte tillåten.

### Spelare

Första versionen tillåter spelaren att:

- skriva till sina verifierade guardians;
- skriva till behöriga ledare för sina aktiva lag;
- skriva i lagchatten enligt lagets policy.

Player-to-player direct är avstängt som default. Senare aktivering kräver klubbpolicy, åldersregel, guardian-/personsamtycke där tillämpligt samt block/report/moderation.

### Guardians

Guardians får kontakta sitt barns behöriga ledare och delta i uttryckligen tillåtna grupp-/announcementytor. Guardians får inte automatiskt se barnets privata konversationer; särskild safeguardingpolicy kan definiera undantag.

## En authorizationregel

- Samma serverfunktion/capabilitymodell används för recipient search, thread creation, participant add och send.
- Deltagare kan inte läggas till genom godtyckligt profil-ID.
- Vid varje send verifieras aktiv participantstatus; en gammal tråd ger inte evig rätt efter att relationen upphört.
- Historik efter avslutad relation styrs av retentionbeslut, inte av fortsatt sendaccess.

## Livscykel och moderering

- En deltagare kan lämna/dölja en frivillig tråd för sig själv.
- Creator eller leader kan inte radera historik för alla enbart genom roll.
- Global hide/delete kräver modereringscapability, reason och audit trail.
- Meddelanden kan ha en kort redigerings-/återkallelseperiod; tidigare version bevaras i audit enligt retentionpolicy.
- Block och report ska finnas innan player-to-player kan aktiveras.

## Bilagor

- Storageobjekt binds till thread/message och är läsbara endast för aktuell participantaccess eller beslutad historikaccess.
- Signed URLs är kortlivade och skapas server-side.
- Metadata och objekt raderas/arkiveras i samma retentionjobb; orphanobjekt är ett testfel.

## Reads, mute och push

- Read state lagras per participant och enhetssynkas genom Realtime/resync.
- “Markera alla” omfattar både messages och announcements enligt deras separata readmodeller.
- Mute/opt-out är fail-closed för frivilliga pushar.
- Push innehåller minsta möjliga metadata och aldrig full känslig body på låsskärm som default.
- Delivery outbox, retry och dedupe följer ECD-08; pushstatus är inte samma sak som message delivery/read.

## Retention

Rekommenderad startpunkt, som måste privacy/legal-verifieras:

- administrativ säkerhetsaudit: längre, starkt begränsad retention;
- message bodies och attachments: klubbpolicy inom fastställda maxgränser;
- pushpayload/deliverymetadata: kort operativ retention;
- read markers: högst trådens retention;
- legal hold/moderation: separat explicit state, aldrig informell permanent lagring.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| MND-01 | Team- och leaderchat skapas automatiskt; group/direct/announcement är separata trådtyper. | Beslutad |
| MND-02 | Direct/group kräver explicit klubb-/lags-/relationsscope; verifierad cross-club-ledarkontakt är det enda globala undantaget i v1. | Beslutad med ändring |
| MND-03 | Spelare får i v1 kontakta guardians, egna ledare och lagchatten; player-to-player är default av. | Beslutad |
| MND-04 | Player-to-player kräver senare safeguardingpaket med policy, samtycke, block/report och moderation. | Beslutad |
| MND-05 | Recipient search, create, participant add och send använder samma serverauktorisering. | Beslutad |
| MND-06 | Leave/hide är personligt; global delete kräver moderation och audit. | Beslutad |
| MND-07 | Attachments följer threadaccess och gemensam objekt-/metadataretention. | Beslutad |
| MND-08 | Mute är fail-closed och push använder dataminimerad preview som default. | Beslutad |
| MND-09 | Retention definieras per dataklass inom centrala maxgränser; legal hold är explicit. | Beslutad |
| MND-10 | Aktiva verifierade ledare får kontakta ledare i andra klubbar via dataminimerad katalog och rate-limitad message request med accept/block/report. | Beslutad |

## Konsekvens

Paketet slutför PD-10 och ger riktning för PD-11/PD-16. Exakta retentionstider och juridiska safeguardingkrav kräver fortsatt privacy/legalbeslut innan implementation.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | MND-01–MND-09 godkända; MND-02 justerad och MND-10 tillagd för cross-club-ledarkontakt. | Produktägaren |
