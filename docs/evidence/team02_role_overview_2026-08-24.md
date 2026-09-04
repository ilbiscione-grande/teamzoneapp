# TEAM-02 – Rollstyrd lagöversikt

**Datum:** 2026-08-24  
**Status:** IMPLEMENTERAD; HOSTED SQL-RUNTIME OCH FYSISK WEBBGRIND VERIFIERADE, ANDROID-/MEDIAGRIND ÅTERSTÅR  
**Livepåverkan:** TEAM-02:s profil- och ledarbehörighetsmigreringar är applicerade på den uttryckligen godkända testdatabasen `hgcshgunvooyudvrcpig`.

## Implementerat

- En privat `core.team_profiles`-modell lagrar kort laginformation, lagtyp, åldersklass och godkänd HTTPS-adress till lagbild.
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

## Verifiering

- Direkt Flutter-analys: **No issues found**.
- Riktad TEAM-02/TEAM-01/AUTH-03/FND-05-svit: **18/18 passerar**.
- Positivt ledartest verifierar lagidentitet, ledare, genvägar, invite- och ansökningsbehov.
- Negativt spelartest verifierar att administrativa rubriker och räknare inte renderas.
- Källkontrakt verifierar privat tabell, klubbåtkomst, capabilitygrind, nollad adminprojektion och avsaknad av direkta grants till ansökningstabellen.
- Säkerhetsutformningen följer aktuell Supabase-vägledning med explicit RLS/revoke, privat definer-funktion, tom `search_path` och explicit RPC-grant.
- Hosted RPC-signaturer, execute-grants och nekad `anon`/`PUBLIC`-åtkomst verifierades 2026-09-01.

## Kvarvarande grind

1. Slutför kvarvarande Androidgranskning av profilredigering, större text och bildfallback.
2. Verifiera invite-/ansökningsräknare, utgångna invites och samtidiga statusändringar mot SQL-fixtures.
3. Fastställ senare redigerings-/uppladdningsflöde och Storage-policy för lagbild; TEAM-02 läser endast en redan godkänd HTTPS-bildadress.

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
