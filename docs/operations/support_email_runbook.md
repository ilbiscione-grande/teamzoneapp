# Supportärenden och e-postaviseringar

## Syfte och aktuell drift

TeamZone samlar supportärenden i den behörighetsskyddade sidan `/support` i
Flutter-webbappen. Nya ärenden skickar även en kort avisering till den gemensamma
supportadressen. Mejlet innehåller endast ärendetyp, intern referens, tidpunkt och
länk till supportkön. Underlag, kontaktuppgifter och annan persondata visas först
efter personlig inloggning i TeamZone.

Aktuell leveranskedja:

```text
Nytt supportärende
  → Supabase/PostgreSQL-trigger
  → internal.support_email_outbox
  → pg_cron (varje minut)
  → pg_net
  → Supabase Edge Function: support-email-worker
  → Resend
  → support@teamzoneapp.se
  → Netlify DNS MX
  → ImprovMX
  → teamzone.mobileapp@gmail.com
```

Supportkön och e-postaviseringen är separata. Ett mejl ger inte mottagaren
behörighet att läsa ett ärende. Beslut fattas alltid på `/support` med ett
personligt supportadministratörskonto så att beslut kan auditloggas.

## Tjänster

| Tjänst | Användning | TeamZone-konfiguration |
|---|---|---|
| Supabase | Auth, PostgreSQL, supportkö, privat e-postkö, Edge Function, Vault, `pg_cron` och `pg_net` | Projekt `TeamzoneApp`, referens `hgcshgunvooyudvrcpig` |
| Resend | Utgående transaktionsmejl | Befintligt TeamZone-konto och verifierad domän `teamzoneapp.se`; TeamzoneApp har en egen API-nyckel |
| Netlify DNS | Auktoritativ DNS för `teamzoneapp.se` | Publicerar MX-posterna för ImprovMX och domänposter som Resend behöver |
| ImprovMX | Tar emot mejl till den gemensamma supportadressen och vidarebefordrar dem | Alias `support@teamzoneapp.se` vidarebefordras till `teamzone.mobileapp@gmail.com` |
| Gmail | Operativ mottagarinkorg | `teamzone.mobileapp@gmail.com`; inget API eller plugin används av TeamZone |
| Firebase Hosting | Drift av Flutter-webbappen och `/support` | Firebaseprojekt `teamzoneapp-b02a2`, origin `https://app.teamzoneapp.se` |

Resend används för utgående mejl. ImprovMX ersätter inte Resend och skickar inga
TeamZone-aviseringar; tjänsten hanterar inkommande post och vidarebefordran.
Netlify DNS är DNS-operatör, inte e-postleverantör.

Teamzone6 använder sedan tidigare samma Resend-konto för bland annat uteblivna
kallelsesvar. TeamzoneApp är ett separat Supabaseprojekt och använder därför en
egen Resend API-nyckel. Nycklar kopieras inte mellan Supabaseprojekt.

## Adresser och mottagarregel

- Avsändare: `TeamZone Support <support@teamzoneapp.se>`.
- Enda applikationsmottagare: aktiva rader i
  `internal.support_notification_recipients`.
- Aktuell aktiv mottagare: `support@teamzoneapp.se`.
- ImprovMX vidarebefordrar adressen till `teamzone.mobileapp@gmail.com`.
- Aktiva rader i `internal.support_admins` styr behörighet till supportkön men
  läggs inte till som e-postmottagare.

Den sista regeln infördes efter att det första leveranstestet visade att ett
personligt supportadministratörskonto också fick en kopia. Migration
`20261003135312_restrict_support_email_to_notification_recipients.sql` tog bort
den kopplingen. Den redan skickade kopian kunde inte återkallas.

## DNS och ImprovMX

Domänens MX-poster ligger hos Netlify DNS:

| Prioritet | Mål |
|---:|---|
| 10 | `mx1.improvmx.com` |
| 20 | `mx2.improvmx.com` |

TTL var 3600 sekunder vid konfigurationen. Offentliga DNS-kontroller såg båda
posterna innan ImprovMX egen setupvy hade uppdaterat sin cache. Meddelandet om
att DNS kan ta minuter eller timmar var därför förväntat och krävde ingen extra
post.

Resends domänverifieringsposter ska lämnas kvar. MX-poster för ImprovMX och
Resends sändningsposter har olika syften och kan finnas samtidigt.

## Supabasekomponenter

### Databas

Följande ärendetyper skapar en outboxrad:

- ansökan om officiell klubb (`club_verification`);
- skyddat klubbnamn (`protected_name`);
- byte av inloggningsadress (`login_email_change`);
- global kontoradering (`person_erasure`).

`internal.support_email_outbox` använder tillstånden `pending`, `processing`,
`delivered`, `failed` och `dead_letter`. Claim sker med `FOR UPDATE SKIP LOCKED`.
Misslyckade leveranser kan försökas igen och stoppas efter fem försök.

### Schemaläggning och worker

