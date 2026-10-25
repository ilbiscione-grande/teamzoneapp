# Engelsk översättningsrelease och omprov – 25 oktober 2026

## Leverans

Översättningsbatchen publicerades till auditappen https://app.teamzoneapp.se.
Första publicerade källrevision: a3e5134798c9651a4ff0be27d6d02632341f11ef.
Dess JavaScript kontrollerades mot det lokala bygget med identisk SHA-256:
27803E6023AF6579E48A9255F2EBEF1EDB39C92717369105A7B2E83C89C9F18F.
Alla sex jobb i [CI 40237314241](https://github.com/ilbiscione-grande/teamzoneapp/actions/runs/40237314241) passerade, inklusive Flutter, SQL, båda sajterna och funktionerna.

Efterföljande komplettering: abbac0924d3313ffce325ec1b1a35bac01ae7c86. Den rättar arkiveringsknappen, TDP:s
text för dagar utan period, spelartid och statistikverktygstips, Live-truppens
rubriker, skottkartans summering och Min vy-dialogens systemetiketter.
Kompletteringen publicerades till Firebase Hosting target test (site
teamzoneapp-b02a2). Miljögrinden bekräftade auditprojektet
hgcshgunvooyudvrcpig. Serverad main.dart.js och lokalt bygge har samma SHA-256:
E6A41470B56812CEFC0153EF84B012D2429A19A9A13D323C7B77DBA706C12676.
Ingen sajt, databas eller funktion publicerades i denna release.

[CI för kompletteringen](https://github.com/ilbiscione-grande/teamzoneapp/actions/runs/40238641745):
Flutter, båda sajterna, Firebase Functions och Edge Functions passerade.
SQL-jobbet kör fortfarande vid rapportens avslut (25 oktober cirka 23:13 CET).
Det finns därför ännu inget komplett grönt CI-kvitto för kompletteringen.

## Manuell omfattning

Befintlig ledarsession: Hugo Olofsson, Demoklubben IF/P2012, språk English.
Faktisk vy 522 × 874. Genomgången var läsande. Formulär öppnades och avbröts;
inga matchhändelser, lagdata, mål, uppgifter eller inställningar sparades.

| Område | Observerat efter första publiceringen |
|---|---|
| Personligt och assistentknapp | English kvar efter omladdning; My assistant och antal/tooltip följer språket. |
| Assistent | Filter, uppgiftsrubriker, påminnelse/uppskjutning samt samtliga granskade inställningsavsnitt på engelska. En svensk arkiveringsknapp hittades och rättades i kompletteringen. |
| Träning 26 oktober | Mål, måltyper, målåtgärder, anteckningsrubrik, material, uppgifter, filer och synlighet på engelska. |
| TDP | Overview, Season, Playing philosophy och Goals, delningsval, principområden och målformulär på engelska. Ingen period i tidslinjen rättades i kompletteringen. |
| Matchplan | Tactics, Set pieces, Opponent and key players samt mallknappar på engelska. |
| Matchanalys | Resultat, statistik, händelsefilter, händelser och rubriken Playing time and statistics på engelska. Spelarradernas minuttal och tooltiptexter rättades i kompletteringen. |
| Match Live | Final score, My view, Custom buttons, Shot map, Events, substitutionshändelser och händelsetyper på engelska. Trupprubriker, kartsummering och tre dialogetiketter rättades i kompletteringen. |

Svenska aktivitetstitlar, taktikinnehåll, övningsbeskrivningar, anteckningar,
materialnamn och lagets egna matchknappar är användarinnehåll och bevaras.
Exempelvis Löpning in i boxen och Bollåtererövring är egna knappar, inte
översättningsfel. Inga krascher eller layoutöverflöden observerades i stegen.

## Automatiska prov för kompletteringen

23/23 riktade prov passerade: Match, assistentens visningsinställningar,
TDP och språkgrinden. Arkiveringsknappens engelska text har en uttrycklig
widgetassertion. Efter den sista kodstädningen passerade Matchsvitens 2/2
prov igen. Statisk analys passerade utan fynd. Övriga tidigare provresultat finns i
[översättningsrättningen](english_translation_fix_2026-10-25.md).

## Kvarvarande acceptans

Detta godkänner enbart de granskade läsande ledarvyerna och formulärens
synliga etiketter. Skrivflöden, andra roller, fysisk mobil och manuell
390-pixelsgranskning återstår. Matchtruppens meddelande No upcoming match
trots kommande matcher i översikten noterades som en separat funktionell
avvikelse; den har inte ändrats i denna språkrelease.

Lokala bildbevis från omprovet finns i `.tmp-acceptance-evidence/`:
`english-release-training.png` och `english-release-tdp-goal.png`.
Dessa är lokala granskningsbilder, inte versionshanterade produktfiler.

## Slutligt manuellt omprov av kompletteringen

Efter omladdning av den publicerade appen verifierades Archive på båda
assistentkorten och No period i TDP:s säsongstidslinje. I matchen mot Aneby SK
visades Goals/Saves och 90 of 90 min i spelarnas statistik, On the pitch (11),
Bench (3), engelsk skottkartssummering samt Events, Custom buttons och Note
i My view. Lagets egna knappar behöll svenska namn. Dialogen avbröts utan
sparande. Sessionen lämnades på Settings → Personal med English valt.

EN-01–EN-04:s observerade svenska systemtexter har rättats och omprovats
inom ovanstående läsomfattning. Detta är inte ett godkännande av hela appen.
Två mindre språkkvalitetsfynd återstår: kartans antal böjs ännu inte i singular
(1 goals), och en hörnhändelses resultat Short visas som Card. De bör få
kontextspecifik språkputs före fullständig engelsk acceptans.

Bildbevis för slutversionen:
.tmp-acceptance-evidence/english-release-match-my-view.png.
