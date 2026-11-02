# Team Development Plan: ny utformning – plan

**Status: riktningen beslutad 2026-11-01. Steg 1–4 är driftsatta på webben 2026-11-02, och steg 5 är byggt lokalt.** Skissen som godkändes ligger i [docs/ux/tdp-skiss.html](../ux/tdp-skiss.html). Den öppnas i en webbläsare.

Produktägaren vill göra om TDP från grunden. Det mesta av dagens funktion behålls, men sidan ska bli snyggare och lättare att använda. Modulen kändes mindre färdig än resten av appen.

## Beslut

1. **TDP är lagets utvecklingssida och samlingspunkt för laget.** Sidan är till för ledare. Spelare och vårdnadshavare får informationen på andra ställen i appen.
2. **Grunden är säsongsplaneringen**, med perioder och faser som i dag.
3. **En period kan delas upp i block** med eget, mer konkret fokus, till exempel "v. 11–12: speluppbyggnad från målvakt".
4. **Blocket (eller perioden) är utgångspunkten när man förbereder en träning.** Ledaren kan alltid välja ett annat fokus. Sidan visar vilka pass som följde blocket, utan att det blir en anmärkning.
5. **Skador och belastning visas på sidan**, både för laget och för varje spelare, tillsammans med rekommendationer, till exempel för en spelare med hög belastning.
6. **Belastning räknas på närvaro och speltid.** Spelarens egen skattning efter passet är ett valfritt komplement.
7. **Sidan byggs i första hand för dator och skärm** och ska utnyttja bredden. Den ska fungera på telefon, men det är inte där den används först.
8. **Årskalendern öppnas i nästan helsida** från säsongens tidslinje. Den ersätter inte tidslinjen. Man zoomar år → månad → vecka → dag och ser både säsongsplanen och vad som händer: matcher, träningar, läger, cuper och möten.
9. **Ett block innehåller fokus, principer och egna kortsiktiga mål.** Blocket blir en liten plan för sig.
10. **Målen ligger i nivåer.** Säsongsmålen är de långsiktiga. Varje period kan ha egna kortsiktiga mål, och det kan varje block också. De kortsiktiga målen ersätter aldrig de långsiktiga, utan visas under dem.
11. **Perioder och block planeras direkt i tidslinjen** ("Planera säsongen"). Man drar ut dem på en veckolinjal, drar i kanterna för att ändra datum och klickar för att fylla i innehållet i en sidopanel.

12. **TDP fungerar både med och utan träningsmodulen.** Har laget träningsmodulen, utgår passplaneringen där från blocket. Har laget den inte, får förberedelserna på händelsesidan (event details) samma utgångspunkt: blockets fokus, principer och mål. Allt annat i TDP fungerar likadant, och kopplingen ska aldrig kräva träningsmodulen. Hämtningen `get_team_plan_suggestion` används redan av båda vägarna (`preparation_services.dart` och `training_services.dart`) och kan byggas ut med blocket.
13. **Delningen behålls.** Ledaren väljer vad spelare och vårdnadshavare ser på lagsidan, som i dag: vision, perioder, principer och mål. Delningen utökas till block och periodernas och blockens kortsiktiga mål. Sidan i sig förblir bara för ledare.
14. **Avstämningarna följer planens rytm.** När ett block tar slut ber assistenten ledaren stämma av blockets mål. Periodens mål stäms av när perioden tar slut och säsongsmålen när säsongen tar slut. Dagens intervall i dagar försvinner. Ledaren kan också stämma av ett mål när hen vill.
15. **Nyckeltalen hämtas i första hand från matcherna**, alltså det som registreras i matchläget: resultat, händelser och KPI-räknare. Ett värde kan också fyllas i eller rättas för hand i efterhand, till exempel för en match som inte registrerades eller ett nyckeltal som matchläget inte räknar.
16. **Spelidén får en egen vy, och den är valfri.** Där beskriver laget sina principer per spelfas, med text och gärna bilder eller länkar till Tacticsboard. Det ska gå väldigt snabbt att komma igång, med **färdiga mallar** att utgå från och justera, till exempel ett bollinnehavande lag, ett kontringslag, högt presspel eller en grund som följer SvFF:s spelfaser. Väljer laget att inte använda vyn, kommer principerna man väljer per block från en standardlista över spelfaserna. Mallarnas innehåll bör granskas av någon med sportmetodisk kunskap innan de släpps.
17. **Spelidén kan skapas med en guide.** Ledaren får frågor om hur laget vill spela i varje fas, till exempel "Vill ni bygga upp kort från målvakten eller spela långt?" eller "Pressar ni högt eller faller ni hem?". Utifrån svaren fylls spelidén i, och sedan kan ledaren justera den. Guiden kan byggas med regler, där svaren styr vilka mallprinciper som väljs, och kräver ingen AI. En AI-variant som formulerar texten har egna grindar (PAR-AI-01/02).
18. **Ett block kan ha övningsförslag ur biblioteket.** Förslagen kommer ur TeamZones och klubbens övningsbibliotek, inklusive tavlor från Tacticsboard, och matchar blockets principer. Ledaren kan också lägga till egna. När ett pass förbereds, i träningsmodulen eller på händelsesidan, visas förslagen och kan läggas in i passet med ett tryck. Det fyller den förberedda rutan "Tips för perioden" (`_trainingTipsFor` i `training_season.dart`).

