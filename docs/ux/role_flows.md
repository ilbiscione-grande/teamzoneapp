# Rollflöden i TeamZone – underlag för UX-genomgång

**Syfte:** beskriva hur appen ser ut och används för varje roll idag, så att vi kan testa flödena ett i taget och förbättra dem.
**Läge:** sammanställt 2026-10-19 från koden (main, commit `06081f9`). Det som är märkt *(verifiera)* är härlett ur koden och behöver bekräftas på telefonen.

Så här testar vi:

1. Logga in med testkontot för rollen (se avsnitt 1) på telefonen och, där det anges, på webben (app.teamzoneapp.se).
2. Gå igenom rollens flöden i ordning och bocka av testpunkterna.
3. Skriv det som känns fel under **Fynd** i rollens avsnitt: vad du ville göra, vad som hände och hur det borde vara.
4. Vi samlar fynden i avsnitt 8 och gör om dem till leveranskort.

---

## 1. Testkonton som behövs

Vi testar i **Demoklubben IF**. Kontona heter `tre60grader+<roll>@gmail.com`. Läget nedan hämtades från databasen 2026-10-19.

| Behov | Konto | Kontext och behörigheter idag | Används för |
|---|---|---|---|
| Spelare | `+spelare` | Spelare i A-lag Herr | Avsnitt 3 |
| Vårdnadshavare med två barn | `+vardnadshavare` | Vårdnadshavare i F2013 och P2015 | Avsnitt 4 |
| Ledare (huvudtränare) | `+tranare` | Ledare i P2012, alla lagbehörigheter inklusive hantera ledare | Avsnitt 5 |
| Ledare (lagledare) | `+lagledare` | Ledare i P2012, utan hantera ledare | Avsnitt 5, skillnad i behörighet |
| Styrelseledamot utan lag | `+styrelse` | Klubbfunktionär för hela klubben: `board.read`, `board.manage`, `economy.read`, `club.messaging.manage` | Avsnitt 6.4 |
| Klubbadministratör utan lag | *saknas* (ditt huvudkonto?) | behöver `club.memberships.manage` | Avsnitt 6.2 |
| Kassör utan lag | *saknas* | behöver `economy.read`, `economy.post`, `economy.approve` | Avsnitt 6.3 |
| Ordförande (godkänner beslut) | *saknas*, eller ge `+styrelse` `board.approve` | | Avsnitt 6.4 |
| Domaransvarig | *saknas*; kan ges till `+styrelse` eller `+tranare` i appen | `club.referees.manage` | Avsnitt 6.5 |
| Ledare i två lag | *saknas*; ge `+tranare` en ledarroll i ett lag till | | Avsnitt 2.3, 5 |
| Ledare som också är kassör | *saknas* | | Avsnitt 7 |
| Föreningsdomare under 15 | *saknas*; ett av `+vardnadshavare`s barn kan bli föreningsdomare | | Avsnitt 7 |

Ekonomi- och styrelsebehörigheter kan inte delas ut i appen idag (lucka 3 i avsnitt 8). Tills vidare sätts de kontona upp med SQL.

---

## 2. Det gemensamma skalet (alla roller)

### 2.1 Navigering

**Bottenmenyn på telefon** har fem knappar i den här ordningen:

1. **Laget**
2. **Kalender**
3. **Hem**, i mitten. Svep uppåt på knappen öppnar snabbåtgärder.
4. **Inkorg**
5. **Femte knappen**, som följer rollen:
   - **Ledare:** Arbetsytor
   - **Med ekonomibehörighet:** Ekonomi
   - **Med styrelsebehörighet:** Styrelse
   - **Alla andra:** Inställningar

   Man kan välja själv under Inställningar, bland Utveckling, Inställningar och de som rollen tillåter.

**Sidomenyn** öppnas med avataren uppe till vänster. På surfplatta och dator är den en fast sidopanel. Den innehåller:

- **Profil:** egen profil (bild, namn, roller).
- **Kontextknapp:** lag och roll, och öppnar kontextväljaren.
- **Huvudrader:**
  - Hem, Kalender, Laget, Inkorg och Utveckling.
  - Arbetsytor, för ledare.
  - Domartillsättning eller Domarersättning, om man har den behörigheten i det aktiva lagets klubb.
- **Admin:** Abonnemang, Ekonomi och Styrelse, styrt av behörigheter.
- **Längst ned:** Inställningar och Logga ut.

**Snabbåtgärder** (svep upp på Hem) styrs av behörigheter:

| Åtgärd | Vem ser den |
|---|---|
| Skapa nytt event, Ny träning, Ny match | `event.manage` |
| Bjud in spelare, Ledare och roller, Kontaktuppdatering | Truppbehörighet (`team.roster.manage`) eller klubbadmin |
| Medlemsansökningar | Klubbadmin |
| Skicka meddelande | Alla |
| Nytt informationsmeddelande | Ledare och klubbadmin |
| Kalender, Laget (för den som får hantera truppen: Hantera laget), Öppna inkorgen | Alla |
| Lagstatistik | `event.manage` eller `event.attendance.manage` |
| Abonnemang, Ekonomi, Styrelse | Respektive behörighet |
| Nyhetsredaktion | `publication.manage` |
| Publika sidor | `publication.manage` eller truppbehörighet (`team.roster.manage`) |

