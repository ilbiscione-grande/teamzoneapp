# Medlemsregister och avgifter för klubbadmin – plan

**Status: steg 1–5 byggda (1–2 den 2026-11-10, 3–5 den 2026-11-11).** Steg 1, registret: migration `20270215090000_club_member_register.sql`, Klubb → Medlemmar → Medlemsregister. Kontaktuppgifter ingår inte än; de följer reglerna i `get_person_contact`. Steg 2, avgiftsomgångar och familjer: migration `20270216090000_club_fee_rounds.sql`, Klubb → Medlemmar → Avgifter. Steg 3, betalstatus: migration `20270217090000_club_fee_payments.sql`, på en skapad omgång. Steg 4, påminnelser i appen: migration `20270218090000_club_fee_reminders.sql`. Steg 5, påminnelser via e-post: migration `20270222090000_club_fee_email_reminders.sql` och Edge Functions `fee-email-worker` och `fee-email-unsubscribe`. Alla fem migrationerna är körda och loggade. Kommer från rollgenomgången för klubbadmin och styrelse. Klubb-sidan (`/club`, commit aaaf2cc) är ingången.

## Produktägarens beslut (2026-11-10)

- **Två slags avgifter:** en *medlemsavgift* för alla som är medlemmar i klubben och en *lag- eller deltagaravgift* för spelarna i ett lag.
- **Familjer:** medlemsavgiften ska kunna subventioneras för familjer.
- **Betalning:** markeras som betald för hand i första versionen, med datum och sätt (Swish, bank, kontant). Ingen betalintegration än.
- **Påminnelser:** i TeamZones inkorg med push, och även via e-post för den som saknar app.
- **Behörighet:** klubbadmin ser registret, och avgifterna hanteras av klubbadmin och kassör. Det är ett nytt behov som skrivs in i [behörighetsöversynen](permissions-review.md) i stället för att behörigheterna breddas nu.

**Fler beslut 2026-11-10:**

- **Familjerabatt:** båda varianterna ska finnas. En omgång kan ha ett tak per familj, en rabatt från andra syskonet, eller båda.
- **Vårdnadshavare** som inte själva spelar räknas som "samma" medlem som barnet. De får ingen egen avgift, men är betalare och mottagare av påminnelser för barnets avgifter. Registret visar dem som "Via barnet".
- **Grundappen:** avgifter, betalstatus och påminnelser ingår i grundappen. Betalning direkt i appen (Swish eller kort) blir ett tillägg som köps till med Ekonomimodulen.

## Det som finns i dag

- `core.club_people`: alla personer i klubben (spelare, ledare, funktionärer och vårdnadshavare). Där finns inget begrepp för "medlem".
- `core.guardian_relations`: kopplar barn till vårdnadshavare. Därifrån kan familjer härledas, till exempel syskon med en gemensam vårdnadshavare.
- `core.fee_obligations` (s10b): tabellen finns, med belopp, förfallodag och status (draft, issued, partially_paid, paid, waived, cancelled), men används inte. Den hör till en kassa (`economy_accounts`).
- E-post: `supabase/functions/_shared/contact_mail.ts` och `contact-email-worker` skickar redan e-post (Gmail tills vidare).
- Spec: `docs/specification/source/14_economy_boardroom_decision.md`, avsnittet Medlemsavgifter. En påminnelse markeras som skickad först när leveransen är bekräftad. En ändring eller eftergift bevarar historiken.

## Steg

1. **Medlemsregister.** En lista över alla i klubben: namn, födelseår eller åldersklass, lag och roll, vårdnadshavare, om personen har ett konto och kontaktuppgifter (enligt kontaktreglerna). Listan går att söka i och filtrera på lag, roll och medlem eller inte, och den kan exporteras till CSV. Klubbadmin kan markera vem som är medlem och vilken medlemskategori personen har (till exempel barn och ungdom, vuxen, stödmedlem). Som standard är spelare och ledare medlemmar.
2. **Avgiftsomgångar.** Till exempel "Medlemsavgift 2027" med belopp per kategori och familjeregel, eller "Lagavgift P2012 vår 2027" med belopp per spelare. En omgång skapar en avgift per person.
   - **Byggt så här:** omgången är ett utkast som räknas om tills avgifterna skapas. Då låses beloppen. Ingen får något meddelande i det här steget.
   - **Familjeregeln (medlemsavgift):** den dyraste avgiften i en familj betalas hel. Syskonrabatten i procent gäller de övriga, och taket begränsar summan för en familj med två eller flera avgifter. Taket tas från de sista avgifterna, och en avgift som blir 0 kr visas som "täcks av familjetaket".
   - **Lagavgift:** ett belopp per aktiv spelare i laget, utan familjeregel.
   - **Kategori saknas:** medlemmar utan känd kategori (inget födelseår) får ingen medlemsavgift. De visas som en varning i utkastet.
   - **Egna tabeller:** `club_fee_rounds` och `club_fees` i stället för `fee_obligations`, eftersom de senare kräver en kassa i Ekonomimodulen. Kopplingen till Ekonomimodulen görs när betalning i appen byggs.
   - **Behörighet:** klubbadmin, eller kassören (`economy.manage` på klubbnivå). Kassören ser bara Avgifter på Klubb-sidan.
