# Engelskt språkpass – 25 oktober 2026

## Bedömning

Efterföljande [översättningsrättning i koden](english_translation_fix_2026-10-25.md)
adresserar EN-01–EN-04 med engelska regressionstester. Den är ännu inte
publicerad eller manuellt omprovad. Fynden nedan beskriver den granskade
publicerade versionen.

**Engelsk acceptans är inte godkänd.** Språkvalet och delar av gränssnittet
fungerar, men flera viktiga komponenter visar fortfarande svenska systemtexter.
Gröna automatiska språkprov innebär därför inte att hela appen är översatt.

Läsande genomgång av publicerad auditapp efter
[språkreleasen](language_release_2026-10-25.md), med användarens val **English**.
Befintlig ledarsession: Hugo Olofsson, Demoklubben IF/P2012.
Faktisk vy: **522 × 874**. Inga lagdata sparades, publicerades eller raderades.
Formulär öppnades för inspektion och avbröts. Språkvalet lämnas på English.

## Provade vyer

| Yta | Fungerar inom provad omfattning | Kvarstående språkfel |
|---|---|---|
| Settings → Personal | Rubriker, språkval, tema, kalenderinställningar och huvudnavigering på engelska. | Assistentknappens namn/tooltip/tillgänglighetsbeskrivning förblir svenska. Övriga inställningsflikars innehåll ingick inte. |
| More och Workspaces | Meny, modulbeskrivningar och Training-kortets korrigerade beskrivning på engelska. | Gemensam assistentknapp på svenska. |
| Training-lista | Upcoming/Previous, Open session, minuttal, status och datum/tid på engelska. | Svenska aktivitetstitlar och träningsfokus är lagets innehåll och räknas inte som språkfel. |
| Training, publicerat pass 26 oktober | Training session, Training focus, Exercises, Warm-up/Main part/Cool-down, Coaching points och synlighetsreglage på engelska. | Målkomponenten och gemensamma förberedelser är delvis svenska, se EN-02. |
| TDP | Modulnamn, Overview/Goals, datum och teckenräknare på engelska. Alla fyra flikar och Nytt mål-dialogen kunde öppnas. | Stora delar av flikar, innehållsetiketter, tomlägen och formulär på svenska, se EN-03. |
| Match, listor och trupp | Next match, Upcoming/Played, förberedelsestatus, matchdatum, kallelsesammanfattning och flera positionsnamn på engelska. | Truppen, Målvakter och Om 6 dagar på svenska. |
| Match, uppställning | Line-up, Formation, Fill in, instruktion, Substitutes och Add/Delete på engelska. | Inget ytterligare språkfel noterades i den synliga uppställningen. Dragning, spelarbyte och sparande ingick inte. |
| Match, matchplan | Yttre navigation, sidhuvud och synlighetsreglage på engelska. | Fältetiketter och mallknappar svenska, se EN-04. |
| Match, Live och efteranalys | Yttre flikar Preparation/Live/Post-match analysis på engelska. Resultat och händelsekarta laddar. | Stora delar av resultatetiketter, statistik, filter och händelsetyper svenska. |
| Assistent | Tillbakaknapp och vissa datumformat följer English. Uppgifterna laddar. | Verktygstips, filter, uppgiftstexter och åtgärdsknappar är svenska, se EN-01. |

Inga nya layoutöverflöden eller krascher observerades i de läsande stegen
vid aktuell vybredd. Det godkänner inte andra bredder, fysisk enhet,
skrivflöden eller andra roller.

## Konkreta fynd

### EN-01 – assistenten följer inte språkvalet (P2)

Observerat: ”Uppdatera uppgifter”, ”Assistentinställningar”, ”Uppskjutet”,
”Arkiverat”, ”Alla”, ”Viktigt”, ”Förberedelser”, ”Förberedelser återstår”,
”Närvaro saknas”, ”Obesvarade kallelser”, ”Åtgärda”, ”Skjut upp”, ”Arkivera”
och ”Påminn…”. Assistentknappens tillgänglighetstext innehåller också
svenska antal och etiketter.
Assistentinställningarna har svenska rubriker, switchar, områdesnamn och
knappen ”Spara visningsinställningar”. Även dessa öppnades utan att sparas.

Berör bland annat `assistant_coach_entry.dart`, `assistant_tasks.dart` och
assistentens presentations-/identitetslager. Eventuellt användarvalt
assistentnamn ska bevaras; systemnamn och systemgenererade uppgifter behöver
en uttrycklig språkpolicy och lokaliserad presentation.

