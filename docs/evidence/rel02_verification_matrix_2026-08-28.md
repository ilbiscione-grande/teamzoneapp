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

## Påbörjad fysisk telefonkörning 2026-08-28

- Xiaomi Mi 9 med Android 10 anslöts via USB och aktuell konfigurerad audit-debugbuild installerades.
- Laget → Översikt och Trupp samt den dataminimerade mobila persondetaljen renderade utan overflow.
- Körningen hittade att Android-back från persondetaljen avslutade appen. TEAM-03 korrigerades till root-navigator, riktade tester passerade 4/4 och analysen var ren.
- Korrigerad build `682A444638127D754D24568F3B3E53243532D421212AD9C435DC9EA8EFE5DC64` installerades; produktägaren bekräftade att back nu stänger sheeten och återgår till Trupp.
- `REL02-I-03` förblir partiell eftersom hela Android- och webbläsarens back/forward-matris inte är färdig. `REL02-RD-01` förblir partiell tills Hem, Kalender, Inbox, rollcapabilities och serverresultat passerar på samma build.
- Kalenderns fysiska telefonkörning hittade därefter 12 px overflow i Månad vid tre event i samma cell. Mobilgränsen ändrades till en titel plus `+N`, CAL-01 passerade 3/3 och analysen var ren.
- Build `629CC42B1C051FF4775A4FAE2AE532ACD5186149297D018AF361671F0FE918A3` installerades; fysisk Mi 9-omkörning bekräftade ett intakt 6×7-rutnät utan overflow.
- Agenda, Månad, Vecka och Dag har därefter renderats fysiskt på Mi 9 utan layoutfel. Vecka/Dag hade inget event i aktuellt intervall, så deras eventfyllda variant kvarstår.
- Inbox laddade riktiga trådar men fysisk kontroll hittade att fyra permanenta footeråtgärder tog en stor del av mobilens innehållsyta. Telefonvarianten komprimerades till menyn `Fler inkorgsåtgärder`; MSG-01 passerade 5/5 och analysen var ren.
- Build `D33B337D5ADC6F684081E38E4D80069F195519481F5A13E6F77EFA31AB47D2A9` installerades och produktägaren bekräftade att footerstacken var borta samt att alla fyra åtgärder fanns i menyn.
- En riktig direkttråd renderade historik och composer utan overflow; fysisk Android-back återgick korrekt till Inbox utan appavslut. Tvåkonto-send/read och reconnect återstår.
- Min assistent-FAB öppnade korrekt leader-/lagkontext och en fail-closed yta. Namndialogen rymdes med tangentbord utan att något namn sparades.
- Fysisk system-back från assistentroute avslutade först appen. Den nästlade GoRouter fick en `RootBackButtonDispatcher`; FND-körningen passerade 7/7 och analysen var ren.
- Build `4FB923D56AE218E57316A02E2A0D6462CD7AF0AC493C4786E8F9D3CB7468655C` installerades och produktägaren bekräftade att Android-back nu återgår från Min assistent till Inbox.
- Samma build tvångsstängdes och kallstartades därefter via Androids launcher. Den giltiga sessionen och valda lagkontexten återställdes direkt till det autentiserade produktskalet med `Thomas lag`; ingen återgång till inloggning eller onboarding skedde.
- Kallstartsdelen av `REL02-I-01` är därmed fysiskt godkänd på Mi 9. Hela avbrottsfallet förblir partiellt tills återgång från bakgrund samt eventuell utgången session har körts i en godkänd miljö.
- Appen skickades även till Androids hemskärm och återöppnades utan processdöd. Den återkom till samma autentiserade Hem-yta med `Thomas lag`, så bakgrund/återgång är fysiskt godkänd på samma enhet och build.
- `REL02-I-01` kvarstår endast som partiell för scenariot utgången/återkallad session, vilket kräver kontrollerad autentiseringsmiljö och körs inte mot Supabase live utan separat godkännande.
- `REL02-I-02` kördes fysiskt från en dataladdad Inbox. Wi‑Fi stängdes av medan mobildata redan var av; de tre cachade direkttrådarna låg kvar utan krasch, utloggning, tomskärm eller dubbletter.
- Telefonens ursprungliga nätläge återställdes (`wifi_on=1`, `mobile_data=0`) och Android rapporterade åter ett validerat Wi‑Fi-nät. Efter återanslutning visades samma tre trådar och samma olästmarkering.
- Offline/återanslutning är fortsatt partiell tills en kontrollerad skrivåtgärd kan provas utan risk för oavsiktlig live-mutation; denna körning ändrade ingen Supabase-data.
- Fysisk 200 %-text på Mi 9 hittade brutna/klippta etiketter i den sexdelade mobilnavigationen. Vid stor text visar `NavigationBar` nu endast vald fliks etikett men behåller alla ikoner och semantiska namn.
- Tillgänglighets-/lokaliseringssviten passerade 9/9, analysen var ren och korrigerad build `AA01C48FD01453EEF4AB6F46324ED2CD6D5CAFFC31952C0CF2F71BAFFF305CB5` installerades.
- Fysisk 200 %-omkörning passerade utan klippta navigeringstexter; font scale återställdes till 1,0. Denna telefon-/Hem-kombination är godkänd, medan övriga fysiska ytor och skärmläsare kvarstår i REL-02:s tillgänglighetsmatris.
- TalkBack aktiverades manuellt på Xiaomi Mi 9 och verifierades som aktiv Android-tillgänglighetstjänst. Produktägaren svepte genom Hem, Laget, Kalender/Månad, Inbox, en riktig direkttråd och Min assistent.
- Fokusordning, fullständiga knapp-/fliknamn, feltext, kalenderkontroller, trådmetadata, formulärkontroller, textburen assistentkontext och Android-back godkändes utan rapporterat fokuslås eller namnlös kontroll. Inget meddelande skickades och ingen serverdata ändrades.
- `REL02-A-01` är därmed fysiskt godkänd för svensk TalkBack på telefon och de prioriterade grundytorna. Tablet/desktop och andra skärmläsarkombinationer omfattas inte av denna passering.
- `REL02-I-03` osparade ändringar kördes fysiskt i eventeditorn. Android-back visade `Kasta ändringar?`; `Fortsätt redigera` behöll texten `rel02 osparat test ändrad`, medan en andra back följd av `Kasta` stängde editorn och återställde den sparade titeln.
- Båda dialoggrenarna är därmed fysiskt godkända på Mi 9 utan krasch eller appavslut. Tillsammans med tidigare godkänd back från persondetalj, direkttråd och Min assistent täcker detta telefonens prioriterade backfall; webbläsarens back/forward kvarstår separat.
- Testförberedelsen skapade av misstag eventet `rel02 osparat test` i stället för att lämna en ny draft öppen. Efter uttryckligt städgodkännande ställdes endast denna post in. Appens livscykel erbjuder därefter varken statusbyte, arkivering eller radering; posten kvarstår därför synligt som `Inställd` och ingen direkt Supabase-ändring gjordes.
- Androids registrerade `teamzone://app/...`-länkar kallstartades därefter på build `AA01C48FD01453EEF4AB6F46324ED2CD6D5CAFFC31952C0CF2F71BAFFF305CB5`. `/team`, `/calendar`, `/inbox` och `/assistant` öppnade respektive canonical yta med giltig session och `Thomas lag` bevarad.
- Okänd route öppnade en neutral `Sidan finns inte`-yta med säker förklaring. `/calendar?event=rel02-nonexistent-event` stannade i Kalender utan felaktig eventdetalj, kontextläcka eller krasch.
- Androiddelen av `REL02-I-02` är godkänd för dessa fall. En riktig trådlänk, feltenant/felscope-ID och motsvarande webbläsarfall återstår; ingen data ändrades av deep-link-körningen.
- `/inbox?thread=rel02-nonexistent-thread` kallstartade dessutom säkert till Inbox med ordinarie tre trådar och utan att öppna en felaktig detalj.
- Inför fysisk `REL02-I-04` öppnades kontextväljaren först skrivskyddat. Kontot exponerade då endast `Thomas lag`, så ett riktigt tvåkontextbyte krävde uttryckligt godkänd testdata i den aktuella Supabase-testdatabasen.
- Xiaomi krävde manuellt systemval för mörkt läge; Android bekräftade därefter `Night mode: yes`/`ui_night_mode=2`. Hem renderade med tydliga rubriker, felcopy, knapp, vald flik och Min assistent-FAB utan förlorad information.
- Produktägaren godkände därefter fysisk mörkerkontroll av Kalender inklusive textburen `Inställd`-status, Inbox med filter/oläst/trådtext och Min assistent med områdesmarkeringar, informationskort och avgränsningstext.
- `REL02-A-04` är därmed godkänd genom kombinationen automatiserad AA-kontrast och fysisk light/dark-telefonpassering; färg användes inte ensam som informationsbärare.
- Fysisk `REL02-A-05` kunde inte aktiveras på Xiaomi Mi 9: MIUI nekade ADB-skrivning av samtliga animationsskalor och exponerade inget `Ta bort animationer`/`Minska rörelser` i tillgänglighetsinställningarna. Skalorna förblev oförändrade på `1.0`.
- Reduced-motion-kontraktet är fortsatt automatiserat godkänt; det fysiska telefonfallet är enhetsblockerat och har inte felmarkerats.
- En full offline-refresh i Inbox verifierade befintlig stale-UX: tre trådar bevarades och kortet `Visar senast verifierade data` visades med senaste verifieringstid.
- Den första återanslutningen lämnade stale-kortet kvar trots validerat Wi-Fi. Inbox fick därför en avgränsad resync med 3/5/10/30 sekunders backoff efter misslyckad refresh; timer och försök nollställs vid framgång och avbryts när ytan stängs.
- MSG-01-testet passerade 5/5 och analysen var ren. Audit-debugbuild `998F0AC65B70C1EF4F8FF0E89712972EE646163D8C5B46B17E68BC96C8F333A2` installerades.
- Fysisk omkörning visade tre trådar + stale offline. Efter Wi-Fi-återställning försvann stale automatiskt inom den avgränsade timeout/backoff-perioden; tre trådar och `Thomas lag` bestod utan användarrefresh. `REL02-I-06` är godkänd. `REL02-I-05` återstår endast för kontrollerad offline-mutation.
- Den fysiska EventDetails-körningen synliggjorde även rå Dart-tid med millisekunder. CAL-05 bytte till lokaliserad datum-/tidsformatering; testet passerade 2/2 och analysen var ren.
- Build `7D1D867FB7622EBA99846738D08D7CB2E5C84967A93CDC3C8D5B69D4450A2EA2` verifierades på Mi 9 med `lördag 29 augusti 2026 · 18:00–20:00` och separat tidszon utan rå timestamp.
- EventDetails användarcopy flyttades därefter bakom localegränsen; CAL-05/FND-05 passerade 11/11 och analysen var ren. Samlad build `A8C081E47E8409B4B72E22882FA5964C1439E941BFB53555C5D3767A42C8B92F` installerades och svensk Kalender kallstartade intakt.
- För fysisk desktop/webb startade den lokala grundappen korrekt på `127.0.0.1:7357`. Browser-pluginens kontrollruntime misslyckades därefter med saknad intern kernel-assetsökväg trots att `browser-client.mjs` fanns.
- Servern stoppades och port 7357 verifierades stängd. Webbläsarens back/forward och fysisk tangentbordsfokus kvarstår miljöblockerade; ingen fristående browserautomation användes som kringgång och den automatiserade desktopgrinden är fortsatt grön.
- Lokal releasewebb kördes därefter på `localhost:5000`. Webbläsarens back/forward följde den kanoniska routen bättre efter att webbens yttre `MaterialApp` slutade konsumera produktens route-information.
- Den första webbroutingfixen byggde emellertid produktroten direkt från en statisk `RouterDelegate` utan `Navigator/Overlay`. `RawTooltip` kastade därför `No Overlay widget found` vid mouseover; releasebyggets felwidget framstod som stora grå, oklickbara block i appbar, navigation och vanliga actions.
- DOM-, semantics-, hovertema-, CanvasKit/Skwasm-, InPrivate- och grafikaccelerationshypoteserna falsifierades. Ett statiskt debugbygge visade den exakta Overlay-exceptionen. Rotdelegaten bygger nu en sidbaserad `Navigator`, så Overlay finns utan att den yttre routern återtar webbläsarens route-information. Tillfällig DOM-/hit-testdiagnostik och hover/CSS-kringgångar togs bort.
- Korrigerad releasewebb startade på `localhost:5000`, svarade med HTTP 200 och fysisk mouseover/klick fungerade igen enligt produktägaren. Full back/forward-, tangentbords- och 200 %-matris återstår innan respektive REL-02-rad klarmarkeras.
- `REL02-A-02` kördes därefter fysiskt i releasewebben. `F6` gav tangentbordsinträde utan mus; `Tab`/`Shift+Tab` följde appens kontroller, `Enter` aktiverade navigation, modal höll fokus, `Esc` stängde och fokus återgick till utlösande knapp. Webbens tangentbords-/fokusfall är godkänt.
- Webbens 200 %-omkörning passerade efter Overlay-fixen över Hem, Laget, Kalender och Inbox. Appbar, sidinnehåll och responsiv bottom navigation behöll mouseover/klick, text klipptes inte och actions förblev åtkomliga. `REL02-A-03` är fortsatt partiell endast för separat fysisk tablet-kontroll.
- `REL02-I-03` passerade full fysisk webbsekvens: Hem → Laget → Kalender → Inbox, tre browser-back till Kalender/Laget/Hem och tre browser-forward till Laget/Kalender/Inbox. Canonical route och `Thomas lag` bevarades utan loop. Tillsammans med tidigare Android-back är raden komplett godkänd.
- Direktinskrivna webbadresser exponerade först blandad path/hash-routing (`/assistant#/home` och motsvarande för övriga ytor). En plattformssäker `usePathUrlStrategy()` infördes för webb, medan Android använder no-op-stub. Riktad analys och 19/19 routing-/grundtester passerade.
- Korrigerad releasewebb verifierades fysiskt: `/team`, `/calendar`, `/inbox` och `/assistant` behöll canonical path utan hash och öppnade rätt yta med återställd session/kontext. `REL02-I-02` är fortsatt partiell endast för riktiga eller fel-scope event-/trådparametrar.
- Webbens obefintliga UUID-fall passerade för både `/calendar?event=00000000-0000-0000-0000-000000000000` och motsvarande Inbox-tråd. Kalender respektive Inbox bestod med neutral information om att detaljen inte kunde laddas; ingen främmande data eller rå backendtext visades och navigationen fortsatte fungera.
- Fysisk kontroll visade därefter att detaljdialogerna inte speglade identiteten i URL:n. Kalender och Inbox fick canonical URL-synk vid öppning (`?event=`/`?thread=`) och återgång till grundroute vid stängning. Riktad analys samt 20/20 grund-/routingtester passerade.
- Korrigerad releasewebb verifierades med ett riktigt event och en riktig Inbox-tråd: adressen uppdaterades medan detaljen var öppen, återställdes vid stängning och kunde kopieras till ny flik där samma detalj laddades med bevarad session och `Thomas lag`. Endast verkligt cross-tenant/fel-scope-ID återstår och ingen live-testdata skapas för detta utan separat upplägg.
- `REL02-I-05` slutfördes i webbens lokala DevTools Offline-läge. Eventskapande misslyckades begripligt utan falsk framgång eller spökpost i listan; efter `No throttling` och refresh fungerade Kalender normalt. Tillsammans med tidigare stale/offline-refresh är raden komplett godkänd utan att testmutationen kunde nå Supabase live.
- Lokal webbsession/site-data rensades därefter i DevTools. Reload visade ren inloggning utan gammal lag-/persondata eller tekniskt fel; ny inloggning återställde `Thomas lag`. `REL02-I-07` har därmed fysisk fail-closed-/reauth-täckning, medan verklig serveråterkallelse/token-expiry fortfarande kräver separat hosted-auth-upplägg.
- Okänd webbpath `/inte-en-giltig-sida` visade neutral saknas-yta utan rå teknisk text eller data; normal navigation tillbaka till appen fungerade.

