# Träning – första test av planeringsmiljö

Användaren har valt att testa Träning som första modul med ett programliknande
arbetsflöde. Detta är en första implementation, inte en färdig omformning av alla moduler.

## Levererat i kod

- Vid minst 1200 logiska pixlars tillgänglig bredd: strukturpanel till vänster,
  tidslinje i mitten och detaljer för vald övning till höger.
- Övningsblock kan dras inom samma passdel. Alternativa pilknappar finns i
  detaljpanelen. Blockbredden följer tiden med minimi- och maximibredd för läsbarhet.
- På smalare ytor behålls den vertikala kortföljden. Brytpunkten är ett första
  implementationsval och behöver utvärderas visuellt med användaren.
- Guiden öppnas från programraden. Tre steg: fokus, namn på passdelarna och
  granskning. Eventets tid fördelas 20/70/10 procent mellan delarna.
- Guiden skapar en enkel struktur, inte färdiga träningsövningar. Den använder
  inga AI-anrop eller övningsbibliotek. Innehåll och tider kan redigeras efteråt.
- Befintliga övningar ersätts först när användaren väljer att använda utkastet;
  granskningssteget beskriver detta. Avbryt lämnar passet orört.
- Utvärdering, delade mål, material och övrig befintlig förberedelse finns kvar
  under Förberedelser på bred skärm och i den befintliga följden på mindre skärm.
- Befintligt publiceringsval bevaras. Guiden sparar eller publicerar ingenting.
  Att spara ett redan publicerat pass uppdaterar fortfarande spelarnas pass.
- Versionskontroll, behörigheter och skydd vid osparade ändringar använder
  befintligt kontrakt. Inga databasändringar.

## Verifiering

Träningsmodulens tester och lokaliserings-/tillgänglighetskontroller: **16 godkända**.
Utökat flödestest omfattar avbruten guide, granskat utkast, sparad tidsfördelning,
bevarad publiceringsinställning och byte mellan 390 och 1440 pixlars bredd.
Svenska och engelska systemtexter finns. Slutlig analys: **inga anmärkningar**.
Efter byte till aktuellt omordnings-API kördes träningsmodulens fyra tester igen,
alla godkända. Releasebyggning för webb är godkänd.

Publicerad till **audit** på `https://app.teamzoneapp.se` med enbart
Firebase Hosting-målet `test`. Byggkontrollen verifierade auditprojektet.
Den publicerade `main.dart.js` matchar lokalt bygge med SHA-256:
`48AF25E69FAB74D486E9CD57A6742BF956547004FE1B93B111856BAED047A877`.

Manuell kontroll i den inloggade engelska auditappen, Hugo Olofsson/P2012:
1440 × 1000 visar struktur, tidslinje och vald övnings detaljpanel.
Guidens tre steg visar 18/63/9 minuter för ett 90-minuterspass och varnar innan
befintliga övningar ersätts. Guiden avbröts; det befintliga auditpasset den
26 november förblev sparat med en övning på 15 minuter, utan spelarpublicering.
390 × 844 visar den vertikala kortföljden. Inga skrivningar gjordes i webbläsaren.
Skärmbilder finns lokalt i `.tmp-training-program/` (ignorerad evidenskatalog).

## Kvar att bedöma i nästa designiteration

Övningens fullständiga redigering öppnas ännu i den befintliga dialogen från
detaljpanelen. Guiden ersätter hela övningsföljden och kan ännu inte justera
enstaka befintliga övningar genom dialog. Match och TDP har inte ändrats.
Huvudappens assistentpanel hör till ett separat beslut och har inte ändrats här.
