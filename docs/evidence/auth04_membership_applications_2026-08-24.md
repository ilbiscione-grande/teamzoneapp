# AUTH-04 – Sök klubb/lag och medlemsansökan

**Datum:** 2026-08-24  
**Status:** LOKALT IMPLEMENTERAD OCH KLIENTVERIFIERAD, SQL-RUNTIME/FYSISK GRIND ÅTERSTÅR  
**Livepåverkan:** Ingen. Migrationen har inte applicerats mot Supabase live.

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

## Kvarvarande grind

1. Exekvera migration och SQL-fixtures i lokal eller separat uttryckligen godkänd testdatabas.
2. Verifiera outsider/cross-club, dubblettansökan, avstängd relation, beslut/replay och samtidiga beslut i SQL-runtime.
3. Verifiera reviewer-kön och godkännande/avslag fysiskt på Android.
4. Köra full regressionssvit igen.

Ingen ändring gjordes i Supabase live, äldre TeamZone-projekt eller äldre databaser.
