# Hosted database lint – 2026-09-11

**Omfattning:** skrivskyddad `supabase db lint --linked` mot `core`, `internal`, `api` och `audit` i det godkända testprojektet `hgcshgunvooyudvrcpig`.

AUTH-06- och AUTH-07-funktionerna gav inga lintfynd. Den globala körningen returnerade däremot befintliga fynd utanför de två kortens omfattning:

- TEAM-06: tvetydig `starts_at` i `internal.create_play_eligibility_for_actor`.
- CAL-03: linter kan inte härleda den sessionsskapade temporära tabellen `pg_temp.cal03_shared` i `internal.update_event_sharing_for_actor`.
- PUB-03: tvetydig `article_id` i `internal.save_editorial_article_for_actor`.
- AC: typ-/volatilitetsfynd i `internal.list_assistant_signals_for_actor` och tvetydig `area_key` i `internal.set_assistant_area_preference_for_actor`.
- Två extra warnings: oläst variabel i medlemsansökningsbeslut och skuggad/oanvänd loopvariabel i eventskapande.

Fynden är dokumenterade som en separat stabiliseringsbacklog. Ingen av dessa funktioner ändrades under AUTH-06/07 och lintresultatet används inte som grund för att felaktigt klarmarkera deras respektive arbetskort.
