# AUTH-06 – Skyddade namn och officiell klubb

**Datum:** 2026-08-24  
**Status:** LOKALT IMPLEMENTERAD OCH KLIENTVERIFIERAD, SQL-RUNTIME/FYSISK GRIND ÅTERSTÅR  
**Livepåverkan:** Ingen. Migrationen har inte applicerats mot Supabase live.

## Implementerat

- Klubbnamn normaliseras serverstyrt med diakritik-, skiljetecken- och vanliga kyrilliska homoglyph-varianter.
- Ett privat register stödjer skyddade kanoniska namn, kända varianter och förkortningar utan att exponera skyddslistan för klienten.
- Klienten får endast neutrala svar: `available`, `review_required` eller `invalid`.
- En databas-trigger stoppar även skapande eller namnbyte som försöker kringgå förhandskontrollen.
- Väntelägets klubbformulär kontrollerar namnet före skapande och visar ett neutralt, lokaliserat granskningsbesked.
- Behörig klubbansvarig kan i Laget-vyn se inofficiell, väntande, officiell, avslagen eller återkallad status med både ikon och text.
- Underlag kan skickas idempotent för TeamZone-granskning; pending-status och underlagshändelse auditloggas.
- Godkännande, avslag och återkallelse finns endast som service-role-kommandon. Klienten saknar beslutskommandon och direkt tabellåtkomst är återkallad.
- Ett godkänt officiellt klubbnamn förs automatiskt in i skyddsregistret. Återkallelse frigör inte namnet för kopior.

## Verifiering

- Direkt Flutter-analys: **No issues found**.
- Riktad AUTH-04–AUTH-06/FND-05-svit: **16/16 passerar**.
- Widgettest verifierar att ett skyddat namn stoppas före klubbskapande.
- Källkontrakt verifierar normalisering/homoglyph, reservnamn, trigger, neutralt granskningssvar, auditkommandon samt service-role-only för beslut och återkallelse.
- Lokaliseringsregressionen verifierar att ny användartext har svensk och engelsk variant.
- Ingen åtkomst till eller ändring av Supabase live gjordes.

## Kvarvarande grind

1. Exekvera migrationen i lokal eller separat uttryckligen godkänd testdatabas.
2. Verifiera normaliserings- och homoglyph-fixtures, samtidiga ansökningar, RLS/ACL och nekad direkt klientmutation med riktiga JWT-roller.
3. Verifiera TeamZone-beslut och återkallelse med service-role-fixtures samt fullständigt auditspår.
4. Genomför fysisk Android-granskning av namnblockering, status och underlagsformulär.
5. Kör full regressionssvit.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
