# TeamZone – fördjupad UI/UX-genomgång

Datum: 26 oktober 2026. Underlag: publicerad auditapp, aktuell kod och produktbeslut.
Rapportrevisionens kodbas: `2bbe1ae91c5d431107baec4e8471ff7368482acb`.
Senast publicerad appkod enligt releasekvittot: `2222bad43a153e9eb0fb2b1519e69b99bd526b89`.

## Förtydligad produktinriktning efter genomgången

Produktägaren har förtydligat att modulerna avsiktligt ska bryta starkt mot
grundappen. Det önskade uttrycket är ett eget planeringsprogram, med
Illustrator, Pixlr och Canva som referenser för arbetsmiljön. Referenserna
avser programmets struktur och känsla; TeamZones uppgift är planering.

Detta ersätter rapportens ursprungliga rekommendation om samma navigationsram
för grundapp och moduler. Miljöbytet är önskat. UX-02 gäller fortsättningsvis
hur en begriplig programmiljö utformas, med tydlig kontext och återgång.
UX-03 om stabila adresser och återställd arbetsposition kvarstår.

En guidad dialog ska också kunna startas, exempelvis för att skapa ett
träningspass. Detta är en önskad förmåga. Teknik, eventuell AI-användning,
frågor och exakt flöde är ännu inte beslutade.

Produktägaren har även preciserat assistentens visning: på bred desktop
är den alltid öppen; på tablet och mobil öppnas den på begäran. Exakt
brytpunkt för bred desktop är inte beslutad. Den ska ge tillräcklig plats
åt huvudinnehållet och får inte återinföra den observerade layoutkollapsen.

Grundappens UX-01–UX-05 gås igenom tillsammans, en punkt i taget.
Modulernas programmiljö behöver en egen gemensam målbild före implementation.

## Bedömning

**TeamZone behöver en sammanhållen arbetsstruktur och bättre prioritering av användarens uppgifter.** Funktionerna presenteras i flera delvis överlappande skal. Användaren behöver förstå var en funktion byggts för att hitta rätt, och samma aktivitet får olika presentation beroende på ingång.

Det finns dessutom ett konkret responsivitetsfel: vid 1024 pixlars fönsterbredd lämnar sidomenyn och assistenten bara 384 pixlar till huvudytan. Hem väljer ändå två kolumner. Ord och datum bryts då ned till några tecken per rad. Detta bör rättas före en större visuell omarbetning.

Min rekommendation är att stabilisera ett centralt flöde – **dagens aktivitet → förbereda → genomföra → följa upp** – och använda det som referens för resten av appen. Behåll funktionerna och deras behörigheter, men ge dem färre, tydligare hemvister och gemensamma gränssnittsmönster.

### De fem viktigaste åtgärderna

1. **Rätta layout utifrån tillgänglig innehållsbredd.** Navigation och assistent får anpassa sig efter arbetsytans behov.
2. **Ge varje aktivitet och plan en kanonisk sida/adress.** Samma träning ska öppna samma arbetsyta från Hem, Kalender och Arbetsytor.
3. **Utforma modulerna som egna planeringsprogram.** Behåll det starka miljöbytet och gör arbetsytan, verktygen, panelerna och återgången begripliga.
4. **Skilj vardagsarbete, administration och personliga val.** Mer, trupphantering och kontextbyte ska få varsin tydlig uppgift.
5. **Inför gemensamma mönster för spara, status, synlighet och nästa handling.** Långa formulär och stora informationskort behöver delas efter arbetsmoment.

Detta är en UX-bedömning och ett förslag till förbättringsarbete. Inga appfunktioner har ändrats eller publicerats under genomgången.

## Metod och avgränsning

Genomgången gjordes läsande i den befintliga sessionen för Hugo Olofsson, Demoklubben IF/P2012. Menyn visar både tränar- och klubbfunktionärsrelaterade möjligheter. Språket lämnades på English. Svenska aktivitetstitlar, namn, övningar och anteckningar har behandlats som användarinnehåll.

Visuellt granskade webbläsarvyer: **390 × 844**, **768 × 1024**, **1024 × 768** och **1280 × 900**. Mellanbredderna användes särskilt för att kontrollera övergången mellan navigationstyper. Slutligt färdigritat innehåll användes för fynd; tillfälliga laddningsbilder räknades inte som fel.

Underlaget omfattar:

