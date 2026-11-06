# Tacticsboard på engelska

Beslutat 2026-11-05: Tacticsboard ska finnas på engelska när det lanseras, cirka
2026-11-16. Det ersätter raden "Andra språk än svenska" under det som väntar i
[tacticsboard-product.md](tacticsboard-product.md).

## Vad som ska bli engelskt

Omfattningen är allt en köpare eller tittare möter, inte resten av Webtools.
Bokningar, turneringar och aviseringar förblir svenska, eftersom de är stängda i
produktionen.

| Del | Var | Omfattning |
| --- | --- | --- |
| Skal, start, inloggning, konto | `webtools/components/`, `webtools/app/` | cirka 10 filer |
| Produktsida och köp | `TacticsProduct`, `RequireTacticsboard`, `TacticsboardSubscription`, `WithdrawPurchase` | cirka 6 filer |
| Editorn | `components/tactics/` med paneler, tidslinje och export | cirka 40 filer |
| Hem, bibliotek, mappar, delning | `home/`, delade sidor, OG-bilder | cirka 30 filer |
| Livegenomgångar | `components/tactics/live/` | cirka 15 filer |
| Texter i `lib/tactics/` | mallar, övningar, fel, formationer | cirka 25 filer |
| Backend | Stripe-språk, ångerkvitto, fel från funktionen, fyra Auth-mejl | se steg 7 |
| Publika sajten | landningssidan, sidfoten, tre juridiksidor | se steg 8 |
| Bilder | `editor.png`, `verktyg.png`, `ytor.png`, `demo.mp4` | klart, se steg 9 |

Totalt 113 filer och drygt 650 rader med svensk text i Webtools.

## Så fungerar det

- **Språket väljs** med en länk i sidfoten och sparas i kakan `tz_lang`, som delas
  av `teamzoneapp.se` och `webtools.teamzoneapp.se`. Utan val styr webbläsaren:
  svenska om den föredrar svenska, annars engelska.
- **Adresserna ändras inte.** En delningslänk fungerar likadant för alla, och
  mottagaren får sitt eget språk. Bara juridiksidorna får egna engelska adresser,
  så att en länk alltid pekar på en bestämd text.
- **Svenskan är nyckeln.** Koden skriver `t("Logga in")`, och `lib/i18n/en/`
  översätter. Då blir koden läsbar, inga nycklar behöver hittas på, och befintliga
  tester som läser svensk text fortsätter att gälla.
- **Inget bibliotek.** Vi behöver två språk och enkla platshållare (`{email}`).
  Det är ett 60-tal rader egen kod.
- **Komponenter** använder `useT()`. **Serverkomponenter** använder
  `await serverT()`. **`lib/`** behåller svensk data, som översätts när den visas,
  eller tar emot `t` som argument. Det finns inget globalt språk, eftersom servern
  renderar åt flera personer samtidigt.
- **Datum och tal** går via `useLocale()` i stället för fast `sv-SE`. Stockholmstid
  behålls där tiden är juridiskt viktig.
- **Vakten:** `tests/i18n.test.ts` underkänner en `t("...")` som saknar engelska,
  och svenska texter utanför `t()` i de områden som är klara.
- **Halvfärdigt syns inte.** Engelska är avstängt tills `TACTICSBOARD_ENGLISH=on`
  sätts. Vi kan alltså driftsätta under arbetet, och sätter flaggan i produktionen
  först när allt är klart.

## Ordlista

Brittisk engelska, som i fotbollen.

| Svenska | Engelska |
| --- | --- |
| taktiktavla, tavla | tactics board, board |
| plan | pitch |
| övning | drill |
| träningspass | training session |
| trupp | squad |
| ledare | coach |
| förlopp, steg | sequence, step |
| livegenomgång | live session |
| bibliotek | library |
| mapp | folder |
| prenumeration | subscription |
| provperiod | free trial |
| ångra köpet | withdraw from the purchase |

## Steg

| # | Vad | Status |
| --- | --- | --- |
| 1 | Språkgrunden: val, kaka, `t`, vakten, språkväljaren | Klart |
| 2 | Skal, start, inloggning, konto | Klart |
| 3 | Produktsidan och köpet, med priser och ångerfunktion | Klart |
| 4 | Editorn, inklusive export och pdf | Klart |
| 5 | Hem, bibliotek, mappar, delade sidor och OG-bilder | Klart |
| 6 | Livegenomgångar | Klart |
| 7 | Backend: Stripe `locale` från språket, språk på kontot, ångerkvitto, Auth-mejl med `{{ if eq .Data.locale "en" }}` | Klart lokalt, se nedan |
| 8 | Publika sajten och juridiken, efter att de svenska texterna är granskade | Nästa |
| 9 | Skärmbilder och demofilm på engelska | Klart lokalt, se nedan |
| 10 | Hela köpflödet på engelska, flaggan på i produktionen | |

## Steg 7: backend