## Godkänd live-fixture och kontextbyte 2026-08-30

Efter produktägarens uttryckliga godkännande skapades en avgränsad andra lagkontext i den aktuella Supabase-testdatabasen. Ingen äldre TeamZone-databas eller separat produktionsmiljö ändrades.

- klubb-ID: `e423cb36-eaf3-44a5-b6d0-0406914a21ae`;
- tillfälligt lag-ID: `a2020000-0000-4000-8000-000000000001`;
- assignment-/kontext-ID: `a2020000-0000-4000-8000-000000000002`;
- team-assignment-ID: `a2020000-0000-4000-8000-000000000003`;
- audit command: `rel02.test_fixture.create.v1`.

Fixture-kontexten kopierade endast leader-kontots sju aktiva, befintliga capability-grants. Produktägaren körde därefter snabb växling `Thomas lag` → verifieringskontexten → `Thomas lag` i webbappen. Senast vald kontext bestod och inget sent svar skrev över valet. Tillsammans med den automatiserade stale-response-grinden är `REL02-I-04` därför godkänd.

Fixture-kontexten behålls tillfälligt för den återstående rollmatrisen. En exakt cleanup finns i `.tmp_rel02_second_context_cleanup.sql`; den får bara köras efter kontroll att inga nya event eller andra beroenden har skapats i fixture-laget.