| Område | Underlag i denna granskning |
|---|---|
| Navigation, Mer, Arbetsytor | Ny manuell granskning på mobilbredd och dator samt kod |
| Hem och assistent | Ny manuell granskning vid flera bredder samt kod |
| Kalender och aktivitet | Ny manuell granskning av månadsvy, Info och Förberedelser |
| Träning | Ny manuell granskning av lista, publicerat pass och övergång från aktivitet |
| TDP | Ny manuell granskning av översikt och Spelidé på dator |
| Laget/Trupp | Ny manuell granskning av översikt, lista och Hantera-menyn |
| Inkorg | Ny manuell granskning av lista och kontaktytan Klubbwebb |
| Inställningar och kontextbyte | Ny manuell granskning av Personligt, Lag, Klubb, Publika sidor och kontextväljaren |
| Match | Kod och tidigare manuellt omprov samma dag av matchplan, navigation och mobilbredd; inget nytt genomförande av Live eller uppställning här |
| Spelare, vårdnadshavare, andra klubbroller | Rollflöden och kod; inte nya inloggningar eller fullständig manuell rollacceptans |
| Publik sajt och Webtools | Berörda gränser/ingångar i appen och produktbeslut; inte en fullständig ny granskning av sajterna |

Inga meddelanden öppnades för att läsas, inga inbjudningar besvarades och inga mål, planer, inställningar eller lagdata sparades. Befintliga AUDIT-poster från tidigare skrivprov användes endast som visningsdata. Deras innehåll är inte ett mått på verklig verksamhet. Viewporten återställdes och appen lämnades på Settings.

Detta är inte en fullständig tillgänglighetscertifiering, säkerhetsgranskning, prestandamätning eller användarstudie. Jag har inte mätt verkliga användares tidsåtgång, felprocent eller upplevelse. Effekter och prioriteringar nedan är professionella bedömningar som behöver valideras.

## Det som redan fungerar och bör bevaras

- Fem återkommande mobilflikar ger en användbar grund. En stor navigationsomläggning behöver inte börja med att byta alla namn eller platser.
- Kontexten klubb/lag visas och många åtgärder är behörighetsstyrda.
- Hem visar nästa/dagens aktivitet tydligt; det är en bra utgångspunkt för ett mer uppgiftsdrivet gränssnitt.
- Truppens lista har en begriplig sökrad och sekundärt filter, utan att alla filter visas samtidigt.
- Gemensamma förberedelser återanvänder information mellan aktivitet och modul. Problemet är presentation och handlingsväg; det är inte belägg för dubbla databaser.
- Utkast, publicering och synlighet är uttryckliga begrepp. De behöver göras lättare att förstå, inte döljas.
- Det finns ett gemensamt tema, typsnitt, spacing-konstanter, asynkrona tillstånd och grundläggande touchmått. Bygg vidare på detta.
- De senast rättade språk- och flikproblemen ska inte återinföras i en omdesign.

## Fynd och prioritering

**P1** betyder först: påtaglig påverkan på centrala arbetsflöden. **P2** betyder därefter: återkommande friktion och otydlighet. **P3** är förfining. Detta är en arbetsprioritering, inte en teknisk incidentklassning.

**V** = visuellt/interaktivt observerat i denna genomgång. **K** = stöd i kod. **B** = bedömning/hypotes som behöver användartestas.

