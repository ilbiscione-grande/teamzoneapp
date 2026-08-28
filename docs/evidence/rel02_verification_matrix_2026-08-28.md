# REL-02 – roll-, enhets- och avbrottsmatris (2026-08-28)

## Resultat

REL-02 har nu en reproducerbar och klarmarkeringsbar verifieringsmodell:

- 12 unika kombinationer av leader, player, guardian och klubbfunktionär × telefon, tablet och desktop/web;
- fyra obligatoriska grundytor per roll-/enhetsfall: Hem, Laget, Kalender och Inbox;
- sju separata avbrottsfall för cold start, deep link, back/forward, kontextbyte, offline, reconnect och session expiry;
- fem tillgänglighetsfall för skärmläsare, tangentbord/fokus, 200 % text, kontrast och reduced motion;
- obligatoriska evidencefält för testare/tid, build, roll/kontext, enhet/viewport, observerat resultat, skärmbild/logg samt pass/defect.

Den stegvisa guiden finns i `docs/implementation/rel02_step_by_step_verification.md` och den maskinläsbara källan i `docs/implementation/rel02_verification_matrix.json`.

## Befintlig täckning som inventerats

- FND-04: komplett strukturellt rollkontrakt för fyra roller och fyra grundytor.
- FND-03: phone/tablet/desktop, canonical navigation, cold link/rebuild och system-back.
- FND-02: stale, offline→online-resync och context-race.
- AUTH-02: sessionåterställning, delad webbenhet och fail-closed session.
- FND-05: semantik, fokus, textskalning, kontrast och reduced motion samt äldre fysisk Android-kontroll.

Äldre bevis är uttryckligen märkta `prior_evidence_requires_regression` och kan inte ensamma klarmarkera en aktuell release.

## Kvarstående

REL-01 är grön och den automatiserade Flutter-baslinjen kan köras. Ingen telefon är ansluten, separata hosted testkonton/testdata saknas och webtools får inte startas. Därför är de manuella matrisraderna fortsatt `structural_only` eller `prior_evidence_requires_regression`; ingen har felaktigt märkts `passed` enbart från widgettester.

Ingen Supabase-liveändring, produktionsprovisionering, webtool eller workspace genomfördes.

## Automatiserad regressionskörning 2026-08-28

Efter att REL-01 blev grön lades `test/rel02_automated_release_matrix_test.dart` till och kördes tillsammans med matriskontraktet. Resultatet var 16/16 godkända tester:

- samtliga 12 kombinationer av leader, player, guardian och klubbfunktionär × telefon 390×844, tablet 800×1100 och desktop/web 1440×900;
- Hem, Laget, Kalender och Inbox öppnades i varje kombination;
- telefon använde `NavigationBar`, medan tablet och desktop/web använde `NavigationRail`;
- rollernas positiva och negativa actions förblev disjunkta och okända rollpaket nekades;
- okonfigurerade ytor renderade fail-safe utan okontrollerade exceptions.

Detta är en aktuell automatiserad releasebaslinje, inte en hosted behörighets- eller fysisk assistive-technology-passering. JSON-matrisens slutstatus förblir därför `partial` tills separata testkonton/testdata och de manuella avbrotts-/tillgänglighetsfallen kan köras inom godkänd miljö.

## Automatiserad avbrotts- och tillgänglighetskörning 2026-08-28

En samlad riktad körning passerade 27/27 tester för canonical cold link/rebuild, system-back och osparade ändringar, säker async-felhantering, fail-closed session, fokusordning, 200 % text på tre viewportar, AA-kontrast, reduced motion och AC-ingångens responsiva kontrakt.

Körningen är paketerad i `tool/rel02_automated_gate.ps1` tillsammans med 4 × 3-matrisen. Den reproducerbara samlade grinden passerade 43/43 tester och skrev `REL02_AUTOMATED_GATE_OK`. Hosted session expiry, webbläsarens back/forward, fysisk offline/reconnect och skärmläsare på riktig enhet står fortsatt öppna och har inte märkts som godkända.

## Utförda kontroller

- JSON parse: godkänd.
- Exakt 4 roller, 3 enheter och 12 unika korsproduktrader: godkänd.
- Exakt 7 avbrottsfall, 5 tillgänglighetsfall och 7 obligatoriska evidencefält: godkänd.
- Kontroll att ingen rad är förtida `passed`: godkänd.
- `git diff --check`: godkänd.
- Riktad Dart-analys av båda REL-02-testerna: godkänd utan anmärkningar.
- Automatiserad roll-/viewportmatris och matriskontrakt: 16/16 godkända tester.
