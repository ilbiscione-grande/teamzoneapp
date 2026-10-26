# Träningsöversikt och sessionstrupp – 26 oktober 2026

## Beteende

Ledaren kommer först till Översikt när ett träningspass öppnas. Där finns
träningsfokus, datum/tid, planerade minuter, publiceringsläge, deltagare,
eventinställningar, övningssammanställning och förberedelser. Planering och
Förberedelser nås genom samma navigering på desktop, tablet och mobil.

Sessionstruppen innehåller namngivna och ospecificerade spelare. Accepterade
kallelser förväljs när en sessionstrupp ännu inte sparats. Ett sparat urval,
även ett uttryckligen tomt urval, ändras inte automatiskt av senare svar.
Kallelsegrupperna accepterat, obesvarat, nekat och okallat finns kvar i valet
från eventets lagtrupp. Ingen kallelse eller närvarofakta ändras av urvalet.

Övningarnas spelarval begränsas till sessionstruppen, både i gränssnittet och
på servern. Ospecificerade spelare får stabil identitet inom sessionen.
Lag/färg väljs fortfarande individuellt per block. Tas en använd spelare bort
från sessionstruppen krävs en bekräftelse; spelarens placeringar tas då också
bort ur övningarna i det lokala utkastet. Ändringarna sparas tillsammans med
passet med befintlig revisionskontroll.

Äldre blockspelare, inklusive ospecificerade, förs in i det första urvalet så
att tidigare planering bevaras. Namn läses från aktuell klubbperson; databasen
sparar inga nya namnkopior i träningsplanen.

## Verifiering

- Flutter: 16 tränings- och lokaliseringskontroller godkända, inklusive svensk
  och engelsk navigering, begränsat spelarval, lagfärger, sparande samt
  avbruten och bekräftad borttagning av en använd sessionsspelare.
- Kodanalys: inga anmärkningar.
- PGlite: training_session_roster godkänd. Verifierar automatisk förselektion,
  sparat tomt urval, bevarade äldre placeringar, separata färger per block,
  avvisade dubbletter och spelare utanför sessionstruppen samt skrivbehörighet.
- Auditdatabas: migration registrerad, roster-kolumn finns, RLS bibehållen,
  anon kan inte anropa sparfunktionen. Säkerhetsrådgivarens befintliga
  fyndtyper är oförändrade före/efter.

## Migration och publicering

CLI-genererad migration: 20261220090000_training_session_roster.sql, ordnad
efter befintliga decembermigrationer. Endast denna migration och historikposten
kördes atomärt via länkad CLI i auditprojektet hgcshgunvooyudvrcpig. Två äldre,
orelaterade migrationsluckor i auditens historik lämnades utanför.

Webbbygge och projektkontroll godkända. Publicerat till Firebase Hosting test
på https://app.teamzoneapp.se. Publicerad main.dart.js matchar lokalt bygge:
SHA-256 40B9AB881DF3934CB72D1C62621416053EFDEF34EEA99BE55BD0DED42C1BA047.

Manuellt verifierat som Hugo Olofsson i P2012 med engelskt appspråk i det
befintliga opublicerade AUDIT-passet den 26 november:

- Passet öppnas på Översikt; fokus, tid, inställningar och äldre spelare visas.
- En tillfällig ospecificerad spelare lades till i sessionstruppen och sparades.
  Övningens valdialog erbjöd just den nya sessionsspelaren; den kunde läggas
  in i blocket och sparas.
- Borttagning ur sessionstruppen visade bekräftelsen och tog även bort
  spelarens blockplacering. Därefter sparades och återöppnades passet.
- De ursprungliga två spelarna finns kvar: ospecificerad i rött och Adam
  Eriksson i blått. Den tillfälliga provspelaren är borttagen. Passet är
  fortfarande opublicerat, med en övning på 15 minuter.
- Översikt och planering granskade i desktop 1440 × 1000 och mobilbredd
  390 × 844. Fysisk telefon har inte använts.

Accepterade kallelser och sparat tomt urval är automatiskt verifierade;
det manuella auditpasset har inga kallelser. Inga kallelsesvar eller
närvarofakta ändrades under provet.

Lokala skärmbilder: .tmp-training-program/session-overview-desktop.png och
.tmp-training-program/session-overview-mobile.png. Befintlig SQL-svit
training_sessions passerade också som regressionstest.
