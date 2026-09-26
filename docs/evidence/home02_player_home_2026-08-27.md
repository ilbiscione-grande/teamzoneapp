# HOME-02 – Spelarens Hem

## Lokalt genomfört

- Spelaren får en separat hemprojektion som kräver player-roll i vald lagkontext och kopplar data till spelarens verifierade `club_person`.
- Lagkortet visar klubb, lag och medlemsantal utan administrativa åtgärder.
- Nästa aktivitet visar tid/plats och öppnar EventDetails.
- Endast spelarens egna aktuella kallelser projiceras. På Hem kan de besvaras med **Acceptera** eller **Avböj**; det tidigare Kanske-alternativet är borttaget. Eventets deltagarvy använder samma knappetiketter. Svarsstatus visas fortsatt som **Kommer/Kan inte**.
- Snabbsvar återanvänder CAL-07:s idempotenta mutationskontrakt med expected revision. Avböjande kräver strukturerad anledning och fritext endast för `other`.
- Player-svar skickar aldrig guardian `acting_as`; inga leader-, roster-, attendance- eller guardianadministrativa actions projiceras.
- Olästa relevanta lagmeddelanden visas som en säker räknare och genväg till inkorgen, inte som meddelandebody.
- Kontextbunden cachefallback märks explicit som inaktuell med senaste servergenereringstid. Gamla kallelser kan läsas men inte besvaras förrän färsk serverdata har hämtats.

## Verifierat lokalt

- `flutter test test/home02_player_home_test.dart test/home03_guardian_home_test.dart`: 9/9 passerar.
- `dart analyze lib test`: inga problem.
- Dart-format och statisk kontraktsgrind täcker person-/kontextisolering, egna kallelser, revisionssäker mutation, decline reason, säker stale-cache samt frånvaro av leader/guardian-actions.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Fysisk spelarverifiering av Acceptera/Avböj, stale revision, decline reason, deep links och mobil/tablet-layout.
- 2026-09-23: webbgenomgång inledd med spelartestkontot i **Thomas lag**. Hem visar **Dina kallelser** och på bred vy korten **Laget**, **Olästa meddelanden** och **Nästa aktivitet: Träning** i högerkolumnen. Ledar-/administrationsåtgärder och kallelseinteraktion återstår att kontrollera i denna genomgång.
- 2026-09-23: produktägaren bekräftade att spelarens Hem inte visar **Planering och administration**, **Nytt event**, trupphantering eller närvaroregistrering. Rollavgränsningen är webbverifierad; egna kallelser återstår att kontrollera.
- 2026-09-23: **Dina kallelser** hade ingen obesvarad kallelse i den aktuella spelarkontexten. Svar/avböjande kan därför inte verifieras med befintligt innehåll och lämnas öppet tills en relevant testkallelse finns.
- 2026-09-23: **Nästa aktivitet: Träning** öppnade rätt EventDetails från spelarens Hem, och X återgick till samma Hem. Deep link och returrutt är webbverifierade för spelarrollen. Smal layout och kallelseinteraktion återstår.
- 2026-09-23: i smalt webbläsarfönster visades korten i ordningen **Dina kallelser → Laget → Olästa meddelanden → Nästa aktivitet** utan horisontell scroll. Spelarens responsiva webbvy är verifierad. En obesvarad testkallelse behövs för den återstående svarskontrollen.
- 2026-09-23: produktägaren skickade från separat ledarsession en riktad testkallelse till spelaren bakom `coach.emilson+tzplayer@gmail.com` för den kommande träningen. Mottagning och svar i spelarens Hem återstår att kontrollera.
- 2026-09-23: den nya kallelsen syntes först efter manuell sidomladdning på spelarens öppna Hem. Orsaken var att Hem inte prenumererade på den redan befintliga privata notifieringskanalen som kallelseutskicket invalidierar. Klienten lyssnar nu på samma kontobundna kanal, debouncar 250 ms och uppdaterar rollens Hem utan att visa ett nätfel som följd av bakgrundshämtning. Ingen server-/schemaändring. Riktad analys och HOME-01–03-test 18/18 passerar; konfigurerad lokal releasewebb byggdes och `/home` svarar 200 på port 5000. Fysisk omtest med en ny förändring återstår.
- 2026-09-23: efter omladdning till den nya webbversionen syntes den riktade träningskallelsen på spelarens Hem med valen **Kan inte** och **Kommer**. Själva svarsmutationen och automatisk uppdatering från nästa inkommande förändring återstår.
- 2026-09-23: produktägaren svarade på kallelsen med **Kommer** och bekräftade att status ändrades korrekt. Därefter begärdes tydligare handlingsetiketter på Hem. Spelarens och ledarens egna kallelseknappar ändrades till **Acceptera/Avböj** utan att ändra svarsvärden eller visad status; fysisk omtest av etiketterna återstår.
- 2026-09-24: spelartestkontot höll Hem öppet medan ledarkontot skickade en ny riktad kallelse från ett framtida event. Produktägaren bekräftade att kallelsen dök upp utan manuell omladdning. Den privata notifieringsbaserade Hem-resynken för en ny inkommande kallelse är därmed webbverifierad; stale revision och separat fysisk enhet återstår.
- 2026-09-24: den nya kallelsens notis öppnade först endast Kalender på grund av en äldre servergenererad `/calendar?event=…`-adress. Notisprojektionen beräknar efter migrering `/calendar/event/…` även för denna redan skapade notis; fysisk omtest från notislistan återstår.
- 2026-09-24: produktägaren bekräftade att spelaren kunde avböja en kallelse från Hem med anledning och att svaret/anledningen visades korrekt. Ändring av samma svar till Acceptera och kontroll att den gamla anledningen försvinner återstår.
- 2026-09-24: produktägaren ändrade därefter samma kallelse till Acceptera från spelarens Hem och bekräftade att det fungerade. Att den tidigare avböjandeorsaken försvann har inte uttryckligen bekräftats; stale revision med samtidiga vyer återstår också.
- 2026-09-24: produktägaren bekräftade uttryckligen att den tidigare avböjandeorsaken försvann efter Acceptera. Svar och privat orsak på spelarens Hem är därmed webbverifierade; samtidighets-/stale-revision-test återstår.
- 2026-09-24: från spelarens Hem öppnade genvägen **Olästa meddelanden** Inkorgen, och webbläsarens Bakåt återgick till Hem. Genväg och retur är webbverifierade.
