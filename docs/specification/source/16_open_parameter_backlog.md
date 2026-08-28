# Ägarfördelad parameterbacklogg

**Status: steg 1 slutfört 2026-08-07. Backloggen är inventerad och grindad; parametervärdena beslutas av angivna sakägare.**

## Syfte

De tio godkända beslutspaketen låser produktens riktning. Detta dokument samlar de exakta värden, policyer och leverantörsval som medvetet inte ska gissas eller hårdkodas i rebuildspecifikationen.

En öppen parameter stoppar bara den dataspecifikation, featureaktivering eller release som anges i kolumnen **Grind**. Den stoppar inte säkert arbete i tidigare, oberoende slices.

## Styrning

Varje parameterbeslut ska dokumentera:

- beslutat värde eller policy, scope och giltighetsdatum;
- namngiven sakägare och godkännare;
- juridiskt, kommersiellt, metodiskt eller operativt underlag;
- säker standard när värdet saknas eller inte kan läsas;
- hur värdet konfigureras, versioneras, auditeras och testas;
- om och när beslutet måste omprövas.

Öppna parametrar får inte ersättas med dolda klientkonstanter. Säkerhets-, privacy- och entitlementparametrar ska utvärderas server-side och fail closed. Publika klienter får bara publishable key; secret/service-role-nycklar får aldrig exponeras.

## Prioritet och grind

- **P0:** krävs före den angivna kärnspecifikationen eller säkerhetsgrinden.
- **P1:** krävs före featureaktivering, pilot eller kommersiell lansering.
- **P2:** kan beslutas inför en senare integration eller optimering.
- **Dataspec:** datamodellen kan inte frysas innan beslutet finns.
- **Aktivering:** datamodell kan förberedas, men funktionen förblir avstängd.
- **Release:** produktionstrafik eller nyckelavveckling får inte ske.

## Privacy, safeguarding och retention

| ID | Parameter som återstår | Ägare/godkännare | Prioritet | Grind | Säker standard tills beslutad | Källa |
|---|---|---|---|---|---|---|
| PAR-PRIV-01 | Retentionmatris för meddelanden, versioner, bilagor, pushmetadata, read markers, eventfiler, audit och legal hold | Privacy/data owner + legal/security | P0 | Dataspec för messaging/storage | Ingen automatisk permanent lagring; minsta operativa data, feature avstängd där laglig retention saknas | PD-11, MND-07/09 |
| PAR-PRIV-02 | Legal basis, samtyckesflöde, minimiålder och guardianregler för publik minderårigdata | Privacy/legal + produktägare | P0 | Publikationsdataspec och aktivering | Minderåriga och deras media/statistik är privata | PD-16, PWD-02/03 |
| PAR-PRIV-03 | Retention och safeguarding för publikt kontaktformulär, cross-club requests, block/report och moderation | Privacy/legal + trust/safety | P0 | Messaging-/public-API-spec | Första kontakt begränsas; player-to-player av; ingen permanent kontaktinbox | MND-02/10, PWD-07 |
| PAR-PRIV-04 | Ålder, visibility, guardianinsyn, opt-out och retention för självskattning/utvecklingsdata | Privacy + sportmetodisk ägare + produktägare | P1 | Aktivering av självskattning | Avstängd; data används aldrig till automatisk ranking/uttagning | ND-09, ACD-07 |
| PAR-PRIV-05 | Produktanalys: eventallowlist, pseudonymisering, samtycke, retention och åtkomst | Produktägare + privacy/security | P1 | Analyticsaktivering | Endast nödvändig sanerad drifttelemetri; ingen beteendeanalys | ND-07, CRD-08 |
| PAR-PRIV-06 | Media-/videopolicy: rättigheter, samtycke, region, retention, export och radering | Privacy/legal + operations + produktägare | P1 | Video Analyzer-integration | Ingen uppladdning eller delning av video | ND-08, WID-07 |