## Player-/guardian-fixture 2026-08-30

Två separat registrerade och e-postverifierade testprofiler var autentiserade men låg korrekt fail-closed i väntrummet utan klubb-/lagrelation. Efter produktägarens livegodkännande kopplades den först skapade profilen till `player` och den senast skapade till `guardian` i befintligt testlag. Inga e-postadresser eller lösenord sparas i evidencen.

- player profile-ID: `9b46ff03-b1e0-43a8-909a-506fe39b7d31`;
- player context-ID: `a2030000-0000-4000-8000-000000000004`;
- guardian profile-ID: `30a042ce-0a84-47a8-b1fd-b0d551829ed4`;
- guardian context-ID: `a2030000-0000-4000-8000-000000000013`;
- guardian person-ID: `a2030000-0000-4000-8000-000000000011`;
- två aktiva child relation-ID:n: `a2030000-0000-4000-8000-000000000014` och `a2030000-0000-4000-8000-000000000015`;
- audit command: `rel02.role_fixture.create.v1`.

Setupen verifierade efter commit att båda kontexterna var aktiva och att guardian-personen hade exakt två aktiva barn. Exakt cleanup finns i `.tmp_rel02_role_fixture_cleanup.sql` och stoppar om eventkallelser har hunnit knytas till fixture-personerna.