| ID | Prioritet | Fynd | Belägg | Rekommenderat resultat |
|---|---|---|---|---|
| UX-01 | P1 | Hem kollapsar till mycket smala kolumner vid mellanbredder | V + K | Layout styrs av innehållsytans faktiska bredd |
| UX-02 | P1 | Modulernas separata skal behöver utvecklas till en tydlig programmiljö | V + K; målbild förtydligad av produktägaren | Egen arbetsmiljö med verktyg, arbetsyta, paneler och tydlig återgång |
| UX-03 | P1 | Öppet träningspass saknar egen webbadress; omladdning tappar arbetspositionen | V + K | Plan och delvy går att länka till och återställa |
| UX-04 | P1 | Träningens läsning, redigering, genomförande och publicering blandas | V + K + B | Tydligt arbetsläge och kort översikt före detaljer |
| UX-05 | P1 | Assistenten konkurrerar om plats och uppmärksamhet | V + K | Uppgiftsytan får företräde; assistenten kan fällas undan |
| UX-06 | P2 | Mer har många likvärdiga val utan uppgiftsgruppering | V + K | Lagets arbete, klubbadministration och mitt konto separeras |
| UX-07 | P2 | Kontextväljaren är också en administrationsmeny | V | Byte av lag/roll blir kort och förutsägbart |
| UX-08 | P2 | Truppens plusperson-knapp öppnar en lång blandad Hantera-meny | V + K | Lägg till person blir direkt handling; administration får egen plats |
| UX-09 | P2 | Spara och synlighet har flera räckvidder på samma arbetsyta | V + K + B | Användaren förstår vad som sparas och vem som ser varje del |
| UX-10 | P2 | Samma eller närliggande begrepp har flera hemvister | V + K | Ordlista och en huvudplats per uppgift |
| UX-11 | P2 | Status och uppmärksamhet visas med många färger, nollor och räknare | V + B | Bara relevanta statusar framhävs; varje räknare förklaras |
| UX-12 | P2 | TDP:s startvy beskriver modell/status mer än nästa utvecklingshandling | V + B | Aktuell period, fokus och nästa avstämning kommer först |
| UX-13 | P2 | Tekniska och språkligt blandade systemtexter återstår | V + K | Uppgiftsnära språk och fullständig språkgranskning av fler tillstånd |
| UX-14 | P3 | Kalenderns månadsvy har svag orientering och få synliga förklaringar | V + B | Veckodagar och tydligare vy-/filteråterkoppling |

### UX-01 – responsivitet behöver utgå från arbetsytan

Vid 1280 pixlar tar sidomenyn 280 och assistenten minst 360 pixlar. Huvudytan blir omkring 640 pixlar. Vid 1024 blir den **384 pixlar**, före intern padding. Hem visar ändå Kommande och Planering/administration bredvid varandra.

I den färdigritade 1024-vyn bryts exempelvis aktivitetstitel, datum och snabbåtgärder över många mycket korta rader. Vid 768 blir layouten också onödigt trång, även utan assistentpanelen.

Koden i `_LeaderHomeContentState.build` använder hela fönstrets `MediaQuery` för tvåkolumnsläget. Skalets sidomeny och assistent har separata breddregler. Kombinationen är ett verifierat problem, inte bara en visuell preferens.

**Åtgärd:** låt komponenter välja layout från sina faktiska constraints. Hem ska få en kolumn när dess egen yta är smal. Gör sidonavigation kompakt/fällbar när det behövs. Assistenten ska enligt produktägarens precisering alltid vara öppen på bred desktop och öppnas på begäran på tablet och mobil. Välj gränsen för bred desktop tillsammans med kravet på en läsbar huvudyta. Ändra inte bara gränsen från 1024 till ett annat godtyckligt fönstermått.

**Godkännande:** ingen vanlig aktivitetstitel bryts teckenvis i de provade bredderna; kolumner byter layout utifrån faktisk arbetsbredd; ändring av panelernas läge bevarar innehåll och navigationsposition. Prova också textförstoring och tangentbord separat.

![Verifierat problem vid 1024 pixlar](../../.tmp-ux-review/16-home-1024-critical.png)

### UX-02 och UX-03 – flera skal och ofullständig navigationsadress

Från grundappen öppnas Träning som en egen helskärmsyta med orange färg och stängkryss. Sidomeny, huvudnavigation och assistent försvinner. TDP gör motsvarande med lila färg och egen sidonavigation. Produktkoden beskriver uttryckligen modulerna som egna appar och öppnar dem med `rootNavigator` och `MaterialPageRoute`.

Det är en avsiktlig implementation. Produktägaren har efter rapporten bekräftat att det starka miljöbytet ska behållas. Förbättringen ska därför göra modulen till ett tydligt planeringsprogram, med en arbetsyta och konsekventa verktygs- och panelområden. Förslaget att behålla grundappens navigationsram inne i modulerna är ersatt.

Ett öppet träningspass låg kvar på `/workspaces` i adressfältet. Jag laddade om sidan och hamnade på Arbetsytors startsida. Jag har inte observerat dataförlust; det verifierade felet är förlorad arbetsposition och avsaknad av en direkt adress till passet.

**Åtgärd:** ge aktivitet, pass, matchplan och delvy stabila routes. Modellera aktiviteter via samma kanoniska identitet och låt moduler vara fördjupningar av arbetet. Behåll modulrättigheter och olika grund-/modulnivåer. Planera kompatibilitet med befintliga länkar och systemets bakåthantering.

