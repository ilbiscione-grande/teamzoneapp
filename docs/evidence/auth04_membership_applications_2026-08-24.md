# AUTH-04 – Sök klubb/lag och medlemsansökan

**Datum:** 2026-08-24  
**Status:** IMPLEMENTERAD OCH VERIFIERAD MOT HOSTED TESTDATABAS SAMT FYSISK ANDROID  
**Livepåverkan:** AUTH-04 är aktiv i det uttryckligen godkända Supabase-testprojektet. Ingen produktionsmiljö har ändrats.

## Implementerat

- Autentiserad sökning kräver 3–80 tecken, returnerar högst 20 resultat och exponerar endast klubb-ID/namn/officiell status samt lag-ID/namn.
- Vänteläget kan söka klubb/lag, visar officiell respektive inofficiell klubb med ikon och text och låter användaren välja spelare, ledare, vårdnadshavare eller klubbfunktionär.
- Ansökan är idempotent och en partiell unik nyckel förhindrar flera samtidiga pending-ansökningar för samma användare, lag och roll.
- Sökanden kan endast lista sina egna ansökningar och återkalla en egen pending-ansökan.
- Beslutsfunktionen kräver `club.memberships.manage`, låser ansökan, skapar person/relation/assignment atomiskt vid godkännande och auditloggar beslutet.
- Ansökningstabellen har RLS men inga direkta klientgrants. `internal`-funktioner har tom `search_path`, explicit authkontroll och explicita execute-grants; `anon` saknar åtkomst.
- Alla nya användartexter går genom sv/en-lokaliseringsgränsen.
- Laget visar endast granskningskön för kontexter med `club.memberships.manage`.
- Reviewer-kön visar minimerad sökandeprofil, lag och begärd roll; godkänn/avslag kräver uttrycklig bekräftelse och har pending-/retry-skydd.

## Verifiering

- Direkt Dart-analys: **No issues found**.
- Riktad AUTH-04-svit: **3/3 passerar**.
- Kombinerad AUTH-04/FND-05-svit efter lokaliseringsrättning: **12/12 passerar**.
- Fullsviten nådde **132 godkända tester** och upptäckte en saknad engelsk AUTH-04-text. Felet rättades och den berörda AUTH-04/FND-05-grinden passerar; fullsviten kördes inte om därefter.
- Supabase officiella RLS/Data API-råd kontrollerades före implementation. Privata tabeller exponeras inte; funktionsgrants är explicita.

## Hosted runtime och fysisk Android-verifiering 2026-09-03–2026-09-10

- Hosted runtimeprov hittade en tvetydig `requested_role`-referens i medlemsansökans `ON CONFLICT`. Migration `20260903103734_auth04_fix_membership_request_role_ambiguity.sql` behåller RPC-signaturen men gör parameter-/kolumnupplösningen explicit.
- Efter fixen passerade sökning med minimerat svar, ansökan, egen väntelista, idempotent replay, reviewer-kö, avslag och beslutsreplay i en helt återställd transaktion.
- Fysisk Android-verifiering bekräftade sökning efter Thomas klubb/Thomas lag, tydlig inofficiell status, samtliga fyra rollval, en enda pending-post vid upprepad ansökan, återkallelse och bevarad statushistorik.
- En användare med befintlig klubbkontext kunde först inte nå sina andra ansökningar. Lag-/rollväljaren innehåller nu `Hitta klubb eller lag`, så sökning och ansökningshantering finns även utanför väntrummet.
- Upprepad identisk ansökan visar nu att ansökan redan väntar på svar i stället för att upplevas som ett tyst knapptryck.
- Fysisk reviewer-kontroll hittade en skillnad mellan översiktens synlighet och granskningsbehörigheten. Migration `20260910175749_auth04_allow_team_leader_membership_review.sql` tillåter `team.roster.manage` endast för en explicit teamkö och beslut i samma team; klubbövergripande kö kräver fortsatt `club.memberships.manage`.
- Ledarkontot kunde därefter öppna kön direkt från `Väntande ansökningar`, se minimerad sökandeinformation, avslå och godkänna. Sökanden såg `Avslagen` efter avslag och fick en fungerande `Thomas lag · Spelare`-kontext efter godkännande.
- Reviewer kan korrigera rollen vid godkännande. Migration `20260910181550_auth04_reviewer_role_override.sql` bevarar ansökt roll, sparar faktiskt godkänd roll separat och auditloggar avvikelsen. Ett återställt runtimeprov verifierade `leader` som ansökt roll, `player` som godkänd/tilldelad roll, exakt ett override-event och idempotent replay.
- Den fysiska Android-kontrollen verifierade samma flöde mellan Thomas klubb och Genomfångsklubben: dialogen visade `Ansökt som: Ledare`, ledaren valde `Godkänn som: Spelare` och sökandens nya kontext blev F2014 · Spelare.
- Riktad AUTH-04-svit passerar **11/11** efter runtime- och UX-fixarna. TEAM-05:s separata inbjudningslista grupperar nu aktiva respektive tidigare poster och passerar **13/13** tester.

## Kvarvarande generell uppföljning

1. Full regressionssvit körs i den samlade releasegrinden; AUTH-04:s riktade grind är grön.

Ingen produktionsmiljö, äldre TeamZone-projekt eller äldre databas har ändrats.