### Spelare på desktop/webb

Produktägaren loggade in med den separata player-profilen och lämnade väntrummet med synlig spelarkontext. Hem och Trupp gav laddningsfel på grund av det kända glappet mellan lokala och livepublicerade projektioner, så `REL02-RD-06` är fortsatt partiell.

Behörighetsgränsen passerade fysiskt: inga ledaråtgärder visades, Kalender listade event men erbjöd inte eventskapande, EventDetails var läsbar men inte redigerbar och spelaren kunde inte administrera andras närvaro. Tom Inbox erbjöd tillåten `Nytt meddelande`, vars mottagarval begränsades till tränare och verifierad guardian-relation. Inget meddelande skickades.

### Vårdnadshavare på desktop/webb

Den separata guardian-profilen lämnade väntrummet med aktiv vårdnadshavarkontext och två serververifierade barnrelationer. Hem visade neutral `Kunde inte hämta innehållet` eftersom `get_guardian_home` ännu inte finns i liveprojektets publicerade migrationer. Därmed kunde den fysiska barnväljaren och acting-as-växlingen inte köras och `REL02-RD-09` förblir partiell.

Övrig fysisk behörighetskontroll betedde sig som förväntat: inga ledaråtgärder exponerades, eventdetaljer var läsbara men inte redigerbara och `Nytt meddelande` erbjöd endast coach som mottagare. Inget meddelande skickades.

### Klubbfunktionär på desktop/webb

Det breda klubbadministratörskontot hade korrekt tillgång till trupp- och eventredigering eftersom dess live-assignment uttryckligen innehåller `club.memberships.manage`, `event.manage` och `team.roster.view`. Rollen ensam gav alltså inte åtkomsten, men kontot var olämpligt som negativ kontroll.

