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
| Bilder | `editor.png`, `verktyg.png`, `ytor.png`, `demo.mp4` | svenska i bild, se steg 9 |

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
| 6 | Livegenomgångar | Klart lokalt |
| 7 | Backend: Stripe `locale` från språket, språk på kontot, ångerkvitto, Auth-mejl med `{{ if eq .Data.locale "en" }}` | Nästa |
| 8 | Publika sajten och juridiken, efter att de svenska texterna är granskade | |
| 9 | Skärmbilder och demofilm på engelska | |
| 10 | Hela köpflödet på engelska, flaggan på i produktionen | |

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
