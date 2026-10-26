# Träning – aktiv arbetsyta i mitten

## Senaste justering: fast minutskala under blocken

Efter ytterligare återkoppling ligger linjen vid övningsblockens nederkant.
Fasta markeringar under linjen visar 0, 15, 30, 45 minuter och så vidare till
passets längd (eller planerad längd om planen är längre). Varje övnings
start-/slutminut står inuti blocket. Blockbredderna är nu proportionella mot
tiden utan den tidigare minsta blockbredden, så att kanterna stämmer med skalan.
En läsbar minsta skala kan göra att hela tidslinjen behöver rullas horisontellt.
Korta block kan korta av texten; pekarhjälpen visar fullständigt namn och tid,
och vald övning redigeras som tidigare i mittenytan. Denna skala ersätter
de tidigare iterationernas ungefärliga blockbredder.

Publicerad till audit. Fyra träningstester är godkända, kodanalysen har inga
anmärkningar och webbbygget är godkänt. Manuellt visuellt kontrollerad vid
1440 × 1000: blocken slutar vid linjen, markeringarna 0–90 visas under den
och intervallen ligger inuti blocken. Inga passdata ändrades vid kontrollen.
Skärmbild: `.tmp-training-program/desktop-quarter-hour-axis.png`.
Publicerad `main.dart.js` matchar lokalt bygge med SHA-256:
`D699CDD27B4ED46B73CE4546CDB5333F8FBE21A5781F231E1364807E08F2F0BB`.

## Senare justering: en gemensam tidslinje

Efter användarens återkoppling har den separata tidsstapeln tagits bort från
desktopens planeringsvy. Planerad tid visas i tidslinjens rubrikrad och de lägre
övningsblocken ligger ovanpå en gemensam linje. Tidslinjens höjd har minskats
från 142 till 104 pixlar; även den tidigare separata tidsstapeln och dess
mellanrum försvinner. Blockens tidsintervall, val och omordning finns kvar.
Överskriden eventtid markeras fortfarande med felkulör. Mobilens tidsöversikt
och kortföljd behålls.

Justeringen är publicerad till samma auditmiljö. Träningsmodulens fyra tester
är godkända och kodanalysen har inga anmärkningar. Releasebyggning och kontroll
av auditprojektet är godkända. Visuellt kontrollerad vid 1440 × 1000 i det
befintliga fyrövningspasset, utan skrivning av passdata. Skärmbild:
`.tmp-training-program/desktop-unified-timeline.png`.
Publicerad `main.dart.js` matchar lokalt bygge med SHA-256:
`EFA9E41AF7CA91EB73C48D60C3D8EBF8B88F8A39099FED913964B3E0C778A3F2`.

## Föregående iteration

Uppföljning av [första testversionen](training_program_trial_2026-10-26.md).
Användaren upplevde att mittenytan var underutnyttjad och valde att gå vidare
med en sammanhängande tidslinje och direkt redigering av vald övning.

## Ändrat

- En gemensam horisontell följd ersätter tre separata tidslinjer med tomma rader.
  Varje block visar passdel, namn, längd samt start-/slutminut från passets början.
  Bredden följer längden med läsbarhetsgränser; tidsangivelserna är exakta även
  när minsta blockbredd gör skalan ungefärlig. Långa följder kan rullas horisontellt.
- Första övningen väljs automatiskt. Namn, organisation och coachpunkter
  redigeras direkt under tidslinjen i mittenytan och följer med i samma sparande.
- Vänsterpanelen har minskats från 220 till 200 pixlar och högerpanelen från
  280 till 220. Mitten får därmed mer bredd.
- Högerpanelen innehåller minuter, passdel, skede och flyttknappar.
  Byte av passdel ordnar om övningen utan att ändra dess innehåll.
  Dra och flyttknappar ändrar ordning inom en passdel.
- Spelarpublicering ligger i programraden. Beteendet är oförändrat: knappen
  Spara sparar även det valda publiceringsläget.
- Den befintliga dialogen finns under Fler alternativ, bland annat för borttagning.
  Kortföljden på mobil/tablet och den guidade starten finns kvar.

## Verifiering

Träningsmodulens tester samt lokalisering/tillgänglighetskontroller: **16 godkända**.
Utökat flödestest omfattar direkt redigering och sparat innehåll, ogiltiga minuter,
omordning med bevarad organisation, avvisad flytt över passdelsgräns och byte
till mobilbredd. Slutlig kodanalys: **inga anmärkningar**. Releasebyggning för
webb och kontroll av auditprojektet är godkända.

## Publicering och visuell kontroll

Publicerad till audit på `https://app.teamzoneapp.se`, enbart Firebase Hosting
`test`. Publicerad `main.dart.js` matchar det lokala bygget med SHA-256:
`F4742D582AD03EAF30A190A61FC90C3A94965F208422BF22D369C89D72B6746C`.

Manuellt läsande granskad som Hugo Olofsson/P2012 med engelska som appspråk.
Ett befintligt pass med fyra övningar kontrollerades vid 1440 × 1000 och
1200 × 900. Val av en annan övning byter innehållet i mitten och egenskaperna
till höger. Ingen layoutöverrinning observerades. Vid 390 × 844 återkommer
kortföljden. Inga ändringar sparades och publiceringsläget ändrades inte.

Skärmbild: `.tmp-training-program/desktop-workspace-v2.png` (lokal ignorerad evidens).
De tidigare begränsningarna om att full övningsredigering kräver dialog är därmed
ersatta för den breda desktopvyn; dialogen används fortfarande på mindre skärm.