Det separata begränsade klubbfunktionärskontot hade endast `board.read`, `board.approve`, `economy.read` och `economy.approve`. Fysiskt verifierades att kontot inte såg trupp eller event och hade tom Inbox. `Nytt meddelande` exponerade däremot hela klubbens mottagarlista.

Kodgranskning bekräftade att `internal.messaging_relationship_allowed` i den ännu ej livepublicerade MSG-02-migrationen också tillåter varje `club_functionary` att kontakta alla klubbmedlemmar enbart genom rollpaketet. Detta strider mot kravet på explicit klubbmandat och dataminimering. `REL02-RD-12` är därför `failed_messaging_recipient_scope`; inget meddelande skickades och korrigering/regression krävs före godkännande.

Defekten korrigerades i den separata migrationen `20260831045035_msg02_explicit_functionary_messaging_capability.sql`. Bred klubbkontakt kräver nu explicit `club.messaging.manage`; samma centrala relationspredikat används av mottagarprojektionen och av MSG-02:s skrivvägar. Funktionen ligger i `internal`, kontrollerar anropande identitet/aktiv assignment och är återkallad för direkt klientkörning.

Migreringen provkördes först i en återställd transaktion och applicerades därefter avgränsat på den godkända Supabase-testdatabasen utan övrig migrationsutrullning. Databassideverifiering med det begränsade kontots JWT-kontext gav exakt `0` mottagare. Riktat kontraktstest och analys passerade; performance advisor gav inga varningar och security advisor visade endast den separata befintliga projektinställningen att leaked-password protection är avstängd. `REL02-RD-12` väntar på fysisk webbregression innan raden kan godkännas.

Efter `Ctrl+F5` öppnade produktägaren `Inbox → Nytt meddelande` igen. Webbappen visade nu det neutrala beskedet att inga mottagare finns och exponerade inga klubbmedlemmar. Tillsammans med tidigare verifierad avsaknad av Trupp/Event för det begränsade mandatet är `REL02-RD-12` godkänd på desktop/webb.

### Ledarens mottagare och kontextisolering

Efter hårdningen visade ledarkontot först inga mottagare eftersom den aktiva kontexten var det tillfälliga, tomma `REL-02 verifieringslag`. Databassideverifiering med ledarens JWT och `Thomas lag` gav exakt tre tillåtna profiler: en player, en guardian och en club_functionary. När produktägaren bytte tillbaka till `Thomas lag` visade webbappen mottagarna korrekt. Detta godkänner både ledarens positiva mottagarfall och negativ isolering mot ett annat lag utan medlemmar.

### Ledare på desktop/webb

Produktägaren verifierade Trupp, Kalender, EventDetails samt deltagar-/närvaroåtgärder med det separata ledarkontot och bedömde dem som korrekta utan att spara teständringar. Kontots synliga ekonomi- och styrelseytor var inte rolläckage: liveinventeringen visade explicita `board.read`, `board.approve`, `economy.read` och `economy.approve` utöver `event.manage`, `team.roster.view` och `development.manage`.

`REL02-RD-03` är fysisk delpassering. Behörighetsdelen är godkänd, men Hem kan inte slutgodkännas förrän `get_leader_home` finns i liveprojektets publicerade projektioner.

## Avgränsad Home-/Trupp-miniutrullning 2026-08-31

Efter uttryckligt godkännande inventerades de tre saknade Home-RPC:ernas beroenden skrivskyddat. Alla relationer fanns live utom den privata `core.thread_personal_visibility`, som krävs för att dolda trådar inte ska räknas i player-/guardian-home.

En återkörningssäker prerequisite-migration `20260831055301_rel02_home_projection_runtime_prerequisites.sql` skapade endast denna tabell med RLS, fail-closed policy, index och återkallade klientgrants. HOME-01/02/03 gjordes idempotenta inför en senare ordinarie migrationskörning. Hela paketet provkördes först i en transaktion som rullades tillbaka.

Vid runtime-verifieringen upptäcktes att HOME-03 använde samma namn för PL/pgSQL-variabeln och kolumnen `guardian_person_id`. Variabeln döptes om till `guardian_actor_person_id`, riktat test/analysering passerade och funktionen applicerades återkörningssäkert.

Efter commit verifierades varje projektion med rätt JWT-kontext:

- leader context `d6c33c2f-a54c-4960-a470-b7d12650b469`: `role_package=leader`, tre planning actions;
- player context `a2030000-0000-4000-8000-000000000004`: `role_package=player`, lagstorlek fyra;
- guardian context `a2030000-0000-4000-8000-000000000013`: `role_package=guardian`, exakt två barn och giltigt explicit selected-child-ID.

Spelarens tidigare Trupp-fel var inte en saknad RPC: `api.list_club_people` fanns redan. Rollkontraktet kräver en begränsad laglista för player/guardian, men fixture-assignments saknade `team.roster.view`. Två exakta, team-scopade läsgrants (`a203…0016`/`a203…0017`) lades till och cleanupen utökades. JWT-verifiering gav fyra trupprader för vardera rollen; inga roster-skrivcapabilities tilldelades.

Performance advisor gav inga varningar. Security advisor visade endast den separata befintliga Auth-inställningen att leaked-password protection är avstängd. De tre roll-/desktop-raderna väntar på fysisk `Ctrl+F5`-regression innan status uppgraderas.

