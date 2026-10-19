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

**Fynd:**

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

**Fynd:**

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

**Fynd:**

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

**Fynd:**

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

**Fynd:**

---

## 7. Dubbla roller

- **Ledare som också är kassör eller ordförande:** ekonomi och styrelse styrs av behörigheter i den aktiva kontexten *(verifiera om behörigheten ligger på lagrollen eller kräver kontextbyte till klubben)*.
- **Spelare som också är föreningsdomare:** "Mina domaruppdrag" på Hem och domaruppdrag i kalendern, utan att byta kontext.
- **Ledare som också är domaransvarig:** Domartillsättning i sidomenyn gäller klubben för det aktiva laget.

- [ ] DR-01 Ledare och kassör: hitta Ekonomi utan att leta.
- [ ] DR-02 Klubbadmin som också är ledare: vad visas i lagkontexten och vad i klubbkontexten?
- [ ] DR-03 Föreningsdomare under 15: vårdnadshavaren svarar på förfrågan och ser ersättning.

**Fynd:**

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