## Byggordning (godkänd 2026-11-01)

1. **Datamodellen.** Block i perioderna, mål i nivåer (säsong, period, block), utökad delning och avstämning vid blockets och periodens slut. Det kräver en SQL-migrering som användaren kör själv. Befintliga planer ska följa med.
   *Byggd 2026-11-01. SQL:en är körd och loggad i `schema_migrations`, och tabellerna och funktionerna är kontrollerade med läsande frågor. Appkoden är inte driftsatt:*
   - `supabase/migrations/20270122090000_team_development_blocks.sql` med testet `supabase/tests/team_development_blocks.local.mjs`.
   - Dart-modeller och tjänster för block, blockmål, blockdelning, förslagets block och avstämning när något tar slut.
   - De tidigare signaturerna för mål och delning finns kvar som omslag.
   - Appen får inte driftsättas förrän SQL:en är körd, eftersom målsparning och delning nu skickar de nya fälten.
2. **Startsidan och planering i tidslinjen.** Startsidan har två kolumner för dator. Planera säsongen görs med drag i tidslinjen. Utan belastning och skador tills vidare.
   *Byggd lokalt 2026-11-01, inte driftsatt.*
   - Modulen har nu sektionerna **Översikt**, **Planera** och **Spelidé**. Flikarna Säsongen och Mål är borttagna.
   - **Översikt** (`team_development_home.dart`):
     - Rubrik med säsongsväljare och en knapp till planeringen.
     - Vänster kolumn: kortet Just nu med blocket, perioden, principerna och fokus, säsongen i en remsa samt blockets och periodens mål.
     - Höger kolumn: avstämningar, säsongsmål och daterade mål.
   - **Planera** (`team_development_planner.dart`, `team_development_timeline.dart`, `team_development_plan_panel.dart`):
     - Säsongsmålen överst.
     - Tidslinjen med veckolinjal och fält för perioder och block. Man drar för att skapa, i kanterna för att ändra datum och i mitten för att flytta.
     - Sidopanelen visar den period eller det block som är valt, med mål, och delningen när inget är valt.
     - Blockdialogen har namn, fokus och upp till åtta principer.
   - Aktivitetsraden (matcher och läger) och "Träningar i blocket" kommer med kopplingen till kalendern i steg 3–4.
