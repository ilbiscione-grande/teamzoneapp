# Juridisk genomgång av Tacticsboard (punkt 11)

Utkast 2026-11-05 i `public-site/app/villkor`, `villkor/tacticsboard` och
`integritet`. Inget är driftsatt. Platshållarna är borta, men bannern
"Juridiskt utkast" ligger kvar tills texterna är granskade. Versionerna och
datumen sätts när texterna publiceras (steg 14 i
`tacticsboard-production.md`).

## Krav före lansering

**Ångerfunktionen** är driftsatt i produktionen 2026-11-05, men inte provad med ett riktigt köp. Sedan 19 juni 2026 kräver 2 kap. 10 a §
distansavtalslagen en funktion för ånger på sajten när avtalet ingås online:

- lätt att hitta under hela ångerfristen och tydligt märkt
- konsumenten anger eller bekräftar namn och avtal
- konsumenten bekräftar ångern uttryckligen
- mottagningsbevis utan dröjsmål, med tidpunkten, i varaktig form
- information före köpet om att funktionen finns och var (2 kap. 2 § p. 10)

Saknas informationen börjar ångerfristen inte löpa (2 kap. 12 §). Brott mot
10 a § prövas enligt marknadsföringslagen (2 kap. 10 b §). Villkoren beskriver
knappen "Ångra köpet" under Abonnemang på kontosidan, så den måste vara provad
innan villkoren publiceras.

Knappen läser köpet och fristen från Stripe, sparar beskedet i
`internal.personal_billing_withdrawals`, avslutar prenumerationen och skickar
mottagningsbeviset till kunden och ett ärende till supporten. Återbetalningen
görs för hand i Stripe, eftersom den begränsade nyckeln inte får läsa fakturor
eller återbetala. Beräkna: betalt belopp minus betalt belopp × (dagar från den
betalda periodens start till mottagandet) / (dagar i perioden). Görs inom 14
dagar. Under provperioden har inget dragits.

## Att granska

1. Ångerrätten vid prenumeration: att den gäller köpet och inte varje
   förnyelse. Ingen källa jag läste tar upp det.
2. Proportionell betalning (2 kap. 15 § p. 3), och att tid under provperioden
   inte kostar något.
3. Texten i Checkout är ändrad till proportionell del, med knappens plats.
4. Ansvarsbegränsningen i båda villkoren.
5. Prisändring med 30 dagars besked.
6. Rättigheterna vid fel enligt lagen om digitalt innehåll och digitala
   tjänster (2022:260). Hänvisningen är inte kontrollerad mot lagtexten.
7. Klubbarnas ansvar: klubben ansvarig och vi biträde. Kräver
   personuppgiftsbiträdesavtal när klubbar börjar använda produktionen.
8. Rättsliga grunder och intresseavvägningar.

## Att besluta eller kontrollera

- **Åldrarna:** 13 år för eget konto och 18 år eller vårdnadshavares
  godkännande för köp är förslag. Registreringen kontrollerar inte åldern.
- **Supportmejl två år** är ett förslag.
- **Säkerhetskopior 7 dygn:** Pro-planens standard, inte avläst i projektet.
- **Gmail:** går supporten till ett vanligt Gmail-konto finns inget
  biträdesavtal. Google Workspace kan behövas.
- **Försäljning bara i Sverige:** skriv in det i villkoren om det blir beslutet.

## Leverantörerna (lästa 2026-11-05)

| Leverantör | Bolag | Plats | Skydd |
|---|---|---|---|
| Supabase | Supabase Pte. Ltd, Singapore | Stockholm (produktionen), Irland (test). Underleverantörer och platser för säkerhetskopior ej bekräftade | SCC. Inget DPF nämns |
| Firebase | Google | App Hosting `europe-west4` i Nederländerna. Google anger att data annars kan behandlas där de har anläggningar | DPF |
| Resend | Plus Five Five, Inc., USA | Lagrar i USA. Sändningsregionen flyttar inte lagringen | SCC och DPF |
| ImprovMX | ImprovMX Incorporation, USA | Inkommande tillfälligt i Paris, utgående via Frankrike och USA | SCC. Ej certifierad enligt DPF enligt egen text |
| Stripe | Stripe Technology Company och Stripe Payment Europe, Irland | Överföring till USA och Indien, enligt en sammanfattning av policyn | DPF (Stripe, LLC), SCC |

Källor: leverantörernas sidor om DPA, integritet och GDPR samt
[Riksdagens lagtext](https://www.riksdagen.se/sv/dokument-och-lagar/dokument/svensk-forfattningssamling/lag-200559-om-distansavtal-och-avtal-utanfor_sfs-2005-59/)
och [Konsumentverket](https://www.konsumentverket.se/marknadsratt-foretag/informationskrav-vid-distansavtal-regler-for-foretag/).
Ikraftträdandet 19 juni 2026 kommer från Konsumentverket och Vinge.