Ledarkontot kördes därefter fysiskt med `Thomas lag` efter `Ctrl+F5`. Hem laddade utan tidigare RPC-fel. Tillsammans med redan godkända Trupp-, Kalender-, EventDetails-, deltagar-/närvaro-, Inbox- och kontextisoleringskontroller är `REL02-RD-03` komplett godkänd på desktop/webb.

Player-profilen kördes därefter efter `Ctrl+F5`. Hem och den capability-scopade begränsade Trupp-listan laddade utan fel, medan redigera/flytta/arkivera/radera saknades. Tillsammans med tidigare godkända Kalender-, läsbara men ej redigerbara EventDetails- och relationsbegränsade Inboxkontroller är `REL02-RD-06` komplett godkänd på desktop/webb.

Guardian-profilen kördes därefter efter `Ctrl+F5`. Hem laddade två barn, visade valt acting-as och bytte barnkontext korrekt. Laget → Trupp visade den begränsade listan utan administrationsåtgärder. Den enda knappen var `Använd kod`, vilket är tillåten självservice för en utfärdad lagkod och inte rosteradministration. Tillsammans med tidigare godkända Kalender-/EventDetails-/Inboxgränser är `REL02-RD-09` komplett godkänd på desktop/webb.

## Guardian/telefon – lagets kalender 2026-08-31

Den fysiska guardian-körningen av Laget → Kalender visade först `Lagets kalender kunde inte laddas`. Orsaken var att lagvyn begärde tre år i ett enda anrop medan `api.list_calendar_page` avvisar intervall över 400 dagar. Klienttjänsten delar nu automatiskt längre intervall i sammanhängande fönster om högst 399 dagar och deduplicerar event som överlappar en fönstergräns. CAL-01-regressionstestet passerade 4/4, analysen var ren och produktägaren bekräftade efter ny webbbuild att lagets Kalender laddar. `REL02-RD-07` är därmed fysisk delpassering; återstående guardian-telefonytor verifieras separat.

Produktägaren verifierade därefter guardian/telefonens vanliga Kalender och ett EventDetails som fungerande med förväntad läsbehörighet. Inga otillåtna guardian-åtgärder rapporterades. Kalenderdelen av `REL02-RD-07` är godkänd; Inbox och mottagargränser återstår.

Guardian/telefonens Inbox fungerade därefter och `Nytt meddelande` exponerade endast den relationsmässigt tillåtna mottagaren `Coach Emilson`. Ingen bred klubbmedlemslista visades. Tillsammans med godkända Hem-/barnväxlings-, Laget-/Trupp- och Kalender-/EventDetails-kontroller är `REL02-RD-07` komplett godkänd.

## Guardian/tablet 2026-08-31

Produktägaren körde guardian-kontot i responsiv tabletviewport 800×1100. Hem visade båda barnen och vald barnkontext korrekt. Laget → Översikt, begränsad Trupp och Kalender fungerade utan rapporterad overflow, klippning eller otillåtna administrationsåtgärder; lagets händelselista laddade och filtreringen fungerade. Vanliga Kalenderns vyer samt EventDetails fungerade med guardianens läsgräns. Inbox fungerade och `Nytt meddelande` visade endast den relationsmässigt tillåtna `Coach Emilson`, utan bred klubbexponering. `REL02-RD-08` är komplett godkänd.

## Player/telefon 2026-08-31

Produktägaren körde den separata player-profilen i responsiv telefonviewport 390×844. Rollanpassat Hem, Laget → Översikt, begränsad Trupp och lagets Kalender fungerade utan rapporterad layoutavvikelse eller otillåtna administrationsåtgärder. Vanliga Kalendern och EventDetails fungerade med spelarens läs-/egen-deltagandegräns; återgången behöll Kalender och avslutade inte appen. Inbox fungerade och `Nytt meddelande` exponerade endast spelarens verifierade `guardian` och den relationsmässigt tillåtna `Coach Emilson`, inte andra spelare eller hela klubben. `REL02-RD-04` är komplett godkänd.

## Player/tablet och återanvänd direkttråd 2026-08-31

Player-profilen kördes i responsiv tabletviewport 800×1100. Hem, Laget → Översikt/begränsad Trupp/Kalender, vanliga Kalenderns vyer, EventDetails och Inbox fungerade utan rapporterade layoutfel eller otillåtna administrationsåtgärder. Mottagarurvalet begränsades till verifierad `guardian` och `Coach Emilson`.

Under kontrollen upptäckte produktägaren att `Nytt meddelande` skapade en ny direkttråd trots att samma två parter redan hade en konversation. Migreringen `20260831151938_msg02_reuse_existing_direct_threads.sql` ändrade den centrala backendkommandofunktionen så att den senaste aktiva direkttråden för samma klubb/profilpar återanvänds. Ett transaktionsbundet advisory lock serialiserar samtidiga förstaförsök; aktuell teamscope läggs till återkörningssäkert och återanvändningen revisions- och auditloggas utan att gammal historik raderas eller slås ihop. Kontraktstestet passerade 7/7, analysen var ren, rollback-beteendetest och driftsatt rollback-test gav `reused_existing_direct=true` respektive `deployed_reuse=true`. Advisor gav inga prestandavarningar och endast den redan kända Auth-varningen om avstängt leaked-password protection. Produktägaren verifierade därefter fysiskt att `Nytt meddelande → Coach Emilson` öppnade den befintliga konversationen med historiken. `REL02-RD-05` är komplett godkänd.

