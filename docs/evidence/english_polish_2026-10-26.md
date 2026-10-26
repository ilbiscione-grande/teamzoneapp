# Språkputs i Match – 26 oktober 2026

## Ändring

Skottkartans engelska summering böjer shot och goal efter antal. Exempel:
1 shot · 1 goal, 2 shots · 0 goals. Den svenska formuleringen behålls.
Resultatet short för hörna och frispark använder systemetiketten Kort passning
på svenska och Short på engelska. Kort för kortutdelning översätts fortsatt Card.
Registreringsdialogen och händelsetidslinjen använder samma resultatkatalog.
Inga lagdata, anteckningar eller sparade händelsevärden ändras.

## Verifiering

20/20 riktade prov passerade: språkgrind, matchplan/analys och Live-modellen.
Statisk analys av slutrevisionen passerade utan fynd. En inledande
kodstilsanmärkning om klamrar rättades före slutbygget. Nytt regressionstest täcker singular/plural, noll mål, Short för båda fasta
situationerna och att Card fortsätter betyda kortutdelning.

## Omfattning

Fortsättning på [engelsk release och omprov](english_release_2026-10-25.md).
Förra releasens CI 40238641745 har nu alla sex jobb godkända, inklusive SQL.
Skriv-/rollacceptans, fysisk mobil och manuell 390-pixelsgranskning återstår.

## Release

Källrevision: 377ce04a54b5370d5335bc811ea0890530a00db9.
CI: https://github.com/ilbiscione-grande/teamzoneapp/actions/runs/40275563525

Publicerad till auditappen https://app.teamzoneapp.se via Hosting target test,
site teamzoneapp-b02a2. Miljögrinden bekräftade auditprojektet
hgcshgunvooyudvrcpig. Lokalt bygge och serverad main.dart.js har samma SHA-256:
47630D652FE1B7A14A185AEE9EB1AC9CE2C7808E8859672929F901E971F1B774.
Inga sajter, funktioner eller databasändringar publicerades.

## Manuellt omprov

Befintlig engelskspråkig ledarsession, Hugo Olofsson i Demoklubben IF/P2012.
Match mot Aneby SK den 24 oktober, Live: skottkartan visar
2 shots · 1 goal · 0 on target · 1 off target · 0 blocked.
Hörnhändelsen visar Corner · Aneby SK · Short.
Kontrollen var läsande, inga händelser ändrades. Användarens svenska
anteckningar och egna knappar behölls. Sessionen lämnades vid Settings.
Bildbevis: .tmp-acceptance-evidence/english-polish-match-2026-10-26.png.

De två kvarvarande språkfynden från 25 oktober är därmed rättade och omprovade.

Vid rapportens avslut körde nya CI-körningens Flutter- och SQL-jobb fortfarande.
Övriga fyra jobb hade passerat. Lokala tester, analys, releasebygge,
miljögrind och manuellt omprov är godkända enligt ovan.
