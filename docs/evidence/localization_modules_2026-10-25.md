# Modulöversättningar – rättning 25 oktober 2026

Uppföljning av språkregressionen i
[nulägesrapporten](app_status_review_2026-10-25.md), utförd efter
dokumentationsavstämningen samma dag. Rättningen är nu pushad och driftsatt
till audit-webben; se [releasekvittot](audit_release_2026-10-25.md).

## Ändring

- De 64 olika texter som språkgrinden rapporterade har fått engelska
  översättningar i `AppStrings`.
- Träningsmodulens sex UI-filer använder språkstödet för rubriker, formulär,
  status, fel, publicering, tidsplanering, närvaro och utvärdering.
- Dynamiska antal, tidsangivelser, dagar och stjärnbetyg har lokalanpassade
  formuleringar. Träningsdelar, spelskeden och utvärderingsalternativ
  lokaliseras vid visning; deras lagrade enumvärden ändras inte.
- Modulernas namn, beskrivningar och åtkomstetiketter i Arbetsytor visas
  på engelska för engelskt språkval. Okända moduler behåller serverns text.
- Det gemensamma kortet med förslag från lagets plan har lokaliserade
  rubriker; användarnas egna mål och spelprinciper översätts inte.
- Träningens utvärderingssammanfattning använder radbrytning på smala
  skärmar. Det nya engelska testflödet upptäckte en horisontell överrinning
  i kombinationen stjärnor och måluppfyllelse, som rättades med `Wrap`.
- Lokaliserade felmeddelanden efter asynkrona skrivningar använder
  språkobjektet som hämtats före anropet, utan ny kontextläsning efter await.

Språkgrindens befintliga kontroll för hårdkodad text omfattar nu även
träningsvyerna. Ett nytt engelskt widgetflöde går genom Arbetsytor,
träningsöversikten, övningsdialogen med spelskede, sparande och utvärdering.
Det verifierar även att svenska övningsnamn och fria anteckningar bevaras.

## Verifiering

| Kontroll | Resultat |
|---|---|
| Riktad regression: språkgrind, träning, matchplan, lagutveckling | 22/22 godkända. |
| Full Flutter-regression | **810/810 godkända**, inklusive den tidigare underkända språkgrinden och det nya engelska flödet. |
| Statisk analys | Godkänd efter samtliga kod- och layoutändringar: inga analysfynd. |
| Dart-format | 13 kontrollerade filer, inga formatändringar behövdes. |

Körkommandon:

```powershell
flutter test test/fnd05_accessibility_localization_test.dart test/training_module_test.dart test/match_plan_test.dart test/team_development_module_test.dart
flutter test
flutter analyze
```

Ovanstående är den ursprungliga lokala verifieringen. Efterföljande
release-webb, GitHub-verifiering och auditdriftsättning redovisas i releasekvittot.
Ingen APK/AAB, iOS-byggnad eller fysisk enhetsprovning ingick.
Övriga drift-, databas- och releasepunkter följs i
[aktuell leveransstatus](../implementation/current_status.md).
