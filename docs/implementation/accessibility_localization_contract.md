# Tillgänglighets- och lokaliseringskontrakt

**Kontrakt:** FND-05  
**Gäller:** Alla nya och ändrade klientytor

## Obligatoriska regler

- Interaktiva touchmål är minst 48×48 logiska pixlar.
- Ikonknappar har tooltip/semantiskt namn. Dekorativa ikoner exkluderas från semantik.
- Rubriker, live-status, loading och fel exponeras semantiskt; färg eller ikon är aldrig enda informationsbärare.
- Tangentbordsordningen följer den visuella och logiska ordningen. Formulär anger `next`/`done` och fungerar utan pekdon.
- Delade animationstider går genom `AppMotion.accessible`; reduced motion ger noll varaktighet.
- 200 % textskala ska fungera utan render-overflow på phone, tablet och desktop. Innehåll som kan bli högre än viewporten är rullbart.
- Semantiska text/bakgrundspar ska uppnå WCAG AA 4,5:1 för normal text.
- Svenska och engelska är obligatoriska klientlokaler. Användartext går via `AppStrings`, domänspecifika stringsklasser eller annan godkänd localegräns.
- Varumärket `TeamZone`, användargenererad text och formaterade data är tillåtna undantag från översättningsordlistan.
- Ingen vy får kapa känslig betydelse eller ersätta fullständiga flik-/statusnamn med enbart färg, ikon eller obegriplig förkortning.

## Verifiering för varje huvudkort

Varje HOME-, TEAM-, CAL-, MSG- och AUTH-kort ska minst lägga till:

1. ett widgettest med relevant semantik och tooltip;
2. ett positivt tangentbords-/fokustest när ytan innehåller formulär eller desktopactions;
3. en 200 %-textskalekontroll på de layouter som ändras;
4. svensk och engelsk copykontroll;
5. kontroll att status fortfarande uttrycks i text när ikon/färg används.

Avvikelse kräver dokumenterad motivering, alternativ åtkomst och separat godkännande; tester får inte lösas genom att globalt begränsa användarens textskala.
