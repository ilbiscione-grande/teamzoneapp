# Mobilbredd och skrivprov – 26 oktober 2026

## Samlad bedömning

Grundläggande skapa/redigera/spara/läsa tillbaka passerade i TDP, Träning och
Match med tydligt märkt auditinnehåll. Kontrollerna gjordes i publicerad auditapp
https://app.teamzoneapp.se, befintlig engelskspråkig ledarsession för Hugo
Olofsson, Demoklubben IF/P2012. Källrevision för appen:
377ce04a54b5370d5335bc811ea0890530a00db9.

Webbläsarens viewport sattes uttryckligen till **390 × 844**, och bilder
granskades visuellt. Detta är ett webbläsarprov med tangentbord/mus,
inte ett prov av fysisk telefon, touch, skärmtangentbord, iOS/Safari,
Android, installation eller push. Andra roller och samtidiga redigeringar
är inte godkända av detta prov.

Vid detta prov hittades en för trång matchflik och svenska systemtexter på
Home. Dessa två fynd är därefter rättade, publicerade och omprovade; se
[rättningskvittot](mobile390_fixes_2026-10-26.md). Fyndbeskrivningarna nedan
behålls som historisk evidens. Språkets helhetsacceptans är fortsatt avgränsad.

## Granskade ytor

| Yta | Resultat inom provad omfattning |
|---|---|
| Settings → Personal | Språkfält, tema och kalenderinställningar ryms. Public pages ligger delvis utanför den horisontella flikraden; inte hela flikens innehåll provat. |
| My assistant | Uppgiftskort, titel, filter och åtgärdsknappar ryms. Filterraden är horisontellt rullbar. Inga uppgiftsåtgärder utfördes. |
| Workspaces | Modulnamn och beskrivningar bryts och ryms. IDP är fortsatt markerad som under utveckling. |
| TDP | Översikt, mållista, nytt mål, detaljdialog och redigering provade. Formulärval radbryts; spara/avbryt ryms. |
| Training | Lista, tomt pass, sparat utkast, övningsdialog och nedre förberedelser/synlighet provade. Huvudknappen Save är åtkomlig och nederdelen går att rulla fram. |
| Match | Översikt, uppställningens tomläge, matchplan och analysens tomläge provade. Fält/mallknappar radbryts och spara går att rulla fram. Fliken Post-match analysis är för trång, se M390-01. |
| Calendar | Månadsvy med vald dag och aktivitet granskad. Periodnavigation, vy/filter och skapa-knapp ryms. Inget nytt event skapades. |
| Home | Händelsekort, kommande aktiviteter och svarsknappar ryms. Svenska systemtexter kvarstår, se EN-05. Inga inbjudningar besvarades. |
| Inbox | Flikar, sökfält, uppmärksamhetskort och konversationslista granskade. Inga meddelanden öppnades eller skickades. |
| Team | Översikt med lagbildens tomläge, nästa aktivitet och senaste match granskad. Kort och datum radbryts inom bredden. Övriga lagflikar ingick inte. |

## Skrivprov och kvarlämnat auditinnehåll

### TDP

Skapade säsongsmålet AUDIT 2026-10-26 TDP skrivprov med beskrivningen
Testinnehåll för mobilbredd och spara/läs tillbaka. Sparade och öppnade
måldetaljen. Ändrade titeln till AUDIT 2026-10-26 TDP skrivprov redigerat,
sparade och verifierade Goal saved samt uppdaterad titel. Markeringen
Dropped sparades därefter och syntes på målkortet. Testmålet behålls som
avbrutet auditspår. Befintliga mål och säsongsperioder ändrades inte.

### Träning

Valde det befintliga eventet 26 november 17:30, som saknade pass. Skapade ett
opublicerat träningsutkast med fokus AUDIT 2026-10-26 Training skrivprov.
Sparbesked: Session saved. Only coaches can see it. Lade till uppvärmningsövningen
AUDIT övning 2026-10-26 med 12 minuter, redigerade den till 15 minuter och
sparade. Stängde passet och verifierade Draft · 1 exercise · 15 min i listan.
Öppnade igen: fokus och övning/minuter fanns kvar och Show the session to
players var avstängt. Utkastet behålls som ledarsynligt auditspår.
Dagens publicerade pass ändrades inte.

### Match

Valde matchen mot Sävsjö FF den 28 november 10:00, som saknade matchplan.
Skapade en plan med Tactics-texten AUDIT 2026-10-26 Match skrivprov och
stängde av taktikinnehållets spelarsynlighet. Published for players lämnades
avstängt. Sparade, ändrade texten till AUDIT 2026-10-26 Match skrivprov
redigerat och sparade igen. Match plan saved visades. Stängde matchen och
verifierade Match plan: Draft i listan. Öppnade planen igen och läste den
redigerade texten med fortsatt avstängd taktiksynlighet. Utkastet behålls
som auditspår. Ingen uppställning, matchhändelse, resultat eller publicering
ändrades.

## Fynd

### M390-01 – analysfliken har för låg höjd för engelsk text (P3)

I matchhuvudets segmentrad bryts Post-match analysis på två rader i
390-pixelsbredd, men radens höjd ger för litet utrymme. Textens nedre rad
ligger tätt mot/klipps av segmentets nederkant. Fliken går att öppna; detta
är ett visuellt läsbarhetsfynd. Reproducerat både i matchplan och valt
analysläge. Berörd komponent: lib/src/features/match_workspace/match_page.dart.
Rekommenderad rättning: tillåt tillräcklig segmenthöjd för två textrader
eller använd en kortare lokaliserad etikett med full tillgänglighetstext.

### EN-05 – Home använder svenska systemtexter med English valt (P2)

Observerat God morgon, Hugo, SENARE IDAG, Kommande, Snabbåtgärder,
Planera aktivitet, Hantera laget och Öppna inkorgen. Datum och
inbjudningssvarens etiketter är engelska. Svenska aktivitetstitlar, namn och
meddelanden är användarinnehåll och ska bevaras.

Ytterligare språkobservation: tomma uppställningspositioner visar svenska
förkortningar som MV, VB, MB, HB och ANF även i engelsk vy. Dessa behöver
bedömas mot önskad språkpolicy för formationskatalogen.

## Evidens och fortsatt acceptans

Lokala bilder i .tmp-acceptance-evidence/:

- mobile390-assistant-2026-10-26.png
- mobile390-tdp-write-2026-10-26.png
- mobile390-training-write-2026-10-26.png
- mobile390-match-write-2026-10-26.png
- mobile390-match-tabs-finding-2026-10-26.png
- mobile390-home-language-finding-2026-10-26.png

CI 40275563525 har nu samtliga sex jobb godkända. Inga kodändringar eller
nya appbyggen ingår i detta acceptanspass. Mobilbredden återställs efter
provet. Fysisk telefon, andra roller, publicering till spelare och mer
omfattande skrivflöden (Live, uppställning, bilagor, konflikter) återstår.
