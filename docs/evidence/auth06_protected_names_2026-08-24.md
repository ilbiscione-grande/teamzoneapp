# AUTH-06 – Skyddade namn och officiell klubb

**Datum:** 2026-08-24  
**Status:** KLAR – HOSTED, AUTOMATISKT OCH FYSISKT VERIFIERAD
**Livepåverkan:** Migrationen är applicerad mot det godkända Supabase-testprojektet `hgcshgunvooyudvrcpig`.

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
- Riktad AUTH-04–AUTH-06-svit efter retryfix: **13/13 passerar**.
- Full Flutter-regression 2026-09-11: **363/363 passerar** och full analys rapporterar **No issues found**.
- Widgettest verifierar att ett skyddat namn stoppas före klubbskapande.
- Källkontrakt verifierar normalisering/homoglyph, reservnamn, trigger, neutralt granskningssvar, auditkommandon samt service-role-only för beslut och återkallelse.
- Lokaliseringsregressionen verifierar att ny användartext har svensk och engelsk variant.
- Migrationen ingår i den synkade hosted migrationsbackloggen som stängdes 2026-09-04.
- Hosted rollback-matris verifierar `Team-Zone`, kyrillisk homoglyph och befintligt klubbnamn som neutralt `review_required`, ett unikt namn som `available`, nekad anon-/authenticated-beslutsåtkomst, idempotent begäran, servicebeslut, återkallelse, fortsatt namnskydd och trestegs-audit.
- Matrisen hittade att retry tidigare nådde `invalid_status` efter första lyckade submit. Framåtmigration `20260910202427_auth06_fix_verification_request_replay.sql` flyttar den aktörsbundna dedupe-kontrollen före statuskontrollen; omkörd matris passerar och rullas tillbaka helt.
- Lokal och remote migrationshistorik är helt synkad genom `20260910202427`.
- Fysisk Android-verifiering på Xiaomi Mi 9 bekräftar hela statuskedjan för `Genomfångsklubben`: inofficiell status, validering av underlagets minlängd, inskickad begäran med `Granskning pågår`, TeamZone-godkännande med officiell markering samt återkallelse med tydlig återkallad status och möjlighet att skicka nytt underlag.
- Den fysiska statuskontrollen använde testprojektets service-skyddade beslutsfunktioner. Klienten kunde varken godkänna eller återkalla status själv.
- Fysisk Android-verifiering med `coach.emilson+tzprotected@gmail.com` bekräftar att `Team-Zone` blockeras före skapande och visar den neutrala texten om skyddat eller befintligt namn.
- Samma yta har nu **Kontakta TeamZone** med ett redigerbart, förifyllt meddelande som inkluderar klubb- och lagnamn. Den fysiska inskickningen lyckades och en skrivskyddad databaskontroll bekräftade ett `pending`-ärende med rätt klubb/lag, 168 teckens meddelande och exakt en auditpost.
- Migration `20260911151216_auth06_protected_name_support_cases.sql` lagrar ärenden i privat schema. Den sökande kan endast skapa och läsa sina egna ärenden. En separat plattformsroll i `internal.support_admins` krävs för kö och handläggning; klubbroller ger aldrig åtkomst.
- Support-admin kan lista kön samt markera granskning, lösa eller avslå med revisionskontroll, idempotens och audit. Menylänken styrs av den minimala serverproben från `20260911173942`; behörighetsgränsen rättades i framåtmigration `20260911175910` efter att rollbacktestet hittade att den första invoker-wrappen inte kunde passera den privata EXECUTE-gränsen.
- Hosted rollback-matrisen `auth06_protected_name_support_cases_rollback.sql` bekräftar egen läsning, nekad vanlig kö-/skrivåtkomst, support-admins listning/handläggning, menyprob, retry, revision och två auditsteg. Den tillfälliga support-adminrollen och testärendet rullas tillbaka helt.
- Backendansluten Android-APK med sökande- och supportadminytan kompilerades och installerades. Flutter-analysen var ren före adminytan; därefter fastnade analys-/widgettestprocessen utan diagnostik, medan det fullständiga APK-bygget verifierade Dart-kompileringen.
- Efter uttryckligt godkännande tilldelades `coach.emilson@gmail.com` aktiv `support-admin`; tilldelningen har en separat auditpost. Fysisk Xiaomi-verifiering bekräftade att **Supportärenden** visas, att ärendet kan flyttas från Väntar till Granskas och därefter lösas med obligatorisk beslutsanteckning. Slutlig skrivskyddad kontroll gav `resolved`, revision 3, rätt handläggare, 63 teckens beslutsanteckning och tre auditsteg.
- Lokal och remote migrationshistorik omfattar supportflödet och dess framåträttning genom `20260911175910`.

## Kvarvarande grind

Ingen kvarvarande AUTH-06-grind.

Ingen ändring gjordes i äldre TeamZone-projekt eller äldre databaser.
