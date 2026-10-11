# Statusrapport för TeamZone, 11 oktober 2026

En genomgång av hela appen den 11 oktober 2026, efter commit `a7d9a63`. Ingen
kod ändrades under genomgången. Underlaget är läsning av kod och
dokumentation, läsfrågor mot testprojektets databas, `npm audit`,
`pub outdated` och en körning av alla lokala SQL-tester.

## Sammanfattning

TeamZone är långt kommet som produkt. Grunden och de flesta funktionerna är
byggda och verifierade mot testmiljön, och databasen är i grunden mycket väl
skyddad. Det finns ingen produktionsmiljö än. Inför en lansering är fyra saker
viktigast:

1. **Den publika webbplatsen kör en Next.js-version med kritiska
   säkerhetshål.** Detta bör åtgärdas först.
2. **Databasens migreringslogg stämmer inte med repot.** Det kan inte visas att
   databasen motsvarar koden.
3. **Release-bygget är signerat med felsökningsnyckeln.** Appen kan inte
   publiceras på Play så här.
4. **Viktiga delar är inte igång:** push-notiser skickas inte, iOS är aldrig
   byggt, och flera funktioner väntar på kontroll på riktig enhet.

## 1. Aktuell status

### Omfattning

| Del | Storlek |
|---|---|
| Flutter-appen (`lib/`) | 66 400 rader, som ett enda bibliotek uppdelat i 42 delfiler |
| Tester (`test/`) | 94 filer och 23 300 rader; 676 tester går igenom |
| Databas | 319 migreringar, 385 publika API-funktioner och 539 interna |
| SQL-tester (PGlite) | 40 tester; alla går igenom |
| Edge Functions | 11 st (betalning, Stripe, notiser, radering, support, media m.fl.) |
| Publik webbplats | Next.js 16 på Firebase App Hosting |
| Övrigt | Firebase-funktioner (övervakning), separat repo för laget.se-agenten |

### Leveransläge enligt dokumentationen

- **Byggstegen S00–S10 är stängda** inom sin godkända omfattning: identitet,
  trupp, kalender, kallelser, närvaro, Inbox, matchläge, utveckling,
  publicering och ekonomi.
- **S11, arbetsytor och webbverktyg, är uppskjutet.** Knappen Arbetsytor är
  bara en platshållare.
- **Driftsättning i produktion (X-OPS-01) återstår.** Det som finns är manifest
  och runbooks.
- **Våg 10 och flera kärnkort, till exempel AUTH-01/02/07, PUB, MSG och HOME,
  står som delvis klara.** De är automatiskt testade och kontrollerade i
  testmiljön, men kontrollen på riktig telefon och surfplatta återstår.
- **Allt körs i testprojektet.** Betalningen körs i Stripes sandlåda för en
  pilotklubb, och den publika webbplatsen är i drift men ännu inte publik.

## 2. Säkerhetsläget

### Det som är bra

Databasen kontrollerades med läsfrågor. Det här är en mycket stark grund:

- API:et exponerar bara schemat `api`. Tabellerna nås aldrig direkt: anonyma
  och inloggade har noll tabellrättigheter.
- RLS saknas bara på interna tabeller, och de kan inte nås utifrån.
- Alla 558 funktioner som körs med förhöjda rättigheter har en fast
  `search_path`.
- Anonyma kan bara köra en enda funktion, en triggerfunktion som de ändå inte
  når.
- Inget GraphQL-API är påslaget. Alla 8 lagringsbuckets är privata, med
  policyer och filtyps- och storleksgränser.
- Inloggningen använder PKCE. Stripe-signaturen kontrolleras, och arbetarnas
  åtkomstnycklar jämförs i konstant tid.
- Repot innehåller inga hemligheter, bara publika nycklar och `.env.example`.
- Laget.se-agenten lyssnar bara på den egna datorn och kontrollerar Host och
  Origin. Inloggningscookies och personuppgifter ignoreras av git.

### Brister, efter allvarlighet