3. **Kopplingen till förberedelserna.** Blocket blir utgångspunkt både i träningsmodulen och på händelsesidan, genom att `get_team_plan_suggestion` byggs ut.
   *Byggd lokalt 2026-11-01, inte driftsatt. Ingen ny SQL behövs, eftersom förslaget fick blocket redan i steg 1.*
   - Förslagsrutan (`team_development_suggestion.dart`, utbruten ur delningsfilen) används på händelsesidans förberedelser, i träningsmodulens pass och i matchplanen.
   - Rubriken visar blocket och perioden. Blockets fokus kommer först och periodens fokus under det.
   - Rutan visar därefter blockets principer, målen framåt och planens andra principer. Ett tryck tar över en princip eller ett mål som fokus.
   - Raden "Blocket är en utgångspunkt. Du kan alltid välja något annat." säger att ledaren kan välja ett annat fokus.
   - Händelsesidan visar nu förslaget redan innan något träningsfokus är valt. Tidigare doldes det tills fokus fanns.
   - Att visa vilka pass som följde blocket kommer med kalenderkopplingen i steg 4.
4. **Årskalendern** med zoom från år till månad, vecka och dag.
   *Byggd lokalt 2026-11-01, inte driftsatt. Ingen ny SQL behövs, eftersom aktiviteterna hämtas med kalenderns `listCalendar` för ledarens uppdrag i laget.*
   - **Var den öppnas:** årskalendern (`team_development_calendar.dart`, `team_development_calendar_days.dart`) öppnas från knappen Årskalender på säsongskortet i Översikt och vid tidslinjen i Planera. På dator ligger den i nästan helsida och på telefon i helskärm.
   - **År:** säsongens månader som kort. Dagarna har periodens färg och en prick för aktiviteter (röd för match). Varje kort summerar matcher, träningar och annat och visar månadens perioder.
   - **Månad:** ett kalenderrutnät där veckonumret har periodens färg och leder till veckan. Blocket står i dagrutan och aktiviteterna visas med tid. Ett tryck på dagen öppnar den.
   - **Vecka:** periodens och blockets fokus och principer överst och sedan sju kolumner med aktiviteterna.
   - **Dag:** aktiviteterna med en knapp Öppna och bredvid "Planen den här dagen". Öppna stänger modulen och går till händelsesidan, där förberedelsen görs.
   - **Navigering:** brödsmulor, pilar och I dag.
   - **Hovring i årsvyn:** när musen hålls över en dag med aktiviteter visas en lista med dem, och listan försvinner när musen flyttas. På telefon visas den med ett långt tryck.
   - **Datumräkning:** tidslinjen och kalendern räknar dagar som kalenderdagar. Förut räknades de som 24 timmar, vilket gav en dag fel efter sommartidens slut.
   - **Översikt:** kortet "Aktiviteter i blocket" (eller perioden) visar genomförda och kommande aktiviteter. Ett tryck öppnar dagen i kalendern.
   - **Inte byggt än:**
     - Om ett pass följde blocket kräver data från förberedelserna och är inte byggt.
     - Skador och belastning på dagen kommer med steg 8–9.
5. **Spelidén.** Vyn, mallarna och guiden.
   *Byggd lokalt 2026-11-02, inte driftsatt. Ingen ny SQL behövs, eftersom principerna sparas en och en med `save_team_development_principle`, som har ett tak på 40 principer per plan.*
   - **Var:** under Spelidé. Vyn med principer per skede och nyckeltal fanns redan.
   - **Kom igång:** när laget saknar principer visar vyn kortet "Kom igång med spelidén" (`team_development_model_start.dart`) med två vägar, Utgå från en mall och Svara på frågor. När principer finns nås samma vägar från en meny bredvid Ny princip.
   - **Mallar** (`team_development_templates.dart`):
     - Grund i alla spelfaser: en princip per skede.
     - Bollinnehav.
     - Omställningar.
     - Högt presspel.
   - **Guiden** ställer sju frågor, en per skede utom anfallsspel och försvar som delar en. Varje svar ger bestämda mallprinciper. Inga svar är obligatoriska, och ingen AI används.
   - **Urvalet:** både mallen och guiden visar förslagen per skede med kryssrutor. Principer som redan finns i spelidén visas som "Finns redan" och läggs inte in igen. Allt kan ändras efteråt.
   - **Utan spelidé:** blockdialogen visar grundlistan (mallen Grund i alla spelfaser) när planen saknar principer. De principer som väljs läggs in i planen när blocket sparas.
   - **Granskning:** mallarnas och guidens texter är ett utkast som behöver granskas av någon med sportmetodisk kunskap innan de släpps till fler lag. Texterna är på svenska även när appen visas på engelska, eftersom de blir lagets egna texter.
   - **Inte byggt än:** bilder och länkar till Tacticsboard på en princip. Det kräver nya fält i databasen.
