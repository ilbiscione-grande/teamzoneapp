# Spelarpanel i träningsplaneringen – 26 oktober 2026

Desktopplaneringen (från 1200 px) visar sessionstruppen direkt vid den valda
övningen. Namngivna och ospecificerade spelare kan markeras utan dialog och
varje markerad spelare får ett eget lag/färg. Räknaren visar antal valda av
sessionens antal spelare. Sökfältet filtrerar namn, utan att ändra urvalet.
Spelare väljs enbart från sessionstruppen; länken Ändra sessionstruppen öppnar
översikten. Mobilens befintliga spelarval och dialoger behålls.

Ändringarna hör till det markerade blocket och sparas med befintlig
sessionsrevision. Inga databasändringar krävs.

Spelarlistan är högst 240 px hög och scrollar internt för större trupper.

## Verifiering

16 tränings- och lokaliseringstester godkända. Desktopflödet markerar en
sessionsspelare direkt, ändrar till grönt lag och sparar. Ett annat block
förblir utan spelare. Befintliga mobil- och engelska flöden passerar.
Kodanalys: inga anmärkningar. Webbbygge och auditprojektkontroll godkända.

## Publicering och manuellt prov

Publicerad till auditappen. Publicerad main.dart.js matchar lokalt bygge:
SHA-256 71F7A9C05431B09777F61D2002D250A5ABD7D49E8A78A8918C08D44017AA32A0.
Manuellt prov som Hugo Olofsson i P2012, engelskt språk, desktop 1440 × 1000:
sökning på Adam filtrerar listan, ospecificerad spelare kan av-/markeras med
uppdaterad räknare, färg ändras till grönt och sparas. Spelaren återställdes
sedan till rött; Adam är kvar i blått. AUDIT-passet förblir opublicerat med
en övning på 15 minuter. Skärmbild: .tmp-training-program/player-panel.png.

## Kompaktare desktopplanering

Träningsfokus flyttat till den gemensamma övre raden med passnamn och status.
Långa passnamn kortas visuellt. Tidslinjen är lägre (104 px inklusive
tidsmarkeringar), mellanrummen mindre och den dubbla övningsrubriken borttagen.
Organisation och coachpunkter delar en rad med tre synliga textrader vardera
och kan växa till åtta. Mobilens layout behålls.
De fyra träningsflödestesterna passerar efter ommöbleringen.

Kompaktlayouten är publicerad till audit och manuellt granskad i 1440 × 1000
med 11 sessionsspelare. Fokus ligger i överraden och organisation/coachpunkter
syns samtidigt i två kolumner. Inga passdata ändrades i detta layoutprov.
Kodanalys utan anmärkningar, webbbygge godkänt. Publicerad main.dart.js matchar
SHA-256 040C8A225A16B45F5F68669C4CFC621CFD22FEF28DC35BCF3820974547CF4A57.
Skärmbild: .tmp-training-program/compact-planning.png.

## Textkolumn bredvid spelarna

Efter nästa återkoppling ligger organisation och coachpunkter ovanpå varandra
i en egen kolumn till höger om spelarpanelen. Relativ bredd är 3:2 för
spelarpanel respektive textkolumn. Gäller desktopplaneringen från 1200 px.

Kolumnlayouten är publicerad och visuellt verifierad i separat kontrollflik
(1280 × 720). Användarens ursprungsflik hade osparade ändringar och lämnades
orörd. Kontrollfliken stängd efter granskning. Inga passdata ändrades.
Fyra träningsflödestester och kodanalys godkända, webbbygge godkänt.
Publicerad main.dart.js matchar SHA-256:
AFF36089583A018286E6E22D84E6CDA7796242E2A609701808D651D1397BD38C.
Skärmbild: .tmp-training-program/player-side-column.png.
