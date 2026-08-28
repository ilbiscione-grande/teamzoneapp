# Beslutspaket 6 – billing, kvoter och entitlements

**Status: godkänt med ändring av produktägaren 2026-08-07. BED-01–BED-09 är beslutade.**

## Mål

Spelare och guardians ska aldrig behöva köpa individuell appaccess. Klubben är billing account och kan använda en gratis grundnivå eller köpa större kapacitet, appmoduler och fristående web tools. Servern ska ha en enda entitlementmodell.

## Billing account och subscription

- Varje klubb har högst ett aktivt `billing_account` per kommersiell miljö.
- En kanonisk subscription består av en basplan och noll eller flera items för moduler/web tools.
- Stripe/providerobjekt är betalningskälla; TeamZone lagrar normaliserad subscriptionstatus och härleder entitlements.
- Gamla profil-/teamabonnemang ska migreras och bli read-only innan de avvecklas.
- Okänd, inkonsistent eller ofullständigt verifierad status ger inte ny betalaccess.

## Kvotmodell

Basplanen begränsar två separata mått:

1. antal aktiva lag;
2. antal unika aktiva, debiteringsgrundande personer i klubben.

Rekommenderad definition av debiteringsgrundande person:

- aktiv rosterperson/spelare räknas även utan Auth-konto;
- aktiv ledare och klubbfunktionär räknas;
- samma person räknas en gång per klubb även med flera roller/lag;
- guardian utan annan operativ roll räknas inte;
- avslutad/inaktiv relation räknas inte efter definierad period.

Detta gör guardians individuellt gratis och förhindrar att platshållare används för att kringgå spelargränsen. Produktägaren kan senare ändra kvotdefinition genom versionerad pricebook, inte kodändring.

## Planer och priser

- Planfamiljerna kan vara Free, Small, Medium, Large och Custom/XL.
- Exakta laggränser, personkvoter och priser lagras i en versionerad pricebook.
- Prisförslagen i `new_teamzone.md` är kommersiella hypoteser och godkänns separat efter validering.
- En befintlig subscription behåller sin price version tills en dokumenterad prisändring/migration träder i kraft.
- Månads- och årsintervall är varianter av samma plan, inte olika entitlementlogik.

## Över kvot och downgrade

- Systemet varnar före och vid kvotgräns.
- En kort konfigurerbar grace period kan tillåta administration men inte fortsatt obegränsad tillväxt.
- Downgrade eller payment failure raderar aldrig klubbdata.
- Betalfunktioner går till read-only/exportläge där det är möjligt; nya premiumwrites blockeras efter grace enligt statusmatris.
- Återaktivering återställer access från samma data, inte från en osäker återimport.

## Moduler

- Appmoduler är subscription items med klubbscope. När klubben köper en modul får samtliga lag i klubben använda den.
- Ett item ger en versionerad entitlement, exempelvis `module.match_workspace` eller `module.player_development`.
- Lagrelation och capabilities avgör fortfarande vem som får se eller mutera respektive lags data; klubbentitlement ersätter inte authorization.
- Paket-/mängdrabatt påverkar pris, inte authorization.
- Trial har start/slut, mål-scope och eligibility; den kan inte startas flera gånger genom race/retry.

## Web tools

- Web tools kan köpas fristående av ett separat billing account eller som item för en TeamZoneklubb.
- Fristående access och TeamZone-linking är separata entitlements.
- En kopplad app får endast läsa integrationens uttryckligen delade projektioner.
- Samma tool kan ha olika pricebook/offering beroende på standalone/bundled, men en kanonisk entitlementnyckel per funktion.

## Checkout och webhook

- Checkout kräver billing capability, explicit target och idempotency key.
- Webhook signaturverifieras, dedupliceras på provider-event och behandlas transaktionellt.
- Out-of-order events jämför providerrevision/timestamp och får inte backa state felaktigt.
- Partiellt databasfel returnerar retrybar failure; det kvitteras inte som lyckat.
- Entitlement recompute är deterministisk, auditerad och kan köras om säkert.

## Försäljningskanal

Vilken kanal som får sälja digitala moduler i mobil/webb ska verifieras mot aktuella butiksvillkor och juridik innan checkout-UX beslutas. Produktkravet är kanaloberoende entitlement, inte en hårdkodad betalväg i klienten.

## Beslut

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| BED-01 | Klubben är billing account; spelare/guardians köper inte individuell grundaccess. | Beslutad |
| BED-02 | En kanonisk basplan + subscription items ersätter äldre parallella accessmodeller. | Beslutad |
| BED-03 | Kvoter mäter aktiva lag och unika aktiva roster/ledar/klubbfunktionärspersoner; rena guardians exkluderas. | Beslutad |
| BED-04 | Pris, kvoter och rabatt ligger i versionerad pricebook; dokumentets priser är ännu hypoteser. | Beslutad |
| BED-05 | Överkvot/downgrade använder varning, grace och read-only – aldrig automatisk dataradering. | Beslutad |
| BED-06 | Moduler är klubbscopeade entitlement-items och gäller samtliga lag i köpande klubb; rabatt påverkar endast pris. | Beslutad med ändring |
| BED-07 | Web tools stöder standalone/bundled och separat linking-entitlement. | Beslutad |
| BED-08 | Checkout/webhook är idempotent, signerad, deduplicerad och fail-closed vid partiella/okända tillstånd. | Beslutad |
| BED-09 | Entitlements är kanaloberoende; aktuell appbutiks-/betalpolicy verifieras innan försäljningskanal låses. | Beslutad |

## Konsekvens

Paketet slutför PD-04 och PD-15 samt ND-10:s strukturella del. Exakta prisnivåer, kvoter, grace period och försäljningskanal förblir parametrar som kräver kommersiell och aktuell policyverifiering.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | BED-01–BED-09 godkända; BED-06 ändrad så att alla appmoduler gäller hela köpande klubben. | Produktägaren |