**Godkännande:** Hem, Kalender och Arbetsytor öppnar samma aktivitet/plan; omladdning och delad internlänk återställer objekt och relevant flik; tillbaka återgår till den plats man kom från. Bekräfta även detta i native-appen innan slutgodkännande.

### UX-04 – långa planer behöver ett läs-/genomförandeläge

Ett pass med fyra övningar visar fokusfält, mål, fulla övningsbeskrivningar, progressioner och coaching points, följt av anteckningar, material, uppgifter, filer och synlighet. På aktivitetens Förberedelser visas återigen den långa publicerade planen. Knappen för att redigera i Träningsmodulen kommer efter planinnehållet.

Det gör det kostsamt att hitta något så vardagligt som material eller nästa övning. Det blir också oklart om sidan främst är en planeringseditor eller ett stöd ute på planen.

**Åtgärd:** visa först passöversikt med tider, övningsordning, status och tydlig handling. Låt övningskort vara kompakta med detaljer på begäran. Lägg redigera-handlingen före den långa läsprojektionen. Skilj planering från ett enkelt genomförandeläge, med material och nästa övning nära till hands. Undvik att bygga en tredje kopia av passets fakta.

**Godkännande:** nästa övning och material går att hitta utan att rulla igenom alla övningsbeskrivningar. En ledare förstår skillnaden mellan Visa pass och Redigera pass. Ett publicerat pass kan granskas utan att allt ser ut som aktiva formulärfält.

### UX-05 – assistenten ska stödja, inte bli en parallell huvudapp

På mobil ligger assistentens foto och räknare ovanpå sidans nedre högra del. Sidor med egen flytande knapp måste flytta sin knapp ovanför den. Koden innehåller en särskild placering för detta. På dator får assistenten en permanent panel på minst 360 pixlar, även när man läser eller administrerar något annat.

I Inkorg syns samtidigt uppmärksamhetskort, notisräknare och assistentuppgifter. De räknar olika saker; detta är inte bevis för felaktiga antal. Men betydelsen och prioriteringen är svåra att överblicka.

**Åtgärd:** alltid öppen assistent på bred desktop och öppning på begäran på tablet/mobil enligt produktägarens precisering; en konsekvent mobilplacering som inte skymmer slutrader eller primära knappar; högst ett tydligt relevant nästa steg direkt i den aktuella aktiviteten. Behåll en separat fullständig uppgiftslista och möjligheten att skjuta upp/arkivera. Märk tydligt skillnaden mellan olästa meddelanden, notiser och åtgärder.

### UX-06 till UX-08 – skilj uppgift från administration

Mer-menyn hade tio likvärdiga rutor i den granskade kontexten: bland annat Arbetsytor, Lagstatistik, Ekonomi, Domartillsättning, Turneringar, Redaktion, Publika sidor, Vår publika sida, Min profil och Inställningar.

Kontextväljaren visade det aktiva laget, ett alternativ för hela klubben och därefter skapa lag, skapa klubb, lagförfrågningar, officiell verifiering och hitta klubb/lag. Truppens person-plusikon öppnade en lång meny där Lägg till person låg efter flera administrativa och mer sällsynta alternativ. Klubbmärke, klubbfärger och verifiering förekommer även där, trots egna inställningsytor.

**Åtgärd:**

- Behåll de stabila mobilflikarna. Gruppera Mer i **Lagets arbete**, **Klubbadministration** och **Mitt konto** med rollstyrt innehåll.
- Låt kontextväljaren i första hand byta kontext. Lägg skapa/ansöka/verifiera under en separat hanteringsingång.
- Ge truppen en tydlig Lägg till person-handling. Samla mindre vanliga personåtgärder i en namngiven truppadministration. Klubbens utseende och verifiering får en huvudplats.
- Låt genvägar gå till dessa huvudplatser i stället för att skapa ytterligare egna menyer eller formulär.

Målet är inte att ta bort funktioner. Målet är att frekventa handlingar ska kunna hittas utan att man går igenom hela administrationsmodellen.

### UX-09 – en tydlig kontraktstext för sparande och mottagare

Träningspassets fokus, övningar och publicering sparas med passets Save-knapp. Gemensamma anteckningar, förberedelseuppgifter och andra delar har egna kommandon. Matchplanen har publicering för planen och synlighet per sektion. Filer har egna mottagarregler. TDP har separata delningsval.

Det är legitima skillnader i data och behörighet. En ensam global formulärmetafor riskerar däremot att ge intrycket att en Save-knapp styr allt på sidan.