**Min assistent** är en flytande knapp. Den visas när det finns något aktuellt och kan dras längs kanten. "Behöver din uppmärksamhet" har flyttats från Hem till assistenten.

### 2.2 Notiser

- Push och notiscentralen.
- Ett tryck öppnar rätt ställe: tråden, matchen, Hem för domaruppdrag, eller matchpoolen.

### 2.3 Kontexter

- En kontext är **ett lag och en roll**, till exempel "P10 · Ledare", eller **hela klubben och en roll**, till exempel "IF Eksjö · Klubbfunktionär".
- Kontextväljaren grupperar per klubb, med det aktiva laget överst. Där finns också:
  - Skapa ytterligare lag
  - Skapa en ny klubb
  - Förfrågningar om nya lag (klubbadmin)
  - Gör klubben officiell (klubbadmin)
  - Hitta klubb eller lag
- Allt i appen, alltså Hem, Laget, Kalender, Inkorg och menyerna, följer den aktiva kontexten.

**Testpunkter**

- [ ] G-01 Bottenmenyns femte knapp stämmer för rollen och går att byta under Inställningar.
- [ ] G-02 Sidomenyn visar bara rader man har behörighet till, och raden för den aktiva sidan är markerad.
- [ ] G-03 Kontextbyte uppdaterar Hem, Laget, Kalender, Inkorg och menyerna utan att något gammalt dröjer kvar.
- [ ] G-04 Snabbåtgärderna känns relevanta för rollen: inget som leder till "saknar behörighet".
- [ ] G-05 Ett tryck på en notis öppnar rätt sida, även från kallstart.
- [ ] G-06 Assistentknappen syns bara när det finns något, och läget sparas efter flytt.

**Fynd:** (Claudes genomgång 2026-10-19 med `+tranare` i webbappen, mobilläge)

- **F-G1 Kalenderfel vid omställning från sommartid** *(rättat, ej driftsatt)*: i oktober stod 25 två gånger, och alla datum efter 25 oktober hamnade en dag fel i månadsvyn. Det påverkade också vilka aktiviteter som visades på vilken dag. Orsaken var att appen räknade fram dagarna med 24-timmarssteg.
- **F-G2 Namnet i sidomenyn visar "Logga ut".** Profilen saknar visningsnamn, och då visas texten för utloggning i stället. Namnet borde hämtas från personen i klubben ("Hugo Olofsson") eller från e-postadressen.
- **F-G3 "Inbox" på engelska** i bottenmenyn och sidomenyn. Resten av appen är svensk ("Inkorg").
- **F-G4 Snabbåtgärderna är svåra att hitta.** Man sveper uppåt på Hem-knappen, men ingenting visar att gesten finns. Det gick inte att öppna dem med mus i webbappen *(prova på telefon)*.
- **F-G5 Första trycket i bottenmenyn efter att sidomenyn stängts** visar bara en verktygstips-ruta och byter inte sida.
- **F-G6 Två flytande knappar på varandra** på Trupp (lägg till person och assistenten). De konkurrerar med varandra och skymmer listan.

**Produktägarens genomgång och beslut 2026-10-19** (byggt samma dag, väntar på migration och driftsättning):

- **F-G7 Appen stängdes vid bakåt** på Hem, Kalender, Laget och Inkorg på Android 16. Orsaken var predictive back (targetSdk 36): den inre routerns "inget att gå tillbaka till" nådde appen. *Rättat:* skalet säger alltid att det hanterar bakåt, så bakåt går till Hem, och på Hem frågar appen "Stäng TeamZone?".
- **G01** *Byggt:* den femte knappen heter **Mer** och öppnar en meny med det rollen och behörigheterna ger:
  - Arbetsytor (ledare), eller Utveckling;
  - Lagstatistik, Ekonomi, Styrelse, Domartillsättning eller Domarersättning;
  - Abonnemang, Nyhetsredaktion och Publika sidor;
  - Vår publika sida, Min profil och Inställningar.

  Inställningen för femte knappen är borttagen.
- **G02** *Byggt:* för ledare ligger Utveckling under Arbetsytor och inte i sidomenyn. Lagstatistik finns också under Arbetsytor.
- **G04** *Byggt:* "Gå till" i snabbåtgärderna slutar med samma länkar som Mer: arbetsytor, länk till den publika sidan (när klubben har publicerat den), Min profil och Inställningar. Svepet fungerar med finger, också på webben.
- **Assistenten** *Byggt:* viktiga uppgifter (dagens kallelser och förberedelser, krockar) har röd ram och etiketten "Viktigt". Assistentknappens siffra är röd när det finns viktiga uppgifter och neutral annars.
- **F-G2** *Rättat:* sidomenyn visar namnet, eller inloggningsadressen om namn saknas. Den visar aldrig "Logga ut".
- **F-G3** *Rättat:* "Inkorg" på svenska.


