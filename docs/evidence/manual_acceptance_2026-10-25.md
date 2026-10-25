# Manuell acceptans – 25 oktober 2026

Uppföljning efter [auditreleasen](audit_release_2026-10-25.md), mot
driftsatt kod från `e0a6ffb`. Detta är en delgenomgång, inte ett slutgodkännande.
Rättningarna nedan finns lokalt och är inte driftsatta.

## Provad omfattning

| Yta | Kontroll | Resultat |
|---|---|---|
| App, svenska, dator 1280 × 720 | Befintlig auditsession, Hem, lagväljare och Inställningar | Vyer laddar. Sessionen har klubbfunktionärs-/spelarroll. Tre befintliga lag visas. |
| App, svenska, ledare 522 × 874 | Hugo Olofsson, Demoklubben IF/P2012, Arbetsytor | Användaren öppnade befintlig ledarsession. Match, TDP och Träning går att öppna. |
| Träning, ledare | Publicerat pass 26 oktober, fyra övningar, mål, material, uppgift, fil och synlighet | Innehåll laddar och ryms i aktuell vy. 83 av 90 minuter stämmer med övningarnas tider. Tidigare-listan laddar. Inga data sparades. |
| TDP, ledare | Översikt, Säsongen, Spelidé, Mål och Nytt mål-dialog | Perioder, delningsval och tomlägen laddar. Tomt mål kan inte sparas; dialogen avbröts. |
| Match, ledare | Kommande/Spelade, trupp, uppställning 4-2-3-1, matchplan, Live och Efteranalys | Trupp och befintlig uppställning laddar. Resultat 1–0 och händelsekarta visas. Gårdagens match visas felaktigt i båda listorna; rättat lokalt. |
| App, tillgänglighet | Aktivera tillgänglighet och granska Hem/Inställningar | Sidomenyn syns visuellt men saknas i tillgänglighetsträdet. Reproducerat i widgettest. |
| Publiksajt, svenska | Start → Hitta klubb → sök Thomas → klubb → lag | Söket visar klubb/lag och verifieringsmärkning. Rätt klubb- och lagsida öppnas. |
| Klubb- och lagsida, mobil 390 × 844 | Visuell granskning och DOM-bredd | Innehållet håller sidans bredd. Sektionmenyn rullar horisontellt. Tom kalender har tydlig text. |
| Webtools, dator och mobil 390 × 844 | Katalog → Tacticsboard → Logga in | Produkt- och inloggningssida laddar, returvägen bevaras. Formuläret ryms i mobilbredd. |
| Webtools, produkttexter | Jämförelse med implementation och dokumenterad betaomfattning | Byggda funktioner beskrivs felaktigt som kommande. Rättat lokalt. |

Inga meddelanden, kontoändringar, ansökningar, bokningar eller andra
verksamhetsposter skickades. Befintlig inloggning användes; inga nya
behörigheter eller konton skapades.

## Fynd och lokala rättningar

1. **Tillgänglighet, sidomeny:** den inre routens modalsemantik dolde
   permanent navigering. Den inre routern har nu en egen semantikbehållare,
   och den permanenta sidomenyn använder Material i stället för en modal
   Drawer. Mobilens öppningsbara Drawer behålls. Regressionstestet saknade
   Kalender före rättningen och hittar nu Kalender, Inställningar och Logga ut.
2. **Layout, sidomeny:** Inställningar bröts mitt i ordet när två knappar
   tvingades dela på 280 pixlar. Knapparna använder nu Wrap och kan flytta
   till varsin rad utan att texten bryts av den konstgjorda halva bredden.
3. **Produkttext, Webtools:** betasidor visar nu ”Det här finns i betan”.
   Tacticsboards animationer, delning, export, bibliotek och livegenomgångar
   samt turneringsplanerarens grupper/schema/resultat/slutspel beskrivs som
   byggd betafunktion. Video Analyzer behåller kommande-status.
4. **Datumfilter, Match:** matchen mot Aneby SK 24 oktober visades både
   under Kommande och Spelade den 25 oktober, trots slutresultat 1–0.
   Kommande hämtade matcher från gårdagens midnatt. Intervallet börjar nu
   vid dagens midnatt. UI-regressionen reproducerar överlappet före rättningen
   och visar därefter gårdagens match endast bland Spelade.
5. **Produkttext, Arbetsytor:** Träning utlovade ett övningsbibliotek, trots
   att appens bibliotekskoppling är en återstående leverans. Beskrivningen
   säger nu träningspass med övningar och utvärdering, på svenska och engelska.

## Automatisk kontroll av rättningarna

- Responsivt skal och befintlig roll-/releasematris: **29 tester godkända**.
- Språkgrind samt Träning, Matchplan och Lagutveckling: **22 tester godkända**.
- Webtools typkontroll och **54 tester godkända**.
- Webtools produktionsbygge: godkänt, Next.js 16.4.3.
- Ny datumregression och befintliga matchplanstester: **5 godkända**.
- Slutlig omkörning av språkgrind, Träning och datumregression efter sista
  texträttningen: **16 tester godkända** (överlappande med kontrollerna ovan).
- Slutlig Flutter-analys av samtliga fem ändrade Dart-filer: **inga fynd**.
  Full projektanalys avbröts efter att paketversionskontrollen fastnat;
  den avgränsade analysen kördes med `--no-pub` och passerade.

Testerna ersätter inte acceptans av skrivflöden, publicering eller samtidig
användning från flera konton. Dessa åtgärder utfördes inte mot lagets data.

## Återstående acceptans

- **Ledaråtkomst löst:** användaren öppnade Hugo Olofsson i Demoklubben
  IF/P2012. Läsande ledargranskning är genomförd enligt tabellen ovan.
- **Engelska – automatiskt verifierad inom testernas omfattning:** språkgrinden
  och det engelska träningsflödet passerar. Användaren beslutade 25 oktober
  att tills vidare redovisa denna automatiska verifiering. Manuell engelsk
  acceptans kvarstår som öppen; ingen manuell engelsk session har genomförts.
  Därefter beställde användaren ett eget språkval under Personligt.
  Det är [implementerat lokalt](language_setting_2026-10-25.md) för nästa auditrelease.
- **Mobil app:** inledande storleksändring slog inte igenom på Flutterfliken.
  Efter användarens byte till ledarsession var den faktiska appvyn
  522 × 874 och provades visuellt. 390-pixels appbredd täcks automatiskt,
  men har inte manuellt godkänts. Publiksajten och Webtools provades vid 390 × 844.
- Inloggade Webtools-verktyg, fysisk enhet, två samtidiga användare,
  skärmläsare med tal och övriga rollkombinationer återstår.
- Lokala rättningar behöver därefter publiceras och verifieras i audit.

Databasens migreringsavstämning, tomdatabasreplay och behörighetsöversyn
ligger kvar i [aktuellt leveransläge](../implementation/current_status.md).