| # | Allvar | Brist | Åtgärd |
|---|---|---|---|
| 1 | Kritisk | Den publika webbplatsen kör `next@16.3.1`. Den har kända säkerhetshål som tillåter fjärrkörning av kod via bildoptimeringen och `next/og`, förfalskade serveranrop och förgiftning av sidcachen. `sharp` och `source-map-js` har också allvarliga hål. | Uppgradera till den senaste 16.3.x-patchen (16.3.8 eller senare), kör testerna och driftsätt. |
| 2 | Hög | Firebase-funktionerna har ett kritiskt hål i `proxy-addr` och ett allvarligt i `@grpc/grpc-js`. | `npm audit fix` och driftsätt. |
| 3 | Hög (drift) | Migreringsloggarna stämmer inte (se 3.1). | Stäm av och dokumentera. |
| 4 | Medel | Release-bygget signeras med felsökningsnyckeln, och koden krymps inte. | En egen release-nyckel och Play App Signing före första publicering. |
| 5 | Medel | Inloggningsfunktionen `auth-password-sign-in` har ingen CAPTCHA och skickar inte vidare användarens IP-adress till Auth. Auth ser då funktionens adress, så spärren mot gissade lösenord kan antingen slå mot alla samtidigt eller inte fungera. CORS tillåter också `http://localhost` i produktion. | Verifiera hur spärren beter sig, överväg Turnstile, och styr de tillåtna ursprungen per miljö. |
| 6 | Medel | Skyddet mot läckta lösenord kräver Supabase Pro. Det är dokumenterat som ett krav före produktion. Den lokala `config.toml` har minsta lösenordslängd 6, medan policyn kräver 12. | Pro i produktion; synka den lokala konfigurationen. |
| 7 | Medel | Den driftsatta Flutter-webben på Firebase Hosting saknar CSP och `frame-ancestors`, så sidan kan bäddas in för klickkapning. | Lägg till säkerhetshuvuden i `firebase.json`. |
| 8 | Låg | Firebase-nyckeln i `google-services.json` och `firebase_options.dart` är publik av design. | Begränsa den i Google Cloud till app-ID och certifikatets fingeravtryck. |
| 9 | Låg | Appens egen länkadress `teamzone://` har ingen verifierad App Link. Risken minskas av PKCE. | Byt till verifierade App Links med `https` i samband med en egen domän. |
| 10 | Låg | `internal.broadcast_message_invalidation()` kan köras av alla roller. | Ta bort rättigheten från PUBLIC (hygien). |

**Personuppgifter:** stödet för radering, gallring och skyddade identiteter
finns. Det öppna policybeslutet om publicering av namn på arkiverade och
minderåriga spelare måste fattas före extern lansering. Laget.se-exporten
skickar personuppgifter via den lokala agenten och ska tas bort med tiden.

## 3. Vad som behöver åtgärdas i koden

### 3.1 Migreringsloggarna stämmer inte (viktigast)

- Repot har 319 migreringar. Supabase egen logg
  (`supabase_migrations.schema_migrations`) har 274, senast från 2026-10-04.
  `internal.migration_provenance` har 292.
- 85 migreringar saknas i Supabase-loggen, eftersom de körts för hand i
  SQL-editorn.
- 12 migreringar finns i ingen av loggarna. Funktionerna verkar fungera, men
  det går inte att visa att de körts i exakt den version som ligger i repot:
  - `20260925070651_pub03_disambiguate_editorial_draft_save`
  - `20260925175025_pub02_projection_reconciliation`
  - `20260925175933_pub02_publication_worker_delivery`
  - `20260925182837_pub02_public_directory_search`
  - `20260925203332_pub07_account_follows_and_feed`
  - `20260925203446_pub07_explicit_public_match_results`
  - `20260926012847_pub08_team_event_visibility`
  - `20260926060124_pub08_invalidation_queue_keys`
  - `20260926062708_pub09_personal_dashboard_content`
  - `20260926070459_match_direct_result_registration`
  - `20260926150243_match_written_reports`
  - `20260926154246_team_follow_notifications`
- **Risk:** en `supabase db push` skulle försöka köra om 85 migreringar, och
  många av dem är inte skrivna för att tåla omkörning. Ingen kan heller
  garantera att testmiljön motsvarar repot inför en produktionsmiljö.
- **Åtgärd:** jämför schemat i testmiljön mot repot med en läsjämförelse, till
  exempel `supabase db diff`. Markera de faktiskt körda migreringarna i
  loggen, och bestäm ett enda sätt att köra migreringar framöver.

### 3.2 Buggar och felrisker

- **Den engelska versionen kraschar på två felvägar.** `AppStrings.feature()`
  kastar ett fel när en engelsk text saknas. Två felmeddelanden saknar
  engelsk text:
  - "Delningen kunde inte sparas. Ladda om och försök igen." i
    `event_details_page.dart`;
  - "Kallelsen kunde inte ändras. Listan kan ha ändrats. Ladda om och försök
    igen." i `event_participants.dart`.

  På engelska slutar felmeddelandet alltså i ett nytt fel. Kontrolltestet för
  översättningar fångar inte meddelanden som sträcker sig över flera rader.
  **Åtgärd:** lägg till texterna, låt `feature()` falla tillbaka till svenska
  och logga i release-läge, och skärp kontrolltestet.
- **210 ställen med `catch (_)`.** Felen sväljs, och de flesta rapporteras inte
  till Crashlytics. Det gör buggar i produktion osynliga.
- **Felrapportering finns bara på Android.** Webben och iOS har ingen.

### 3.3 Kodstruktur och underhåll

- **Mycket stora filer:**

  | Fil | Rader |
  |---|---|
  | `roster_surface.dart` | 6 427 |
  | `inbox_surface.dart` | 3 797 |
  | `calendar_surface.dart` | 3 514 |
  | `product_shell.dart` | 2 297 |
  | `match_mode_page.dart` | 2 087 |

  Hela appen är ett enda bibliotek med 42 delfiler, så alla privata klasser är
  synliga överallt. Det gör ändringar riskablare och testning av enskilda
  delar svårare. Bryt ut dialoger och vyer till egna filer stegvis, när de
  ändå ändras. Undantaget är laget.se-exporten, som redan är ett eget
  bibliotek.
