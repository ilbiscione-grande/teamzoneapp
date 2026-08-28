# Beslutspaket 10 – klientplattformar, kvalitet och release

**Status: godkänt av produktägaren 2026-08-07. CRD-01–CRD-10 är beslutade.**

## Mål

Rebuilden ska ha ett tydligt plattformskontrakt och en reproducerbar releasekedja. Mobil, tablet och desktop-webb ska ge samma domänbeteende även när layouten skiljer sig.

## Stödda klienter

Rekommenderad v1:

- Androidapp;
- iOS-app;
- responsiv Flutter-webbapp för authenticated TeamZone;
- responsiv Next.js-sajt för publik webb.

Tablet stöds genom mobilapparnas adaptiva layout och webben. Native Windows/macOS/Linux är inte egna v1-releaseplattformar; desktopanvändning sker i webbläsaren. Detta minskar release- och notificationmatrisen utan att ta bort desktopåtkomst.

## Navigation och layout

- De fem huvudytorna har stabila, semantiska routes.
- URL/deep link innehåller explicit club/team/event när vyn kräver context och servern verifierar access.
- Webrefresh, browser back/forward, Android back och iOS navigation återställer samma kanoniska vy.
- Nested detail/workspace-state som ska kunna delas får routekontrakt; tillfälliga dialogs/sheets behöver inte vara URL-state.
- Centrala breakpointtokens definierar phone, tablet och desktop-webb; inga lokala godtyckliga trösklar.

## Offline och cache

- Appen visar global connectivity-/syncstatus.
- Senast verifierad read-data kan visas som tydligt märkt cache med timestamp.
- Hög-risk-writes som billing, transfer, roster administration och matchkommandon kräver serverkontakt.
- Endast uttryckligen idempotenta kommandon får köas offline. Callupresponse kan köas med synlig pendingstatus, expiry och serverkonflikthantering.
- Användaren får aldrig se en optimistisk write som permanent lyckad innan serverack.

## Session och Realtime

- Session restore har explicit loading/timeout/retry och får inte felaktigt visa onboarding.
- Expired/revoked session ger säker reauthentication och rensar tenantcache.
- Varje kritisk Realtimekanal rapporterar status och kör full versionerad resync efter reconnect.
- App resume och web visibility använder samma resynckontrakt.
- Offlinegap och stale revision är testfall, inte endast SDK-ansvar.

## Klienttillstånd

- Loading, empty, error, stale/offline och retry är separata komponenttillstånd.
- Råa backendfel visas aldrig för användare; säkert fel-ID kan kopplas till sanerad telemetry.
- Alla mutationer har disabled/pending/success/failure/retry och skydd mot dubbeltryck.
- Kritiska flows har avbrotts- och processrestarttest.

## Språk, tema och tillgänglighet

- All användarsynlig copy går genom lokaliseringskatalog; svenska och engelska är releasekrav.
- Layout testas med längre engelska texter och stora textskalor.
- Semantiska design-/färgtokens används för light/dark/system; kontrast testas.
- Screen reader, keyboard/focus på web, touch targets, text scale och reduced motion ingår i definition of done.
- Custom canvas/gestureytor får semantiska och keyboard-/alternativa kontroller.

## Observability

- Central strukturerad logger med severity, release, environment och correlation ID.
- Tokens, secrets, rå pushpayload och känsliga personfält redigeras vid källan.
- Flutter-, platform-, async-zone- och serverfel fångas i sanerad crash/error telemetry.
- Performance för startup, navigation, query och Realtime reconnect mäts utan att blanda produktanalys med person-/sportsdata.
- Feature-/integration-kill switches och health dashboards finns för kritiska tjänster.

## Release och compatibility

- Varje artefakt är signerad, reproducerbar och kopplad till commit, schema/API-version och environment.
- Databasschema/API förändras additivt först; gammal och ny klient kan samexistera under ett tidsbegränsat compatibility window.
- Feature flags aktiverar nya vertikala slices per testklubb/cohort.
- Migration körs mot tom miljö och sanerad live-lik kopia; rollback/roll-forward dokumenteras.
- Smoke och tenant-/authmatris körs efter deploy före trafikökning.
- Legacy anon/service-role-nycklar avaktiveras först när signerad klient/webb använder nya nycklar och faktisk Auth/Storage/Realtime/Edge-trafik är verifierad.
- Root analyze/test/integration/a11y/securitygrind måste vara ren; tillfälliga filer får inte förorena releasegrinden.

## Beslut som produktägaren behöver bekräfta

| ID | Föreslaget beslut | Rekommendation |
|---|---|---|
| CRD-01 | V1 stöder Android, iOS, responsiv Flutter-webb och publik Next.js; native desktop skjuts upp. | Beslutad |
| CRD-02 | Fem huvudroutes och delbara details har kanoniskt deep-link/refresh/back-kontrakt. | Beslutad |
| CRD-03 | Centrala phone/tablet/desktop-webb-breakpoints ersätter lokala trösklar. | Beslutad |
| CRD-04 | Offline visar cache/status; endast explicit idempotenta writes köas och hög-risk-writes kräver nät. | Beslutad |
| CRD-05 | Session expiry och Realtime reconnect har user-facing recovery och full versionerad resync. | Beslutad |
| CRD-06 | Loading/empty/error/stale/retry är distinkta och råa backendfel visas aldrig. | Beslutad |
| CRD-07 | Svenska/engelska, theme och accessibilitymatris är blockerande releasekrav. | Beslutad |
| CRD-08 | Sanerad strukturerad observability, crash capture, performance och kill switches krävs. | Beslutad |
| CRD-09 | Rebuilden releasas additivt med feature flags, compatibility window och verifierad rollback/roll-forward. | Beslutad |
| CRD-10 | Legacy API-nycklar stängs först efter signerad release och observerad trafik på nya nycklar. | Beslutad |

## Konsekvens

Paketet slutför PD-18 och PD-19 på produktnivå. Exakta breakpointvärden, cache-SLA, compatibilitylängd, telemetryprovider och releasekanaler specificeras senare men får inte försvaga dessa grindar.

## Beslutshistorik

| Datum | Beslut | Beslutsfattare |
|---|---|---|
| 2026-08-07 | CRD-01–CRD-10 godkända som bindande målbild för rebuildspecifikationen. | Produktägaren |
