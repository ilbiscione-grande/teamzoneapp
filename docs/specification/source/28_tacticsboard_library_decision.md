# Beslutspaket 13 – Tacticsboards bibliotek och kopplingen till appen

**Status: godkänt av produktägaren 2026-10-24. TBL-01–TBL-19 är beslutade.**

## Mål

Tacticsboard blir ursprunget för träningens innehåll: övningar, träningspass och sessioner skapas och förvaltas i Tacticsboard, och sparas i ett bibliotek. I TeamZone-appen kopplar ledaren sedan in övningar och pass från biblioteket i en träning. Appen får inget eget övningsbibliotek.

Bakgrund: produktägaren beslutade 2026-10-24 att biblioteket ska ha Tacticsboard som ursprung. Den som skapar en tavla ska kunna spara den i TeamZones gemensamma bibliotek, och det är upp till varje användare vad man använder därifrån. Inom klubben ska man kunna sätta upp ett lokalt bibliotek för klubbens lag.

Paketet bygger på beslutspaket 11 (MFD-04 bilagor, MFD-08 träningspasset med kopior och ursprung) och det som redan finns i Tacticsboard: projekt med tavlor som har stabila id:n (`core.tactics_projects`, typerna match, träning och utbildning), egna mallar (`core.tactics_templates`) och livelektioner. Träningsmodulens steg 1, passet med block, är byggt och används oförändrat.

## Ett bibliotek, olika synlighet

Ändrat av produktägaren 2026-10-25: biblioteket är ett och detsamma. Den som delar väljer vem som ser det, och klubben kan erbjuda sina lag en utvald lista.

| Del | Vem lägger till | Vem ser och använder | Exempel |
|---|---|---|---|
| Mitt bibliotek | Jag | Jag | Alla mina projekt, match, träning och utbildning, publicerade eller inte |
| Mina favoriter | Jag markerar | Jag | Övningar ur biblioteket som tillägg till mitt eget |
| Delat med hela communityn | Alla som har Tacticsboard | Alla som har Tacticsboard | Övningar som tränare delar med varandra, TeamZones startövningar |
| Delat bara med klubben | Klubbens ledare | Klubbens ledare | Klubbens spelidé i övningar, en gemensam uppvärmning |
| Klubbens lista | Den som förvaltar klubbens lista | Klubbens ledare | Ett urval ur hela biblioteket som klubben erbjuder sina lag, och det som delats bara med klubben |

## Vad som finns i biblioteket

- **Övning:** en tavla (med ramar om den är animerad) och uppgifter om övningen: namn, del av passet (uppvärmning, huvuddel, avslutning), minuter, antal spelare, ytans storlek, organisation, coachpunkter, skede i spelet (förbundets åtta skeden, som spelidén) och ålder eller nivå.
- **Pass:** övningar i ordning, fördelade på passets delar, med tema och mål. Det är samma form som träningspasset i appen.
- **Session:** en följd av tavlor för genomgång eller livelektion (Tacticsboards typ utbildning), till exempel spelidén för en period.

## Beslut

