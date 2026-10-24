# Beslutspaket 12 – matchen live på lagets publika sida

**Status: godkänt av produktägaren 2026-10-24. PLM-01–PLM-09 är beslutade.**

## Mål

När en ledare registrerar händelser i Matchmodulens Live ska lagets publika sida visa matchen live: ställning, klocka och matchens gång i matchrapportens referatstil. När matchen är slut ligger flödet kvar som "Matchens gång", och ledarens matchrapport visas när den publiceras, som idag.

Paketet flyttar en gräns i publiceringsbeslutet (10) och pub07, som hittills bara publicerat uttryckligen publicerade slutresultat: inga spelare, ingen statistik och inga liveresultat. Allt annat i publiceringsmodellen gäller oförändrat: bara uttryckligen publicerad data, minderåriga dolda som standard (PWD-02) och lagstatistik utan återidentifiering i små urval.

## Beslut

| Id | Beslut | Status |
|---|---|---|
| PLM-01 | Spelare nämns vid namn i den publika texten bara med aktivt namnsamtycke (`core.publication_consents`, fältklass `name`, syfte `public_team_profile_v1`, med vårdnadshavarens godkännande när det krävs). Övriga skrivs som "en spelare" eller lagnamnet. Utan samtycke lämnar namnet aldrig databasen till den publika sidan. | Vald |
| PLM-02 | Individuell statistik (spelartabell, speltid, antal per spelare) publiceras inte i detta paket. Den kräver samtycket `individual_statistics` och ett eget beslut. Publikt visas bara händelseflödet och lagens siffror. | Förslag |
| PLM-03 | Laget väljer under Publicering om dess publicerade matcher rapporteras live (standard av). Ledaren kan stänga av, eller slå på, för en enskild match i Live. Live kräver att både laget och eventet är publicerade. | Vald |
| PLM-04 | Det publika flödet tar med mål, avslut, räddningar, straffar, kort, byten och skador. Anteckningar, egna knappar, KPI-räknare, bytesplan och uppställning publiceras inte. | Förslag |
| PLM-05 | Efter slutsignal ligger flödet kvar som "Matchens gång" bredvid resultatet. Matchrapporten (för hand eller skapad från händelserna) visas bara när ledaren publicerar den, som idag. | Vald |
| PLM-06 | Flödet lagras som en publik projektion som databasen skriver efter varje matchkommando: händelsens typ, minut, sida, utfall, ställning, och namn bara enligt PLM-01. En rättad eller borttagen händelse ändras eller försvinner publikt vid nästa skrivning. | Förslag |
| PLM-07 | Referatets formuleringar har en enda källa, en JSON-fil som både appen och den publika sidan läser, så att appens utkast och den publika texten låter likadant. | Förslag |
| PLM-08 | Den publika sidan hämtar en pågående match var 20:e sekund genom den befintliga publika läsvägen, med samma rate limit. Ingen publik Realtime-kanal i detta paket. | Förslag |
| PLM-09 | Stängs live av för en match, eller avpubliceras eventet eller laget, tas flödet bort publikt direkt. | Förslag |

## Ordning

1. Projektionen och dess skrivning efter matchkommandon, inställningen per lag och match, namn enligt samtycke (migration och SQL-test).
2. Formuleringarna som delad JSON; appens generator läser den.
3. Den publika sidan: livekort med ställning, klocka och flöde, uppdatering var 20:e sekund, och "Matchens gång" efter matchen.
4. Inställningarna i appen: under lagets Publicering och knappen i Live.
