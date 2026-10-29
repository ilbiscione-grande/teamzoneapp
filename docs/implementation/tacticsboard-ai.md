# Tacticsboard: tavlor skapade av AI – plan

**Status: planerad, inte påbörjad. Produktägaren beslutade 2026-10-29 att dokumentera förslaget och bygga det vid ett senare tillfälle.**

Tränaren beskriver ett problem, till exempel *"vi bygger upp från inspark, ibland pressar deras nia högt, ibland nian och tian tillsammans – hur spelar vi oss ur det?"*, eller ber om en analys som *"hur spelar Como under Fàbregas?"*. AI:n skapar då ett projekt med tavlor, frames, effekter och förklarande texter. Tränaren granskar och justerar resultatet i editorn.

Arbetssättet är redan prövat för hand (2026-10-29). Projekten *Speluppbyggnad från inspark* och *Como under Fàbregas* togs fram från en beskrivning respektive från webbsökning:
1. ett kompakt manus skrevs (startpositioner och sedan steg),
2. kod byggde tavlorna från manuset,
3. tavlorna importerades och granskades frame för frame,
4. krockar mellan spelare rättades.

En inbyggd AI gör samma sak.

## Det som redan finns

- **Projektfil och import/export** (`webtools/lib/tactics/transfer.ts`): ett genererat projekt kan sparas som nytt projekt utan någon ny databasdel.
- **Effekterna** som AI:n behöver: Spår, Pil, Markera, Zooma, Puls, Lys upp, Poppa fram, Rita fram, Tona in.
- **Rörelsens inbromsning per frame och böjda vägar** (`pathControl`).
- **Dokumentmodellen** (`webtools/lib/tactics/model.ts`) och `normalizeDocument`, som gör ett inkommande dokument helt.

## Förslag på uppbyggnad

1. **Serverfunktion i webtools**, till exempel `app/api/tactics/ai/route.ts`.
   - Anropar Claude via Anthropics TypeScript-SDK (`@anthropic-ai/sdk`).
   - API-nyckeln är en hemlighet i App Hosting, på samma sätt som `SUPABASE_SECRET_KEY`. Den får aldrig ligga i webbläsaren.
   - Bara inloggade användare får anropa funktionen. Varje anrop loggas med användare, tokens och kostnad, så att kvoten kan räknas.
2. **Manusformat i stället för hela dokument.** AI:n svarar med ett kompakt manus, begränsat av *structured outputs* (JSON-schema):
   - startpositioner per spelare (`h1`–`h11`, `a1`–`a11`) i meter på planen,
   - steg med förflyttningar, böjda vägar, vem som har bollen, effekter per objekt, tid och inbromsning,
   - en text per frame och en beskrivning per tavla.

   Koden (`lib/tactics/spec.ts`) bygger sedan tavlorna. Logiken finns i byggskriptet `ops/tacticsboard_build_como.ts` från 2026-10-29 och flyttas in. Den importerbara filen det gav finns i `ops/Como_under_Fabregas.tacticsboard.json`. Manuset är ungefär en tiondel så stort som dokumentet och svårare att få fel.
3. **Systemprompt.** Den beskriver:
   - planens koordinater (105 × 68 m, anfallsriktning åt höger, y = 0 är vänster sidlinje i anfallsriktningen),
   - nycklarna för spelarna,
   - vad varje effekt betyder och när den passar,
   - de två projekten ovan som exempel.

   Prompten och exemplen ligger först i anropet och cachas (*prompt caching*), så de blir ungefär 90 % billigare efter första anropet.
4. **Automatisk granskning** innan resultatet visas. Den kontrollerar:
   - spelare som står ovanpå varandra,
   - en boll som saknar ägare,
   - koordinater utanför planen,
   - fel antal spelare per lag,
   - effekter på objekt som inte passar.

   Små fel rättas av koden. Större fel skickas tillbaka till AI:n i ett nytt försök, högst ett.
5. **Gränssnitt:** knappen *Skapa med AI*.
   - Ett textfält och ett val av utgångsläge: tom plan, nuvarande tavla (positionerna skickas exakt som data) eller en bild.
   - Förloppet strömmas.
   - Resultatet blir ett nytt projekt eller nya tavlor i det öppna projektet.

### Faser

| Fas | Innehåll |
|---|---|
| 1 | Serverfunktion, manusformat, systemprompt, automatisk granskning och *Skapa med AI* med text och nuvarande tavla. Resultatet blir ett nytt projekt. Kvot per användare med kostnadslogg (se *Kvot per användare*), och tränarnas rättelser sparas. Uppskattning: 1–2 arbetspass. |
| 2 | Bild som utgångsläge, följdinstruktioner (*"flytta sexan längre bak"*) och nya tavlor i ett befintligt projekt. |
| 3 | Webbsökning för analysfrågor och ett testset för att mäta kvaliteten när prompten ändras. |