Cronjobbet `support-email-worker` kör varje minut och anropar
`internal.invoke_support_email_worker()`. Funktionen hämtar projekt-URL och en
dedikerad worker-nyckel från Supabase Vault och anropar Edge Functionen via
`pg_net`.

Edge Functionen har gatewayinställningen `verify_jwt=false` eftersom anropet
kommer från databasen. Den är ändå privat: varje anrop måste ha den separata
headern `x-teamzone-worker-token`, vars värde jämförs mot
`SUPPORT_WORKER_TOKEN`. Ett anrop utan nyckel har verifierats ge HTTP 401.

Workern använder en servernyckel för att claima och slutföra outboxrader. Varken
worker-nyckeln, Resend-nyckeln eller Supabase servernyckel får finnas i Flutter,
publik JavaScript, migrationsfiler, dokumentation eller Git.

Varje Resend-anrop använder idempotensnyckeln
`teamzone-support-<outbox-id>`. Detta minskar risken för dubbla mejl om Resend
accepterar anropet men workern avbryts innan databasstatusen sparas.

## Konfiguration utan hemliga värden

Supabase Edge Function secrets:

| Namn | Innehåll |
|---|---|
| `RESEND_API_KEY` | Separat Resend API-nyckel för TeamzoneApp |
| `SUPPORT_WORKER_TOKEN` | Slumpad intern nyckel för databasens workeranrop |
| `SUPPORT_EMAIL_FROM` | `TeamZone Support <support@teamzoneapp.se>` |
| `SUPPORT_PORTAL_URL` | `https://app.teamzoneapp.se/support` |

Supabase Vault:

| Namn | Innehåll |
|---|---|
| `project_url` | Edge Function-basadressen för TeamzoneApp |
| `support_email_worker_token` | Samma interna worker-nyckel som Edge Functionen verifierar |

Hemliga värden ska skapas och roteras direkt i respektive leverantör och
Supabase. De ska aldrig klistras in i ärenden, chattar eller dokument.

## Driftkontroll

Kontrollera i denna ordning:

1. Supabase Edge Functions visar `support-email-worker` som `ACTIVE`.
2. Cronjobbet `support-email-worker` är aktivt och senaste körningen är
   `succeeded`.
3. Outboxen lämnar inte växande mängder `failed` eller `dead_letter`.
4. Resend visar mejlet och providerstatusen.
5. ImprovMX visar `teamzoneapp.se` som korrekt konfigurerad.
6. Mejlet når `teamzone.mobileapp@gmail.com`, inklusive kontroll av skräppost.

TeamZones status `delivered` betyder för närvarande att Resend har accepterat
mejlet. Den bekräftar inte slutlig leverans till Gmail. Resend-webhooks för
`delivered`, `bounced` och `complained` är en möjlig senare förbättring.

## Felsökning

| Symptom | Trolig orsak | Kontroll |
|---|---|---|
| `provider_not_configured` | `RESEND_API_KEY` saknas | Kontrollera endast att secretnamnet finns i rätt Supabaseprojekt |
| `provider_http_401` eller `403` | Ogiltig Resend-nyckel, fel behörighet eller avsändardomän | Kontrollera API key och domänstatus i Resend |
| `recipient_not_configured` | Ingen aktiv rad i mottagarregistret | Kontrollera `internal.support_notification_recipients` |
| Resend accepterar men Gmail får inget | ImprovMX, MX-propagering eller skräppostfilter | Kontrollera Resend Events, offentlig MX och ImprovMX-logg |
| Personligt administratörskonto får kopia | Äldre mottagarfunktion eller oönskad mottagarrad | Kontrollera installerad claim-funktion och mottagarregistret |
| Cron lyckas men inget skickas | Kön är tom | Detta är normalt; workern svarar med `claimed=0` |

Vid nyckelrotation skapas först en ny Resend-nyckel, därefter uppdateras
`RESEND_API_KEY` i TeamzoneApp och ett avgränsat leveranstest körs. Den gamla
nyckeln tas bort först när testet har passerat. Worker-nyckeln måste uppdateras
atomiskt i både Edge Function secrets och Vault för att undvika avbrott.

## Genomförd verifiering 2026-10-03

- Edge Function `support-email-worker` version 5 driftsattes och är aktiv.
- Ett anrop utan worker-nyckel gav HTTP 401.
- Cronjobbet kördes och rapporterade `succeeded`.
- Det första riktiga testet gav `claimed=1`, `delivered=1`, `failed=0`.
- Mejlet nådde den konfigurerade Gmail-inkorgen genom ImprovMX.
- Ett transaktionellt mottagartest returnerade exakt
  `{support@teamzoneapp.se}` och rullades tillbaka.
- Databaslint rapporterade inga nya fynd från supportmejlskomponenterna. Projektet
  har sedan tidigare separata lintfynd i andra funktioner; de hanteras utanför
  denna integration.

Detaljerad implementationsevidens finns i
[`../evidence/support_club_verification_queue_2026-10-03.md`](../evidence/support_club_verification_queue_2026-10-03.md).
