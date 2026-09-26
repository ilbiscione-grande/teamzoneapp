# TEAM-02 – Rollstyrd lagöversikt

**Datum:** 2026-08-24  
**Status:** SLUTFÖRD – IMPLEMENTERAD, HOSTED SQL/STORAGE, 369/369 REGRESSION SAMT FYSISKT VERIFIERAD PÅ WEBB OCH ANDROID INKLUSIVE HELA PRIVATA BILDFLÖDET OCH STÖRRE TEXT  
**Livepåverkan:** TEAM-02:s profil-, ledarbehörighets- och privata lagbildsmigreringar är applicerade på den uttryckligen godkända testdatabasen `hgcshgunvooyudvrcpig`.

## Implementerat

- En privat `core.team_profiles`-modell lagrar kort laginformation, lagtyp, åldersklass och referens till lagets aktiva privata bildobjekt. Äldre godkända HTTPS-adresser kan fortfarande läsas, men kan inte längre matas in i klienten.
- En minimerad RPC returnerar endast lagets identitet, profilfält, aktiva ledarnamn och sammanfattande medlemsantal till en användare med klubbåtkomst.
- Aktiva inbjudningar och väntande medlemsansökningar räknas endast när servern bekräftar `club.memberships.manage`; annars returneras noll.
- Klienten kräver dessutom samma capability innan det administrativa åtgärdskortet över huvud taget byggs.
- Översikten visar responsiv lagbild med beskärning och tillgänglig semantisk etikett.
- Saknad eller trasig bild får en professionell neutral fallback utan rått backendfel.
- Saknad presentation eller ledarlista har separata begripliga tomtexter.
- Lagidentitet, klubb, lagtyp, åldersklass, presentation och ledare visas utan administrativa persondetaljer.
- Genvägar leder till Trupp, lagets Kalender och Inbox.
- Behörig ledare ser aktiva inbjudningar, väntande ansökningar och totalsumma för ärenden som kräver åtgärd.
- Player/guardian utan capability ser inte det administrativa kortet, även om en felaktig klientfixture skulle innehålla administrativa räknare.
- All ny användartext har svensk och engelsk lokalisering.
- Lagprofilformuläret har `Välj lagbild`, förhandsvisning, `Byt lagbild` och `Ta bort lagbild` i stället för ett URL-fält. JPG, PNG och WebP tillåts upp till 5 MB.
- Originalet ligger i den privata bucketen `team-profile-images`. Ett capabilitykontrollerat, idempotent staging-anrop måste skapa exakt objektnyckel innan Storage accepterar upload. Upsert är avstängt.
- Aktivering sker atomiskt tillsammans med profilrevisionen. Ersatta/borttagna bilder blir omedelbart oläsbara men behålls privat för en senare explicit retention-/rensningsrutin.
- Läsning kräver både en serverauktorisering och Storage SELECT-RLS mot en aktiv bild som fortfarande är kopplad till profilen och en klubb aktören har åtkomst till. Klienten använder endast en signerad URL på 60 minuter och har 15 sekunders timeout.
- Privat original blir inte automatiskt den publika klubbsajtens bild. Publik transformation/skanning/variant förblir PUB-04:s separata grind.

## Verifiering

