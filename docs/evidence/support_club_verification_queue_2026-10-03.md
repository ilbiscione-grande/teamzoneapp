# Supportkö för officiella klubbar – 2026-10-03

## Levererat

- Ansökningar om officiell klubb visas i den befintliga webbaserade supportkön.
- Endast aktiva `support_admins` får lista och besluta ärendena. Beslut kräver
  motivering, förväntad revision och idempotensnyckel och auditloggas.
- Supportnavigationen visas på webb och desktop i desktopbredd. Direktåtkomst
  skyddas fortfarande av serverbehörigheten.
- Nya klubbverifieringar, skyddade klubbnamn, byten av inloggningsadress och
  globala kontoraderingar skapar en rad i `internal.support_email_outbox`.
- E-postkön innehåller bara ärendetyp, intern referens och revision. Underlag,
  kontaktuppgifter och annan persondata hämtas aldrig till mejlet.
- `support-email-worker` är publicerad med en separat intern worker-nyckel.
  Gateway-JWT är avstängt för databasens cronanrop, men anrop utan den särskilda
  nyckeln avvisas. Aviseringar går till `support@teamzoneapp.se`, som också är
  standardavsändare. Resend används för utgående leverans.

## Driftstatus

- Migrationerna `20261003094810`, `20261003100000`, `20261003101010`,
  `20261003110959`, `20261003134430` och `20261003135312` är applicerade i
  auditprojektet `hgcshgunvooyudvrcpig`.
- Den redan öppna klubbverifieringen är tillagd i e-postkön.
- TeamZone använder sedan tidigare Resend i Teamzone6. TeamzoneApp är ett eget
  Supabase-projekt och använder därför en separat Resend-nyckel i samma konto.
- Resend och avsändaren är konfigurerade för TeamzoneApp. Workern anropas varje
  minut via `pg_cron` och `pg_net` med en separat, slumpad worker-nyckel som
  endast finns i Edge Function secrets och Vault.
- `support-email-worker` version 5 är aktiv med gateway-JWT avstängt och egen
  worker-nyckelkontroll. Ett anrop utan nyckeln gav HTTP 401.
- Ett verkligt leveranstest tog den väntande verifieringsposten ur kön. Resend
  accepterade mejlet (`claimed=1`, `delivered=1`, `failed=0`) och kön visar
  därefter en levererad post. Cronjobbet `support-email-worker` är aktivt varje
  minut.
- Efter leveranstestet upptäcktes att aktiva supportadministratörers privata
  kontoadresser också lades till som mottagare. Mottagarurvalet begränsas nu
  till den separata mottagarlistan, där endast `support@teamzoneapp.se` är
  aktiv. Supportadministratörer får fortsatt handlägga kön efter inloggning men
  får inte automatiskt en privat mejlkopia.
- Den aktiva supportadministratören använder ett personligt konto. Det ger
  spårbara beslut; en gemensam supportbrevlåda kan användas som mottagare utan
  att dela inloggningsuppgifter.
- Netlify DNS är auktoritativ DNS för `teamzoneapp.se`. MX-posterna pekar på
  ImprovMX, som vidarebefordrar `support@teamzoneapp.se` till den operativa
  Gmail-inkorgen. Resend och ImprovMX har separata roller: Resend skickar ut,
  ImprovMX tar emot och vidarebefordrar.

## Verifiering

- `flutter analyze`: utan anmärkning.
- `flutter test test/auth04_membership_application_test.dart`: 17/17.
- Hosted lästest som aktiv supportadministratör: en godkänd och en väntande
  verifieringsansökan returneras.
- Security- och performance-advisors: inga nya varningskategorier; den privata
  outboxtabellen följer projektets befintliga RLS-utan-direktpolicy-mönster.
- Releasewebben är ombyggd med auditkonfiguration och serveras på
  `http://localhost:5000`; `/support` och `main.dart.js` svarar 200 och den
  serverade builden innehåller det nya verifierings-RPC-anropet.

## Driftbeskrivning

Samlad tjänstetopologi, DNS, hemlighetsnamn, mottagarregler, rotation,
statusdefinitioner och felsökning finns i
[`../operations/support_email_runbook.md`](../operations/support_email_runbook.md).