---

## 3. Spelare

**Mål:** förstå vad som händer härnäst och vad man behöver göra.

### 3.1 Komma in

- **Inbjudan från ledaren:** länk eller kod, sedan konto och godkännande av villkor. Spelaren landar på Hem i lagets kontext.
- **Medlemsansökan:** Hitta klubb eller lag, välj "Ansök som: Spelare", och ledaren eller administratören godkänner.

### 3.2 Hem

- Hälsning med förnamn och datum.
- **Nästa aktivitet** som huvudkort, med Acceptera och Avböj när det finns en kallelse. Avböj frågar efter anledning: sjukdom, skada, inte tillgänglig, transport eller annat.
- **Resten av idag** och **Kommande**.
- **Olästa meddelanden**, som leder till inkorgen.
- Kortet **Mina domaruppdrag**, om spelaren också är föreningsdomare.

### 3.3 Laget

- Flikarna **Översikt**, **Trupp** och **Kalender**. Statistik finns inte.
- Trupp har sök och filter (status, vem, position och sortering). Lagkamraternas profiler visas med det som är tillåtet.

### 3.4 Kalender

- De egna aktiviteterna och svar på kallelser.
- Aktivitetssidan: Info (tid, plats, samling, domare), förberedelser och deltagare (det som är tillåtet).

### 3.5 Inkorg

- Bara fliken **Inkorg**.
- Skicka meddelande till ledare (tillåtna mottagare) och svara i trådar.

### 3.6 Övrigt

- **Utveckling:** egen utveckling *(verifiera innehåll)*.
- **Egen profil** via avataren. Inställningar, adress- och kontaktuppgifter.

### 3.7 Nyckelflöden att testa

- [ ] SP-01 Svara Ja på en kallelse från Hem, svaret syns direkt och hos ledaren.
- [ ] SP-02 Svara Nej med anledning, och ändra sedan till Ja.
- [ ] SP-03 Hitta samlingstid och plats för nästa match på högst två tryck.
- [ ] SP-04 Skicka ett meddelande till tränaren.
- [ ] SP-05 Hitta en lagkamrat och se vad som får visas.
- [ ] SP-06 Uppdatera sina kontaktuppgifter.
- [ ] SP-07 Få en kallelse som push, tryck och svara.

**Fynd:** (Claudes genomgång 2026-10-19 med `+spelare`, Hugo Lindgren i A-lag Herr, webbappen, bara tittat)

- **F-S1 Veckonumret blev fel efter omställningen till vintertid** *(rättat, ej driftsatt)*: med 20 oktober valt stod vecka 42, fast det är vecka 43.
- **F-S2 Hem för tränaren saknade namn i hälsningen**, eftersom kontoprofilen inte har något namn *(rättat, ej driftsatt)*. Hälsningen använder nu namnet i laget, som sidomenyn.
- **F-S3 Utveckling i Mer leder till en låst sida**: "Utvecklingsplaner är inte tillgängliga. Den här rollen saknar behörighet i aktuell lagkontext." Spelaren ska inte erbjudas en sida som den inte får se. Antingen tas den bort för spelare, eller så visar den spelarens egen utveckling.
- **F-S4 Ingen väg att säga "kan inte komma"** till en träning utan kallelse. Hem och aktivitetssidan har inga svarsknappar då.
- **F-S5 Aktivitetssidan visar ledartext för spelaren**: "Kallelse behövs inte. Assistenten påminner inte om saknade kallelser. Ändras i menyn ⋮".
- **F-S6 Uppföljning före aktiviteten** visar spelaren "Närvaro –" och tomma staplar utan förklaring.
- **F-S7 Ledarna på Laget → Översikt är bara text.** Spelaren kan inte trycka på en ledare för att se kontakt eller skriva till hen.
- **F-S8 Trupplistan visar ingen position när huvudposition saknas**, fast profilen visar "Mittfältare". Spelaren själv är inte markerad med "(du)" i listan.
- **F-S9 Spelaren ser "Visa medlemskort" på lagkamraters sidor.** Behöver bestämmas: ska lagkamrater se varandras medlemskort?
- **F-S10 Filterikonen i kalendern har en röd prick** som om ett filter vore aktivt, utan att spelaren valt något *(verifiera vad pricken betyder)*.
- **F-S11 Min profil markerar "Laget" i bottenmenyn** i stället för "Mer". En rad i inkorgen (lagchatten) saknar datum.
- Det som fungerar bra: Hem visar tydligt nästa träning och Kommande, Mer är kort och relevant, och kalendern visar oktober rätt.