## Leader/telefon – lagscopad rosterhantering 2026-08-31

Vid `REL02-RD-01` visade ledarkontots Trupp först endast `Använd kod` och assistent-FAB. Kod- och liveinventering bekräftade att båda ledarkontexterna endast hade `team.roster.view`; all rosteradministration krävde det bredare `club.memberships.manage`. Detta stred mot det godkända rollkontraktet att ledaren ska administrera det egna laget utan implicit klubbadmin.

Migreringen `20260831153810_team_leader_scoped_roster_management.sql` tilldelade aktiva lagledare `team.roster.manage` och lät befintliga team-scopade rosterkommandon acceptera detta smalare mandat endast när ett konkret mållag finns. Klienten visar rosteradministration för team- eller klubbmandat men håller klubbomfattande `Skapa ytterligare lag` och `Klubbverifiering` bakom `club.memberships.manage`. Sju TEAM-testfiler passerade 26/26, analysen var ren och rollback-API-verifieringen gav `context_grant=true` samt `overview_manage=true`. Advisor gav inga nya fynd. Efter ny webbbuild verifierade produktägaren fysiskt att Medlemsansökningar, Hantera och personredigering visas korrekt medan klubbvalen förblir dolda. Truppdelen av `REL02-RD-01` är godkänd.

Leader/telefonens eventkontroll hittade därefter att liveprojektet saknade `api.save_squad_draft_v2`. CAL-06 applicerades avgränsat efter rollback-validering. Runtimekontrollen visade samtidigt att CAL-06 läser arkiveringsfält från den ännu ej publicerade CAL-04-kedjan. Eftersom CAL-02 och CAL-03 innehöll separata äldre parserdefekter och inte behövdes för draftflödet applicerades de inte. I stället lades den minimala idempotenta migreringen `20260831201834_cal06_runtime_archival_prerequisite.sql` till med arkiveringskolumner, shape-constraint och partiellt index. Ett återställt liveanrop gav `draft_saved=true`, varefter produktägaren skapade en riktig draft.

Vid fysisk `Lås trupp` föll CAL-06:s `internal.lock_squad_for_actor` på en positionsbaserad insert i `internal.command_deduplication`: kommandonamnet hamnade i en UUID-kolumn. Samma defekt fanns i `send_callups_for_actor`. Grundmigreringen och den avgränsade livekorrigeringen `20260831202517_cal06_fix_command_deduplication_inserts.sql` använder nu explicita kolumnlistor i båda funktionerna. Rollback-test mot den riktiga draften gav `locked=true`, CAL-06-kontraktstestet passerade 4/4 och advisor gav inga nya fynd. Produktägaren verifierade därefter fysiskt att truppen kunde låsas. Inga kallelser skickades under kontrollen.

Närvarokontrollen visade därefter `Närvarobehörigheten kunde inte kontrolleras`. Klienten anropade CAL-08:s `api.get_attendance_permissions`, som saknades live tillsammans med `record_attendance_v2`. Hela `20260827075525_cal08_atomic_attendance.sql` passerade rollback-validering mot den kompletterade CAL-06-miljön; ledarens publika API-kontroll gav `permissions=true`. Migreringen applicerades avgränsat, CAL-08-testet passerade 3/3 och advisor gav inga nya fynd. Produktägaren verifierade därefter att närvaroformuläret öppnas. Ingen närvarostatus sparades.

Leader/telefonens Inbox, trådlista, tillåtna mottagarurval, återanvändning av befintlig direkttråd och mobil återgång verifierades därefter utan avvikelse. Tillsammans med godkända Hem-, Laget-/Trupp-, Kalender-/EventDetails-, deltagardraft-/låsnings- och närvarokontroller är `REL02-RD-01` komplett godkänd.

## Leader/tablet 2026-09-01

Produktägaren körde ledarkontot i `Thomas lag` med responsiv tabletviewport 800×1100. Hem, Laget → Översikt/Trupp/Kalender, lagscopade rosteråtgärder, vanliga Kalenderns vyer, EventDetails, eventformulär, deltagardraft/låst trupp, närvarovy och Inbox fungerade utan rapporterade layout- eller behörighetsavvikelser. Klubbomfattande roster-/verifieringsval förblev dolda. Inbox behöll relationsgränser och återanvände befintlig direkttråd. Inga nya person-, kallelse- eller närvaroändringar sparades. `REL02-RD-02` är komplett godkänd.

## Club functionary/telefon 2026-09-01

Det begränsade klubbfunktionärskontot verifierades i mobilviewport 390×844. Hem visade de uttryckliga ekonomi-/styrelsemandaten men inga ledaråtgärder. Laget avslöjade först en klientavvikelse: en klubbkontext utan `team_id` behandlades som ett misslyckat lagöversiktsanrop. Klienten korrigerades så att inget rosteranrop görs utan lagkontext och visar i stället ett vägledande tomläge med `Använd kod`; regressionstestet godkändes 3/3 och den ombyggda webbversionen verifierades fysiskt. Kalendern exponerade inga otillåtna laghändelser eller eventåtgärder. Inbox exponerade inga mottagare utan tillåten relation. `REL02-RD-10` är komplett godkänd.

