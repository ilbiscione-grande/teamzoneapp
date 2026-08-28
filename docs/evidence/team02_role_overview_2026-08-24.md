# TEAM-02 – Rollstyrd lagöversikt

**Datum:** 2026-08-24  
**Status:** LOKALT IMPLEMENTERAD OCH KLIENTVERIFIERAD; SQL-RUNTIME OCH FYSISK/HOSTED GRIND ÅTERSTÅR  
**Livepåverkan:** Ingen. Migrationen har inte applicerats mot Supabase live.

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
- Ingen åtkomst till eller ändring av Supabase live gjordes.

## Kvarvarande grind

1. Exekvera migrationen i lokal eller separat uttryckligen godkänd testdatabas.
2. Verifiera outsider/cross-club, player/guardian, team leader och club administrator med riktiga JWT-roller.
3. Verifiera invite-/ansökningsräknare, utgångna invites och samtidiga statusändringar mot SQL-fixtures.
4. Fastställ senare redigerings-/uppladdningsflöde och Storage-policy för lagbild; TEAM-02 läser endast en redan godkänd HTTPS-bildadress.
5. Genomför fysisk Android-/webbgranskning av bildbeskärning, fallback, långa namn, större text och genvägar.
6. Kör full regressionssvit.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