**Produktägarens beslut 2026-10-19** (byggt samma dag, väntar på migration och driftsättning):

- **F-S3 och G02** *Byggt:* Utveckling visas inte i sidomenyn eller i Mer, för någon roll. Ledare når den via Arbetsytor. Den kan komma tillbaka när arbetsytorna öppnas för fler roller.
- **F-S4** *Byggt (kräver migration `20261113090000`):* frånvaroanmälan.
  - **Läget:** ett lag kan stänga av "Kallelser till aktiviteter" på Laget → Översikt. Då förväntas alla komma, och nya och kommande aktiviteter utan skickade kallelser följer valet. Varje aktivitet kan ändras med "Kallelse behövs" i menyn ⋮.
  - **Spelaren:** spelaren, eller vårdnadshavaren för sitt barn, anmäler med "Kan du inte komma?" → Anmäl på Info-fliken, med samma anledningar som vid avböjd kallelse, och kan ångra.
  - **Ledaren:** ledarna får en notis, "Frånvaroanmälan", som inte visar vem eller varför. Ledaren ser anmälan med anledning på Deltagare. Efter aktiviteten bekräftar första trycket frånvaron.
  - **Uppföljningen:** visar "Anmäld frånvaro: N · X av Y frånvarande hade anmält".
- **F-S5** *Byggt:* texten om assistentens påminnelser visas bara för dem som kallar.
- **F-S6** *Byggt:* före aktiviteten visar Uppföljning spelaren "Uppföljningen visas när aktiviteten är genomförd."
- **F-S7** *Byggt:* ledarna på Laget → Översikt går att trycka på och öppnar ledarens sida.
- **F-S8** *Byggt:* trupplistan visar huvudposition, eller annars den första positionen, och "(du)" efter ens eget namn.
- **F-S9** *Byggt:* medlemskortet syns bara på den egna sidan och för dem som hanterar laget.
- **F-S10** *Rättat:* det aktiva laget räknas inte som filter, så ingen röd prick visas. *Rättat:* efter "Alla lag" gick det inte att välja tillbaka ett enda lag när man bara har ett lag.
- **F-S11** Min profil markerar Laget, och det är rätt. *Rättat:* inkorgsraden visar alltid datum, även när förhandsvisningen är lång.
- **F-S12** *Byggt:* spelare ser inga cirklar för att välja trupp, inga påminnelseklockor och inga pilar på andras rader på Deltagare.
- **F-S13 Integritetsfel** *(rättat, kräver migration)*: sedan CAL-11 såg alla i laget allas kallelser och närvaro. Kallelser är nu privata som standard igen. Ett lag kan visa dem för spelarna ("Spelarna ser vilka som är kallade" på Laget → Översikt), och varje aktivitet kan välja annat under Deltagare → ⋮ → "Vad spelarna ser…". Närvaro syns bara för dem som hanterar laget och för personen själv.
- **Matchläget** *Byggt:* matchläget visas bara för ledare och för den som har behörighet för matchdagen. **Startelva** finns i stället under Förberedelser vid matcher. Ledaren sätter startelva (start, bänk, position och formation) och väljer "Visa för spelarna". Spelarna ser den då direkt under Förberedelser *(kräver migration `20261113090000`)*.


---

## 4. Vårdnadshavare

**Mål:** hantera rätt barns aktiviteter och svar.

- **Hem:** "Visa för barn" (barnväljare) och "Du agerar för {barn}". Barnets identitet följer med i svaren. I övrigt samma kort som spelaren, för det valda barnet.
- **Kalender** och **svar:** för det valda barnet. Barn i olika lag ger olika kontexter *(verifiera hur väljaren och kontexten samverkar)*.
- **Laget:** barnets lag med tillåten information.
- **Inkorg:** trådar om barnet och kontakt med ledare.
- **Föreningsdomare under 15:** vårdnadshavaren svarar på domarförfrågningar och ser ersättningen till 18 år ("Mina domaruppdrag").

### Nyckelflöden att testa

- [ ] VH-01 Byta barn på Hem, och att rätt barns kallelser visas utan rester från det förra.
- [ ] VH-02 Svara på kallelse för barnet och se att ledaren ser vem som svarat.
- [ ] VH-03 Två barn i olika lag: hitta båda barnens nästa aktivitet snabbt.
- [ ] VH-04 Kontakta barnets ledare.

**Fynd (2026-10-20, Hanna i F2013 och Liam i P2015):**

