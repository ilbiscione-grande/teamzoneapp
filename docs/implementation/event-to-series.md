# Göra ett befintligt event till en serie

Status: **planerad, inte byggd** (beslut 2026-11-17: inte nu).

## Nuläge

Ett event är engångsevent eller serie från början och kan inte göras om
efteråt.

- Formuläret visar "Återkommande serie" bara när ett event skapas
  (`creating` i `lib/src/features/calendar/calendar_surface.dart`).
- Serier skapas bara av `api.create_event_v2`, som lägger in ett event per
  tillfälle med samma `recurrence_id`.
- `api.revise_event_v3` ändrar fält inom scope `one`/`forward`/`all` men
  kan inte lägga till tillfällen eller sätta `recurrence_id`.

Det man kan göra i dag är att skapa en ny serie från samma dag och ta bort
engångseventet. Svar, deltagare och resursbokningar på det gamla eventet
följer inte med.

## Förbättringen

Ledaren öppnar ett engångsevent, slår på "Återkommande serie", väljer
frekvens och slutdatum och sparar. Det befintliga eventet blir seriens
första tillfälle och behåller allt det har. Följande tillfällen skapas
efter det.

## Att lösa när det byggs

- Ny serveråtgärd (till exempel `api.extend_event_to_series`) med
  revision, idempotensnyckel och samma gränser som när en serie skapas
  (2–104 tillfällen, ingen serie för matcher).
- Vad nya tillfällen ärver: typfält, audience, plats, kallelser och
  träningspass.
- Resursbokningar: bara det första tillfället har bokning. Bestäm om nya
  tillfällen ska bokas eller om ledaren hänvisas till Bokningshanteraren.
  Seriegrunder får inte hamna i otakt (se
  [seriegrunder](../evidence/booking_series_plans_2026-10-31.md)).
- Notiser: ett meddelande om den nya serien, inte ett per tillfälle.
- Konflikter med `forward`/`all`-ändringar som redan förutsätter ett
  ankare i serien.
