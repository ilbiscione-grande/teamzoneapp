# AC-04 – Min assistent-identitet och personligt namn

Datum: 2026-08-28  
Status: lokalt implementerad och Flutter-verifierad; mobil namn-UX fysiskt verifierad, PostgreSQL-runtime/kontosynk och standardnamn återstår.

## Levererat

- Ny användarcopy använder **Min assistent** medan befintliga AC-ID:n, route och tekniska nycklar bevaras.
- Assistentytan visar säker fallback och låter användaren spara, ändra eller återställa ett personligt namn.
- Namnet lagras privat per profil, är revisionerat och kommandot är idempotent.
- Namnet används endast för presentation och ingår inte i authorization, RLS eller capabilitybeslut.
- Klient och databas validerar längd och kontrolltecken.
- Klienten varnar när ett namn kan förväxlas med TeamZone, support, officiell avsändare eller legitimerad vårdprofession.
- Det personliga namnet visas tillsammans med funktionsetiketten **Min assistent**, så att identiteten förblir begriplig.

## Säkerhet och datagräns

- `core.assistant_preferences` har RLS aktiverat och saknar direkt tabellåtkomst för `anon` och `authenticated`.
- Läsning och mutation sker via smala autentiserade RPC-funktioner.
- Mutationen använder `expected_revision` och `internal.command_deduplication`.
- Radering av profilen raderar preferensen genom `on delete cascade`.
- Ingen migrering eller annan ändring har körts mot Supabase live.

## Verifiering

- `dart analyze lib test`: inga problem.
- Riktade tester: AC-02, AC-03 och AC-04, 8/8 passerade.
- `git diff --check`: inga whitespace-fel; endast befintliga radslutsvarningar.
- På Xiaomi Mi 9 visade namn-dialogen privat kontosynkcopy, 40-teckensgräns, tom-värde-återställning samt Avbryt/Spara utan overflow med tangentbordet öppet. Ingen namnmutation utfördes.

## Kvarvarande grindar

- Kör migreringen i lokal PostgreSQL och verifiera RPC/RLS när Docker eller motsvarande runtime finns.
- Verifiera sparning, återställning och synk mellan två verkliga klienter för samma konto.
- Besluta och clearera det sportiga internationella standardnamnet separat. Fram till dess är fallback **Min assistent**.
