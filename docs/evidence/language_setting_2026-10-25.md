# Språkval under Personligt – 25 oktober 2026

Implementerat lokalt efter användarens önskemål. Ändringen är inte driftsatt.

Under **Inställningar → Personligt → Språk** kan användaren välja:

- Enhetens språk (standard).
- Svenska.
- English.

Valet ändrar appens locale direkt utan utloggning och sparas på enheten
med SharedPreferences (`teamzone.language`). Enhetens språk tar bort
åsidosättningen. Valet synkas inte mellan enheter och ändrar inte
användarskrivet innehåll, som övningsnamn eller anteckningar.
Samma inställning finns när Personligt visas inbäddat i profilsidan.

Språkpreferensen kopplas in både med och utan konfigurerad backend.
Okända sparade språkvärden använder enhetens språk. Ett sent återläst
värde skriver inte över ett nytt val som användaren redan gjort.
Vid skrivfel gäller valet fortfarande i sessionen och appen visar att
det inte kunde sparas. Läsfel loggas och lämnar enhetens språk aktivt.

Ett UI-test verifierar växling svenska → engelska på inställningssidan,
att sidan stannar kvar, att engelskan återställs efter omstart och att
Enhetens språk återgår till enhetens locale och tar bort det sparade valet.
Språk-, roll-, tränings- och inställningsregressioner: **45 tester godkända**.
Statisk analys av samtliga sex berörda Dart-filer: **inga fynd**.
Manuell engelsk acceptans av driftsatt app återstår.
