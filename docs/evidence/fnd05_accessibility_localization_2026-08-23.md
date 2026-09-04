# FND-05 – Tillgänglighet och lokalisering

**Datum:** 2026-08-23  
**Status:** VERIFIERAD  
**Omfattning:** Lokal Flutter-klient och fysisk Android-smoke. Ingen livebackend, webtools, workspace eller provisionering.

## Implementerade förbättringar

- Inloggningens e-post/lösenord har explicit tangentbordsordning `next`/`done` och ligger kvar i `AutofillGroup`.
- Kontextväljaren i appbaren kan krympa vid stor text, ellipsiserar visuellt och exponerar hela namnet via tooltip.
- `AppStateCard` är rullbart när stor text gör innehållet högre än tillgänglig viewport.
- Kvarvarande `Match`, `Trupp` och `Minimal rosterprofil` i prioriterade ytor går genom localegränsen.
- Ett permanent kontrakt förbjuder globala textskalebegränsningar och kräver 48 px, semantik, fokus, reduced motion, AA-kontrast och textburen status.

## Automatiserad verifiering

- Touchmål i Filled/Outlined/Text/IconButton: minst 48×48.
- WCAG AA-kontrast för primary/onPrimary, surface/onSurface och error/onError i ljust och mörkt tema.
- `AppMotion.accessible` returnerar noll varaktighet vid reduced motion.
- Tangentbords-Tab flyttar fokus från e-post till lösenord; actions är `next` och `done`.
- Produktens autentiserade shell körs med 200 % text på 390×844, 800×1100 och 1440×900 utan overflow.
- Alla renderade IconButtons i shell har textalternativ.
- Prioriterade auth/home/team/calendar/inbox/shell-filer kontrolleras mot localeordlistan och direkt hårdkodad användartext nekas.
- Riktad FND-05/UX-svit: **15/15 passerar**.
- Full regressionssvit: **113/113 passerar**.
- `flutter analyze`: **No issues found**.

## Manuell/fysisk Android-kontroll

- Enhet: Samsung SM-S931B, 1080×2340, density 480.
- Uppdaterad lokal debug-APK installerades som `com.teamzone.teamzone`.
- Systemets font scale höjdes reversibelt från 1,0 till 2,0.
- Kallstart lyckades på 1 046 ms.
- TeamZone-rubrik, miljötext, felrubrik och full säker feltext var läsbara; inget visuellt overflowband syntes.
- UI-semantiken exponerade rubrik och full feltext, inte enbart verktygsikonen.
- Inga Flutter- eller AndroidRuntime-fel hittades i avgränsad logcat.
- Font scale återställdes i `finally` och verifierades därefter som 1,0.

Kontrollen gällde den lokala fail-closed-vyn eftersom ingen livebackend fick användas. Autentiserade huvudytor vid 200 % täcks av widgetmatrisen.

### Kompletterande Mi 9-kontroll 2026-08-28

- En autentiserad Xiaomi Mi 9-körning vid 200 % hittade att sex permanenta etiketter i mobilens `NavigationBar` bröts och klipptes, främst `Kalender` och `Utveckling`.
- Vid textskala 150 % eller högre visar navigationen nu endast etiketten för vald flik. Alla sex ikoner och deras fulla semantiska fliknamn finns kvar.
- Två saknade engelska menytexter som lokaliseringsgrinden samtidigt upptäckte (`Fler inkorgsåtgärder`, `Slå på notiser`) lades till.
- Riktad tillgänglighets-/lokaliseringskörning passerade 9/9 och analys av ändrade filer var ren.
- Audit-debugbuild `AA01C48FD01453EEF4AB6F46324ED2CD6D5CAFFC31952C0CF2F71BAFFF305CB5` installerades. Fysisk omkörning vid 200 % visade vald `Hem`-etikett och sex intakta ikoner utan brutna eller klippta navigeringstexter.
- Telefonens font scale återställdes och verifierades som 1,0 efter körningen.

### TalkBack-passering på Mi 9 2026-08-28

- TalkBack verifierades aktivt och produktägaren genomförde fysisk svepnavigering på Hem, Laget, Kalender inklusive Månad, Inbox, en direkttråd och Min assistent.
- Rubriker, felcopy, appbaråtgärder, flikar, kalenderkontroller, trådmetadata, composer, assistentkontext och medicinsk avgränsning lästes begripligt i logisk fokusordning.
- Färg var inte ensam informationsbärare, ingen namnlös kontroll eller fokusfälla rapporterades och Android-back från assistenten återgick korrekt.
- Inget meddelande skickades och ingen live-data ändrades under kontrollen.

## Kontrakt

- `docs/implementation/accessibility_localization_contract.md`
- `test/fnd05_accessibility_localization_test.dart`