### EN-02 – gemensamma förberedelser i Träning saknar engelska (P2)

Observerat: ”MÅL FÖR TRÄNINGEN”, ”Lägg till mål”, ”Fylls i efteråt”,
”minst 10”, ”Ja”, ”Åtgärder för målet”, ”Nytt mål”, ”Spara mål” och
måltyperna i dialogen. Även ”ANTECKNINGAR”, ”Redigera anteckningar”,
”UPPGIFTER”, ”FILER”, ”Lägg till material”, ”Lägg till uppgift”,
”Lägg till fil”, ”Synlig för alla deltagare”, ”Alla” och ”Fler val” är svenska.

Mål och förberedelser återanvänds från `calendar/event_followup.dart` och
`calendar/event_preparation.dart`. Åtgärda den gemensamma komponenten så
att samma rättning gäller där den visas i andra flöden.
Materialnamn, uppgiftsbeskrivning, filnamn och anteckningstext är lagets data
och ska inte automatiskt översättas.

### EN-03 – TDP är endast delvis lokaliserad (P2)

Observerat i alla fyra flikar: ”Säsongen”, ”Spelidé”, ”Säsongens perioder
är avslutade”, ”Säsongsmål”, ”Inga säsongsmål än”, ”Kommande kortsiktiga mål”,
”Delas med spelarna”, ”Ändra säsongen”, ”Inget delas än”, ”Spelprinciper”,
”Ny princip”, ”Inga principer än”, ”Nyckeltal” och ”Nytt nyckeltal”.
Måldialogen har ”Nytt mål”, ”Säsong”, ”Kortsiktigt”, ”Mål”, ”Beskrivning”,
”Avbryt” och ”Spara”, trots engelska teckenräknare.

Berör TDP:s modul, säsong, delning, spelidé, mål och redigeringskomponenter.
Lagrade säsongsnamn, periodnamn och beskrivningar ska hållas åtskilda från
systemetiketter; exempelvis ett sparat namn ”Säsong 2026” är inte i sig ett språkfel.

### EN-04 – Matchs detaljvyer och dynamiska etiketter saknar engelska (P2)

- Översikt/trupp: ”Truppen”, ”Målvakter” och ”Om 6 dagar”.
- Matchplan: ”Taktik”, ”Standardsituationer”, ”Motståndaren och nyckelspelare”,
  ”Försvar:”, ”Anfall:”, ”Hörnor för:” och andra systemgenererade mallknappar.
- Live: ”Slutresultat”, ”Min vy”, ”Publikt”, ”Skottkarta”, ”Vi”,
  ”Händelser”, ”Slutsignal”, ”Periodslut” och händelsetyper.
- Efteranalys: ”Slutresultat”, ”Avslut”, ”På mål”, ”Hörnor”, ”Frisparkar”,
  ”Räddningar”, ”Händelser på planen”, ”Alla”, ”Hela” och ”Speltid och statistik”.

Källor omfattar `match_module.dart`, `match_squad.dart`, matchplanens
redigeringskomponenter, `match_live_parts.dart` och `match_analysis_parts.dart`.
Spelarnamn, klubbnamn och användarskrivna matchkommentarer bevaras.

## Testlucka och rekommenderad rättningsordning

Den befintliga språkgrinden inventerar huvudsakligen literala `.feature(...)`-
anrop och kontrollerar råa Text-strängar i ett urval filer. Det fångar inte
all dynamisk text, alla återanvända komponenter eller alla modulflikar.
Exempel: `_ModuleShell` anropar `.feature(section.label)`; en saknad dynamisk
etikett kan därför visas på svenska i release utan att inventeringen upptäcker den.

1. Lokalisera gemensamma förberedelser och assistentens systempresentation.
2. Slutför TDP och Match, inklusive dialoger, dynamiska antal och tillgänglighetstext.
3. Lägg till engelska UI-regressioner för TDP och Match samt ett icke-tomt
   träningspass med mål, material, uppgifter och filer. Testa även språkbyte
   när vyerna redan är öppna, och att användarnas svenska innehåll bevaras.
4. Kör om manuellt engelskt språkpass innan engelsk acceptans stängs.

Denna genomgång är en granskning: inga applikationsändringar eller
driftsättningar genomfördes. Ingen ny testsuite kördes, eftersom koden inte ändrades.
