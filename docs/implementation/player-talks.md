# Spelarsamtal

**Status: byggd och driftsatt 2026-11-25.** Beslutad av produktägaren samma dag som första delen av IDP:n (MFD-09: mål, aktiviteter och avstämningar; ett samtal är en avstämning).

## Hur det fungerar

- **Var:** spelarens profil, fliken *Samtal*, senaste först. Från ett enkätsvar (profilens flik *Enkäter* och enkätens *Svar*) öppnar knappen *Spelarsamtal* samtalet som utgår från svaret, eller ett nytt.
- **Innehåll:** datum, ledarna som var med, valfritt enkätsvar som underlag, *Ledarnas anteckningar* och *Vi kom överens om*. Enkätsvaret visas bredvid på dator och som utfällbar del på telefon.
- **Sparas medan man skriver.** Inget sparas förrän något är skrivet. Att lämna sidan väntar på sista sparningen och varnar om den misslyckas. Någon annans ändring skrivs aldrig över (revision, `PT409`); texten kan då kopieras.
- **Ta bort** bekräftas två gånger.

## Behörighet och data

- Lagets ledare med `development.manage` och modulen Säsongsplanering (`internal.player_talk_club`); ändra kräver att modulen inte är skrivskyddad. Ingen läser samtal om sig själv. Inget delas med spelaren eller vårdnadshavare.
- Anteckningarna ligger i `core.player_talks`, skilt från `core.development_plans` som spelaren kan läsa. *Vi kom överens om* är en egen kolumn så att den kan delas utan anteckningarna.
- Hälsa och bestraffningar ingår inte (MFD-09); det står vid fältet, liksom att texten kan begäras ut.
- Samtalet finns kvar om enkätsvaret tas bort eller spelaren lämnar laget. När en person raderas (anonymiseras) tas personens samtal, enkätsvar och enkätlänkar bort (triggern `erase_player_talks_and_surveys`). Före den här migrationen låg enkätsvaren kvar.
- Spårningen (`audit.command_events`) säger att ett samtal skrevs eller togs bort, aldrig vad som stod.
- Migration `20270425090000_player_talks.sql`. Tester: `supabase/tests/player_talks.local.mjs`, `test/player_talks_test.dart`.

## Kvar att avgöra med resten av IDP:n

- Om och när *Vi kom överens om* delas med spelaren och blir mål.
- Vad vårdnadshavare ser, per ålder.
- Hur länge samtalen sparas, och om det ska stå i integritetstexten.