- VH-F1 Matchläget syntes för vårdnadshavaren. *Åtgärdat:* kräver ledarbehörigheten för matchdagen (`match_live`).
- VH-F2 Ledartexten "Kallelse behövs inte … Ändras i menyn ⋮" syntes. *Åtgärdat:* bara för den som kan ändra aktiviteten.
- VH-F3 Frånvarokortet sa "Kan du inte komma?" till vårdnadshavaren. *Åtgärdat:* "Kan inte Hanna komma?".
- VH-F4 Ledarna på Laget → Översikt ledde till "Medlemsdetaljen är inte tillgänglig". *Åtgärdat:* raderna är inte länkar för vårdnadshavare.
- VH-F5 (VH-04) "Nytt meddelande" var tomt och sa "Inga mottagare matchar sökningen". F2013:s ledare saknar konton (demodata). *Åtgärdat:* tomläget förklarar varför.
- VH-F6 Barnväljaren visades med ett enda barn. *Åtgärdat:* döljs med ett barn.
- VH-F7 Utan visningsnamn visas inloggningsadressen i menyn på två rader. *Åtgärdat:* en rad.
- VH-F8 Flerdagsaktiviteter visades "16:00–16:00" i kalenderns lista. *Åtgärdat:* med datum.
- VH-F9 (VH-03) Barn i olika lag syns bara efter lagbyte i menyn. *Åtgärdat:* barnväljaren listar barnen i alla dina vårdnadshavarlag ("Liam · P2015"), och ett barn i ett annat lag byter lag och visar det barnet.
- VH-F10 "Skapa en ny klubb" ligger i lagbytet för alla roller. *Beslut:* ska finnas kvar för alla, även vårdnadshavare.
- VH-F11 Räknarna (utkast, kallade, ja, obesvarade, nej) överst på aktiviteten sa inget för vårdnadshavaren. *Åtgärdat:* visas bara för den som kallar.

---

## 5. Ledare

**Mål:** planera laget och agera på det som kräver uppmärksamhet.

### 5.1 Komma in

- Skapar ett nytt lag eller klubb, eller blir inbjuden som ledare.
- Behörigheterna sätts per ledare under **Ledare och roller**. Grupperna är:
  - **Trupp:** hantera trupp och ledare.
  - **Aktiviteter:** skapa och ändra, kallelser, närvaro, sen närvarorättelse och logistik.
  - **Träning:** träningsplanering.
  - **Match:** matchplan och taktik, och matchläge live.
  - **Utveckling och Publicera.**

  Det finns färdiga titelpaket, till exempel huvudtränare, assisterande tränare, lagledare och specialisttränare.

### 5.2 Hem

- Nästa aktivitet, med egen kallelse om ledaren är kallad. Resten av idag och Kommande.
- **Snabbåtgärder:** "Planering och administration" på bred skärm, med skapa aktivitet, hantera laget och inkorgen.
- Uppmärksamhetspunkter (saknad närvaro, obesvarade och liknande) finns i **Min assistent**, inte på Hem.

### 5.3 Laget

- Flikarna **Översikt**, **Trupp**, **Kalender** och **Statistik**.
- **Översikt:** lagbild, info, ansökningar och inbjudningar.
- **Trupp:**
  - Aktiva visas som standard.
  - Filter på status, vem, flera positioner och sortering.
  - Personsidor med roller, titlar och positioner.
- **Bjud in spelare** (kod och länk), **Kontaktuppdatering** och **Ledare och roller**.

### 5.4 Kalender och aktiviteter

- **Skapa:** träning, match eller event.
- **Aktivitetssidan:**
  - Info, med domare: typ av domare, antal och sökfält.
  - Kallelser: välja trupp, skicka och påminna.
  - Närvaro, uppföljning, förberedelser och logistik.
- **Match:** matchplan och matchläge.
- **Matchpoolen:** söka träningsmatch, annonsera och bevaka.

### 5.5 Inkorg

- Flikarna **Inkorg**, **Matchpool** och **Klubbsajt**.
- Informationsmeddelanden till laget. Markera lästa per klubb.

### 5.6 Arbetsytor och Utveckling

Arbetsytor är femte knappen och har planeringsytor *(verifiera innehåll)*. Utveckling innehåller spelarutveckling.

### 5.7 Nyckelflöden att testa

- [ ] LE-01 Skapa en match med motståndare och plats, kalla trupp och skicka.
- [ ] LE-02 Se vilka som inte svarat och påminna dem.
- [ ] LE-03 Ta närvaro på plats på telefonen, under en aktivitet.
- [ ] LE-04 Bjud in en ny spelare och godkänn när hen registrerat sig.
- [ ] LE-05 Ge en assisterande tränare rätt behörigheter.
- [ ] LE-06 Lägga till domare på matchen (sök, eller Lägg till ett namn).
- [ ] LE-07 Skicka informationsmeddelande till laget och se vilka som läst.
- [ ] LE-08 Lägga ut och boka en träningsmatch i matchpoolen.
- [ ] LE-09 Svara på en kontrollfråga om föreningsdomare.
- [ ] LE-10 Ledare i två lag: byta lag och göra samma sak i det andra laget.

**Fynd:** (Claudes genomgång 2026-10-19 med `+tranare`, bara tittat, inget ändrat)