## Sportmetodik, hälsa och Assistant Coach

| ID | Parameter som återstår | Ägare/godkännare | Prioritet | Grind | Säker standard tills beslutad | Källa |
|---|---|---|---|---|---|---|
| PAR-METHOD-01 | Regler, tidsfönster och trösklar för workload-, attendance- och watchpointsignaler | Sportmetodisk ägare + produktägare | P1 | Signalaktivering | Endast transparenta råfakta; inga medicinska slutsatser | PD-13, ACD-03/04 |
| PAR-METHOD-02 | Minimiålder, guardianvisibility och process för injury clearance, suspension och dismissal | Sportmetodisk ägare + privacy/legal | P0 | Health-/sanctiondataspec | Manuell behörig clearance; osäker status blockerar riskfylld action | PD-13, ACD-05–07 |
| PAR-AI-01 | Modell-/tjänsteleverantör, region, DPA, dataallowlist, prompt-/outputretention och incidentflöde | Produktägare + privacy/security | P1 | Generativ AC-aktivering | Regelbaserad AC; ingen känslig person-, hälso- eller minderårigdata till modell | ND-01/02, ACD-01–03 |
| PAR-AI-02 | Modellkvalitetsgrind, provenancekrav, utvärderingsdataset, kostnadstak och kill-switchansvar | Produktägare + tech lead + security | P1 | Generativ pilot/release | Generativ funktion avstängd | ACD-08/09 |

## Ekonomi, billing och kommersiella värden

| ID | Parameter som återstår | Ägare/godkännare | Prioritet | Grind | Säker standard tills beslutad | Källa |
|---|---|---|---|---|---|---|
| PAR-FIN-01 | Juridisk omfattning: intern kassauppföljning kontra bokföring, exportkrav, dataklassning och retention | Finance/legal owner | P0 | Ekonomidataspec | Produkten beskriver sig endast som intern uppföljning/export | PD-14, EBD-05 |
| PAR-FIN-02 | Beloppsgränser, risknivåer, dual control, mandat och attestflöden | Finance/legal + security + klubboperations | P0 | Ekonomiska skrivkommandon | Hög risk blockeras eller kräver två uttryckliga godkännanden | EBD-08/09 |
| PAR-FIN-03 | Valutor, avrundning, avgiftsstatus, påminnelsepolicy samt regler för sponsorpledge/settlement | Finance/billing owner | P1 | Economy/fees-aktivering | Ingen automatisk betal- eller settlementbekräftelse | EBD-04/06/07 |
| PAR-BILL-01 | Versionerad pricebook: planer, priser, valuta, moms, årsplan, klubbkvoter och modulrabatter | Produktägare + billing/finance | P1 | Kommersiell lansering | Inga priser från målbildsdokumentet hårdkodas | ND-10, BED-03/04 |
| PAR-BILL-02 | Graceperiod, downgrade-/överkvotmatris, read-only/export och återaktivering | Billing owner + produktägare + support | P0 | Entitlementdataspec | Okänd/utgången entitlement nekar premiumwrites; data raderas aldrig | PD-15, BED-05/08 |
| PAR-BILL-03 | Checkout-/försäljningskanaler och aktuella Apple/Google/webb-/betalvillkor | Billing/legal + produktägare | P1 | Checkoutrelease | Ingen klientcheckout aktiveras utan verifierad kanal | BED-09 |

## Plattform, drift, API och integration