**Åtgärd:** använd konsekventa statusrader: Utkast/Sparat/Opublicerade ändringar och en tydlig mottagarsammanfattning. Ange vad en spara/publicera-handling omfattar. En plan och dess filer får inte låtsas ha samma synlighet om de har olika regler. Lägg till Förhandsvisa spelarvy där det är relevant, utan att ändra säkerhetsmodellen.

**Godkännande:** en provperson kan beskriva vad som sparas, vilka som ser planen och vilka bilagor som är delade innan hen trycker. Osparade ändringar och fel visas konsekvent. Behörighets- och samtyckesregler bevaras.

### UX-10 till UX-14 – begrepp, status och nästa handling

**Begrepp:** Utveckling och IDP finns samtidigt i Arbetsytor, där IDP är avaktiverad. Lagstatistik har flera ingångar. Publika sidor, Vår publika sida, Redaktion och Klubbwebb förekommer på olika ställen. Klubbwebb i Inkorg visar i själva verket kontaktförfrågningar från klubb-/lagsajten, vilket passar som kommunikation men behöver ett tydligare namn, exempelvis Webbförfrågningar. Bestäm en ordlista för tema, fokus, mål, plan, aktivitet och pass.

**Status:** På ett träningsevent utan krav på kallelse visas ändå fem nollräknare för kallelsestatus. På mobil syns de som färgade cirklar utan skrivna kategorier. Visa i stället deltagar-/närvarostatus som är relevant för eventets arbetssätt. Använd färg tillsammans med text och ikon, inte som ensam förklaring.

**TDP:** Den granskade startvyn domineras av säsongens tidsförlopp, beskedet att perioderna har slutat och mål/tomlägen. Det är korrekt visningsdata, men säger lite om vad ledaren bör göra härnäst. Visa aktuell period/fokus, nästa avstämning och kopplade aktiviteter. Behåll historik och avbrutna mål i en mindre framträdande vy. Spelidé-sidans många tomma områden kan introduceras stegvis med en första tydlig handling, utan att tvinga ledaren att fylla alla delar.

**Språk:** Aktivitetsinfo innehöll svenska systemtexter om att kallelse inte behövs och formuleringen 15 min före start. Klubbwebb och integrationsraden i Inställningar hade också svenska systemetiketter trots English. Detta är nya observationer; de tidigare rättningarna av Home och analysfliken är fortfarande utförda. Truppadministration innehåller dessutom produkttext om scopeade serverkommandon. Den sortens implementationsförklaring hjälper inte användaren att fatta sitt beslut.

**Kalender:** Månadsvyn saknade synliga veckodagsrubriker i den provade mobilvyn. Ikoner för datum/vy/filter har tillgänglighetsnamn, men behöver tydligare visuell återkoppling om aktuell vy och aktiva filter. Detta är en förbättringsbedömning; inget datumfel verifierades här.

## Vad dokumentationen säger – och hur det stämmer

| Avsikt | Nuläge | Slutsats |
|---|---|---|
| Grundappen ska göra vardagsarbetet enkelt; fördjupning ges genom moduler | Vardag och fördjupning finns, men kräver ofta byte av skal och begrepp | Modulgränserna behöver inte vara navigationsbrott |
| Eventytan ska visa en kort projektion från modulen | Träningseventet visar den fulla övningstexten före redigeringslänken | Återgå till en verklig sammanfattning med tydlig öppna/redigera-handling |
| En källa för aktivitet, plan, uppställning och historik | Återanvändning finns, men presentationerna och vägarna varierar | Samordna gränssnittet kring objekten; skapa inte parallella dataägare |
| Svenska och engelska ska vara fullständiga | Ytterligare systemtexter på svenska observerades | Rätta språkmönster och granska fler vyer/tillstånd, inte bara fler ord |
| Stabil roll- och kontextanpassning | Behörighetsstyrning finns; flera roller syns samtidigt i menymodellen | Förtydliga arbetsroll och åtgärdens räckvidd; ändra inte åtkomstregler som UX-genväg |

Produktvisionens ursprungliga fem ytor är historik; senare beslut om Mer och statistik under Laget gäller. Rapporten föreslår inte att äldre navigation ska återinföras. En samordning av modulskal behöver förankras som ett nytt UX-beslut, med bevarad modul-/entitlementmodell.

## Föreslagen målstruktur

### Ett sammanhang, flera arbetsdjup

