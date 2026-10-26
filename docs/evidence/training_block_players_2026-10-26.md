# Spelare och lagfärger per övning

## Funktion

Varje träningsblock har en egen lista över spelare. Ledaren kan lägga till
ospecificerade spelare eller välja flera spelare från eventlagens trupp,
välja blått/rött/grönt/gult lag eller neutral färg för varje spelare och ta
bort spelare från just det blocket. Samma person kan ha olika färg i olika
övningar. Färg visas också som lagtext, så informationen inte enbart bärs av färg.

Valet ändrar inte kallelser, eventtrupp eller närvaro. Det sparas tillsammans
med passet på befintlig revision och omfattas av samma publiceringsval.
Publicerade pass visar även övningens spelarindelning. Redigeraren finns i
desktopens mittenyta samt under övningskort på mindre skärm.

Högst 80 spelare per block. Samma namngivna person kan bara finnas en gång
i samma block. Truppväljaren filtrerar bort redan tillagda personer och har sökning.

## Data och verifiering

Migration `20261219090000_training_block_participants` lägger till en JSONB-lista
i befintliga `core.training_blocks`. Saknad lista läses som tom för äldre data.
RPC-sparandet validerar format, antal och personreferenser mot eventets aktiva
spelartrupp. Namn på namngivna spelare hämtas från databasens personpost vid
läsning; spelarnamn kopieras inte till den sparade blocklistan. Ändrat namn
slår därför igenom när passet hämtas igen. RLS, kapabilitetskontroll,
publiceringsgräns och revisionskonflikter behålls.

Supabase CLI skapade migrationsfilen. Den placerades efter de befintliga
framtidsdaterade decembermigrationerna för korrekt replayordning.
Auditprojektet är verifierat som `hgcshgunvooyudvrcpig`.
CLI:s dry run fann två äldre, orelaterade lokala migrationer som saknas i
remotehistoriken. De tillämpades inte. Endast den aktuella migrationen och dess
historikpost kördes atomärt via `supabase db query --linked --file`.

Databastest i PGlite verifierar oberoende färg per block, kanoniskt namn,
avvisad utomstående person, dubblett, felaktigt format/färg och över 80 spelare,
publiceringsgräns, skrivbehörighet och revisionskonflikt.
Appens tränings- och lokaliseringskontroller: **16 godkända**. Flödestestet
lägger till anonym spelare, ändrar färg, väljer en truppspelare och sparar båda.
Modelltestet verifierar JSON-retur och att vanlig övningsredigering behåller listan.
Kodanalys: inga anmärkningar.

Auditfråga efter migration verifierar giltig anonym spelare, avvisad ogiltig
färg, registrerad migration, bibehållen RLS och att anon inte kan spara.
Supabase Advisors har samma befintliga fynd före och efter: 126 informationsfynd
för RLS utan policy samt varningar för pg_net-schema och lösenordsskydd.
Inga nya fynd från denna ändring.

## Publicering och manuell acceptans

Webbbygge och projektkontroll är godkända. Appen är publicerad till audit via
Firebase Hosting `test`, med den nya migrationen i samma auditprojekt.
Publicerad `main.dart.js` matchar lokalt bygge med SHA-256:
`54DC653F5357E77E9B808CC1D643AD3958D4CA6042C88D0082B8C85A0A14D58B`.

Fyra SQL-sviter är gröna: training_sessions, training_block_participants,
training_evaluations och training_goals_list. Den nya sviten kontrollerar också
att sparade spelarlistor inte innehåller namnkopior och att namnändring slår
igenom vid läsning.

Manuellt test genomfört som Hugo Olofsson i P2012 med engelskt appspråk:
I det befintliga AUDIT-passet den 26 november lades en anonym spelare till,
ändrades till rött lag och en truppspelare (Adam Eriksson) lades till i blått lag.
Passet sparades och öppnades igen från träningslistan; båda spelarna och deras
färger kvarstod. Passet är fortfarande opublicerat. Inga kallelser eller
närvarofakta ändrades.

Desktop 1440 × 1000 och mobil 390 × 844 har visuellt kontrollerats.
Lokala skärmbilder finns i `.tmp-training-program/block-players-desktop.png`
och `.tmp-training-program/block-players-mobile.png`.