3. **Betalstatus.** En lista per omgång med obetald, betald och efterskänkt. Avgifter markeras som betalda för hand, en eller flera i taget, och det går att filtrera fram de obetalda. Kassören ser summan och kan exportera.
   - **Byggt så här:** på en skapad omgång syns betalt och obetalt med summor, och listan går att filtrera på alla, obetalda, betalda och efterskänkta. Man kan välja alla obetalda eller några och markera dem betalda samtidigt, med betalningsdag, sätt (Swish, bank, kontant, annat) och en valfri anteckning. En avgift kan efterskänkas med en anledning eller ändras tillbaka till obetald. En avgift på 0 kr (familjetaket) har inget att betala. Varje ändring sparas i granskningsloggen med det tidigare värdet. CSV-exporten innehåller namn, kategori, betalare, belopp, rabatt, status, betalningsdag, sätt och anteckning.
4. **Påminnelser i appen.** Påminnelser skickas till de som inte har betalat: till personen, och för barn till vårdnadshavarna, via inkorgen och push. Listan visar när var och en senast påmindes och vem som inte kan nås.
   - **Byggt så här:** "Påminn obetalda", eller bara de valda, skickar en notis i inkorgen och en push till personen och vårdnadshavarna som har konto. Varje mottagare får en notis per utskick med omgångens namn och beloppet, och den öppnar Mina avgifter (`/fees`). En avgift påminns högst en gång per 20 timmar. Listan visar "påmind" med datum och "kan inte nås" för den som saknar mottagare med konto, och efter utskicket står hur många som påmindes och vilka som inte kan nås. Pushen skickas inte om alla avgifter den gäller hunnit bli betalda. Omgången har "Så betalar man" (till exempel Swish-nummer), som kan ändras även efter att avgifterna är skapade.
   - **Mina avgifter:** den inloggades och barnens obetalda avgifter och de som betalats det senaste året, med belopp, sista betalningsdag och hur man betalar. Sidan nås i dag från notisen, inte från menyn.
   - **Notisfunktionerna** (`notification_title`, `notification_preview`, `notification_deep_link`, `push_message_for_outbox`) är kopierade från databasen och har fått avgiften tillagd.
5. **Påminnelser via e-post.** Samma påminnelse skickas till e-postadressen för den som saknar app, med en Swish-referens per avgift. Innan steget byggs ska avsändare, gränser och avregistrering bestämmas.
   - **Byggt så här (beslut 2026-11-11):** samma påminnelse går också som mejl till den som saknar konto i TeamZone, alltså personen eller barnets vårdnadshavare, när klubbens register har en e-postadress (`club_people.contact_email`). Ett mejl går per adress och utskick och nämner avgifterna, beloppen, sista betalningsdagen och "Så betalar man".
   - **Avsändare:** "<klubb> via TeamZone" <avgifter@teamzoneapp.se>, som kan ändras med `FEE_EMAIL_FROM_ADDRESS`. Mejlet ber mottagaren att inte svara utan kontakta klubben.
   - **Gränser:** samma som i appen, högst en påminnelse per avgift och 20 timmar. Ett mejl vars avgifter hunnit bli betalda skickas inte.
   - **Avregistrering:** en länk i mejlet och `List-Unsubscribe` (one-click). Länken pekar på mejlets id med en HMAC-signatur, aldrig på adressen. Den avregistrerade adressen sparas som hash och får inga fler avgiftsmejl. Den som då varken har konto eller e-post visas som "kan inte nås".
   - **Sändning:** `fee-email-worker` körs varje minut via pg_cron, bara när något väntar, och skickar via Resend som klubbsajtens svar (`RESEND_API_KEY`). Avregistreringslänkarna signeras med `CONTACT_REPLY_SECRET` med eget prefix. Swish-referens per avgift är inte byggd än.

Senare: Swish-QR, import av bankfil och en riktig betalintegration.

**Familjer (beslut 2026-11-10):** appen räknar fram familjerna automatiskt, där barn med en gemensam vårdnadshavare blir en familj. Klubbadmin kan sedan slå ihop eller dela familjer för hand, till exempel när föräldrarna bor isär eller för halvsyskon. En ändring för hand gäller tills klubbadmin tar bort den. Byggt i steg 2 under Avgifter → Familjer, där man kan flytta ut, lägga till och följa vårdnadshavarna igen. Bara medlemmar räknas: en vårdnadshavare som inte är medlem är betalare, inte en del av familjens avgifter.

## Öppna frågor

Inga just nu.
