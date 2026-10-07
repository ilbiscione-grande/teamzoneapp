# Nyckeltal och uppföljning (steg 1–2)

Mål (KPI:er) sätts under Förberedelser och följs upp under Uppföljning.
Migrationer: `20261008090000_event_kpis_followup.sql` (katalog, mål,
uppföljning) och `20261009090000_match_kpi_counters.sql` (live-räknare i
Matchläge). Tester: `supabase/tests/event_kpis_followup.local.mjs`,
`supabase/tests/match_kpi_counters.local.mjs`, `test/prep01_event_preparation_test.dart`.

## Vad som finns

- Katalog per eventtyp och sport (`internal.event_kpi_catalog()`) plus egna mål.
- `core.event_kpi_targets`: mål, jämförelse, målvärde, synlighet för spelare,
  manuellt utfall. Automatiska värden (närvaro, svar, sena, gjorda/insläppta
  mål) räknas vid läsning.
- Uppföljning-fliken: att göra, närvaro mot lagets snitt, svar, sena,
  frånvaroorsaker, närvarotrend, mål mot utfall med trend.
- Matchläge: +/− för räknebara manuella mål som idempotenta matchkommandon
  (`kpi`-fakta); övriga manuella mål fylls i efter slutsignal.

## Avgränsning mot matchmodulen

Eventytan (Matchläge, Förberedelser, Uppföljning) ska hållas enkel. Det som
finns nu får vara kvar tills vidare, men när matchmodulen byggs **flyttas
de matchspecifika delarna dit**:

- live-räknarna för nyckeltal i Matchläge,
- matchspecifika nyckeltal i katalogen (skott, hörnor, räddningsprocent,
  tekniska fel, bollvinster, speluppbyggnad, "alla spelade en halvlek"),
- matchuppföljning med resultat, händelser, spelartabell och rapport
  (tidigare planerat som steg 3).

Bygg inte ut matchanalys/statistik vidare på eventytan i väntan på det.

## Avgränsning mot träningsmodulen

Samma princip gäller den kommande träningsmodulen, som ska fokusera på
kort- och långsiktig utveckling (lag och individ). Dit hör bland annat
träningsutvärdering, utvecklingsmål över tid, individuella mål och
uppföljning av fokusområden över en säsong. De träningsnyckeltal som finns
i katalogen nu (fokus uppnått, intensitet) är enkla per-pass-mål och kan
flyttas eller ersättas när modulen byggs.

## Det som stannar på eventytan

Det som gäller ett enskilt event oavsett modul: närvaro, svar, sena,
frånvaroorsaker, närvarotrend och enkla mål per event med utfall.
