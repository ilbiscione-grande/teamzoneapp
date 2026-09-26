# TEAM-01 – Lagets tre grundflikar

**Datum:** 2026-08-24  
**Status:** SLUTFÖRD – IMPLEMENTERAD, HOSTED, FULLT REGRESSIONSVERIFIERAD OCH FYSISKT KONTROLLERAD PÅ MOBIL, TABLETLAYOUT OCH WEBB  
**Livepåverkan:** Resultatprojektionen är applicerad mot det godkända Supabase-testprojektet `hgcshgunvooyudvrcpig`.

## Implementerat

- Laget har exakt flikarna `Översikt`, `Trupp` och `Kalender`.
- Befintlig rosterlista och dess capabilitystyrda åtgärder återanvänds oförändrade under Trupp.
- Översikt har en stabil responsiv grund och neutral lagbildsfallback; fullständigt rollstyrt innehåll tillhör TEAM-02.
- Kalender är en lista och inte en fullständig kalenderkomponent.
- Endast `Kommande` visas initialt. En segmenterad växling visar i stället `Tidigare`, med stigande respektive fallande tidsordning.
- Eventtyp väljs bakom en kompakt filterknapp till höger om periodväljaren; aktivt filter visas som borttagbar chip. Alla händelser, Matcher, Träningar och Möten stöds.
- Händelser visas i tydliga kort med lokaliserat datum, klockslag, typ, plats och inställd status. En färdigspelad match visar registrerat slutresultat från matchprojektionen; resultat saknas fail-closed om matchen inte är slutförd eller ingen projektion finns.
- Endast event för den aktiva lagkontexten visas.
- En listpost pushar event-ID till huvudkalenderns befintliga auktoritativa EventDetails-vy. Tillbaka-navigation återanvänder samma lagkalendervy och bevarar period samt eventtypfilter.
- Vald lagflik kodas som `/team?tab=overview|roster|calendar` och bevaras vid canonical deep link och refresh.
- Eventdetalj kodas som `/calendar?event=<id>` och öppnas även efter deep link/refresh.
- Ny användartext har svensk och engelsk lokalisering.

## Verifiering

- Direkt Flutter-analys: **No issues found**.
- Riktad TEAM-01/FND-03/FND-05-svit: **20/20 passerar**.
- Widgettest går från huvudnavigationen till Laget, verifierar de tre flikarna och öppnar kalenderlistans struktur/filter.
- Routekontrakt verifierar bevarad flikquery och samma EventDetails-ingång som huvudkalendern.
- Befintligt billing-querykontrakt regresserade först när all query började bevaras; korrigerat så endast Team/Calendar behåller sin uttryckliga UI-state. Sluttestet passerar.
- Uppföljande TEAM-01-widgettest 2026-09-12: **3/3 passerar** och verifierar kommande som standard, periodbyte, dold filtermeny, färdig match med resultat `3–1` samt att `Tidigare + Matcher` bevaras efter EventDetails/back.
- Backendansluten debug-APK kompilerades och installerades utan datarensning. Fysisk Xiaomi Mi 9-kontroll bekräftade exakt tre grundflikar, endast kommande som standard, fungerande periodbyte, samtliga eventtypfilter, läsbara kort, samma EventDetails och bevarat `Tidigare + Matcher` efter appens bakåtpil.
- Migration `20260912054644_team01_calendar_match_results.sql` är applicerad och remote-registrerad. Den utökar endast den befintliga actor-läsbara kalenderprojektionen och lämnar pågående/ej rapporterade matcher utan resultatuppgifter.
- Cold deep link `teamzone://app/team?tab=calendar` startade appen från helt stoppad process direkt på rätt Kalender-flik. Första system-back visade först felaktigt avsluta-dialogen eftersom den kalla ingången saknade historik. En första rättning gick till Hem men lämnade cold-linkdestinationen bakom roten och skapade en Hem/Kalender-loop. Slutlig rättning tömmer den syntetiska historiken när cold-linkdestinationen faller tillbaka till Hem. Fysisk omtest bekräftade: första back går till Hem, andra visar `Stäng TeamZone?`, och Avbryt stannar på Hem.
- Webbgrinden på `localhost:5000` bekräftade direktlänk och refresh till Kalender samt öppning av EventDetails. Ett verkligt webbhistorikfel hittades: browser-back från detaljen landade på lagets Översikt trots att Kalender syntes före öppningen. Flikbytet använder nu en explicit `pushReplacement`, så den valda lagfliken är detaljsidans faktiska returpost utan att flikbyten skapar en rad nästan identiska historikposter. Riktad svit passerar **3/3** efter ändringen och fysisk webbomtest bekräftade att browser-back återgår till Kalender med `Tidigare + Matcher` bevarat.
- Full Flutter-regression 2026-09-12 passerar **367/367**. Första körningen hittade ett för brett AUTH-06-test som matchade klubbnamnet både i namnfältet och i det nya förifyllda supportmeddelandet; kontrollen snävades in till exakt fältvärde, AUTH-04-sviten passerade därefter **15/15** och full omkörning blev grön.
- Tabletens responsiva layout verifierades 2026-09-12 i webbappen vid cirka 800–1000 px bredd. Flikar, periodväxling, filter, händelsekort, långa namn, resultat och EventDetails renderades utan kapning eller överlappning.

## Kvarvarande grind

Ingen kvarvarande grind för TEAM-01.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
