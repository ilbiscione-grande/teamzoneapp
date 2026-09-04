# MSG-01 – Inbox och automatiska systemtrådar

Datum: 2026-08-27  
Status: lokalt genomfört; Inboxens mobilgrund och footerregression fysiskt verifierade, runtime/tvåkonto/reconnect återstår

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
- Uppdateringar som flyttar en kontolänk eller capability-grant reconcilerar både den gamla och den nya relationens lag. Dubbletter dedupliceras innan sync, så samma lag behandlas en gång per triggerkörning.

Supabase-skillens säkerhetschecklista styrde gränsen: systembindningstabellen saknar klientgrants, RLS är fail-closed, Realtime-policy binder topic exakt till `auth.uid()` och service-sync exponeras endast för `service_role`.

## Verifiering

- Direkt Dart-format: 3 filer, 0 återstående ändringar.
- Statisk SQL-/UI-kontraktsgrind: godkänd.
- Migrationen har 14 dollar-quotes, 7 funktionsdefinitioner och jämnt quote-antal.
- Ett riktat Flutter-kontraktstest har lagts till för systemtrådar, capability, privat resync samt sök/filter.
- `dart analyze lib test`: godkänd utan anmärkningar den 2026-08-28.
- Riktade MSG-01/MSG-02-, repository- och scope-tester: godkända.
- Full Flutter-regression: 278/278 tester godkända den 2026-08-28.

### Fysisk Mi 9-regression 2026-08-28

- Inbox laddade riktiga direkttrådar, sök, Alla/Oästa/Lag/Ledare/Tystade, oläst-badges, `Markera alla som lästa` och Nytt meddelande på Xiaomi Mi 9.
- Första körningen hittade att fyra `persistentFooterButtons` tog nästan halva mobilens innehållsyta och konkurrerade med trådlistan, compose-FAB och Min assistent.
- Telefonlayouten använder nu en enda semantiskt namngiven trepunktsmeny, `Fler inkorgsåtgärder`, för Förfrågningar, Ledarkontakt, Notiser och Inställningar. Tablet/desktop behåller synliga footeråtgärder.
- Riktad MSG-01-körning passerade 5/5 och analysen var ren.
- Audit-debugbuild `D33B337D5ADC6F684081E38E4D80069F195519481F5A13E6F77EFA31AB47D2A9` installerades; produktägaren bekräftade fysiskt att footerstacken var borta och att samtliga fyra åtgärder fanns i menyn.
- En riktig direkttråd öppnades på samma build. Historik, avsändare, composer, bilaga, teckengräns, skicka, fäst, aviseringar och fler alternativ renderade utan overflow.
- Android-back stängde tråden och återgick till Inbox utan att avsluta appen. Den visuellt ellipsiserade trådrubriken noteras som icke-blockerande mobil polish.

### Offline och automatisk återanslutning 2026-08-28

- Fysisk pull-to-refresh utan nät behöll tre verifierade trådar och visade `Visar senast verifierade data` med tidpunkt.
- Reconnect saknade först automatisk resync. Inbox fick en livscykelbunden 3/5/10/30-sekunders backoff efter misslyckad stale-refresh; lyckad resync och dispose avbryter timern.
- Riktat MSG-01-test passerade 5/5 och analysen var ren.
- Build `998F0AC65B70C1EF4F8FF0E89712972EE646163D8C5B46B17E68BC96C8F333A2` verifierades på Mi 9: stale-kortet försvann automatiskt efter återanslutning, exakt tre trådar kvarstod och lagkontexten bevarades.

## Återstår

- PostgreSQL-runtime och Security/Performance Advisors.
- Fortsatt fysisk verifiering med minst leader och player: send/unread/read, mute, join/leave och capability revoke. Reconnect/resync är godkänd för leader-kontot.
- Separat godkännande före eventuell Supabase-liveändring.

Ingen Supabase-liveändring, driftsättning, webtools eller workspace utfördes.