- **Språket i betalningen.** Webtools skickar `locale: "en"` till `tacticsboard-billing` bara på engelska. Svenska anrop ser ut som förut. Checkout och kundportalen öppnas då på brittisk engelska, med samtycket på engelska.
- **Ordning vid driftsättning.** Funktionen avvisar okända fält, så den ska driftsättas innan flaggan slås på. Så länge flaggan är av skickas inget nytt fält.
- **Språket på kontot.** Sparas som `locale` i kontots användardata när kontot skapas och när någon använder Webtools med flaggan på. Mejl som skickas utan inloggning går efter det. Konton utan värde får svenska.
- **Ångerkvittot** går på det språk personen använder när hen ångrar. Mejlet till supporten är kvar på svenska.
- **Mejlmallarna** i `supabase/templates/` är nu på båda språken och ska klistras in på nytt under Authentication → Emails, först i test och sedan i produktion. Konton utan värde får svenska, så det påverkar ingen befintlig användare.
- **Ämnesrader** att klistra in. Prova dem i test först. Följer inte ämnet språket eller stoppas mejlet, använd i stället båda språken i samma rad:
  - Confirm signup: `{{ if and .Data.locale (eq .Data.locale "en") }}Confirm your email address{{ else }}Bekräfta din e-postadress{{ end }}`
  - Magic link: `{{ if and .Data.locale (eq .Data.locale "en") }}Your code to sign in{{ else }}Din kod för att logga in{{ end }}`
  - Reset password: `{{ if and .Data.locale (eq .Data.locale "en") }}Choose a new password{{ else }}Välj ett nytt lösenord{{ end }}`
  - Change email: `{{ if and .Data.locale (eq .Data.locale "en") }}Confirm your new email address{{ else }}Bekräfta din nya e-postadress{{ end }}`
- **Villkoren.** Det engelska samtycket länkar till `https://public.teamzoneapp.se/en/terms/tacticsboard`, som skapas i steg 8. Texten ska granskas med de andra engelska juridiktexterna.
- **Provat 2026-11-05 i produktionen:** bekräftelsemejlet kom på engelska, från en lokal sida med engelska på. Länken landade på den svenska sidan, eftersom flaggan är av i produktionen. Lösenordsmejlet följer språket som är sparat på kontot, och det ändras bara när man är inloggad med flaggan på. Efter en inloggning med svenska vald kom det på svenska, så båda språken är provade. Utloggad går sidans språk inte att föra över till mejlet, och det får vara så.
- **Kvar att prova i steg 10:** att Stripes kvitton och fakturamejl kommer på engelska efter ett engelskt köp, och att länkarna i mejlen landar på engelska med flaggan på. Sidan följer kakan och webbläsaren, inte kontot, så en länk som öppnas i en annan webbläsare kan bli svensk.

## Steg 9: bilder och film

- **Ett nytt demoprojekt** med påhittade lag och spelare ersätter projektet med riktiga spelares namn, på båda språken. Hemmalaget heter Blå/Blue och bortalaget Röd/Red.
- **Bilder per språk:** `verktyg.png` och `editor.png` har var sin `-en`-version. `TacticsProduct` väljer efter sidans språk.
- **Bara en version:** `ytor.png` och filmen har ingen text. Filmen är 7,5 sekunder utan ljud och klubbmärke, och väger 0,5 MB i stället för 6 MB. Dess första bild är affischen, `demo-poster.jpg`, så att ingen svensk text syns innan filmen startar.
- **Steg 8:** den engelska landningssidan ska använda `editor-en.png`. Den svenska använder `editor.png` och får den nya bilden när Webtools driftsätts.
- **Så togs de:** projektet laddades i `/tacticsboard/demo` i Chrome utan fönster. Filmen är tavlans uppspelning bild för bild, utan knappar.

## Förhandsvisning av länkar

En delad länks titel och bild i en chatt följer språket i begäran. Chatttjänster anger
oftast inget språk, och då blir det svenska. När språket finns på kontot (steg 7) bör
förhandsvisningen följa ägarens språk.

Steg 8 beror på den juridiska granskningen. Engelska villkor är en översättning av
den text som godkänns, så de kan inte bli klara förrän den svenska texten är det.

## Beslut som behövs

1. **Valuta:** bara kronor vid lanseringen, eller även euro? Rekommendation: kronor.
   Stripe visar en köpare utomlands priset i kronor, och banken växlar. Euro kräver
   nya priser i Stripe och i databasen.
2. **Moms utanför Sverige:** bara Sverige är registrerat i Stripe. Köper en konsument
   i ett annat EU-land innan OSS är registrerat tas ingen moms ut, men momsen kan
   ändå behöva redovisas. Stäm av med redovisningskonsulten. Köpare utanför EU är
   en egen fråga. Rekommendation: marknadsför inte utomlands förrän OSS är klart.
3. **Vilken text gäller vid tvist:** rekommendation: engelska versionen är en
   översättning och den svenska gäller. Hör med den som granskar, eftersom en
   konsument i ett annat EU-land kan ha rätt till sitt eget lands konsumentskydd.
4. **Granskning av översättningen:** de engelska juridiktexterna bör granskas som de
   svenska.

## Inte med

- TeamZone-appen, bokningar och turneringar.
- Supportens granskning av anmälningar. Anmälningar sparas på svenska, och supporten läser dem på svenska.
- Text som användarna själva skrivit, till exempel namn på tavlor och innehåll i
  delade bibliotek.
- Fler språk än två. Lösningen kan bära fler, men de ingår inte.
