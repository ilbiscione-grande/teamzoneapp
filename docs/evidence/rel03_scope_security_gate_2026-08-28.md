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

## Återställningsbar leveransgräns

Den första granskade återställningspunkten skapades på `main` som root-commit `bef10fb` (`chore: establish TeamZone rebuild baseline`). Committen innehåller 554 avsedda käll-, test-, migrations-, konfigurations- och evidencefiler. Lokala `.tmp-*`-artefakter, CLI-cache, buildoutput, `node_modules`, lokala miljöfiler och lokal evidence är ignorerade och ingår inte.

REL-01 är grön och den återställningsbara leveransgränsen är nu etablerad. REL-03 står fortsatt som `[~]` enbart eftersom beroendet REL-02 fortfarande har uttryckligen uppskjutna hosted/fysiska slutkontroller.

## Slutlig beroendestängning 2026-09-01

REL-02 är nu grön med 12/12 roll-/enhetsfall, 7/7 avbrottsfall, 5/5 tillgänglighetsområden och `REL02_AUTOMATED_GATE_OK` (44/44). REL-03:s tidigare enda öppna beroende är därmed stängt. Scopegrinden kördes om skrivskyddat och gav `REL03_SCOPE_GATE_OK`; detta innebar ingen produktionsprovisionering, webtools/workspaces-start eller ändring av det gamla TeamZone-projektet.

## Kontroller

- `tool/release_scope_gate.ps1`: godkänd.
- Paket-/runtime-referensscan: godkänd.
- Secret-liknande filnamn och värdemönster granskades; endast dokumenterade rollnamn, placeholders och publika Firebase-klientnycklar förekommer i revisionen.
- Förbjuden stagingkontroll: inga temporära filer, buildoutput, lokala miljöfiler eller lokala evidencefiler.
- Git-återställningspunkt: `bef10fb`.