- **F-L1 Hem visar inte det som behöver göras.** Dagens träning har 16 obesvarade kallelser, närvaro saknas för tre aktiviteter och slutresultat saknas för en match. Allt det finns bara i Min assistent (5). Hem ser lugnt ut, med "Din kallelse: Accepterat" och Kommande. Förslag: ett kort på Hem med assistentens viktigaste punkter, eller åtminstone "16 har inte svarat" på dagens aktivitet.
- **F-L2 Påminn alla är gömd.** "Påminn alla obesvarade" ligger i trepunktsmenyn på Deltagare, bland urvalsverktyg med svåra namn ("Behörighetsgrupp", "Generator"). Den borde ligga som knapp vid "14 kallade · 0 svarat".
- **F-L3 Siffror utan förklaring på aktivitetssidan.** Fem färgade cirklar (0, 17, 1, 16, 0) har ingen text. Titeln ("Träning") kommer också först en stund efter att sidan öppnats.
- **F-L4 Deltagarraderna har tre små ikoner** (klocka, bock och kryss) utan text. Det är lätt att trycka fel, och det är oklart om bocken betyder svar eller närvaro.
- **F-L5 Trupplistan visar "P2012" på varje rad**, vilket inte säger något i lagets egen trupp. Position, roll eller status (till exempel skadad) vore mer användbart.
- **F-L6 Spelarsidan saknar vårdnadshavare och kontaktvägar.** För en 14-åring står e-post och telefon som "Ingen angiven", och det finns ingen knapp för att skicka meddelande. Ledaren behöver se vårdnadshavarna och kunna kontakta dem.
- **F-L7 Laget → Översikt visar inte ansökningar eller inbjudningar** som väntar, trots att det står i målbilden för ledare. Senaste match visas utan resultat, och ingenting visar att resultatet saknas.
- **F-L8 Inkorgen har inga flikar** (Matchpool och Klubbsajt) för ledaren *(verifiera varför: villkoret för Matchpool är ledare)*. Datumen står som "2026-10-07 · 20:09", medan resten av appen skriver "22 okt. 2026".
- **F-L9 Arbetsytor (femte knappen) innehåller bara Utveckling**, som redan finns i sidomenyn. Resten är tre ytor märkta "Kommer". Kalender eller Meddelanden vore troligen en mer användbar femte knapp tills vidare.
- **F-L10 Kalenderlistan** visar inte hur många som svarat på en kallelse, och inte om något saknas, till exempel närvaro.
- **F-L11 Varje flik på aktivitetssidan visar en laddningssymbol** en stund. Det känns segt.

**Produktägarens beslut 2026-10-19:**

- **F-L1** Hem visar redan bra vad som är aktuellt. Det viktiga markeras på assistentknappen i stället (se G-avsnittet).
- **F-L2** *Byggt:* knappen "Påminn" ligger på samma rad som sökfältet och trepunktsmenyn på Deltagare.
- **F-L3** Ingen ändring. Cirklarna har en förklaring när man trycker på dem, och det räcker.
- **F-L6** *Byggt:* spelarsidan visar vårdnadshavare med telefon och e-post (så långt kontaktskyddet tillåter). Den har en knapp "Skicka meddelande till spelare och vårdnadshavare" som öppnar inkorgen med dem förvalda.
- **F-L5** *Byggt:* truppraden visar bara huvudpositionen. Lagnamnet visas bara när personen tillhör ett annat lag.
- **F-L8** Matchpool och Klubbsajt syns hos produktägaren, så det var inget fel. *Rättat:* datumen i inkorgen skrivs som i resten av appen ("7 okt. 2026 · 20:09").
- **F-L9** Löst genom Mer (G01). Fler arbetsytor kommer senare.


---

## 6. Klubbmedlem utan lagkoppling

En kontext för hela klubben, till exempel "IF Eksjö · Klubbfunktionär". Personen har ingen lagroll men har klubbuppdrag genom behörigheter.

| Uppdrag | Behörighet | Var arbetet görs |
|---|---|---|
| Klubbadministratör | `club.memberships.manage` | Medlemsansökningar, Förfrågningar om nya lag, Gör klubben officiell, Inställningar → Klubb (märke, färger), Ledare och roller, Domartillsättning (alltid) |
| Kassör | `economy.read`, `.post`, `.approve`, `.manage`, `.reverse` | Ekonomi (femte knappen och sidomenyn) |
| Ordförande eller styrelse | `board.read`, `.manage`, `.approve` | Styrelse (femte knappen och sidomenyn) |
| Abonnemangsansvarig | `club.billing.manage` | Abonnemang |
| Redaktör | `publication.manage` | Nyhetsredaktion, Publika sidor |
| Domaransvarig | `club.referees.manage` | Domartillsättning i sidomenyn |
| Domarersättning | `club.referees.pay` | Domarersättning i sidomenyn |

### 6.1 Det personen ser idag *(enligt koden)*

