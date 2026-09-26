# CAL-02 – skapa och redigera event/serie

Datum: 2026-08-27, slutverifierad 2026-09-17  
Status: genomförd och verifierad mot hosted testdatabas samt fysisk webb

## Levererat i klienten

- Samma fullständiga editor används för nytt event och redigering.
- Titeln genereras från eventtypen: `Träning`, `vs Motståndare`, `Möte` eller `Aktivitet`.
- Formuläret omfattar typstyrda uppgifter, beskrivning, lag, kompakt status, start/slut, samling, heldag, tidszon, plats och audience.
- Träning har tema, fokus och träningsplan; match har motståndare, hemma/borta och matchanteckningar; möte har syfte och agenda.
- Samlingstid är redigerbar med standard 15 minuter för träning/aktivitet, 75 för match och 5 för möte.
- Planerad (`scheduled`) är standard; en kompakt statusikon kan växla nya event till/från utkast.
- Audience kan väljas direkt mellan spelare, ledare, vårdnadshavare och hela klubben; minst ett val krävs.
- Engångsevent eller daglig/veckovis serie skapas med start- och slutdatum; klienten räknar deterministiskt fram 2–104 förekomster från valt intervall.
- Serier måste vid redigering välja `Bara detta`, `Detta och framåt` eller `Hela serien`.
- EventDetails kan publicera utkast, återställa inställda event, ställa in och markera planerade event som genomförda via befintlig revisionssäker transition.
- Formuläret har osparade-ändringar-skydd och begripliga valideringsfel.

## Serverkontrakt

- `create_event_v2` och `revise_event_v3` lagrar typfälten strukturerat och verifierar auth, `event.manage`, tenant, revision, tillåtna fält och one/forward/all.
- Ett transaktionsbundet advisory lock serialiserar hela eventserien.
- Ny ankartid omvandlas till en delta som appliceras på varje vald förekomst; förekomster kollapsar därför inte till samma timestamp.
- Ändrad sluttid blir en gemensam validerad duration relativt varje förekomsts nya start.
- Hela-serien-redigering uppdaterar recurrence rule-local start och tidszon.
- Audience för det ägande laget ersätts atomiskt, medan framtida shared-team-specifika audience-rader bevaras inför CAL-03.
- Platsnamn återanvänds inom klubben eller skapas tenantbundet; tom plats rensar kopplingen.
- Revision, event revision snapshot, outbox, command deduplication och audit uppdateras per berörd förekomst.

## Sparade platser

- `list_saved_event_locations` kräver `event.manage` för exakt klubb-/lagkontext.
- Queryn filtrerar alltid `event_locations.club_id = target_club_id`, normaliserar dubblettnamn och returnerar högst 100 förslag.
- Ett sammansatt klubb-/normaliserat namn-/recent-index stöder queryn.
- Klienten visar högst åtta tydliga förslagschips och tillåter fortfarande ett nytt platsnamn.

## Filer

- `lib/src/features/calendar/calendar_surface.dart`
- `lib/src/features/calendar/calendar_services.dart`
- `lib/src/core/localization/app_strings.dart`
- `supabase/migrations/20260827063902_cal02_event_editor_locations.sql`
- `supabase/migrations/20260915104026_cal02_typed_event_fields_and_assembly.sql`
- `supabase/migrations/20260915153142_cal02_grant_typed_event_commands.sql`
- `supabase/tests/cal02_typed_event_fields_rollback.sql`
- `test/cal02_event_editor_test.dart`

## Verifiering

- Riktad CAL-02-svit: 3/3 godkända.
- Flutter web release kompilerar med audit-konfiguration.
- Hosted migrationshistorik är synkroniserad genom `20260915153142`.
- PostgreSQL-rollbacktest verifierar både create och revise v3, strukturerade fält, samlingstid och revision 2 utan kvarlämnad testdata.
- Fysisk webbgrind verifierar alla fyra eventtyper, automatiska titlar, serieperiod samt `Bara detta`, `Detta och framåt` och `Hela serien`.

## Resultat

CAL-02 är stängd. Ingen separat produktionsprovisionering har gjorts; verifieringen avser det uttryckligen godkända hosted testprojektet `hgcshgunvooyudvrcpig`.