| ID | Parameter som återstår | Ägare/godkännare | Prioritet | Grind | Säker standard tills beslutad | Källa |
|---|---|---|---|---|---|---|
| PAR-OPS-01 | Kanoniska produktionsdomäner, redirect/deep-link origins, hostingprojekt och miljönamn | Operations + tech lead + security | P0 | Auth-/webbreleasespec | Endast explicit allowlistade origins; inga wildcardredirects | PD-17, PWD-08/09 |
| PAR-API-01 | Full endpointallowlist för avsiktligt publika projections/RPC:er, fält, rate limits och enumerationgränser | Security + produktägare + tech lead | P0 | Public API-freeze | Ingen anonym åtkomst utöver explicit godkänd allowlist | PD-20, PWD-04/05 |
| PAR-API-02 | API-/eventversionering, compatibilitypolicy, deprecationfönster och integrations-SLA | Tech lead + operations | P0 | API-spec | Additiva ändringar; gamla konsumenter bryts inte tyst | ND-03–05, WID-06 |
| PAR-OPS-02 | Cache-/CDN-SLA för avpublicering, läs-cacheålder, offline-expiry och resyncgränser | Operations + privacy/security + tech lead | P0 | Cache-/publicationsspec | Stale data märks; känslig tenantcache rensas vid auth-/scopeförlust | PWD-06/09, CRD-04/05 |
| PAR-OPS-03 | Compatibilityfönster, canary/cohort, smokegrind, rollback/roll-forward och verifierad trafiknivå före nyckelavveckling | Tech lead + operations/security | P0 | Release och legacy key retirement | Legacy key lämnas aktiv tills signerad release är verifierad; secret key finns bara server-side | PD-19, CRD-09/10 |
| PAR-OPS-04 | Exakta breakpoints, stödda OS-/browser-/deviceversioner och accessibility-testmatris | Tech lead + design/QA | P1 | Klientrelease | Centrala tokens och konservativ stödmatrix; ingen plattform annonseras utan test | PD-18, CRD-01–07 |
| PAR-OPS-05 | Telemetry/crashprovider, dataplacering, redactionregler, retention, larm och kill-switchjour | Operations + privacy/security | P1 | Production observability | Lokalt sanerade fel-ID:n; inga tokens, secrets eller känsliga payloads | CRD-08 |
| PAR-INTEG-01 | Webtool tenant-linking, identity proof, consent, unlink, syncretry och incidentägarskap | Tech lead + security + respektive produktägare | P1 | Första webtoolintegrationen | Fristående tenant/auth; ingen automatisk profilmatchning eller delad DB-write | ND-04, WID-06/09 |
| PAR-INTEG-02 | SMS-provider, opt-in, avsändare, landstöd, kostnadsansvar, rate limit och retention | Produktägare + privacy + billing/operations | P2 | SMS-pilot | SMS avstängt | ND-06 |

## Supabase- och säkerhetsgrindar för steg 2

Följande är tekniska specifikationskrav, inte valfria produktparametrar:

- authorization baseras aldrig på användarstyrd `user_metadata`;
- alla tabeller i exponerade scheman har RLS och avsiktliga grants/policies;
- `TO authenticated` kombineras med objekts-/tenantscope och UPDATE har både `USING` och `WITH CHECK`;
- privileged funktioner ligger utanför exponerat schema när det är möjligt, har explicit execute-grant och verifierar actor/target;
- views som exponeras respekterar anroparens säkerhetskontext;
- publika projections har separat allowlist och negativa anon-/tenanttester;
- publishable key får användas i klient, medan secret/service-role endast får finnas server-side;
- Auth-, Storage-, Realtime- och Edge Functions-flöden ingår i compatibility- och key-rotationstester.

## Status efter inventering

| Omfattning | Resultat |
|---|---|
| Produktens arkitekturstyrande riktning | Godkänd i beslutspaket 1–10 |
| Kvarvarande parameterfamiljer | 25 registrerade med ägare, prioritet, grind och säker standard |
| Parametrar som måste lösas före relevant dataspec | P0-rader med grinden Dataspec/API-spec/Auth-spec |
| Parametrar som kan skjutas till featureaktivering | P1/P2 med funktionen avstängd eller begränsad |
| Nästa arbete | Detaljerad domän-, data- och API-specifikation, med P0-grindarna som explicita beroenden |
