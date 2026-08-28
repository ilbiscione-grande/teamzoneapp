# Beslutspaket 2 – person, roster, lån och övergång

**Status: godkänt av produktägaren 2026-08-07. PRD-01–PRD-07 är beslutade.**

## Mål

En spelare ska kunna läggas in innan konto finns, senare claima sin historik, representera flera lag, lånas mellan klubbar och byta klubb utan att gamla matcher eller statistik byter ägare i efterhand.

## Rekommenderad begreppsmodell

### Konto och person

- `profile` representerar inloggningskontot och privata kontoinställningar.
- `person` är en intern stabil identitet som kan finnas utan Auth-konto.
- Ett verifierat claim binder högst ett aktivt personobjekt till en profil. Merge/split är en särskild auditerad administrationsoperation.
- Global personidentitet exponeras inte som en fritt sökbar cross-tenant-katalog.

### Klubbens rosterpost

- `club_person` är klubbens tenantägda representation av personen.
- Klubben äger sina lokala kontakt-/rosterfält och får inte läsa andra klubbars poster.
- En person kan ha historiska eller samtidiga `club_person`-poster, exempelvis vid lån.
- Kontoägaren kan se sin egen aggregerade historik genom serverhärledd access utan att klubbarna får se varandras data.

### Lagrepresentation över tid

- `team_assignment` anger hemlag och medlemsperiod med `valid_from`/`valid_to`.
- `team_eligibility` anger andra spelbara lag, med typ: `development`, `dispensation`, `loan` eller `guest` och egen giltighetstid.
- Eventdeltagande, callup, attendance och matchstatistik sparar den representation som gällde vid händelsen.
- Historik räknas aldrig om genom att gamla rader flyttas till nytt lag eller ny klubb.

### Övergång

En permanent övergång ska:

1. kräva behörig initiator och accepterande målklubb;
2. avsluta gammal aktiv assignment vid ett explicit datum;
3. skapa ny klubbpost/assignment utan att ändra historiska facts;
4. dela endast beslutade minimifält;
5. logga actor, källa, mål, samtycke och före/efter.

### Lån och gäst

- Lån är en tidsbegränsad cross-club eligibility med godkännande från båda klubbarna och personen/guardian där det krävs.
- Gäst är en smalare, event- eller periodbunden eligibility och ger inte automatiskt full lagmedlemsaccess.
- Mottagande klubb ser endast de personfält och sportdata som behövs för den beslutade representationen.

### Claim och platshållare

Claim får inte göras genom enbart namnlikhet. Rekommenderad ordning:

1. klubben/guardian skapar platshållaren;
2. en scopead, tidsbegränsad invite utfärdas;
3. inloggad person eller guardian bevisar relationen;
4. servern kontrollerar dubbletter och utför claim atomiskt;
5. alla historiska referenser behåller samma person/roster-ID;
6. konflikt går till manuell, auditerad review – aldrig automatisk merge.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| PRD-01 | Intern `person` är stabil identitet; `profile` är konto och `club_person` är tenantägd rosterrepresentation. | Beslutad |
| PRD-02 | Klubbar kan inte söka/läsa andra klubbars rosterposter; aggregering är endast för personen och särskilt godkända flöden. | Beslutad |
| PRD-03 | Hemlag och spelbara lag modelleras temporalt med assignment respektive typed eligibility. | Beslutad |
| PRD-04 | Statistik och historik binds till representationen vid eventet och skrivs aldrig om vid flytt. | Beslutad |
| PRD-05 | Permanent övergång kräver source/target-acceptans; lån/gäst är tidsbegränsade och dataminimerade. | Beslutad |
| PRD-06 | Claim är token-/relationsverifierat, atomiskt och fail-closed; oklar dubblett går till manuell review. | Beslutad |
| PRD-07 | Minderårig claim, lån och övergång kräver beslutad guardian-/samtyckespolicy innan implementation. | Beslutad |

## Konsekvens

Paketet slutför PD-03 och en stor del av PD-07. Det möjliggör korrekt totalstatistik utan att offra tenantisolering, men kräver en temporal datamodell och explicita transfer-/claim-RPC:er i rebuildspecifikationen.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | PRD-01–PRD-07 godkända som bindande målbild för rebuildspecifikationen. | Produktägaren |