- **Samma databasfunktion definieras om i många migreringar**, till exempel att
  skapa event och matchens arbetsyta. Det är svårt att se vad som gäller nu.
  Inför en schemaöversikt eller samlade migreringar inför produktion, och en
  kontroll mot den driftsatta versionen före varje omskrivning.
- **Lint-reglerna är bara standardpaketet** `flutter_lints`. Överväg striktare
  regler, till exempel om oanvända resultat och async-luckor.
- **Gamla data i eventfälten:** träningsplan, agenda med mera ligger kvar i
  databasen men kan inte längre ändras. Det behövs ett beslut om att flytta in
  dem i Förberedelser eller rensa dem.

### 3.4 Beroenden och verktyg

- **Flutter-paketen ligger efter:**
  - `file_picker` 10 → 13, en ny huvudversion;
  - `go_router` 17 → 18, en ny huvudversion;
  - `supabase_flutter` 2.16 → 2.18, och Firebase-paketen;
  - en ny Flutter-version finns.

  Versionerna är låsta exakt, vilket är bra, men de behöver uppdateras
  regelbundet.
- **Ingen CI.** Det finns ingen `.github/workflows`. Alla 676 Flutter-tester,
  40 SQL-tester och 58 webbtester körs bara för hand. Inför GitHub Actions med
  analys och alla tester vid varje push, plus `npm audit` och `pub outdated`.
- **SQL-testerna körs mot förenklade fixturer i PGlite**, inte mot det riktiga
  schemat. De fångar logikfel men inte avvikelser från den driftsatta
  databasen.

## 4. Vad som ska byggas framöver

### A. Före produktion (blockerar lansering)

1. Uppgradera säkerhetspatchar: Next.js och Firebase-funktionerna.
2. Stäm av migreringsloggarna och sätt upp en produktionsmiljö på Supabase Pro
   med skydd mot läckta lösenord (X-OPS-01, PAR-OPS-03).
3. Release-signering, Play-konto, butiksmaterial och iOS-bygge. iOS har aldrig
   byggts eller testats; i dag utvecklas bara på Windows.
4. **Push-notiser.** Arbetaren finns, men leveransen via en leverantör är
   avstängd tills den konfigureras. I dag når inga notiser ut.
5. Juridiska texter, det vill säga villkor och integritet (AUTH-07), och
   beslutet om namn på arkiverade spelare.
6. Den gemensamma kontrollen på riktig telefon och surfplatta för våg 10 och
   de öppna kärnkorten.
7. CI och felrapportering för alla plattformar.

### B. Påbörjat men ofärdigt

- **PUB-02:**
  - klubbens självbetjäning för att publicera med förhandsgranskning;
  - lagets ansökan om publik sida;
  - märkning av officiella och inofficiella klubbar;
  - klubbkatalogen;
  - integritetstester.
- **Egen domän (PUB-05)** och den publika lanseringen.
- **Laget.se:** att skapa aktiviteter, steg 2, är uppskjutet. Borttagningen av
  exporten planeras när den inte behövs.
- **Matchformat:** periodlängderna per format (5v5 3×15 och så vidare) är
  antaganden och behöver bekräftas. Matchläget visar 2×45 innan en match har en
  arbetsyta.
- **Min assistent och notiser:** själva leveransen och verifiering med verklig
  data för flera roller.

### C. Uppskjutet enligt beslut

- Arbetsytor och webbverktyg (S11).
- Import av medlemmar och event med förhandsgranskning.
- Historik och total statistik.
- Återanvändbara grupper.
- Full match- och träningsplanering.
- Livebevakning av matcher på den publika sidan.
- Meddelanden mellan spelare, som kräver policy, ålderskrav och moderering.
- Skador och avstängningar samt belastning, som kräver ett integritetsbeslut.
- Generativ AI, som är spärrad av PAR-AI-01/02.
- Avgifter och betalningar, som är spärrade av PAR-FIN-03.

## 5. Rekommenderad ordning

| Prioritet | Åtgärd | Ungefärlig insats |
|---|---|---|
| 1 | Uppgradera Next.js och Firebase-funktionerna, testa och driftsätt | Timmar |
| 2 | Lägg till de två engelska texterna och en säker reserv i `feature()` | Timmar |
| 3 | Stäm av migreringsloggarna mot testmiljön | 1 dag |
| 4 | CI med analys och alla testsviter | 1 dag |
| 5 | Säkerhetshuvuden för Flutter-webben, CORS per miljö, verifierad spärr vid inloggning | 1–2 dagar |
| 6 | Felrapportering: inga tysta `catch`, plus webb och iOS | 2–3 dagar |
| 7 | Release-signering, iOS-bygge och push-leverantör | 1–2 veckor |
| 8 | Produktionsmiljön enligt X-OPS-01 | Enligt runbook |
| 9 | Kontroll på riktig enhet för våg 10 | 1–2 dagar |
| 10 | Stegvis uppdelning av de största filerna och regelbunden uppdatering av beroenden | Löpande |
