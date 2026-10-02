# Min assistent – kontextanpassade ledaruppgifter

## Omfattning

Första leveransen återanvänder `get_leader_home` och `get_event_details`.
Ingen databasändring, ny signaltröskel, generativ AI, pushleverans eller
aktivering av AC-01 ingår. Den befintliga oberoende HOME-05-projektionen
är fortsatt källa för obesvarade kallelser och saknad närvaro.

## Beteende

- Hem visar **Mina uppgifter** från användarens ledarkontexter.
- Andra sidor visar **Här och nu** för aktuellt lag. Eventdetaljer begränsar
  den delen till det öppnade eventet. Övriga uppgifter finns under **Mina uppgifter**.
- Samma event/uppgift visas endast en gång. Närvaro prioriteras före kallelser,
  därefter sorteras korten på aktivitetens tidpunkt.
- Korten visar klubb, lag, eventtitel, tid, antal och en expanderbar förklaring
  med källa och hämtningstid. Ingen deltagares namn eller kontaktuppgift visas.
- Länkar öppnar deltagarfliken med uppgiftens uttryckliga lagkontext. Sidhuvudet
  visar klubb och lag även om uppgiften öppnades från ett annat lags överblick.
  Användarens globala lagval ändras inte av ett sådant besök.
- Återgång från event laddar om uppgifterna. Desktoppanelen uppdateras även
  efter registrering i eventet. Manuell uppdatering och återgång till appen
  hämtar också nya uppgifter.
- Mobilens ursprungssida hämtas från den översta GoRouter-routen, inte bara
  webbadressen. Detta behövs för sidor öppnade med `push` på Android.

## Behörighet och fel

Serverns befintliga behörighetskontroll gäller för varje läst ledarkontext
och event. Klienten filtrerar dessutom på de två aktuella capabilities.
Assistenten använder en färsk läsning utan översiktens vanliga cachefallback:
återkallad behörighet får inte lämna kvar gamla uppgifter som aktuella.

Fel i en kontext tar bort dess delvis hämtade uppgifter och märker överblicken
som ofullständig; andra lyckade kontexter kan fortfarande visas. Ett tomt
felresultat betyder inte att allt är klart. Eventåtgärder går genom ordinarie
deltagarvy och serverkommandon. Okända explicita kontext-id:n i eventlänken
leder till ej-hittad-vyn.

Datakällans befintliga avgränsningar är kvar: närvarouppgiften räknar accepterade
kallade utan närvarofaktum på event som slutade de senaste sju dagarna.
Det hindrar inte registrering av okallade deltagare i deltagarlistan.
Metadata hämtas en gång per unikt event under en uppdatering; en framtida
samlad serverprojektion kan minska antalet anrop vid stora mängder uppgifter.

## Verifiering

- Nya modell-/widgettester: sidkontext, roll/capabilityfilter, externa länkar,
  deduplicering, färsk behörighet, partiella fel, gammal data, återförsök,
  kontextbyte och borttagning efter åtgärd.
- Integrationstester i `cal11_event_details_page_test.dart`: assistent →
  deltagarflik → assistent samt event → kontextanpassad assistent.
- De 30 testerna i assistentens nya testfil och CAL-11-filen passerar.
- Hosted read-only-kontroll bekräftar att båda befintliga API-endpoints finns
  och att ledarprojektionen kontrollerar aktörens kontexter samt squad- och
  attendance-capabilities.
- Slutlig `flutter analyze --no-pub`: inga anmärkningar.
- Slutlig full Flutter-testsvit: **544/544 passerar**.
- Webbens releasebygge mot auditprojektet passerar.
- Android debugbygge mot auditprojektet passerar. SDK/Kotlin-pluginvarningar
  finns i byggverktygen men blockerar inte bygget.
- S25 är inte ansluten; fysisk S25-verifiering återstår.
- Denna leverans är byggd lokalt; ingen hostingpublicering eller installation
  på telefon har gjorts.

## Senare leveranser

Planeringsluckor, ofärdig planering, positiva signaler och andra specialistområden
följer sina beslutade datagrindar. Historik, avfärdning och notifieringsbudget för
signaler aktiveras inte genom denna presentation av befintliga uppgifter.
