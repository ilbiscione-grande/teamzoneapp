# TEAM-01 – Lagets tre grundflikar

**Datum:** 2026-08-24  
**Status:** LOKALT IMPLEMENTERAD OCH KLIENTVERIFIERAD; FYSISK DEEP-LINK/NAVIGATIONSGRIND ÅTERSTÅR  
**Livepåverkan:** Ingen. Inga backend- eller Supabase live-ändringar gjordes.

## Implementerat

- Laget har exakt flikarna `Översikt`, `Trupp` och `Kalender`.
- Befintlig rosterlista och dess capabilitystyrda åtgärder återanvänds oförändrade under Trupp.
- Översikt har en stabil responsiv grund och neutral lagbildsfallback; fullständigt rollstyrt innehåll tillhör TEAM-02.
- Kalender är en lista och inte en fullständig kalenderkomponent.
- Händelser delas i `Kommande` och `Tidigare` med stigande respektive fallande tidsordning.
- Filter finns direkt för Alla, Matcher, Träningar och Möten.
- Endast event för den aktiva lagkontexten visas.
- En listpost navigerar med event-ID till huvudkalendern, som öppnar sin befintliga auktoritativa EventDetails-vy.
- Vald lagflik kodas som `/team?tab=overview|roster|calendar` och bevaras vid canonical deep link och refresh.
- Eventdetalj kodas som `/calendar?event=<id>` och öppnas även efter deep link/refresh.
- Ny användartext har svensk och engelsk lokalisering.

## Verifiering

- Direkt Flutter-analys: **No issues found**.
- Riktad TEAM-01/FND-03/FND-05-svit: **20/20 passerar**.
- Widgettest går från huvudnavigationen till Laget, verifierar de tre flikarna och öppnar kalenderlistans struktur/filter.
- Routekontrakt verifierar bevarad flikquery och samma EventDetails-ingång som huvudkalendern.
- Befintligt billing-querykontrakt regresserade först när all query började bevaras; korrigerat så endast Team/Calendar behåller sin uttryckliga UI-state. Sluttestet passerar.

## Kvarvarande grind

1. Verifiera system-back, appomstart, cold deep link och refresh på fysisk Android samt webb.
2. Verifiera eventtryck mot riktig testdata och tillbaka-navigation till rätt lagflik.
3. Kontrollera telefon/tablet/desktop visuellt med långa lag- och eventnamn.
4. Kör full regressionssvit.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