## Kostnad

Kostnaden räknas per **token**, ungefär ¾ ord. Det som skickas till AI:n (indata) och det AI:n skriver (utdata, inklusive tänkandet) har olika pris. Priserna gällde i oktober 2026, i USD per miljon tokens:

| Modell | Indata | Indata från cache | Utdata |
|---|---|---|---|
| Claude Opus 5.5 (bäst) | 4,00 | 0,20 | 20,00 |
| Claude Sonnet 5.5 (halva priset) | 2,00 | 0,20 | 10,00 |

Att skriva till cachen kostar 1,25 gånger indatapriset. Cachen lever i cirka 5 minuter, så vid låg trafik betalas skrivningen ofta på nytt.

### En generering

Uppskattning för ett projekt som de två exemplen, med Opus 5.5:

| Del | Tokens | Kostnad (USD) |
|---|---|---|
| Systemprompt och exempel (från cache) | ~10 000 | 0,002 |
| Systemprompt och exempel (skrivs till cache) | ~10 000 | 0,05 |
| Tränarens beskrivning och utgångsläge | ~2 000 | 0,008 |
| Manuset AI:n skriver | ~4 000 | 0,08 |
| AI:ns tänkande | ~8 000 | 0,16 |
| Nytt försök efter granskningen (cirka var fjärde gång, snitt) | – | 0,06 |
| **Typiskt totalt** | | **~0,30** |

- **En enkel tavla** (lägre effort, mindre tänkande) kostar cirka **0,10–0,15 USD**.
- **Fyra tavlor med mycket tänkande** kostar cirka **0,55 USD**.
- **Med webbsökning** (fas 3) tillkommer sökningarna (cirka 10 USD per 1 000 sökningar) och sidornas text som indata. Räkna med **0,50–0,80 USD**.

### 15 genereringar per användare och månad

Räknat med 10,50 kr per USD. Anthropic fakturerar i USD, och moms hanteras som omvänd skattskyldighet för företag.

| | Opus 5.5 | Sonnet 5.5 |
|---|---|---|
| Typiskt (0,30 resp. 0,15 USD per generering) | 4,50 USD ≈ **47 kr** | 2,25 USD ≈ **24 kr** |
| Små tavlor | ≈ 19 kr | ≈ 10 kr |
| Stora projekt | ≈ 87 kr | ≈ 44 kr |

Det är det **högsta** en användare med 15 genereringar per månad kan kosta. De flesta använder inte hela kvoten.

| Användare som använder hela kvoten | Opus 5.5 / mån | Sonnet 5.5 / mån |
|---|---|---|
| 100 | 450 USD ≈ 4 700 kr | 225 USD ≈ 2 400 kr |
| 1 000 | 4 500 USD ≈ 47 000 kr | 2 250 USD ≈ 24 000 kr |

### Att hålla nere kostnaden

- **Sonnet 5.5 i stället för Opus 5.5** halverar kostnaden. Kvaliteten för just tavlor behöver provas med testsetet (fas 3) innan beslut.
- **Lägre effort** för enkla förfrågningar (en tavla) ger mindre tänkande och därmed lägre utdatakostnad.
- **Kvot per användare** och ett tak för hela tjänsten per månad i Anthropics konsol.
- **AI-generering i abonnemanget.** När webtools-apparna blir abonnemang kan AI-genereringen ingå i Tacticsboard-abonnemanget. Kostnaden per användare ovan är golvet för vad den delen behöver kosta.

## Kvot per användare

Användaren ser ett **antal skapanden per månad**, till exempel *"12 av 15 kvar"*. Det är lätt att förstå och att ta betalt för. Servern kontrollerar samtidigt **kostnaden i kronor**, eftersom ett skapande kan kosta från cirka 1 kr (en tavla) till cirka 6 kr (ett stort projekt).

1. **Spärr per användare och månad.** Spärren slår till på det som kommer först:
   - antalet, till exempel 15, eller
   - kostnaden, till exempel 60 kr.

   Kostnaden räknas ur de exakta tokens som varje svar från Claude innehåller. Den som gör 15 jättestora projekt stoppas av kronbeloppet. Alla andra märker aldrig av det.
