# Min assistent – beslutad målmodell och implementationsguide

**Status:** GODKÄNT PRODUKTBESLUT / AC-04–AC-08 LOKALT IMPLEMENTERADE

**Fastställt:** 2026-08-28

**Livegräns:** dokumentet ger inte behörighet att ändra Supabase live eller aktivera generativ AI

## 1. Beslut

- Funktionens fasta grundnamn är **Min assistent**.
- Assistenten ska få ett kort, sportigt och internationellt användbart standardnamn. Det beslutas senare efter separat namn-, varumärkes-, app- och domänkontroll.
- Varje användare ska kunna välja ett eget personligt namn på sin assistent.
- Ett personligt namn ändrar endast presentation – aldrig dataåtkomst, specialistområde, instruktioner, behörighet, prioritet eller tillåtna handlingar.
- Användaren möter en gemensam assistent, ingång, historik och uppmärksamhetskö.
- Specialistområden är policy- och presentationsprofiler ovanpå samma säkra kärna, inte självständiga gestalter med konkurrerande inkorgar.
- Varje post visar område med **textetikett + ikon + färg**. Färg är aldrig ensam betydelsebärare.
- Prioritet och allvarlighetsgrad visas separat från områdesfärgen. Rött/gult/grönt reserveras i första hand för status, varning och resultat.
- System-, säkerhets-, juridik- och driftmeddelanden kommer fortsatt från TeamZone.

## 2. Terminologi och kompatibilitet

| Begrepp | Betydelse |
|---|---|
| Min assistent | Fast funktionsnamn i navigation, inställningar och onboarding |
| Standardnamn | Gemensamt personligt produktnamn; ännu inte beslutat |
| Personligt namn | Användarens frivilliga, kontosynkade visningsnamn |
| Specialistområde | Stabil klassificering för data, behörighet, språk, ikon, färg och notifieringspolicy |
| Post | Förklarad, tidsmärkt och deduplicerad signal eller sammanfattning |
| Assistentkärna | Gemensamt register, freshness, capabilitygrind, prioritering, audit och feedback |

`Assistant Coach` och befintliga `AC-*`-ID:n får tills vidare finnas som tekniska/historiska namn för migrations- och testkompatibilitet. Ny användarcopy använder **Min assistent** och ett specialistområde. Assistant Coach kan senare vara en intern profil under Lagplanering, men är inte längre paraplynamnet.

## 3. Första områdesregister

| Stabil nyckel | Svensk etikett | Färgkaraktär | Ikonkaraktär | Omfattning | Grind |
|---|---|---|---|---|---|
| `team_planning` | Lagplanering | blå | taktik/planering | event, deltagardraft, kallelser, närvaro | befintliga event-capabilities |
| `training_support` | Träningsstöd | grön | aktivitet/träning | träningsplanering och praktisk uppföljning | datagrind före aktivering |
| `individual_development` | Individuell utveckling | lila | utvecklingskurva | personliga mål och progression | person-/samtyckesgrind |
| `rehab_support` | Rehabstöd | turkos | återhämtning | följa beslutad plan och påminna | LATER-04; inga medicinska beslut |
| `club_administration` | Klubbadministration | orange | klubb/sköld | medlemskap, publicering och klubbuppgifter | klubb-capabilities |
| `communication` | Kommunikation | cyan | meddelande | relationstillåtna svar och uppföljning | messaging-capabilities |

Första tokens är `assistant.area.blue`, `.green`, `.purple`, `.teal`, `.orange` och `.cyan`. De renderas alltid med etikett och områdesspecifik ikon, har automatiskt kontrasttestats i ljust/mörkt tema och är separata från status-/prioritetstokens. Registret versionshanteras; etiketter och design får ändras utan att stabila nycklar eller historik bryts.

## 4. Namnkontrakt

1. Visa standardnamnet när användaren inte har valt ett eget namn.
2. Spara personligt namn per profil, aldrig per klubb eller lag.
3. Synka namnet mellan enheter med en revisionerad, idempotent kontopreferens.
4. Tillåt återställning till standardnamnet.
5. Normalisera whitespace och Unicode samt sätt kort, mobilvänlig maxlängd.
6. Tomt, ogiltigt eller borttaget värde faller säkert tillbaka till standardnamnet.
7. Namnet får inte lagras i authorization claims eller användas i RLS/capabilitybeslut.
8. Namnet behandlas som användarskapat innehåll vid loggning, export och support.
9. Visa varning vid möjlig sammanblandning med legitimerad yrkesperson, verklig funktionär eller systemavsändare.
10. Grundläget är privat; eventuell framtida delning kräver separat modereringsbeslut.

## 5. Gemensam uppmärksamhetsmodell

