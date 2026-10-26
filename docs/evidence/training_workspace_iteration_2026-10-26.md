# Träning – aktiv arbetsyta i mitten

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