6. **Nyckeltal från matcherna.**
7. **Övningsförslag ur biblioteket.**
8. **Belastning och rekommendationer**, när PAR-METHOD-01 är beslutad och speltid per spelare finns.
9. **Skador**, när PAR-METHOD-02 är beslutad.

IDP tas efter detta.

Planeringsvyn finns som skiss i [docs/ux/tdp-planering-skiss.html](../ux/tdp-planering-skiss.html).

## Sidans uppbyggnad (enligt skissen)

**Startsidan har två kolumner.**

- **Vänster kolumn, planen:**
  - *Just nu:* period, block, fokus och principer, och "Förbered nästa träning".
  - Säsongens tidslinje med perioder och block, med en knapp till årskalendern.
  - Periodens mål och nyckeltal.
  - Träningarna i blocket, både gjorda och kommande.
- **Höger kolumn, laget:**
  - *Behöver din uppmärksamhet:* skadade, hög belastning, mål som inte är avstämda, upprepad frånvaro.
  - Rekommendationer.
  - Spelarna, med belastningen de senaste 14 dagarna och status.

**Årskalendern:**

| Nivå | Visar |
|---|---|
| År | Tolv månadskort med dagarna färgade efter period, prickar för matcher och läger, och en summering per månad. |
| Månad | Kalenderrutnät med aktiviteterna i dagrutorna. Veckonumret har periodens färg. |
| Vecka | Sju kolumner med veckans period och block överst, och aktiviteterna med tid och fokus. |
| Dag | Aktiviteterna med fokus från blocket, närvaro eller kallelse, och knappar för att förbereda eller öppna. Bredvid visas "Laget den här dagen" med skadade och hög belastning, och blockets fokus. |

Det finns en brödsmulestig, pilar för att bläddra och en knapp för att hoppa till i dag.

## Grindar som påverkar bygget

- **Skador är hälsodata.** [PAR-METHOD-02](../specification/source/16_open_parameter_backlog.md) spärrar data om hälsa och sanktioner tills beslut finns om minimiålder, vad vårdnadshavare ser och hur en spelare friskförklaras. Det rör sig om särskilt känsliga uppgifter om minderåriga. Skadedelen kan planeras, men byggs först när besluten finns.
- **Belastningssignaler och rekommendationer.** Enligt PAR-METHOD-01 ska regler, tidsfönster och gränsvärden bestämmas. Fram till dess visar appen bara råa fakta och inga medicinska slutsatser. Rekommendationerna är regelbaserade. Generativ AI har egna grindar (PAR-AI-01/02).
- **Data som saknas:** egen skattning, och speltid summerad över säsongen. Speltid per match räknas fram i matchmodulens Efteranalys ur startelvan, bytena och röda kort, men sparas inte. I dag finns närvaro och matchhändelser. Matcher som inte registrerades live kan sedan 2026-11-02 fyllas i efteråt i Live.

## Ändrad modulgräns

Tidigare beslut (2026-10-07) lade lagets och spelarnas utveckling i träningsmodulen. Nu är **TDP navet för lagets utveckling**, och träningsmodulen hämtar sin utgångspunkt därifrån. Den individuella utvecklingsplanen (IDP) är ännu inte påbörjad. Den ska kopplas till TDP:s perioder och block, och hur det ska gå till återstår att bestämma.

## Öppna frågor

- Vem som granskar mallarna för spelidén innan de släpps. Fyra mallar finns som utkast (2026-11-02).
- Hur IDP kopplas in. Beslutat att ta det senare (2026-11-01).
- Om guidens frågor och regler (i `team_development_templates.dart`) behöver justeras efter granskningen.