- Varje post har exakt ett primärt område och kan ha sekundära filtertaggar.
- Samma domänhändelse skapar bara en synlig huvudpost, även om flera områden kan tolka den.
- En global prioriterings- och dedupliceringsmotor väljer huvudpost och presentation.
- Områden har inga separata pushköer. En gemensam budget avgör `direkt`, `sammanfattning`, `endast i Min assistent` eller `av`.
- Kritiska systemmeddelanden går utanför assistentbudgeten genom vanliga TeamZone-flöden.
- Positiva och informativa poster samlas normalt i digest i stället för att avbryta.
- Användaren kan filtrera historik och styra preferenser per område.
- Varje post visar källa, kontext, beräkningstid, freshness/stale, förklaring, område och eventuell säker handling.

## 6. Säkerhets- och ansvarskontrakt

- Servern bestämmer vilka källor, personer, klubbar, lag och actions användaren får se; område eller namn ger aldrig behörighet.
- Specialistprofiler har allowlist för datakällor, signalnycklar, målroller, presentationsfält och actions.
- Navigation kan ske direkt. Mutation kräver ordinarie preview, explicit bekräftelse, serverauktorisation, idempotens och audit.
- Generativ AI förblir separat blockerad tills leverantör, region, dataminimering, retention, minderårigdata, utvärdering och incidentflöde godkänts.
- Rehabstöd får inte diagnostisera, ordinera, rangordna medicinsk risk eller besluta om återgång till spel.
- Assistenten beskrivs som digital funktion, inte människa eller legitimerad expert.

## 7. Stegvis implementation

### Fas A – namn och presentation

- [ ] Besluta sportigt, internationellt standardnamn efter clearance.
- [x] Inför användarcopy `Min assistent` utan att bryta tekniska AC-ID:n.
- [~] Skapa privat kontopreferens för personligt namn med revision, reset och fallback; lokal implementation klar, runtime/kontosynk återstår.
- [~] Bygg onboarding och inställning för standardnamn eller eget namn; inställning klar, onboarding och standardnamnsbeslut återstår.
- [ ] Verifiera lång text, Unicode, textskalning, skärmläsare och mobilbredd.

### Fas B – specialistområden

- [x] Inför versionshanterat register med stabil nyckel, etikett, ikon och design-token.
- [x] Ge varje AC-01-signal ett primärt område; de första fem tillhör initialt Lagplanering.
- [~] Rendera etikett och ikon tillsammans med färg i återanvändbar badge och assistentytan; skarpa kort, historik och detaljvy inväntar aktiverade poster.
- [x] Testa ljust/mörkt tema, automatisk textkontrast och färgoberoende betydelse genom etikett + ikon.
- [x] Håll ej godkända områden registrerade men fail-closed/inaktiva.

### Fas C – en gemensam kö

- [x] Generalisera signalregistret till gemensam assistentkärna med kompatibel migration.
- [x] Inför cross-area canonical key, global prioritet och deterministisk vinnare.
- [~] Inför gemensam notifieringsbudget och digest; kontrakt och lokal budgetplanering klara, serverruntime och faktisk leverans förblir blockerade.
- [x] Lägg till gemensam aktuell/historik-växling, områdesfilter och privata kontosynkade preferenser per område.
- [ ] Verifiera att samma event inte blir flera poster från olika områden.

### Fas D – roll, kontext och specialistpolicy

- [x] Definiera datakälla, capability, målroll, presentation och actions per område.
- [x] Anpassa innehåll efter leader, player, guardian och klubbfunktionär utan cross-context-läckage.
- [x] Bevara mobil-FAB och integrerad tablet/desktop-panel med samma data och rättigheter.
- [x] Visa aktiv klubb/lag/person och acting-as där det behövs före handling.
- [~] Lägg till transparent feedback, dismiss/restore och varför-posten-visas per område; kortkontrakt, förklaring och AC-03-livscykel finns, fysisk skarp postverifiering återstår.

### Fas E – aktivering

- [ ] Kör PostgreSQL-runtime, advisors och flerrollsmatris i godkänd icke-live miljö.
- [ ] Kör fysisk mobil/tablet/desktop-verifiering inklusive offline, stale, reconnect och kontextbyte.
- [ ] Aktivera endast områden vars datakvalitet, freshness, integritet och ägarskap passerat.
- [x] Generativ AI har en separat fail-closed grind och kräver nytt produkt-, integritets-, leverantörs-, region-, retention-, minderårigdata-, eval-, drift- och incidentgodkännande.

## 8. Godkänd när

- Användaren uppfattar en enda personlig assistent och kan välja/återställa dess namn.
- Varje post förstås utan färg och visar område, kontext, källa och freshness.
- Ingen domänhändelse dupliceras mellan områden och notifieringsmängden styrs globalt.
- Namn och specialistprofil kan aldrig utöka behörighet eller datatillgång.
- Systemmeddelanden kan inte förväxlas med assistentposter.
- Rehab-/hälsogränser och generativ AI förblir fail-closed tills separata grindar godkänts.

## 9. Öppna beslut

- Sportigt internationellt standardnamn.
- Slutlig visuell finjustering av de nu införda färgtokens och ikoner efter fysisk tillgänglighetsprovning.
- Maxlängd, varningslista och eventuell framtida delning av personligt namn.
- Vilka områden utöver Lagplanering som ingår i första aktiverade versionen.
