# AC-07 – Roll-, kontext- och enhetsanpassad presentation

Datum: 2026-08-28  
Status: lokalt implementerad och Flutter-verifierad; leader/mobil FAB, kontext och back fysiskt verifierade, runtime/flerroll/tablet/desktop återstår.

## Levererat

- Serverprojektionen utgår från exakt aktivt assignment/context-ID och hämtar roll från serverns assignment, aldrig från användarstyrd metadata.
- Områden kräver både matchande målroll och minst en relevant capability på samma assignment och scope.
- Leader, player, guardian och `club_functionary` använder samma kö men får olika tillåtna områden.
- Saknad relevant roll/capability ger en tom blockerad kö i stället för data från annan roll eller kontext.
- Guardian acting-as kräver en aktiv, giltig `core.guardian_relations`-relation och visas sedan med personens namn.
- Aktiv klubb, lag, roll och eventuell acting-as visas i en tydlig kontextbanner före innehåll och handling.

## Responsiv presentation

- Mobil behåller en gemensam flytande FAB.
- Tablet/desktop behåller en integrerad sidopanel med aktiv lag-/klubbkontext och roll.
- Den fullständiga assistentytan använder samma `TeamZoneContext`, tjänster och rättigheter oavsett ingång.
- Inga separata specialistinkorgar har skapats.

## Historik, filter och preferenser

- En gemensam växling finns mellan Aktuellt och Historik.
- Roll-/capabilityrelevanta områden kan filtreras i samma vy.
- Per-områdespreferenser styr synlighet och önskat leveransläge: direkt, sammanfattning, endast i Min assistent eller av.
- Preferenser lagras privat per profil, är revisionerade och idempotenta.
- Preferenser kan aldrig ändra specialistregistrets grindstatus; ett blockerat område ger fortsatt effektivt leveransläge `off`.

## Postkontrakt

- Ett återanvändbart postkort visar områdets text + ikon + färg, separat freshness/status, förklaring, källa och beräkningstid.
- Klubb, lag, roll och eventuell acting-as visas före säker handling.
- Säker handling är navigation; domänmutation aktiveras inte av AC-07.

## Säkerhet

- `core.assistant_area_preferences` har RLS och saknar direkt åtkomst för `anon` och `authenticated`.
- Läsning och mutation sker via smala autentiserade RPC-funktioner.
- Servern validerar assignment, tidsperiod, capabilityscope och guardian-relation.
- Profilsradering kaskadraderar preferenserna.
- Ingen Supabase-liveändring har gjorts.

## Verifiering

- `dart analyze lib test`: inga problem.
- AC-01–AC-07 riktad regression: 28/28 passerade.
- Separat AC-07-svit: 6/6 passerade.
- Testerna täcker roll + capability, explicit kontext/acting-as, postens transparency/freshness/action, privat revisionsskyddad preferens och responsiv FAB/panel-kontrakt.
- PostgreSQL-runtime/advisors kunde inte köras eftersom lokal Docker-runtime saknas.
- Audit-debugbuild `4FB923D56AE218E57316A02E2A0D6462CD7AF0AC493C4786E8F9D3CB7468655C` verifierades på Xiaomi Mi 9, Android 10. Inbox-FAB öppnade Min assistent med explicit Thomas klubb, Thomas lag och Ledare samt fail-closed information utan aktiva områden.
- Första fysiska Android-back från assistentens fullskärmsroute avslutade appen. Produktens nästlade GoRouter saknade en plattformsdispatcher.
- Produkten fick en `RootBackButtonDispatcher`; nytt widgettest öppnar assistenten via FAB, skickar system-back och kräver återgång till Hem. Samlad riktad FND-körning passerade 7/7 och analysen var ren.
- Produktägaren bekräftade på den korrigerade builden att Android-back nu återgår från Min assistent till Inbox utan appavslut.

## Kvarvarande grindar

- Kör migration, RLS/RPC och stale-revision i godkänd icke-live PostgreSQL-miljö.
- Verifiera leader/player/guardian/club_functionary samt dubbla roller på samma lag med verkliga konton.
- Verifiera guardian acting-as med flera barn och kontextbyte.
- Genomför fysisk mobil/tablet/desktop-kontroll av FAB, sidopanel, textskalning, filter, historik och preferensdialog.
- Skarpa assistentposter förblir blockerade tills AC-08 och relevanta områdesgrindar godkänts.
