# Beslutspaket 1 – identitet, roller och kontext

**Status: godkänt av produktägaren 2026-08-07. IDD-01–IDD-06 är beslutade.**

## Varför detta måste avgöras först

Auditens största identitetsproblem är att databas, Dartmodell, shell, route och billing beskriver användaren på olika sätt. Målbilden kräver dessutom att samma person kan vara exempelvis ordförande i en klubb, ledare och vårdnadshavare i en annan samt spelare i ett tredje lag.

## Rekommenderad målmodell

### 1. En Auth-användare och en privat profil

Ett konto motsvarar en `profile`. Profilen innehåller personliga kontoegenskaper, inte lagroll eller authorization.

### 2. Rosterperson är separat från konto

En rosterperson kan existera utan konto och bära historik. När personen registrerar sig skapas en verifierad, auditerad länk mellan profil och rosterperson. Gamla events, lagrepresentationer och statistik flyttas inte till en ny rad.

### 3. Roller visas i UI, capabilities styr servern

Begripliga rollpaket används i produkten:

- spelare;
- ledare;
- vårdnadshavare;
- klubbfunktionär.

Underroller beskriver funktion eller relation. Authorization avgörs däremot av explicita capabilities med scope och giltighetstid, exempelvis:

- `team.events.manage` för ett lag;
- `team.roster.view` för ett lag;
- `member.callup.respond` för en rosterperson;
- `club.billing.manage` för en klubb;
- `club.memberships.manage` för en klubb.

Klienten får aldrig ge rättighet enbart från rollnamn. Servern härleder capabilities från verifierade relationer.

### 4. Läsytor kan aggregera, skrivningar måste ha explicit target

Hem, Kalender och Inbox får samla data från flera behöriga klubbar/lag. Varje mutation måste däremot ange och visa exakt target klubb/lag/event och servern måste verifiera relationen.

Laget och vissa workspaceytor öppnas i en explicit team-/clubkontext. URL och synlig kontext ska alltid kanoniseras till samma objekt.

### 5. Väntrum är ett kontotillstånd, inte en falsk lagroll

En authenticated profil utan aktiv relation får ett begränsat väntrum för invites, requests och klubbclaim. `guest` används endast om produkten beslutar om en verklig, scopead gäst-/lånerelation; det får inte vara fallback för okänd roll.

## Alternativ som avråds

- Ett enda globalt “aktivt lag” för all läsning: fungerar dåligt för flera samtidiga roller.
- En växande enum där varje kombination blir en roll: skapar samma drift som idag.
- Authorization i JWT `user_metadata`: användaren kan ändra metadata och claims blir stale.
- Rosterplatshållare som falska Auth-konton: försvårar claim, privacy och historik.
- Automatisk cross-club profilmerge genom namn/e-post utan verifierat claimflöde.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| IDD-01 | Serverauthorization bygger på scopeade capabilities; roller är UI-/paketeringsbegrepp. | Beslutad |
| IDD-02 | Hem/Kalender/Inbox aggregerar flera contexts; mutationer kräver explicit target. | Beslutad |
| IDD-03 | Rosterperson och Auth-profil är separata och claimas med verifierad länk. | Beslutad |
| IDD-04 | Konto utan relation får väntrum; okänd roll fail-closed. | Beslutad |
| IDD-05 | Klubbfunktionär är ett rollpaket med capabilities, inte en enda allsmäktig roll. | Beslutad |
| IDD-06 | `guest` reserveras för verkligt scopead gäst/lånerelation och får ett begränsat definierat UI. | Beslutad |

## Om paketet godkänns

PD-01 och PD-02 är beslutade. PD-03 är delvis beslutad; exakt global kontra klubbägd rosteridentitet och transfermodell specificeras i beslutspaket 2.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | IDD-01–IDD-06 godkända som bindande målbild för rebuildspecifikationen. | Produktägaren |