| Id | Beslut | Status |
|---|---|---|
| TBL-01 | Tacticsboard är ursprunget för övningar, pass och sessioner. Appen har inget eget övningsbibliotek, och Träningsmodulens planerade bibliotek (MFD-08, steg 2) ersätts av kopplingen till Tacticsboard. | Beslutad av produktägaren 2026-10-24 |
| TBL-02 | En övning är en tavla med uppgifterna ovan, ett pass är övningar i ordning och delar, en session är tavlor i följd. Uppgifterna fylls i när man sparar till biblioteket och kan ändras efteråt. | Beslutad |
| TBL-03 | Ett bibliotek. Alla som har Tacticsboard kan dela en egen övning, ett pass eller en session, och väljer då om det ska synas för hela communityn eller bara för en av ens klubbar. Var och en väljer själv vad man använder. (Ändrad 2026-10-25 från tre separata bibliotek.) | Beslutad av produktägaren 2026-10-24, ändrad 2026-10-25 |
| TBL-04 | Det som sparas i ett delat bibliotek är en låst version. Ändrar upphovspersonen sin tavla publiceras en ny version, och den som redan använt övningen behåller sin version tills hen väljer den nya. | Beslutad |
| TBL-05 | Allt som delas rensas från trupp och spelare (som mallarna idag). Upphovspersonens namn visas på det som delas i TeamZones bibliotek. Den som delar godkänner att andra får använda och kopiera innehållet. | Beslutad |
| TBL-06 | Upphovspersonen kan ta bort sitt eget ur TeamZones bibliotek. Den som redan lagt in det i ett pass behåller sin kopia. | Beslutad |
| TBL-07 | Innehåll i TeamZones bibliotek kan rapporteras, och TeamZones support kan dölja det (som annonserna i matchpoolen). | Beslutad |
| TBL-08 | Klubben erbjuder sina lag en kurerad lista, Klubbens lista: övningar, pass och sessioner utvalda ur hela biblioteket, och det som delats bara med klubben. Alla ledare i klubben kan dela med klubben och använda listan. Den som delat något kan sluta dela det. Vem som förvaltar listan (väljer ut och tar bort det som delats med klubben) avgörs i behörighetsöversynen (`docs/implementation/permissions-review.md`); tills dess gör de med `club.memberships.manage` det. (Ändrad 2026-10-25.) | Beslutad, ändrad 2026-10-25 |
| TBL-09 | I appens träningspass väljer ledaren "Från biblioteket" och söker i sitt eget bibliotek, i hela biblioteket och i klubbens lista. En övning läggs in som ett block med uppgifterna kopierade och en länk till den låsta versionen av tavlan. Ett helt pass kan läggas in i en träning på en gång. | Beslutad |
| TBL-10 | En kopia i ett pass skrivs aldrig över av biblioteket. Finns en nyare version visar appen det, och ledaren väljer om blocket ska uppdateras. | Beslutad |
| TBL-11 | Tavlan visas i appen som förhandsbild, och öppnas i Webtools visare med en kortlivad visningsnyckel. Spelarna ser tavlorna i ett publicerat pass, aldrig utkast. | Beslutad |
| TBL-12 | Biblioteket i Tacticsboard följer rättigheten `webtool.tacticsboard`, kopplingen i appen `module.training` och `webtool.tacticsboard_link` (BED-07). Under betan är de öppna. | Beslutad |
| TBL-13 | TeamZones startövningar (femton övningar från den gamla appen, med del, minuter, organisation och skede) läggs in i TeamZones bibliotek som TeamZones egna, utan tavla tills någon ritar dem. | Beslutad |
| TBL-14 | Ordningen i MFD-14 ändras: kopplingen till Tacticsboard kommer före IDP. Träningsmodulens utvärdering (steg 3) byggs oberoende av detta paket. | Beslutad |
| TBL-15 | Det som delas i TeamZones bibliotek visar alltid upphovspersonens namn; inget alias. | Beslutad av produktägaren 2026-10-24 |
| TBL-16 | En övning anges med både åldersklass (till exempel 7–9, 10–12, 13–15, 16+) och förbundets spelform (3 mot 3 till 11 mot 11), och kan filtreras på båda. | Beslutad av produktägaren 2026-10-24 |
| TBL-17 | Bara träningens innehåll (övningar, pass och sessioner) delas i klubbens och TeamZones bibliotek. Matchens tavlor, som matchplan och genomgång, är bundna till laget och stannar i mitt bibliotek och lagets projekt i Tacticsboard. | Beslutad av produktägaren 2026-10-24 |
| TBL-18 | Mitt bibliotek är bara det jag själv skapat, publicerat eller inte. Varje användare kan favoritmarkera övningar, pass och sessioner i biblioteket; favoriterna visas som tillägg till det egna biblioteket och kan användas som utgångspunkt för nya projekt. | Beslutad av produktägaren 2026-10-25 |
| TBL-19 | Mitt bibliotek är alla mina projekt i en lista, oavsett typ, och kan filtreras som TeamZones bibliotek (ord, typ, del av passet, skede, åldersklass och spelform). Det finns inget separat steg att spara i biblioteket: en tavla publiceras som övning, eller ett projekt som pass eller session, direkt från projektet till klubben eller hela communityn. En ikon visar på projektet och på tavlans flik om något är publicerat och för vem. | Beslutad av produktägaren 2026-10-25 |

## Ordning

1. Tacticsboard: uppgifterna för en övning och ett pass på tavlor, och "Spara i biblioteket" (mitt bibliotek).
2. TeamZones bibliotek: dela, låsta versioner, sök och filter (del, skede, ålder, antal spelare), rapportera, och startövningarna.
3. Dela bara med klubben, och klubbens lista med ett urval ur hela biblioteket.
4. Appen: "Från biblioteket" i träningspasset (mitt bibliotek, hela biblioteket och klubbens lista), övningar och hela pass som kopior med länk, och "ny version finns".
5. Visning i appen: förhandsbild och Webtools visare med visningsnyckel, för ledare och för spelarna i ett publicerat pass.

## Öppna frågor

Inga. Alias, ålder och nivå samt matchens tavlor är besvarade (TBL-15–TBL-17).

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-10-24 | Tacticsboard är ursprunget för biblioteket av övningar, pass och sessioner; övningar kopplas från biblioteket till appen. Alla som skapar en tavla kan spara den i TeamZones bibliotek, och klubben kan sätta upp ett lokalt bibliotek. | Produktägaren |
| 2026-10-24 | Förslaget skrivet; Träningsmodulens eget bibliotek (steg 2) pausat och ej byggt. | – |
| 2026-10-24 | De öppna frågorna besvarade: inget alias, både åldersklass och spelform, bara träningens innehåll delas (TBL-15–TBL-17). | Produktägaren |
| 2026-10-24 | Hela paketet godkänt, TBL-01–TBL-17. | Produktägaren |
| 2026-10-25 | Ett bibliotek i stället för tre: den som delar väljer hela communityn eller bara klubben, och klubben erbjuder sina lag en kurerad lista ur hela biblioteket (TBL-03, TBL-08 och TBL-09 ändrade). | Produktägaren |
| 2026-10-25 | Mitt bibliotek är bara egna tavlor; favoriter ur biblioteket som tillägg (TBL-18). | Produktägaren |
| 2026-10-25 | Mitt bibliotek är alla mina projekt med samma filter som biblioteket; publicering direkt från projektet, med ikon för vad som är publicerat (TBL-19). | Produktägaren |
