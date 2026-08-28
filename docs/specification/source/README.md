# TeamZone rebuild – produktunderlag

## Status

**Produktdeltat med 34 CHG-poster godkändes av produktägaren 2026-08-07.** Godkännandet låser förändringskatalogen som planeringsbas, men inte teknisk lösning, pris eller öppna beslut.

Detta är första målbildslagret ovanpå den godkända auditen. Underlaget bygger på:

- `new_teamzone.md` – produktägarens beskrivning av önskad app.
- `docs/audit_deep_dives/14_rebuild_synthesis/` – verifierat nuläge, fynd, beslut och krav.

Auditdokumenten beskriver **vad som finns och har verifierats**. Denna katalog beskriver **vad rebuilden ska bevara, ändra eller lägga till**. Målbilden är ännu inte en färdig teknisk specifikation och innebär inget implementations- eller deploygodkännande.

## Dokument

- `00_product_vision_and_scope.md` – normaliserad produktvision och scope.
- `01_product_delta.md` – Behåll/Förbättra/Ersätt/Ta bort/Nytt per område.
- `02_decisions_and_questions.md` – beslut som målbilden löser eller skapar.
- `03_target_user_journeys.md` – prioriterade användarresor.
- `04_traceability_matrix.md` – koppling mellan målbild, auditbeslut och rebuildkrav.
- `05_delivery_sequence.md` – rekommenderad ordning för specifikation och implementation.
- `06_identity_role_context_decision.md` – första arkitekturstyrande beslutspaketet.
- `07_person_roster_transfer_decision.md` – andra beslutspaketet om person, roster, lån och övergång.
- `08_event_squad_callup_decision.md` – tredje beslutspaketet om eventägande, squad, kallelse och närvaro.
- `09_messaging_notifications_decision.md` – fjärde beslutspaketet om Inbox, minderårigskydd och meddelandelivscykel.
- `10_publication_privacy_hosting_decision.md` – femte beslutspaketet om publik webb, samtycke och hosting.
- `11_billing_entitlements_decision.md` – sjätte beslutspaketet om klubbplaner, kvoter, moduler och web tools.
- `12_assistant_coach_signals_decision.md` – sjunde beslutspaketet om Assistant Coach, workload och utvecklingsdata.
- `13_workspaces_integrations_decision.md` – åttonde beslutspaketet om Match, Training, Development och web tools.
- `14_economy_boardroom_decision.md` – nionde beslutspaketet om klubbadministration, ekonomi, avgifter och sponsring.
- `15_client_platform_release_decision.md` – tionde beslutspaketet om plattformar, offline, tillgänglighet och release.
- `16_open_parameter_backlog.md` – ägarfördelad backlogg för kvarvarande legal-, metod-, ekonomi-, drift- och säkerhetsparametrar.
- `17_domain_model_and_invariants.md` – domängränser, source of truth, capabilitymodell och invariants.
- `18_target_data_model.md` – logisk mål-datamodell, schemastrategi, constraints och legacy mapping.
- `19_authorization_rls_storage_contract.md` – fail-closed authorization-, RLS-, Storage-, token- och serverkontrakt.
- `20_api_command_query_event_contract.md` – queries, commands, events, Realtime och API-versionering.
- `21_migration_compatibility_verification.md` – additiv migration, cutover, rollback och verifiering.
- `22_step_2_traceability_and_gate.md` – spårbarhet, kända öppningar och godkännandegrind för steg 2.
- `23_technical_security_review.md` – teknisk/säkerhetsmässig review, livebaseline, korrigeringar och implementationsgrindar.
- `24_implementation_slice_plan.md` – taskindelad plan för S01–S11, parameterberoenden, auditgrindar och separata livegodkännanden.
- `25_greenfield_bootstrap_plan.md` – S00 för ny kodbas i `C:\Dev\TeamzoneApp`, toolchain, Fluttergrund, secrets och evidens.

## Nästa grind

Produktdeltat, beslutspaket 1–10, steg 2 och sliceplanen är produktgodkända 2026-08-07. Rebuilden ska vara ett greenfield-projekt i `C:\Dev\TeamzoneApp`; legacyrepot är endast spec-/evidenskälla. Nästa grind är separat tillstånd att köra S00 enligt dokument 25. Därefter krävs nytt implementationstillstånd för S01; varje Supabase-livekörning kräver senare egen evidensreview och uttryckligt godkännande.
