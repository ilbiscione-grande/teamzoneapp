# Tacticsboard: prov från början till slut (punkt 14)

Provet görs i testmiljön: Webtools på
`https://teamzoneapp-webtools--teamzoneapp-b02a2.europe-west4.hosted.app`,
Supabase-projektet `hgcshgunvooyudvrcpig` och Stripes testläge. Inga riktiga
kort används.

**Arbetsfördelning:** du loggar in, registrerar och betalar med Stripes testkort.
Jag får inte logga in åt dig. Efter varje steg kontrollerar jag databasen
(bara läsning) och skriver resultatet i kolumnen. Tidshoppen i steg 6 gör jag
med SQL på ditt testkonto, när du säger till.

**Konton:** använd en ny e-postadress för steg 1–7, till exempel
`dittnamn+tb1@gmail.com`. Gmail levererar plusadresser till samma inkorg. Steg
8–9 behöver ett andra nytt konto (`+tb2`).

**Stripes testkort** (valfritt datum framåt, valfri CVC och postnummer):

| Kort | Vad som händer |
|---|---|
| `4242 4242 4242 4242` | Betalningen går igenom |
| `4000 0025 0000 3155` | Kräver 3-D Secure, godkänn i rutan |
| `4000 0000 0000 0341` | Kortet sparas, men varje debitering misslyckas |

## Stegen

| # | Du gör | Förväntat i gränssnittet | Jag kontrollerar | Resultat |
|---|---|---|---|---|
| 1 | Öppna `/appar/tacticsboard` utloggad, tryck "Prova gratis i 7 dagar" och skapa kontot `+tb1` | Registreringen, villkorssteget, sedan Tacticsboards startsida | Profilen finns, villkoren godkända | Godkänt 2026-11-04. Bekräftelselänken landade på `localhost:3000` (Site URL i testprojektet), men kontot bekräftades. Villkoren 2026-08-24 godkända 07:19 |
| 2 | Skapa ett projekt och en tavla, rita något | Raden "7 dagar kvar av provperioden" | `personal_billing_accounts` har en rad med slut om 7 dagar, `audit.command_events` har starten | Godkänt 2026-11-04. Provperioden 07:31 till 11 nov 07:31, starten loggad. Projektet "Testtavla" med 3 tavlor sparat 4 gånger, en länk till hela projektet |
| 3 | Logga ut, välj "Glömt lösenord" och byt lösenord via mejlet | Mejlet kommer, nytt lösenord fungerar | Inget (Auth) | |
| 4 | Konto → Abonnemang → köp månad med `4000 0025 0000 3155` | Stripe Checkout på svenska, 39 kr, 3-D Secure, tillbaka till `/konto?betalning=klar` | Prenumerationen `active`, provperiodens rest som `trial_end` | |
| 5 | "Hantera betalning" → byt kortet till `4000 0000 0000 0341`. Säg till mig. I Stripes dashboard: prenumerationen → avsluta provperioden nu | Raden om misslyckad betalning, "Uppdatera kortet" | Tillståndet `grace` med `grace_ends_at` 14 dagar fram, allt går fortfarande att spara | |
| 6 | Säg till. Jag flyttar `grace_ends_at` bakåt. Ladda om | "Prenumerationen har upphört" med knapparna för månad och år. Tacticsboard är helt låst (spärren gäller även läsningar), men inget är borttaget | `internal.personal_entitlement_status` = `denied`, en sparning ger `tacticsboard_locked` | |
| 7 | Byt tillbaka till `4242…` i portalen och betala fakturan, sedan säg upp prenumerationen | Allt fungerar igen, sedan raden "Prenumerationen avslutas …" | `active`, sedan `cancel_at_period_end` | |
| 8 | Skapa kontot `+tb2`, öppna Tacticsboard en gång. Säg till, så sätter jag provperioden som slut | "Provperioden är slut" med knapparna för månad och år | `denied`, ingen ny provperiod startar | |
| 9 | På `+tb2`: köp år, se att lanseringspriset 292,50 kr visas. Avsluta sedan kontot (skriv AVSLUTA) | Kontot borta, utloggad | Stripe-prenumerationen avslutad, inga rader kvar, loggraden `account.self_erased.v1` | |
| 10 | Upprepa 1, 2 och 4 på riktig telefon (Safari eller Chrome) och iPad, med Apple Pay eller Google Pay om det finns | Inget klipps, knapparna går att nå | | |

**Delade länkar under läsläget:** i steg 6, öppna en länk som delades i steg 2
i ett privat fönster. Den ska fortfarande fungera.

**Efter provet:** testkontona kan ligga kvar eller avslutas med steg 9.
Prenumerationerna i Stripes testläge kostar inget.