2. **Tak per anrop:**
   - `max_tokens` sätter ett hårt tak för det AI:n skriver, inklusive tänkandet. Det ger ett tak på kostnaden per anrop, till exempel högst cirka 5 kr.
   - Indata begränsas: beskrivningen till några tusen tecken, och en bild i taget med begränsad storlek.
   - Högst ett nytt försök efter granskningen.
3. **Skydd mot missbruk:**
   - ett skapande i taget per användare,
   - högst ett visst antal per timme, till exempel 5.
4. **Tak för hela tjänsten:**
   - ett utgiftstak i Anthropics konsol som sista skyddsnät,
   - ett eget månadstak i appen med varning, till exempel ett mejl vid 80 %.

   Når tjänsten taket stängs knappen med ett vänligt meddelande i stället för att anropen börjar fallera.

**Uppbyggnad i databasen:**
- En tabell för AI-användning med användare, tid, modell, tokens (indata, cache, utdata), kostnad och status.
- En databasfunktion som **reserverar** ett skapande innan anropet. Den kontrollerar antal, kronor, pågående anrop och timgränsen i samma transaktion, så att två samtidiga klick inte kan smita förbi kvoten.
- När svaret kommer fylls den verkliga kostnaden i.
- Misslyckade eller avbrutna anrop räknas in i kostnaden men drar inte av från användarens antal. Ingen ska straffas för ett fel som inte var deras.
- Tabellen ger också underlaget för abonnemangspriset: snittkostnad per skapande och fördelningen mellan användare.

## Gränser för antal användare

Det finns **ingen gräns för hur många användare appen kan ha**. Anthropic begränsar organisationen, inte antalet användare:

- **Hastighet:** anrop per minut och tokens per minut, både indata och utdata.
- **Utgifter:** ett tak per månad.

Båda gränserna höjs automatiskt i nivåer (*usage tiers*) ju mer krediter organisationen har köpt. Över de högsta nivåerna avtalas de med Anthropic. De exakta siffrorna visas i Anthropics konsol under *Limits* och ska kontrolleras vid lansering.

**Räkneexempel:** 1 000 användare med 15 genereringar per månad blir 15 000 genereringar, ungefär 500 per dag. Även om 100 av dem görs under samma kvällstimme blir det cirka 2 per minut och ungefär 25 000 utdatatokens per minut. Det ryms i Anthropics vanliga nivåer.

Vid en träff mot hastighetsgränsen (svar 429) försöker SDK:n igen automatiskt. Gränssnittet ska då säga *"Många skapar just nu, försök igen om en stund"*.

## Egen fotbollsmodell?

En egen modell, tränad från grunden eller finjusterad på fotboll, lönar sig inte nu:

- **Kostnad:** att träna en modell från grunden kostar miljontals kronor. En finjustering kräver infrastruktur, drift och underhåll, och blir mycket dyrare än 24–47 kr per användare och månad.
- **Data:** det behövs tusentals bra exempel där en beskrivning hör ihop med färdiga tavlor. Det finns två.
- **Kunskapen finns redan:** de stora modellerna kan spelidéer, pressfällor, tredje man och falsk nia. Det svåra är exakta positioner och att undvika krockar, och det löser granskningen i koden bättre.
- **Utvecklingen går fort:** de allmänna modellerna blir bättre och billigare varje halvår.

Det som ger nästan samma effekt till en bråkdel av priset:

1. **Bra instruktioner och exempel** (se ovan).
2. **TeamZones bibliotek som exempelbank.** Liknande övningar och pass hämtas ur biblioteket och skickas med som exempel, till exempel vid frågan *"en rondo för 10–12 år"*. Det är en fördel som växer med biblioteket.
3. **Spara tränarnas rättelser** av AI-skapade tavlor redan från fas 1. De förbättrar instruktionerna direkt, och på sikt är det den data en finjustering skulle kräva.

Frågan kan bli aktuell igen vid tiotusentals aktiva användare, där AI-kostnaden är en stor del av intäkterna, vid egna data som positionsdata eller video (Video Analyzer), eller vid krav på att köra utan nätverk.

## Att besluta innan bygget

- Ett konto hos Anthropic (console.anthropic.com), en API-nyckel som hemlighet i App Hosting och ett utgiftstak i konsolen.
- Modell: Opus 5.5 eller Sonnet 5.5, efter prov med testsetet.
- Kvot per användare och månad (antal och kronbelopp), timgräns och tjänstens månadstak, samt om AI ska ingå i abonnemanget eller köpas till.
- Text i villkoren om att beskrivningar och bilder skickas till Anthropic för att skapa tavlorna. Spelarnamn är de enda personuppgifterna och kan utelämnas.
