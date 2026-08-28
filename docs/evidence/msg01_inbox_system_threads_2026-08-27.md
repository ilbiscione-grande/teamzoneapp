# MSG-01 – Inbox och automatiska systemtrådar

Datum: 2026-08-27  
Status: lokalt genomfört, runtime/fysisk verifiering återstår

## Levererat

- Inbox söker i ämne, preview, senaste avsändare och trådtyp.
- Horisontella filter finns för Alla, Olästa, Lag, Ledare och Tystade.
- Varje rad visar unread-badge, muteikon, senaste preview/avsändare och lokal datum/tid.
- Manuell pull-to-refresh kompletteras med privat Realtime-topic `message:inbox:{auth.uid}`. Invalidation och reconnect debouncas 300 ms före full serverresync.
- Varje aktivt lag får exakt en `team`- och en `leader`-tråd genom unik `(team_id, thread_kind)`-bindning.
- Trådar skapas vid laginsert/lagstatus och reconcileras efter assignment-, person-account-link- och capabilityförändringar.
- Lagchatten härleder deltagare från aktiva lagassignment och aktiva kontolänkar. Avslutad relation blir synligt borttagen från aktivt deltagande utan att historiken förstörs.
- Ledarchatten kräver dessutom aktiv leader-assignment med aktuell `team.roster.view`-grant vid reconciliation.
- Den centrala `actor_can_access_thread` återkontrollerar samma capability vid varje läsning och sändning. En gammal deltagarrad räcker alltså inte.
- Lagarkivering stänger systemtrådarna och tar bort aktiva deltaganden; återaktivering kan reconcileras.

Supabase-skillens säkerhetschecklista styrde gränsen: systembindningstabellen saknar klientgrants, RLS är fail-closed, Realtime-policy binder topic exakt till `auth.uid()` och service-sync exponeras endast för `service_role`.

## Verifiering

- Direkt Dart-format: 3 filer, 0 återstående ändringar.
- Statisk SQL-/UI-kontraktsgrind: godkänd.
- Migrationen har 14 dollar-quotes, 7 funktionsdefinitioner och jämnt quote-antal.
- Ett riktat Flutter-kontraktstest har lagts till för systemtrådar, capability, privat resync samt sök/filter.
- `flutter analyze` och `flutter test` startade men gav ingen output och avbröts kontrollerat efter den kända lokala wrapper-/analysserverlåsningen.
- Direkt `dart test` är inte en giltig ersättning eftersom projektet använder `flutter_test`; den vägen avvisades utan beroendeändring.

## Återstår

- PostgreSQL-runtime och Security/Performance Advisors.
- Körning av `flutter analyze` och `flutter test test/msg01_inbox_system_threads_test.dart` i fungerande Flutter-runner.
- Fysisk verifiering med minst leader och player: initiala systemtrådar, send/unread/read, mute, join/leave, capability revoke och reconnect/resync.
- Separat godkännande före eventuell Supabase-liveändring.

Ingen Supabase-liveändring, driftsättning, webtools eller workspace utfördes.
