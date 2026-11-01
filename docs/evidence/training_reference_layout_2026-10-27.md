# Träningsmodulens programlayout – 27 oktober 2026

Desktopplaneringen följer användarens visuella referens: en samlad topprad
med passnamn, tid, träningsfokus, sparstatus och befintliga åtgärder.
Tidslinjen ligger över hela arbetsytans bredd ovanför fyra separata paneler:
passets struktur, övningsinnehåll, övningens spelare och egenskaper.
Passdelarna får gemensamma färger i struktur och tidslinje.

Organisation och coachpunkter redigeras i övningens centrala panel.
Spelarna har en egen kolumn med sökning, kryssrutor och individuella
lagfärger. Kolumnen scrollar själv och använder fortfarande bara den
sparade sessionstruppen. Publiceringsreglaget ligger under egenskaper.
Befintlig revisionskontroll och sparfunktion används.

Illustrationer, formaterad text och nya strukturerade egenskaper från
referensbilden ingår inte i denna layoutiteration. Mobilens arbetsflöde
behålls. Desktopprogrammet används från 1200 px.

## Verifiering

Fyra träningsflödestester godkända, inklusive svenska desktopval, färgbyte,
sparande och engelskt flöde. Kodanalys utan anmärkningar. Omprovet fångade
en för smal meny vid kompakt färgknapp; menyn har nu egen bredd 240 px och
hela flödet passerar igen. Färgknappen visar en tillgängligt namngiven
färgmarkör så att spelarnas namn får plats. Arbetsytorna har ljusa kort.

## Publicering och visuell acceptans

Slutversionen är byggd och publicerad till auditappen. Publicerad main.dart.js
matchar lokalt bygge, SHA-256:
83B46F399B1312594822CF6A2630BDD242CE4C631BD6D8033B53F462D24857DB.
Visuellt granskad i 1440 × 1000 som Hugo Olofsson i P2012 med engelskt
appspråk. Det sparade 90-minuterspasset har fem övningar och elva sessionsspelare.
Kontrollen visar fullbreddstidslinje, fyra paneler, läsbara spelarnamn på en rad
och komplett färgmeny. Inga passdata ändrades. Kontrollfliken stängdes och
användarens ursprungliga flik lämnades orörd.
Skärmbild: .tmp-training-program/reference-layout.png.

## Iteration 2 – närmare referensbilden

Desktopplaneringen har nu egen topprad (ikon, passnamn, datum/tid/plats/lag,
träningsfokus, sparstatus med senaste sparning, Spara, Guidad planering och
meny) och understrukna flikar. Tidslinjen har intervallval (5–30 min),
zoom och Anpassa, prickar på axeln och valt block i passdelens förstärkta färg.
Passets delar visar numrerade övningar med draghandtag, meny för redigera/ta
bort och "Lägg till övning" per del. Övningspanelen har redigerbar rubrik,
Byt övning (öppnar övningsdialogen), kopiera, ta bort med Ångra, samt
organisation och coachpunkter med verktygsrad där punkt- och numrerad lista
fungerar. Deltagarkolumnen har sök, filter (Alla/Valda/Ej valda), initialer,
numrering, färgval per spelare och "Lägg till ospecificerad spelare".
Egenskaper: längd, passets del, spelfas och antal spelare per lagfärg.

Platshållare tills datamodellen har stöd: övningsbild (ritad plan med
"Övningsbild kommer snart"), syftesruta, Syfte, Yta och Material (inaktiva
fält), samt fetstil/kursiv/länk i verktygsraden.

Verifiering: kodanalys utan anmärkningar, fyra träningsflödestester godkända.
Skärmbild från widgettest med Geist i 1680 × 960:
.tmp-training-program/reference-match.png.

## Iteration 3 – översikt och förberedelser i samma stil

På desktop (från 1200 px) använder Översikt och Förberedelser samma topprad,
flikar, ljusa bakgrund och vita paneler som Planering. Översikten får en rad
med nyckeltal (planerad tid med stapel, övningar med passdelsfärger,
sessionstrupp, synlighet). Korten är paneler med fet rubrik, inställningarna
visas med ikoner, och övningarna listas numrerade med passdelens färgprick.
Rubrik och fokusfält visas inte i översikten, eftersom toppraden har dem.

Förberedelser visas i tre paneler: Mål och fokus (planerad tid, säsongsplan,
mål), Förberedelser (anteckningar, material, uppgifter, filer) och Övningar
(numrerad lista som öppnar planeringen, synlighet och utvärdering).
Den delade `_PreparationTab` har fått en valfri `sessionLayout`; eventsidorna
påverkas inte. Mobilvyerna är oförändrade.

Verifiering: kodanalys utan anmärkningar; träningsflödet och hela
förberedelsesviten (30 tester) godkända. Skärmbilder från widgettest i
1680 × 960: .tmp-training-program/programme-overview.png och
programme-preparation.png.

## Iteration 4 – mobilvyerna efter mobilreferensen

För ledare under 1200 px (telefon och surfplatta) har träningspasset nu samma
ljusa bakgrund och vita paneler som desktop:

- **Topprad:** passets namn, tid och plats på Översikt, och på de andra
  flikarna "90 min • fokus". Spara ligger i toppraden. Guidad planering, Lägg
  till övning och Visa för spelarna ligger i ⋮-menyn.
- **Fokus:** en egen rad på Översikt. Den öppnar en dialog där fokus
  redigeras.
- **Flikar:** understrukna och lika breda.
- **Översikt:**
  - Bildyta (placeholder) med minuter, övningar och deltagare.
  - Publicerad/Utkast-väljare.
  - Rutor för plats, träningsfokus, sessionstrupp och material.
  - Raden Träningsmål.
  - Sessionstruppen, inställningarna och utvärderingen som paneler.
- **Planering:**
  - Varje passdel har en färgad rubrik med +.
  - Övningarna ligger på en tidslinje med minutintervall (0–10, 10–15 …).
  - Varje övning har en ⋮-meny för redigera, flytta, kopiera och ta bort.
- **Övningssida:** ett tryck på en övning öppnar den med fyra flikar.
  - Övning: bild, beskrivning och syfte (placeholder). Starta övning är
    inaktiverad, eftersom övningsläget kommer senare.
  - Spelare: valda spelare först med Rensa, övriga hopfällda, och lagfärg per
    spelare.
  - Coachning: organisation, coachpunkter och egna noter (placeholder).
  - Inställningar: samma egenskaper som på desktop.
- **Förberedelser:** samma tre paneler som desktop, under varandra.

Spelare som inte får redigera ser passet som tidigare.

Verifiering:

- Kodanalysen ger inga anmärkningar.
- Träningsflödet (uppdaterat för övningssidan), förberedelsesviten och
  modulgrunden går igenom.
- Skärmbilder från ett widgettest i 390 × 844 ligger i
  .tmp-training-program/phone-*.png.