| Plats | Huvuduppgift | Ska inte bli |
|---|---|---|
| Hem | Vad händer nu, vad behöver jag göra, nästa relevanta handling | En katalog över hela produkten |
| Kalender | Hitta, skapa och öppna aktiviteter | En alternativ ägare till planer och mål |
| Aktivitet | Info, deltagare, plan och uppföljning för samma aktivitet | En lång kopia av alla modulens formulär |
| Laget | Människor, relationer, laginformation och lagstatistik | All klubbadministration |
| Arbetsytor | Översikter över match, träning och lagutveckling | En serie separata appar med olika navigationsregler |
| Inkorg | Konversationer, anslag och inkommande förfrågningar | En allmän plats för publiceringsinställningar |
| Klubbadministration | Ekonomi, publicering, verifiering och andra klubbuppdrag | En blandning i varje lagmeny |
| Mitt konto | Profil, egna kopplingar, språk, utseende och notispreferenser | Verksamhetsadministration |

Detta är en ansvarsfördelning, inte åtta nya huvudflikar. Behåll mobilens fem fasta ingångar och använd grupperade sekundärytor. Alla alternativa ingångar ska öppna samma kanoniska vy.

### Exempel: bättre träningsflöde

1. Hem visar dagens träning och en relevant ledarhandling: Förbered pass eller Öppna pass.
2. Samma aktivitet öppnas från Kalender och Arbetsytor, med samma titel, datum, lag och adress.
3. Översikten visar tider, fokus, planstatus, deltagarläge och nästa handling. Fulla övningsbeskrivningar är sekundära.
4. Planering/redigering har ett tydligt sparområde och mottagarsammanfattning.
5. Genomförande prioriterar övningsordning, tid och material. Ändring av planinnehåll är en uttrycklig handling.
6. Uppföljning visar de mål och utvärderingar som hör till passet. Historik bevaras.

Förslagets klickmål är högst två tydliga val från Hem till ett relevant pass eller dess planering. Det är ett föreslaget acceptanskriterium, inte ett uppmätt förbättringsresultat. Nuvarande väg via Mer → Arbetsytor → Träning → Öppna pass innebär fyra val. Vägen via aktiviteten finns redan men redigeringslänken är begravd efter text.

## Genomförande i prioriterad ordning

Storlek anger relativ omfattning, inte kalenderlöfte. S = avgränsat, M = flera komponenter, L = flera sammanhängande flöden.

| Paket | Prioritet/storlek | Leverans | Kontroll innan nästa steg |
|---|---|---|---|
| A. Arbetsbredd | P1 / M | Constraintsbaserad Hem-layout, panelpolicy och kompakt navigation | Läsbart vid 390, 768, 1024 och 1280; även mellan brytpunkterna |
| B. En aktivitet, en väg | P1 / L | Kanoniska routes och samma aktivitetsingång från Hem/Kalender/Arbetsytor | Omladdning, direktlänk, tillbaka och återgång till lista fungerar |
| C. Träning som referensflöde | P1 / M–L | Kort översikt, tydlig redigering/genomförande och rätt placerade handlingar | Verkliga ledare hittar nästa övning, material och redigering utan hjälp |
| D. Samordnade menyer | P2 / M | Grupperad Mer, ren kontextväljare och uppdelad trupp-/klubbadministration | Vanliga uppgifter hittas; sällan använda funktioner är fortfarande åtkomliga |
| E. Gemensamma komponentkontrakt | P2 / M | Status, spara, synlighet, tomlägen, fel, formulär och språk | Samma beteende i Träning, Match och TDP |
| F. Sprid och validera | P2 / L | Använd referensmönstret i Match/TDP och rollanpassade ytor | Spelare, vårdnadshavare och klubbroller provas med rätt konton |

**Rekommenderad start:** Paket A, följt av en begränsad prototyp av Paket B/C för dagens träning. Vänta med bred utrullning till övriga moduler tills det flödet är begripligt och validerat. Meny- och ordlistearbetet kan förberedas parallellt, men bör inte införa ytterligare navigationslager.

## Design- och utvecklingsprinciper som hindrar ny spretighet