- **Hem:** två räknare, **Kommande aktiviteter** och **Obesvarade kallelser**, plus nästa aktivitet. Det finns inget om klubbens ärenden.
- **Laget:** "Du är inte kopplad till något lag", med en knapp till Inställningar.
- **Kalender:** klubbens aktiviteter *(verifiera vad som visas i hela-klubben-kontext)*.
- **Inkorg:** Inkorg, och Klubbsajt för den som hanterar klubbsajtens meddelanden.
- **Femte knappen:** Ekonomi, Styrelse eller Inställningar.

### 6.2 Klubbadministratör – flöden att testa

- [ ] KA-01 Godkänna en medlemsansökan.
- [ ] KA-02 Godkänna en förfrågan om nytt lag.
- [ ] KA-03 Göra någon till ledare i ett lag med rätt behörigheter.
- [ ] KA-04 Ändra klubbmärke och färger.
- [ ] KA-05 Utse domaransvarig och domarersättning.
- [ ] KA-06 Få en överblick över klubbens lag och var något behöver göras.

### 6.3 Kassör – flöden att testa

- [ ] KS-01 Hitta Ekonomi från Hem.
- [ ] KS-02 Bokföra, godkänna och vända en post *(enligt Ekonomi-ytan)*.
- [ ] KS-03 Betala ut domarersättning: lista, export och utbetald.

### 6.4 Ordförande – flöden att testa

- [ ] OR-01 Hitta Styrelse och se ärenden och beslut.
- [ ] OR-02 Godkänna ett styrelsebeslut.
- [ ] OR-03 Skicka information till alla ledare eller hela klubben.
- [ ] OR-04 Få en överblick över klubbens läge (medlemmar, lag, aktivitet).

### 6.5 Domaransvarig – flöden att testa

- [ ] DA-01 Öppna Domartillsättning från sidomenyn och se det aktiva lagets matcher. Visa hela klubben.
- [ ] DA-02 Tillsätta, godkänna anmälningar och sätta regler per lag.
- [ ] DA-03 Godkänna rapporter och skicka kontrollfråga.

**Fynd (2026-10-20, Benjamin Jonsson, ordförande: board.read/manage, economy.read, club.messaging.manage):**

- KF-F1 Hem har bara räknarna "Kommande aktiviteter 102" och "Kallelser att svara på 0", plus nästa aktivitet med rå tidsstämpel ("2026-10-20 17:30:00.000"). Inget om styrelse, ekonomi eller klubbens lag. (Lucka 1 bekräftad.)
- KF-F2 Hem och Kalender säger emot varandra: Hem räknar 102 kommande och visar en träning i dag, men kalendern visar bara cupresan.
- KF-F3 Laget säger "Du är inte kopplad till något lag" med en knapp till Inställningar. (Lucka 2 bekräftad.)
- KF-F4 Menyn visar e-postadressen och "Klubbfunktionär", fast personen heter Benjamin Jonsson och är ordförande enligt Styrelse.
- KF-F5 Styrelse visar mandaten (ordförande, kassör, sekreterare, ledamot, revisor) med ISO-datum. Klubbtitlarna finns alltså som mandat (lucka 4 delvis fel). Ärenden och beslut (OR-01/02) finns inte.
- KF-F6 Ekonomi har rubriken "Economy" på engelska och uppmanar till att skapa en kassa utan någon knapp för det (personen har bara economy.read).
- KF-F7 Mottagarlistan i Nytt meddelande har rader utan namn (konton utan visningsnamn; listan läser bara kontots namn, inte personens namn i klubben) och "Ledare" säger inte vilket lag.
- KF-F8 Anslag till spelare, ledare, vårdnadshavare eller alla i klubben fungerar (OR-03).
- KF-F9 Kalendern tog runt tio sekunder att ladda i klubbkontexten.

**Byggt 2026-10-20 (kräver migration 20261114090000):**

- A. Hem för en klubbkontext utan lag: kort efter behörighet (Styrelse med väntande mandatändringar, Ekonomi med poster att attestera, Medlemsansökningar och Förfrågningar om nya lag för klubbadministratören, Domartillsättning, Skicka anslag), sedan Klubbens lag. Räknarna och den råa tidsstämpeln är borta (KF-F1, KF-F2).
- B. Laget utan lag visar Klubbens lag med medlemmar och nästa aktivitet. Ett lag öppnas som läsvy: bild, om laget, ledare och de fem närmaste aktiviteterna (vad, när, var; inte deltagare). Klubbadministratörens köer öppnas också härifrån (KF-F3).
- C. Menyn visar namnet i klubben och styrelsetiteln (KF-F4), Styrelse visar svenska datum (KF-F5), Ekonomi heter Ekonomi och säger att kassören skapar kassorna för den som bara får läsa (KF-F6), mottagarlistan visar personens namn i klubben och lagen (KF-F7).
- Kvar: kalenderns laddtid i klubbkontexten (KF-F9) och ärenden/beslut i Styrelse (OR-01/02).

---

## 7. Dubbla roller

