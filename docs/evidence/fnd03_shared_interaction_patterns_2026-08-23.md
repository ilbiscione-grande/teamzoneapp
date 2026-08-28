# FND-03 – Gemensamma interaktionsmönster

**Datum:** 2026-08-23  
**Status:** Verifierad  
**Omfattning:** Lokal klient och dokumentation. Ingen Supabase-liveändring, provisionering, webtools eller workspace.

## Resultat

- `AppFormController` ger ett gemensamt kontrakt för dirty-state, pending-state och skydd mot dubbel submit.
- `AppUnsavedChangesScope` använder plattformens backflöde och kräver uttryckligt val innan osparade ändringar kastas.
- Inloggningen använder validerade `TextFormField`-fält och samma pendingkontroll.
- Eventdialogen använder det gemensamma skyddet för osparade ändringar.
- `AppListController` samlar sökning, filter, sortering, sidindelning och "visa fler" i en deterministisk modell.
- Trupp och Inbox använder listmodellen, sökning, tomt sökresultat och pull-to-refresh. Kalenderns refresh ligger kvar på FND-02:s gemensamma asyncmodell.
- `ProductRouteContract` är enda register för nu definierade huvud- och hjälprutter. Cold start och refresh bevarar känd path och okänd path faller säkert tillbaka till Hem.
- GoRouter fortsätter att äga browserhistorik/back-forward. Formulärens `PopScope` fångar Android/system-back när ändringar är osparade.
- Shellens responsiva navigation använder fortsatt endast `AppBreakpoints`; inga konkurrerande lokala breddgränser hittades.

Detaljrutter skapas inte i förväg utan registreras i samma routekontrakt när respektive verklig detaljvy införs. FND-03 introducerar därmed inte tomma eller vilseledande deep links.

## Viktiga filer

- `lib/src/shared/forms/app_form_controller.dart`
- `lib/src/shared/lists/app_list_controller.dart`
- `lib/src/app/product_route_contract.dart`
- `lib/src/app/product_routes.dart`
- `lib/src/features/auth/auth_surfaces.dart`
- `lib/src/features/roster/roster_surface.dart`
- `lib/src/features/calendar/calendar_surface.dart`
- `lib/src/features/messaging/inbox_surface.dart`
- `test/fnd03_shared_interaction_patterns_test.dart`
- `test/fnd01_fnd03_verification_test.dart`

## Verifiering

- `flutter analyze` – inga problem.
- `flutter test test/fnd03_shared_interaction_patterns_test.dart` – 9/9 passerar.
- `flutter test` – 95/95 passerar efter den samlade FND-01–FND-03-verifieringen.
- Befintliga breakpointtester verifierar phone/tablet/desktop-gränser och att appskalet använder de centrala tokensen.
- Befintliga app-smoke-tester verifierar shell och destinationsrendering för giltig behörig kontext.
- Den kompletterande widgetmatrisen verifierar 390×844, 800×1100 och 1440×900 utan layoutundantag.
- Cold link till `/team` överlever full app-rebuild och system-back kräver bekräftelse innan osparade ändringar kastas.

## Avgränsningar framåt

- Fullständiga detail views och deras URL-parametrar tillhör respektive TEAM-, CAL- och MSG-kort och ska registreras centralt när vyerna finns.
- En bredare visuell phone/tablet/desktop-matris samt fokus, textskalning och reduced motion hör till FND-05.