- Varje funktion får en namngiven huvudplats och ett kanoniskt objekt. Genvägar är länkar, inte nya implementationer av samma arbetsyta.
- Definiera ett skal för grundappen och en gemensam programmiljö för modulerna, med tydlig övergång, kontext och återgång.
- Låt modulerna bryta tydligt mot grundappen. Samordna verktyg, paneler och planeringsinteraktioner mellan modulerna så att kunskap från ett planeringsprogram går att återanvända i nästa.
- Skilj läsläge och redigering när stora planobjekt annars blir överväldigande.
- Ange vad som sparas nu, vad som kräver Save och vem som ser respektive del.
- Pröva en ny funktion i sitt verkliga sammanhang: vänsternavigation, assistent, långa namn, svenska/engelska och tomma/fyllda tillstånd.
- Utöka de gemensamma UI-komponenterna stegvis när referensflödet är fastlagt. Stora ytfiler är en underhållssignal; antal rader bevisar inte dålig UX och motiverar inte en total omskrivning.
- Inför ett kort produktbeslut för nya ingångar: vilken uppgift stödjs, vilken roll, var hör den hemma och vilken befintlig väg ersätter eller använder den?

## Hur förbättringen bör mätas

Gör först en verklig baslinje med ledare och därefter andra roller. Rapporten innehåller inga påhittade användarresultat.

| Uppgift | Mätning | Föreslaget godkännande |
|---|---|---|
| Hitta och förbered dagens träning | Självständig uppgiftsframgång, felval och tid | Flertalet klarar utan vägledning; beslutad tröskel efter baslinjen |
| Hitta material och nästa övning | Tid, antal onödiga vybyten/rullningar | Tydlig förbättring mot samma baslinje |
| Förstå vad spelare ser | Användaren beskriver mottagare innan publicering | Rätt svar för både plan och bilagor i alla kritiska prov |
| Återvänd efter avbrott | Omladdning, direktlänk, tillbaka och native-resume | Rätt objekt och relevant delvy återställs |
| Lägg till en person | Hitta handlingen utan administrativ vägledning | Direkt, begriplig primär handling |
| Läs Hem på olika bredder | Visuell kontroll med verkligt innehåll och förstoring | Inga teckenvisa radbrytningar eller skymda primärhandlingar |

En rimlig första studie är ett mindre antal riktiga ledare med varierande vana. Välj även en verklig vårdnadshavare/spelare för att undvika att ledarens förenkling gör deras vardag sämre. Fysisk telefon, skärmtangentbord, touch och skärmläsare måste provas innan slutlig tillgänglighets- och enhetsacceptans.

## Tekniska hållpunkter och källor

Kodpunkter som förklarar fynden:

- [product_shell.dart](../../lib/src/app/product_shell.dart): sidomenyns 280 pixlar, panelkompositionen, Mer och de dolda svepgenvägarna.
- [assistant_coach_entry.dart](../../lib/src/features/assistant_coach/assistant_coach_entry.dart): sidopanelens bredd är 25 procent, begränsad till 360–480 pixlar.
- [overview_surface.dart](../../lib/src/features/overview/overview_surface.dart), bland annat rad 1169 i granskad revision: Hem väljer bred layout från hela fönstrets bredd.
- [module_shell.dart](../../lib/src/features/workspaces/module_shell.dart), rad 35–37 och 216: moduler och undersidor öppnas ovanpå roten som imperativa routes.
- [product_route_contract.dart](../../lib/src/app/product_route_contract.dart): stabil aktivitetssida finns redan; modulernas individuella pass saknar motsvarande routemodell.
- [workspaces_surface.dart](../../lib/src/features/workspaces/workspaces_surface.dart): utveckling, statistik och modulöppnare.
- [training_session_page.dart](../../lib/src/features/training/training_session_page.dart): passets Save/publicering och blandningen av planeditor och förberedelser.
- [event_preparation.dart](../../lib/src/features/calendar/event_preparation.dart): självständiga sparkommandon för gemensamma förberedelser.
- [roster_surface.dart](../../lib/src/features/roster/roster_surface.dart): den samlade Hantera-menyn, inklusive texten om scopeade serverkommandon.

Produktunderlag:

- [Produktvision](../specification/source/00_product_vision_and_scope.md).
- [Modulgrunder](../specification/source/26_module_foundations_decision.md), särskilt kort projektion på eventytan och gemensamma kärnobjekt.
- [Historiska rollflöden](role_flows.md), lästa tillsammans med senare beslut.
- [Aktuellt leveransläge](../implementation/current_status.md).
- [Tidigare mobilbredd/sparprov](../evidence/mobile390_write_acceptance_2026-10-26.md) och [efterföljande rättningar](../evidence/mobile390_fixes_2026-10-26.md).

