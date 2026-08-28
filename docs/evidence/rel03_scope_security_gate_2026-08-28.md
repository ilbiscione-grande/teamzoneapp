# REL-03 – scope- och säkerhetsgrind (2026-08-28)

## Resultat

Den skrivskyddade grinden `tool/release_scope_gate.ps1` passerar med `REL03_SCOPE_GATE_OK`.

Verifierat:

- `C:\Dev\TeamZone` är en läsbar och git-ren worktree; inga ändringar gjordes där.
- Produktkod, klientkonfiguration och runtimeverktyg refererar inte till den gamla projektsökvägen.
- Den aktuella auditmiljön är `hgcshgunvooyudvrcpig` och Firebaseprojektet är `teamzoneapp-b02a2`.
- Produktion är `not_provisioned` och har varken Supabase- eller Firebaseprojektreferens.
- Roten innehåller inga `webtools`- eller `workspaces`-kataloger.
- Releaseverktygen innehåller inga `supabase db push`, `supabase functions deploy`, `firebase deploy` eller `flutterfire configure`.
- Android namespace och applicationId är `com.teamzone.teamzone`.
- iOS huvudtargets använder `com.teamzone.teamzone`.
- Varje arbetskort som är `[x]` eller `[~]` har minst en motsvarande evidencefil.

## Supabasegräns

Ingen Supabaseanslutning eller liveändring gjordes under REL-03. Tidigare livearbete är dokumenterat i separata slice-/rolloutbevis, bland annat `hosted_core_migration_rollout_2026-08-27.md`. Den här grinden validerar lokala mål och verktygsgränser; den försöker inte skriva eller provisionera något.

## Öppen leveransgräns

Arbetsytan saknar fortfarande en första git-commit. Filerna är därför lokalt bevarade men det finns ingen revisionsidentifierad återställningspunkt för den samlade leveransen. Dessutom är REL-01 och REL-02 partiella. Den sista REL-03-punkten och hela kortet står därför korrekt som `[~]`.

## Kontroller

- `tool/release_scope_gate.ps1`: godkänd.
- Paket-/runtime-referensscan: godkänd.
- PowerShell-syntax och `git diff --check`: godkända.
