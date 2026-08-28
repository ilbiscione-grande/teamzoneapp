# AUTH-07 – Villkor, integritet och frivilliga samtycken

**Datum:** 2026-08-24  
**Status:** LOKALT IMPLEMENTERAD OCH KLIENTVERIFIERAD; JURIDISKT INNEHÅLL, SQL-RUNTIME OCH FYSISK/HOSTED GRIND ÅTERSTÅR  
**Livepåverkan:** Ingen. Migrationen har inte applicerats mot Supabase live.

## Implementerat

- En autentiserad användare passerar en fail-closed juridisk statusgrind innan profil, klubb eller lagdata laddas.
- Aktiv version och publik URL lagras separat för användarvillkor respektive integritetspolicy.
- Användaren intygar separat att villkoren godkänns och att integritetspolicyn har lästs.
- Acceptansen lagras per profil, dokumenttyp och exakt version med tidpunkt och källa.
- En ny aktiv materiell version saknar automatiskt acceptans och visar därför grinden igen.
- Servern avvisar stale submit om dokumentversionen ändrats medan formuläret varit öppet.
- Marknadsföring är en separat frivillig inställning, är av som standard och krävs aldrig för att fortsätta.
- Marknadsföring kan senare stängas av eller aktiveras i Integritetsinställningar utan påverkan på appfunktionerna.
- Acceptans och ändrad marknadsföringsinställning är idempotenta och har separata auditkommandon.
- Generella juridiska attesteringar använder inte och ändrar inte tabellerna för minderårig-, guardian- eller publiceringssamtycke.
- All ny användartext har svensk och engelsk lokalisering.

## Verifiering

- Direkt Flutter-analys: **No issues found**.
- Riktad AUTH-04–AUTH-07/FND-05-svit: **18/18 passerar**.
- Widgettest verifierar att appinnehåll blockeras, båda obligatoriska attesteringarna krävs och marknadsföring förblir av om användaren inte väljer den.
- Källkontrakt verifierar versionslås, false-default, separat opt-out-kommando, audit och frånvaro av guardian-/publiceringskoppling.
- Lokalisering och tillgänglighetsregression passerar.
- Säkerhetsutformningen följer aktuell Supabase-vägledning: privata tabeller, explicit RLS/revoke, tom `search_path` och explicita funktionsgrants.
- Ingen åtkomst till eller ändring av Supabase live gjordes.

## Kvarvarande grind

1. Privacy/legal måste godkänna de faktiska dokumenttexterna, versionsbeteckningarna och publika URL:erna. De lokala seedvärdena är inte ett juridiskt godkännande.
2. Exekvera migrationen i lokal eller separat uttryckligen godkänd testdatabas.
3. Verifiera RLS/ACL, stale versionsbyte, idempotent retry och audit med riktiga JWT-roller.
4. Genomför fysisk Android- och webbgranskning av dokumentlänkar, textskalning, tangentbord/fokus och opt-out.
5. Kör full regressionssvit.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
