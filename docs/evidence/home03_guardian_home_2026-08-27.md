# HOME-03 – Vårdnadshavarens Hem

## Lokalt genomfört

- Guardian-hemsidan kräver guardian-roll i vald lagkontext och en verifierad kontokoppling till vårdnadshavarens `club_person`.
- Barnväljaren innehåller endast barn med aktiv, giltig guardian/custodian-relation och aktiv tilldelning i det valda laget.
- Servern avvisar ett explicit barn-ID som inte tillhör relationen eller lagkontexten; klientvalet är aldrig auktorisation.
- Kallelser filtreras till valt barn. Barnets namn visas både överst och direkt vid svarsknapparna.
- Varje snabbsvar skickar serverprojektionens `acting_as_person_id`, expected revision och strukturerad decline reason genom CAL-07-flödet och vidare till audit.
- Nästa event och meddelanderäknare begränsas till valt lags relationstillåtna kontext; ingen meddelandebody exponeras.
- Cachefallback isoleras per lagkontext och valt barn samt märks explicit som inaktuell. Barnbyte och kallelsesvar spärras tills relationen har verifierats mot servern igen.

## Verifierat lokalt

- Gemensam HOME-01–HOME-03-regression: 15/15 tester passerar.
- `dart analyze lib test`: inga problem.
- Dart-format och statisk kontraktsgrind täcker aktiv relation, barn-/lagisolering, synlig acting-as, mutationens acting-as/revision/decline reason och skrivskyddad stale-cache.
- Ingen Supabase-liveändring eller produktionsprovisionering är gjord.

## Återstår

- PostgreSQL-runtime/advisors när en godkänd lokal databas är tillgänglig.
- Fysisk guardianverifiering med minst två barn, två lagkontexter, stale revision och avslutad relation.
- 2026-09-23: produktägaren öppnade vårdnadshavarens Hem i Thomas lag och såg bara **Testspelare S04** i barnväljaren. Detta är inte i sig en avvikelse: de två barn som användes i REL-02 var en tillfällig fixture vars relationer och tilldelningar senare avslutades vid godkänd cleanup. Den nuvarande enbarnsvyn kan användas för acting-as/svarstest, men flerbarnsgrinden kräver en separat aktiv testrelation och markeras inte klar här.
- 2026-09-23: produktägaren bekräftade att Hem visar **Du agerar för Testspelare S04** och att det finns en kallelse under barnets kallelser. Synlig acting-as och kallelseläsning är därmed webbverifierade för den aktiva relationen; själva svarsmutationen återstår.
- 2026-09-23: kallelsen var redan besvarad men visade fortsatt båda svarsknapparna utan att markera det sparade valet. Det är korrekt att kunna ändra svaret medan servern tillåter det, men Hem återanvänder nu deltagarvyns valmarkerade Acceptera/Avböj-knappar. Status och svarsmutation är oförändrade; fysisk omtest återstår.
- 2026-09-23: efter ombyggd lokal webbversion bekräftade produktägaren att S04:s redan sparade svar nu har en tydligt markerad knapp i vårdnadshavarens Hem. Visuell omtest passerar; ändring av svar och serverns acting-as-spår återstår.
- 2026-09-24: produktägaren ändrade S04:s kallelsesvar från Hem och bekräftade att status och valmarkering ändrades. Avböjandeorsaken syntes däremot inte på Hem. Migration `20260924102411_home03_visible_own_decline_reason.sql` berikar endast de egna eller det valda barnets redan behörighetskontrollerade kallelser med orsak från exakt aktuell svarsrevision; klienten visar lokaliserad anledning bara när aktuell status är Avböj. Transaktionskontroll rullades tillbaka utan ändringar, migrationen applicerades i godkänd testdatabas och ett lästest med vårdnadshavarens behörighet gav en kallelse med synlig aktuell orsak utan att logga orsakstexten. HOME-01–03 19/19 tester, riktad analys och lokal releasewebb passerar. Fysisk omtest av orsaksvisningen återstår.
- 2026-09-24: produktägaren laddade om vårdnadshavarens Hem och bekräftade att **Anledning** nu syns vid S04:s avböjda kallelse. Den fysiska orsaksvisningen är godkänd; kontroll av att en senare acceptans tar bort orsaken återstår.
- 2026-09-24: produktägaren ändrade därefter S04:s svar till **Acceptera** och bekräftade att Acceptera markerades medan **Anledning** försvann. Den aktuella svarrevisionens orsak visas alltså inte efter ett senare accepterat svar. HOME-03:s enbarns-/acting-as-/svarsflöde är fysiskt verifierat; flerbarns-, lagbytes-, stale-revision- och avslutad-relationsgrind kvarstår.
- 2026-09-24: i mobilsmalt webbläsarfönster syntes S04:s kallelse, markerat svar och **Du agerar för Testspelare S04** tydligt utan horisontell scroll. Guardian-Hemmets smala responsiva vy är webbverifierad; riktig mobilenhet och övriga öppna relationstest kvarstår.
- 2026-09-24: produktägaren ändrade S04:s svar i en av två öppna vårdnadshavarflikar; den andra fliken uppdaterades inte. `respond_callup_for_actor` sparade svar utan en notifieringspost eller privat invalidiering, medan Hem redan lyssnade på `notification:center:<profile>`. Migration `20260924105355_home_callup_response_invalidation.sql` skickar nu endast `{}` på den befintliga privata kanalen till svarande konto och aktiva kontolänkar för kallad person/vårdnadshavare. Ingen svars-/orsaksdata skickas. Rollback-kontroll, 20/20 HOME-01–03-tester och analys passerar; migrationen applicerades i godkänd testdatabas och triggern verifierades aktiv utan direkt `authenticated`-EXECUTE. Fysisk tvåfliksomtest återstår.
- 2026-09-24: ett riktigt `api.respond_callup`-anrop under vårdnadshavarens JWT/roll lyckades med den nya triggern aktiv och rullades sedan tillbaka helt; testkallelsens sparade svar ändrades inte av kontrollen. Fysisk tvåfliksomtest återstår.
- 2026-09-24: efter omladdning av båda öppna guardian-Hem bekräftade produktägaren att ett ändrat S04-svar uppdaterade status och valmarkering i den andra fliken utan ny manuell omladdning. Tvåflikssynk för samma vårdnadshavarkonto är webbverifierad; separat enhet och andra aktörer återstår.
- 2026-09-24: produktägaren öppnade S04:s kallelse från vårdnadshavarens Hem och stängde EventDetails med X. Återgången gick till samma Hem med S04 fortfarande valt. Guardian-flödets eventlänk och barnkontext vid retur är webbverifierade.