Extern vägledning, kontrollerad 26 oktober:

- Flutter skiljer mellan hela fönstrets mått och en widgets lokala utrymme; det stödjer rekommendationen att välja rätt mätpunkt för responsivitet. [Flutter: General approach to adaptive apps](https://docs.flutter.dev/ui/adaptive-responsive/general).
- Förutsägbar återkommande navigation är ett relevant tillgänglighetsmål. Rapporten gör ingen formell bedömning av efterlevnad. [W3C: Consistent Navigation](https://www.w3.org/WAI/WCAG22/Understanding/consistent-navigation.html).
- Reflow ger stöd för att kontrollera läsbarhet när tillgänglig yta förändras. De genomförda viewportproven ersätter inte ett fullständigt zoom-/WCAG-prov. [W3C: Reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html).

## Skärmbildsregister

Bilderna finns lokalt i `.tmp-ux-review/` och versionshanteras inte. De dokumenterar auditdata, inte ett komplett designförslag.

| Bild | Visar |
|---|---|
| 01-more-390.png | Tio likvärdiga menyval |
| 02-workspaces-390.png | Utveckling, statistik, moduler och avaktiverad IDP |
| 03-training-top-390.png | Planeditor, mål och långa övningskort |
| 04-training-bottom-390.png | Material, uppgifter, filer och synlighet långt ned |
| 05-event-info-390.png | Nollräknare, informationsflikar och blandade systemtexter |
| 06-event-training-summary-390.png | Lång publicerad plan på aktivitetssidan |
| 07-event-desktop-panels.png | Sidomeny, innehåll och permanent assistent |
| 08-training-module-desktop.png | Modulens separata helskärmsskal |
| 09-tdp-overview-desktop.png | Säsongsförlopp, avslutade perioder och målläge |
| 10-context-switcher-desktop.png | Kontextbyte blandat med klubbadministration |
| 11-roster-management-desktop.png | Truppens långa administrationsmeny |
| 12-inbox-desktop.png | Uppmärksamhetskort, notiser och assistent samtidigt |
| 13-web-contact-inbox-desktop.png | Klubbwebb betyder kontaktförfrågningar |
| 14-home-desktop.png | Två innehållskolumner inom redan begränsad arbetsbredd |
| 15-home-768.png | Trång layout vid mellanbredd |
| 16-home-1024-critical.png | Tydlig text- och layoutkollaps vid panelbrytpunkten |

## Förslag att diskutera: planeringsprogram och guidad start

Följande är diskussionsunderlag, inte beslutad layout:

- Överst: planens namn, datum/lag, sparstatus, förhandsvisning och publicering.
- Till vänster: planens struktur, exempelvis uppvärmning, huvuddel och avslutning.
- I mitten: den faktiska planen, med övningar/block i en tidsatt ordning.
- Till höger: egenskaper för markerad övning eller del, exempelvis tid, organisation och coaching points.
- En tydlig startmöjlighet: Skapa själv eller Guidad planering. Guiden ska kunna återöppnas under arbetet.
- Paneler anpassas för smala skärmar; programkänslan ska inte kräva att alla paneler är synliga samtidigt.

En möjlig guidad träningsdialog börjar med passets ramar, fokus/mål,
gruppens förutsättningar, övningar och tidsfördelning. Den slutar med ett
granskningsbart utkast i samma planeringsyta. Användaren ska kunna gå tillbaka,
ändra svar och fortsätta manuellt. Publicering är en separat uttrycklig handling.
Frågorna och hur mycket hjälp guiden ska ge behöver utformas tillsammans.

För UX-01 är det avgränsade förslaget att börja i grundappen: använd
innehållets faktiska bredd, prioritera en läsbar huvudkolumn och låt
navigation/assistent bli kompakta eller tillfälliga när utrymmet inte räcker.
Det förändrar inte modulernas avsedda separata identitet.

## UX-01 – fastlagd assistentprincip

- Bred desktop: assistenten är alltid öppen.
- Tablet och mobil: assistenten öppnas på begäran.
- Huvudinnehållets layout styrs av dess faktiska tillgängliga bredd.
- Vid begränsat utrymme används en huvudkolumn och vid behov kompakt navigation.
- Exakt brytpunkt och minsta arbetsbredd återstår att prova fram; de är inte beslutade pixelvärden.
- Principen gäller grundappen. Modulernas separata planeringsmiljö utformas för sig.
