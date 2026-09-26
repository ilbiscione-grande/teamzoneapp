# MSG-01 – Inbox och automatiska systemtrådar

Datum: 2026-08-27  
Status: genomfört och godkänt; lokalt, hosted samt fysiskt verifierat inklusive tvåkontoflöde, join/leave och capability revoke/restore

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

### Webbregression 2026-09-20

- Produktägaren verifierade sök samt filtren Alla, Olästa, Lag, Ledare och Tystade i den hostade testdatabasen via den lokala webbbuilden.
- Ett meddelandes X-knapp såg först ut att inte göra någonting: dialogen stängdes men den ännu inte uppdaterade `?thread=`-parametern öppnade samma tråd omedelbart igen.
- Klienten minns nu ett nyss avvisat tråd-id tills inkorgsroutern har tagit bort parametern. X stänger explicit den översta dialognavigatorn och återgången kan därför inte tävla med en samtidig listresync.
- Riktat MSG-01-test passerade 6/6 och analysen var ren. Produktägaren bekräftade därefter att X återgår till inkorgen och att en tystad konversation visas under filtret Tystade.
- Tvåkontogrinden kördes med ledarkontot och `coach.emilson+tzplayer@gmail.com`: ett nytt ledarmeddelande gav korrekt olästmarkering och preview hos spelaren, öppning markerade tråden som läst och tog bort den ur Olästa. Ett svar från spelaren gav därefter motsvarande oläst/preview/läst-flöde hos ledaren.
- Join/leave-grinden hittade först en verklig åtkomstläcka: historikbevarande `Avsluta i laget` avslutade `core.team_assignments`, men lämnade spelarens approll i `core.assignments` aktiv. Spelaren behöll därför Hem, lagöversikt samt läs- och skrivrätt i lagchatten.
- Migration `20260920163500_team08_sync_player_context_with_roster.sql` inför en central trigger som synkroniserar rosterperioder med exakt motsvarande `player`-roll, utan att ändra kontolänken eller separata leader-/guardian-/club-functionary-roller. Befintliga avvikelser reconcilerades och systemtrådens vanliga assignment-trigger tog bort inaktuella deltagare.
- Efter hosted migration och ny inloggning hamnade den avslutade spelaren korrekt i väntrummet. Återaktivering gav tillbaka lagkontexten och samma lagchatt med bevarad historik; ingen dubbletttråd skapades.
- Ett medlemskap som godkänts som ledare saknade först explicita capability-grants trots korrekt rollvisning. Migration `20260920172500_auth04_materialize_leader_capability_bundle.sql` materialiserar därför standardpaketet för aktiva lagledare och backfillade befintliga avvikelser.
- En avgränsad fysisk revoke-fixture (`20260920175000_msg01_revoke_test_leader_roster_view.sql`) avslutade endast `team.roster.view` för testledaren i Thomas lag. Efter ny inloggning försvann ledarchatten, en gammal direktlänk nekades och vanlig lagchatt samt andra ledarfunktioner fanns kvar.
- Den uttryckligen godkända återställningen `20260920180500_msg01_restore_test_leader_roster_view.sql` återaktiverade samma grant. Ledarchatten och dess tidigare historik kom tillbaka utan att en dubblett skapades.
- Riktat MSG-01-test passerade slutligen 8/8. Lokal och hosted migrationshistorik är synkroniserad till och med `20260920180500`.

## Slutstatus

- MSG-01 är godkänt. Tvårolls send/unread/read, mute, reconnect/resync, join/leave och capability revoke/restore är fysiskt verifierade.
- De ovan namngivna migrationerna applicerades efter separata uttryckliga godkännanden i den aktuella Supabase-testdatabasen. Ingen produktionsprovisionering, webtools eller workspace utfördes.