## Club functionary/tablet 2026-09-01

Samma begränsade klubbfunktionärskonto verifierades i tabletviewport 800×1100. Hem behöll endast de uttryckliga ekonomi-/styrelsemandaten. Laget visade det nya säkra tomläget med `Använd kod`; ingen lagöversikt, trupp, lagkalender eller administrationsåtgärd exponerades. Kalendern visade inga otillåtna laghändelser eller eventåtgärder. Inbox exponerade inga mottagare utan tillåten relation. Navigation Rail, layout och tillbaka-navigering fungerade. `REL02-RD-11` är komplett godkänd, och därmed är samtliga 12 roll-/enhetskombinationer fysiskt verifierade.

## Textskalning/tablet 2026-09-01

Webbläsaren kördes med 200 % zoom och DevTools-viewport 1600×2200, vilket gav en effektiv appyta motsvarande tablet 800×1100. Hem, Laget, Kalender och Inbox verifierades utan klippt eller överlappande text, horisontellt overflowfel eller trasig Navigation Rail. `REL02-A-03` är därmed godkänd för telefon, desktop/web och tablet.

## Deep links med fel scope 2026-09-01

Två befintliga objekt-ID:n valdes skrivskyddat i Supabase-testdatabasen: ett event och en aktiv tråd där det begränsade klubbfunktionärskontot inte var deltagare. Direkta länkar till `/calendar?event=…` respektive `/inbox?thread=…` öppnades med detta konto. Kalendern visade endast det neutrala tomläget `Inga event i vald vy`; Inbox visade endast `Inkorgen är tom`. Ingen titel, deltagare, meddelandetext, rå backendtext eller annan främmande data exponerades. Tillsammans med tidigare canonical-route-, riktiga behöriga ID- och obefintliga UUID-kontroller är `REL02-I-02` komplett godkänd.

## Reduced motion/webb 2026-09-01

Webbläsarens Rendering-emulering sattes till `prefers-reduced-motion: reduce`. Produktägaren växlade mellan Hem, Laget, Kalender och Inbox samt öppnade/stängde dialog. Navigation, status och återkoppling bestod utan flimmer, fastnat läge eller försvunna kontroller. Tillsammans med den automatiserade grinden är `REL02-A-05` godkänd för webben. Xiaomi-enhetens systemtoggle kunde tidigare inte aktiveras trots två försök och kvarstår dokumenterad som en enhetsspecifik begränsning, inte ett appfel.

## Serveråterkallad session 2026-09-01

Efter uttryckligt godkännande återkallades exakt en aktiv Supabase-session för det begränsade klubbfunktionärens testkonto. Ingen användare, profil eller verksamhetsdata raderades. Vid `Ctrl+F5` gick webbappen direkt till inloggningen och återställde ingen tidigare klubbdata. Tillsammans med den tidigare lokala site-data-/reauth-kontrollen är `REL02-I-07` komplett godkänd.

## Slutbeslut 2026-09-01

REL-01 är grön. REL-02:s 12 roll-/enhetsfall, sju avbrottsfall och fem tillgänglighetsområden är fullständigt verifierade och samtliga maskinläsbara rader är `passed`. Den slutliga automatiserade omkörningen passerade 44/44 app-, matris- och statuskontraktstester med `REL02_AUTOMATED_GATE_OK` efter att statuskontraktet uppdaterats från den tidigare medvetet låsta `partial`-fasen till slutstatus. Xiaomi Mi 9 saknar användbar systemtoggle för reducerad rörelse; motsvarande appbeteende passerade både automatiserad kontroll och fysisk webbemulering och begränsningen är uttryckligen dokumenterad. REL-02 stängs som godkänd.

## Fixture-cleanup 2026-09-01

Produktägaren godkände cleanup i den aktuella Supabase-testdatabasen. Skrivskyddad inventering visade att den ursprungliga raderingsfilen inte längre var säker att köra: fixture-personerna hade två kallelser, två truppsnapshot-rader, sex tråddeltaganden och fyra skickade meddelanden. En första transaktion stoppades av en foreign key och rullades tillbaka helt. Den korrigerade cleanupen tog därefter bort det tomma `REL-02 verifieringslag` och dess kontext, men avslutade i stället för att radera player-/guardian-assignment, teamkopplingar, guardianrelationer, kontolänkar, capabilities och aktiva tråddeltaganden. Person- och klubbpersonsposter markerades avslutade så historiska referenser förblev giltiga.

Efterkontrollen gav 0 kvarvarande extralag, 0 aktiva fixture-assignments, 0 aktiva fixture-kontolänkar, 0 aktiva guardianrelationer och 0 aktiva fixture-tråddeltaganden. Två historiska kallelser och fyra historiska meddelanden finns kvar. Ordinarie ledarkonto och begränsat klubbfunktionärskonto har vardera exakt en aktiv kontext, och exakt ett ordinarie aktivt lag finns kvar. Cleanupen auditloggades som `rel02.test_fixture.cleanup.v1`. Auth-kontona raderades inte.