- Direkt Flutter-analys: **No issues found**.
- Riktad TEAM-02/TEAM-01/AUTH-03/FND-05-svit: **18/18 passerar**.
- Positivt ledartest verifierar lagidentitet, ledare, genvägar, invite- och ansökningsbehov.
- Negativt spelartest verifierar att administrativa rubriker och räknare inte renderas.
- Källkontrakt verifierar privat tabell, klubbåtkomst, capabilitygrind, nollad adminprojektion och avsaknad av direkta grants till ansökningstabellen.
- Säkerhetsutformningen följer aktuell Supabase-vägledning med explicit RLS/revoke, privat definer-funktion, tom `search_path` och explicit RPC-grant.
- Hosted RPC-signaturer, execute-grants och nekad `anon`/`PUBLIC`-åtkomst verifierades 2026-09-01.
- Migrationerna `20260912134327_team02_private_team_image_upload.sql` och `20260912140450_team02_team_image_signed_read_policy.sql` rollbackvaliderades med riktig Postgres innan push och är remote-registrerade. Security Advisor visar ingen ny media-/RLS-varning; endast den tidigare kända Auth-varningen för läckta lösenord kvarstår.
- Riktad TEAM-02-svit efter uppladdningsändringen: **7/7 passerar**.
- Full Flutter-regression efter det nya RosterServices-/Storage-kontraktet: **369/369 passerar**.
- Fysisk Xiaomi Mi 9-verifiering bekräftade filval, lokal förhandsvisning, privat upload, sparad profil, signerad återläsning, bildvisning och efterföljande bildbyte. Första försöket hittade en verklig saknad Storage SELECT-policy: objektet och profilaktiveringen var korrekta men signerad URL kunde inte skapas och sidan fortsatte ladda. Den medlemsbundna policyn lades till och omtest passerade utan att bilden behövde laddas upp igen.
- Slutlig Xiaomi-kontroll bekräftade även `Ta bort lagbild`, neutral fallback och att både översikten och redigeringsdialogen förblir läsbara/skrollbara med cirka 200 % textstorlek. Bilden kunde därefter laddas upp igen.
- Hosted rollback-fixturen `team02_overview_counts_rollback.sql` skapade ett isolerat lag med aktiv, utgången och återkallad invite samt väntande och avslagen ansökan. Actorprojektionen räknade exakt **1 aktiv invite + 1 väntande ansökan**. Efter statusändring till återkallad respektive tillbakadragen räknade nästa projektion **0 + 0**. Hela fixturen avslutades med `ROLLBACK` och markören `TEAM02_OVERVIEW_COUNTS_ROLLBACK_OK`.

## Kvarvarande grind

Ingen kvarvarande grind för TEAM-02. Publik transformerad bildvariant hör till PUB-04 och påverkar inte stängningen av den privata lagöversikten.

## Lokal profilredigering 2026-09-01

TEAM-02 har kompletterats med ett capabilitystyrt formulär för lagtyp, åldersklass, kort presentation och en befintlig HTTPS-lagbild. Player/guardian ser inte redigeringsknappen. En separat edit-projektion hämtar aktuell profilrevision; update-kommandot validerar längder och HTTPS, serialiserar per lag, kräver expected revision, återanvänder idempotensresultat och skriver ett minimerat audit-event utan presentationstext eller URL.

Den nya migreringen är `20260901100421_team02_team_profile_edit.sql` och applicerades 2026-09-01 på den uttryckligen godkända Supabase-testdatabasen `hgcshgunvooyudvrcpig`. Säker filuppladdning är medvetet inte låtsasaktiverad: den kräver senare privat staging, skanning och en godkänd bildvariant.

Verifiering:

- TEAM-01/02 riktad Flutter-regression: 7/7.
- Riktad Dart-analys av ändrade roster-, lokaliserings- och testfiler: inga problem.
- Transaktionsbunden Supabase-testdatabasvalidering skapade båda publika RPC-signaturerna (`read_rpc=true`, `write_rpc=true`) och rullade därefter tillbaka hela migreringen utan bestående liveändring.
- Bestående testdatabasdriftsättning verifierades med `read_rpc=true`, `write_rpc=true`, execute för `authenticated` och nekad execute för `anon`/`PUBLIC`. Migreringshistoriken matchar den lokala versionen `20260901100421`.
- Den efterföljande ledarkorrigeringen `20260901104226_team02_allow_team_leader_profile_edit.sql` låter `team.roster.manage` redigera endast det egna laget. Hosted funktionsdefinitioner gav `true` för overview/read/write och migreringshistoriken synkroniserades.
- Produktägaren verifierade fysiskt på webb att `Redigera lagprofil` visas för ledarkontot, att formuläret öppnas och att ändringar kan sparas mot backend.
- Full `flutter analyze` startade men fastnade utan diagnostik och avbröts kontrollerat; detta ersätts inte felaktigt av den riktade analysen.
5. Genomför fysisk Android-/webbgranskning av bildbeskärning, fallback, långa namn, större text och genvägar.
6. Kör full regressionssvit.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
