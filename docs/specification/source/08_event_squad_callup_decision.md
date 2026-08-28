# Beslutspaket 3 – event, squad, kallelse och närvaro

**Status: godkänt av produktägaren 2026-08-07. ECD-01–ECD-09 är beslutade.**

## Mål

EventDetails ska vara en sammanhängande livscykel från planering till uppföljning. Delade lag, grupper, cross-team-spelare och notifieringar får inte skapa parallella mutationvägar eller otydligt ägande.

## Event och delade lag

- Varje event har exakt en ägande klubb och ett primärt ägande lag.
- Ytterligare deltagande lag kopplas genom explicita `event_team`-relationer med capabilities, exempelvis `view`, `manage_roster` eller `co_manage`.
- Sekundärlagsledare får bara redigera de delar som relationens capabilities tillåter.
- Audience (`players`, `leaders`, `guardians` med flera) styr synlighet och kallelsemål men skapar inte automatiskt redigeringsrätt.
- Shared event får aldrig bindas ihop enbart genom att klienten skickar godtyckliga team-ID:n.

## Recurrence och eventstatus

- En serie är ett förstaklassobjekt; varje förekomst är ett event med egen identitet.
- Serieändring skapar en revision och appliceras atomiskt på beslutat framtidsscope. En enskild förekomst kan ha override.
- Eventstatus följer en state machine: `draft`, `scheduled`, `cancelled`, `completed`.
- Cancel och complete är explicita, auditerade transitioner. Cancel kan utlösa återkallelse av callups/notiser.

## En squadkälla

- Eventets revisionerade `squad_draft` är enda source of truth innan callups skickas.
- Manuell individ, “alla”, sparad grupp, helt lag och generator är endast sätt att fylla samma draft.
- Grupper är återanvändbara urvalsmallar och skapar aldrig callups direkt.
- Varje draftmedlem måste ha giltig assignment/eligibility för eventets lag och tidpunkt eller en explicit eventguest-approval.
- Send fryser en version av draften till callups. Senare tillägg blir separata late callups och skrivs inte över av plansynk.

## Callup och response

- Callupstatus: `draft`, `pending`, `accepted`, `declined`, `cancelled`.
- `pending` betyder skickad men obesvarad. `draft` är aldrig mottagarsynlig.
- Decline reason är valfri men strukturerad anledning och fritext hålls separata.
- Guardian acting-as-child är explicit i kommandot och auditloggen; svaret ägs fortsatt av barnets callup.
- Svar via push använder scopead, single-use eller säkert idempotent token med expiry och samma servertransition som appen.

## Attendance

- Attendance är separat från callupresponse.
- Status: `unknown`, `present`, `late`, `partial`, `absent`.
- `unknown` får aldrig räknas som absent eller present.
- Late/partial kan kompletteras med minuter eller anteckning enligt eventtyp.
- Ändring efter beslutad tidsgräns kräver särskild capability och skapar revisionspost.

## Leverans och retry

- Send/cancel/reminder skriver domänändring och notification outbox atomiskt.
- Push/SMS-leverans är asynkron och har per mottagare status, retry och dedupe.
- Avstängd kanal eller leveransfel ändrar inte callupens domänstatus och får inte presenteras som full leverans.
- Notification preferences är fail-closed för frivilliga utskick; produktkritiska undantag måste definieras uttryckligen.

## EventDetails-yta

- **Info:** säker, rollanpassad sammanfattning och praktisk information.
- **Trupp:** squad draft, callups, responses och attendance med tidsstyrda lägen.
- **Förberedelser:** eventtypsspecifik planering med valfria modulprojektioner.
- **Uppföljning:** resultat, KPI/reflektion/beslut och importerad moduldata.
- Personliga anteckningar och staff-/participantinformation har separata visibilitynivåer.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| ECD-01 | Event har ett primärt ägande lag; delade lag får explicita capabilities per relation. | Beslutad |
| ECD-02 | Audience styr synlighet/mottagare men aldrig ensam redigeringsrätt. | Beslutad |
| ECD-03 | Recurrence är förstaklassobjekt och event använder state machine för draft/scheduled/cancelled/completed. | Beslutad |
| ECD-04 | Revisionerad squad draft är enda väg till callups; grupper/alla/generator är inputmetoder. | Beslutad |
| ECD-05 | Eligibility valideras server-side vid draft och send; late callups är explicita och bevaras. | Beslutad |
| ECD-06 | Callup response och attendance är separata state machines med `unknown` som eget närvarotillstånd. | Beslutad |
| ECD-07 | Guardian acting-as är explicit och auditerat; pushtoken har scope, expiry och replay/idempotensskydd. | Beslutad |
| ECD-08 | Notification outbox, leveransstatus och retry är separerade från callupens domänstatus. | Beslutad |
| ECD-09 | EventDetails använder Info/Trupp/Förberedelser/Uppföljning med eventtyp- och visibilitykontrakt. | Beslutad |

## Konsekvens

Paketet slutför PD-05–PD-08 och ger en gemensam grund för Kalender, EventDetails, push, attendance, Match Space och Training Space.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | ECD-01–ECD-09 godkända som bindande målbild för rebuildspecifikationen. | Produktägaren |