- **Ledare som också är kassör eller ordförande:** ekonomi och styrelse styrs av behörigheter i den aktiva kontexten *(verifiera om behörigheten ligger på lagrollen eller kräver kontextbyte till klubben)*.
- **Spelare som också är föreningsdomare:** "Mina domaruppdrag" på Hem och domaruppdrag i kalendern, utan att byta kontext.
- **Ledare som också är domaransvarig:** Domartillsättning i sidomenyn gäller klubben för det aktiva laget.

- [x] DR-01 Ledare och kassör: hitta Ekonomi utan att leta. *Provat 2026-10-20 som Hugo Olofsson i P2012.*
- [x] DR-02 Klubbadmin som också är ledare: vad visas i lagkontexten och vad i klubbkontexten? *Provat 2026-10-20 som Hugo Olofsson (ledare P2012, kassör och klubbadmin).*
- [ ] DR-03 Föreningsdomare under 15: vårdnadshavaren svarar på förfrågan och ser ersättning.

**Fynd (2026-10-20):**

- DR-F1 Inget testkonto hade dubbla roller. Ett klubbuppdrag utan lag (kassör, ordförande, klubbadmin) blev en egen kontext, så en ledare som också är kassör måste byta till klubbkontexten för att se Ekonomi.
- *Byggt:* klubbuppdragets behörigheter följer med in i dina lagkontexter i samma klubb. Ekonomi och Styrelse syns i menyn och under Mer i laget (inte på lagets Hem, beslut 2026-10-20), klubbrollens möten visas på lagets Hem under Klubbens möten, assistenten rapporterar klubbrollens uppgifter (mandatändringar, poster att attestera, ansökningar) i alla kontexter, och menyn visar "Huvudtränare · Kassör". Klubbkontexten finns kvar för klubbens Hem och lag. Medlemsansökningar och lagförfrågningar för hela klubben ligger kvar i klubbkontexten.
- Testdata: Hugo Olofsson (+tranare, ledare i P2012) görs också till kassör med en SQL som produktägaren kör.
- DR-02 i laget: lagbytet erbjuder Skapa ytterligare lag (skapar direkt), Förfrågningar om nya lag och Gör klubben officiell; Inställningar har Klubb. I klubbkontexten: Hem med Ekonomi, Medlemsansökningar och Förfrågningar om nya lag, och Domartillsättning i menyn.
- DR-F2 Medlemsansökningar från klubbens Hem öppnade två ark ovanpå varandra (trupplistans egen länkhantering körde också i klubbkontexten) och arket saknade stängknapp, så man fastnade. *Åtgärdat:* bara klubbens Laget öppnar kön i klubbkontexten, och arket har en stängknapp.
- DR-F3 "Månad" bröts till "Måna d" i kalenderväljaren under Inställningar. *Åtgärdat.*
- DR-F4 Lagbytet visar klubbkontexten som "Hela klubben · Klubbfunktionär" utan uppdragen (Kassör, klubbadmin). *Ej åtgärdat.*


---

## 8. Luckor jag redan ser i koden (att bekräfta i testet)

1. **Hem för klubbfunktionärer är tomt.** Det visar bara räknarna Kommande aktiviteter och Obesvarade kallelser. Det saknas en översikt med klubbens ärenden: ansökningar, förfrågningar om lag, rapporter att godkänna, ekonomi att attestera och styrelseärenden.
2. **Laget-fliken säger "Du är inte kopplad till något lag"** för den som är ordförande eller kassör. Den borde visa klubbens lag, eller bytas mot något relevant.
3. **Ekonomi- och styrelsebehörigheter kan inte delas ut i appen.** De sätts idag bara i databasen (pilotmigreringar). Det finns ingen vy där administratören utser kassör eller ordförande.
4. **Klubbtitlar saknas.** Titlar som Kassör finns bara på lagnivå. Ordförande, sekreterare, kassör, ungdomsansvarig och domaransvarig som klubbtitlar finns inte.
5. **Klubbadmin är utspritt.** Det finns i kontextväljaren (förfrågningar om lag, gör officiell), snabbåtgärderna (medlemsansökningar), Inställningar → Klubb, sidomenyn (Abonnemang, Domartillsättning) och Publika sidor. Det finns ingen samlad "Klubb"-ingång.
6. **Kontextbyte för dubbla roller:** klubbuppdrag kan kräva byte till klubbkontexten *(verifiera)*.
7. **Ledarens uppmärksamhetspunkter finns bara i assistenten.** När assistentknappen är dold ser Hem lugnt ut, även när något behöver göras *(bedöm i testet)*.

---

## 9. Ordning för testet (förslag)

1. Gemensamt skal (avsnitt 2) med ledarkontot.
2. Ledare (avsnitt 5), eftersom den används mest.
3. Spelare (avsnitt 3) och vårdnadshavare (avsnitt 4).
4. Klubbmedlem utan lag (avsnitt 6), där de största luckorna finns.
5. Dubbla roller (avsnitt 7).
