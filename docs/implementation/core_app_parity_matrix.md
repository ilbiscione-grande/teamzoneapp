# TeamZone grundapp – funktions- och UX-paritetsmatris

**Status:** FASTSTÄLLD  
**Upprättad:** 2026-08-23  
**Omfattning:** Inloggning/Skapa konto, Hem, Laget, Kalender/EventDetails, Inbox/notiser och publik klubbsajt  
**Styrande plan:** `docs/implementation/core_app_workplan.md`

## 1. Syfte och arbetssätt

Det här dokumentet märker först upp den tidigare appens användarsynliga funktioner innan ny implementation fortsätter. Varje rad ska gås igenom och godkännas tillsammans med produktägaren.

Märkningen betyder:

| Märkning | Betydelse |
|---|---|
| **Behåll** | Funktionen och dess huvudsakliga användarnytta ska finnas i grundappen. |
| **Förbättra** | Användarnyttan ska finnas kvar, men UX, datamodell, behörighet eller robusthet ska byggas om. |
| **Senare** | Funktionen ingår i målbilden men implementeras efter grundappens första stabila leverans. |
| **Ta bort** | Den gamla funktionen eller det gamla beteendet ska inte föras över. |
| **Nytt** | Funktionen saknas eller är väsentligt annorlunda i gamla appen men är redan beslutad för rebuilden. |

Kolumnen **Beslut** börjar som `Föreslagen`. Efter gemensam genomgång ändras varje accepterad rad till `Godkänd`. Ingen rad i detta utkast är ett nytt produktbeslut i sig.

## 2. Gemensamma acceptanskriterier

Alla rader märkta **Behåll**, **Förbättra** eller **Nytt** ska uppfylla följande när de implementeras:

- [ ] Behörighet och tenantgräns verifieras på servern, inte bara i klienten.
- [ ] Ledare, spelare och vårdnadshavare ser rätt innehåll och rätt handlingar.
- [ ] Mobil, tablet och desktop har en avsiktlig layout för användningssituationen.
- [ ] Laddning, tomläge, fel, retry och återanslutning är begripliga och testade.
- [ ] Tillgänglighet omfattar skärmläsare, tangentbord/fokus, textskalning och kontrast.
- [ ] Kritiska flöden har automatiserade tester och dokumenterad manuell verifiering.
- [ ] Ingen rå backendinformation, token eller personkänslig payload visas eller loggas.

## 3. Inloggning, konto och organisationsstart

| ID | Tidigare funktion/beteende | Gammal källa | Märkning | Mål i rebuilden | Rebuildläge | Beslut |
|---|---|---|---|---|---|---|
| AUTH-01 | Inloggning med lösenordslös e-postkod | `OnboardingFlow`, identity deep dive | **Förbättra** | Behåll e-post-OTP/magic link med tydlig leverans-, expiry- och retry-UX. | Grund finns | Godkänd |
| AUTH-02 | Automatisk kontoskapning i samma OTP-flöde | `signInWithOtp(...shouldCreateUser: true)` | **Förbättra** | Skilj begripligt på Logga in och Skapa konto utan att skapa dubbla identiteter. | Delvis | Godkänd |
| AUTH-03 | Lösenordsinloggning | Saknas som fullvärdigt gammalt alternativ | **Nytt** | Erbjud e-post + lösenord parallellt med OTP/magic link. | Ej verifierad | Godkänd |
| AUTH-04 | Glömt lösenord/återställning | Saknas i gamla OTP-flödet | **Nytt** | Komplett, säker återställning med neutrala svar och fungerande deep link. | Ej verifierad | Godkänd |
| AUTH-05 | Håll mig inloggad och sessionsåterställning | `session_persistence.dart`, `main.dart` | **Förbättra** | Förutsägbar session, säker utloggning samt UX för utgången/återkallad session. | Grund finns | Godkänd |
| AUTH-06 | Invite code kan förhandsvisas och accepteras | invitation repository, onboarding | **Förbättra** | Tidsbegränsad, scopead och idempotent invite med tydligt mål innan acceptans. | Grund finns | Godkänd |
| AUTH-07 | Sök klubb, se lag och skicka gå-med-förfrågan | onboarding/product shell | **Förbättra** | Ansökan med rätt klubb/lag/roll, status, återkallelse och godkännande/avslag. | Delvis | Godkänd |
| AUTH-08 | Skapa klubb med första lag | `CreateClubSurface`, `create_club_with_team` | **Förbättra** | Ny användare kan skapa klubb och första lag direkt, med tydlig ägar-/administratörsroll. | Grund finns | Godkänd |
| AUTH-09 | Skapa ytterligare lag i klubb | `CreateTeamSurface`, `create_team_in_club` | **Behåll** | Behörig klubbadministratör kan skapa fler lag med validerade grunduppgifter. | Grund finns | Godkänd |
| AUTH-10 | Officiell klubbstatus | Enkla `official_club`-spår i gamla appen | **Förbättra** | TeamZone-godkännande, verifieringsstatus och synlig skillnad mellan officiell och inofficiell klubb. | Delvis | Godkänd |
| AUTH-11 | Skyddade klubbnamn | Saknar komplett gammalt flöde | **Nytt** | Reserverade/existerande namn kräver TeamZone-granskning; säkert alternativnamn kan användas under tiden. | Ej byggd | Godkänd |
| AUTH-12 | Flera klubb-/lag-/rollkontexter och aktivt kontextval | `get_my_contexts`, `ProductShell` | **Förbättra** | Stabil kontextväljare, kanonisk URL/deep link och serververifierad åtkomst. | Grund finns | Godkänd |
| AUTH-13 | Automatisk prioritering leader → guardian → player | `ProductShell` | **Förbättra** | Respektera senast giltiga val; använd endast begriplig fallback när val saknas/upphört. | Grund finns | Godkänd |
| AUTH-14 | Vänteläge utan aktiv lagkontext | onboarding/product shell | **Behåll** | Tydlig väntesida med ansökningsstatus, nästa steg och möjlighet att skapa/ansluta annat lag. | Delvis | Godkänd |
| AUTH-15 | Koppla ett konto till en förskapad spelar-/personpost; äldre flöden kunde förlita sig på namnlikhet eller annan bred matchning | äldre medlems-/inviteflöden | **Förbättra** | Kontokopplingen behålls men får inte ske automatiskt enbart genom namn eller annan osäker matchning. Den kräver personlig, scopead inbjudan eller verifierad relation, ska återanvända samma spelarpost och skicka oklar dubblett till manuell granskning. | Mål beslutat | Godkänd |

## 4. Hem – roll- och situationsanpassad startsida

| ID | Tidigare funktion/beteende | Gammal källa | Märkning | Mål i rebuilden | Rebuildläge | Beslut |
|---|---|---|---|---|---|---|
| HOME-01 | Gemensam startsida/Today för ledare | `home_surface.dart` | **Förbättra** | Ledarens hem prioriterar dagens lagarbete, åtgärder, planering och nästa event. | Grund finns | Godkänd |
| HOME-02 | Separat spelarhem | `player_home_surface.dart` | **Förbättra** | Spelaren ser egna kallelser, nästa aktivitet, laginformation och relevanta meddelanden. | Grund finns | Godkänd |
| HOME-03 | Separat vårdnadshavarupplevelse | `parent/` | **Förbättra** | Vårdnadshavaren väljer barn och ser barnets kallelser, event och relevanta meddelanden. | Grund finns | Godkänd |
| HOME-04 | Nästa event och praktisk eventinformation | Home/Today providers | **Behåll** | Nästa relevanta event visas med tid, plats, status och en tydlig väg till EventDetails. | Grund finns | Godkänd |
| HOME-05 | Svara på kallelse från hemmet | player/parent callup cards | **Förbättra** | Spelare/guardian kan svara snabbt utan att tappa acting-as, decline reason eller audit. | Delvis | Godkänd |
| HOME-06 | Åtgärdskort för obesvarade kallelser och saknad närvaro | watchpoint/unmarked attendance sheets | **Förbättra** | Deterministiska, rollstyrda uppgifter visas som vanliga produktkort innan AC använder samma signaler. | Delvis | Godkänd |
| HOME-07 | Watchpoints som särskild produktfunktion | `watchpoint_*sheet.dart`, smart watchpoint-RPC | **Ta bort** | Namn, UI och separat Watchpoints-koncept förs inte över. | Gammalt koncept kvar lokalt | Godkänd |
| HOME-08 | Min assistent | Saknas som motsvarande gammal funktion | **Nytt** | En gemensam assistent med personligt namn och tydliga specialistområden byggs ovanpå stabila event-, trupp-, callup- och närvarosignaler. | Teknisk AC-grund finns | Godkänd |
| HOME-09 | Min assistent som flytande knapp på mobil | Saknas | **Nytt** | FAB nere till höger på mobil; tablet/desktop får integrerad panel där utrymme finns. | Ej produktionsklar | Godkänd |
| HOME-10 | Notisbadge och genväg till samlad notification center | notification providers/center | **Förbättra** | En konsekvent inkorg för uppmärksamhet med korrekt unread/read och deep links. | Grund finns | Godkänd |
| HOME-11 | Belastnings-, skade- och high-load-signaler på hemmet | workload/high-load/watchpoints | **Senare** | Återkommer först när policy, datakvalitet och rollvis integritet är verifierade. | Gamla spår finns | Godkänd |
| HOME-12 | Samma innehållstäthet oavsett skärm och situation | äldre lokala responsiva lösningar | **Ta bort** | Mobil fokuserar på snabb handling; tablet/desktop får planeringsöverblick och fler samtidiga paneler. | Gemensam grund behövs | Godkänd |

## 5. Laget – klubbkontext, översikt, trupp och händelser

| ID | Tidigare funktion/beteende | Gammal källa | Märkning | Mål i rebuilden | Rebuildläge | Beslut |
|---|---|---|---|---|---|---|
| TEAM-01 | Lagyta med blandade delfunktioner | `team_surface.dart` | **Förbättra** | Grundsidan får exakt tre flikar: **Översikt**, **Trupp** och **Kalender**. Kalenderfliken visar en filtrerbar lista över lagets tidigare och kommande händelser, inte en fullständig kalendervy. | Delvis | Godkänd |
| TEAM-02 | Lagets grundinformation och bild | team/settings/public data | **Förbättra** | Översikt visar lagbild, namn, lagtyp/åldersklass, ledare, kort information och relevanta genvägar. Behöriga ledare ser även aktiva inbjudningar, väntande ansökningar och ärenden som kräver åtgärd. | Delvis | Godkänd |
| TEAM-03 | Trupplista | team roster providers | **Förbättra** | Snabb, rollstyrd lista med sök/filter, tydlig status och fungerande mobil/desktop-layout. | Grund finns | Godkänd |
| TEAM-04 | Skapa medlem manuellt | player form, `create_member_with_membership` | **Förbättra** | Skapa person/klubbpost/lagrepresentation atomiskt med dubblettskydd och minimerade fält. | Grund finns | Godkänd |
| TEAM-05 | Redigera medlems- och spelaruppgifter | member detail/player form | **Förbättra** | Klubben ändrar bara sin tenantägda rosterinformation; global personidentitet skrivs inte över. | Delvis | Godkänd |
| TEAM-06 | Medlemsdetalj med grundinformation | `member_detail_surface.dart` | **Behåll** | Rollstyrd detaljyta med kontakt, lagroll, tröjnummer, position och status i fas 1. | Grund finns | Godkänd |
| TEAM-07 | Riktad inbjudan och generell lagkod | invitation repository, member detail | **Förbättra** | Båda stöds med scope, expiry, återkallelse, idempotent acceptans och begriplig status. | Grund finns | Godkänd |
| TEAM-08 | Guardianrelationer | `guardian_relations`, player form | **Förbättra** | Verifierad relation, barnets integritet, acting-as och tydlig livscykel. | Grund finns | Godkänd |
| TEAM-09 | Roller och capabilities i laget | memberships/context | **Förbättra** | UI visar handlingar från capabilities; okänd/guest-roll faller inte till trasig skärm. | Delvis | Godkänd |
| TEAM-10 | Spelbara lag | `get_member_playable_teams`, save RPC | **Förbättra** | En spelare kan ha sitt ordinarie lag och samtidigt vara behörig att representera andra lag genom exempelvis utvecklingsspel, dispens, lån eller gästspel. Behörigheten kan gälla en säsong, till ett valt datum eller tills vidare. Säsongsbundna behörigheter upphör vid säsongsslut, medan tillsvidarebehörigheter granskas regelbundet. Ordinarie lagtillhörighet och historik påverkas inte. | Grund finns | Godkänd |
| TEAM-11 | Flytta medlem genom att ändra nuvarande lagrad | `move_member_to_team` | **Förbättra** | Behörig ledare kan flytta en spelare mellan lag från valt datum. Tidigare lagtillhörighet avslutas och en ny skapas utan att historiska event, närvaro eller statistik skrivs om. Flytt mellan klubbar är ett separat godkännande- och övergångsflöde. | Mål beslutat | Godkänd |
| TEAM-12 | Arkivera/radera global medlem från ett lag | `archive_team_member`, `delete_team_member` | **Förbättra** | Behörig ledare kan arkivera eller ta bort spelaren från den aktiva truppen utan att historiska fakta försvinner. Radering av klubbens personuppgifter kräver två separata användare: behörig lagansvarig initierar och behörig klubbansvarig godkänner. Global radering/anonymisering kräver dessutom skyddad TeamZone-granskning. Systemet ska efter genomförd radering fortsätta fungera med bevarade verksamhetsfakta, obrutna referenser och en neutral anonymiserad representation där identitet inte längre får visas. | Mål beslutat | Godkänd |
| TEAM-13 | Historiska medlemskap och totalstatistik | member detail/statistics | **Senare** | Fas 2 efter korrekt temporal person-/roster-/assignmentmodell. | Uppskjuten | Godkänd |
| TEAM-14 | Spelarimport från fil/text | `ImportPlayersSheet`, `import_players` | **Senare** | Fas 2 med preview, validering, dubblettkontroll och återställningsbar batch. | Uppskjuten | Godkänd |
| TEAM-15 | Sparade grupper/urval | squad/group-spår | **Senare** | Fas 2; grupper blir återanvändbara urvalsmallar och skapar aldrig callups direkt. | Uppskjuten | Godkänd |
| TEAM-16 | Skador och avstängningar i medlemsdetalj | injury/suspension panels | **Senare** | Återinförs efter särskilt policy-, behörighets- och integritetspaket. | Ej grundappsprio | Godkänd |
| TEAM-17 | Händelser som lagets fulla kalender | team/calendar navigation | **Förbättra** | Lagfliken är en lista, inte full kalender: tidigare/kommande samt filter för bl.a. matcher och träningar. | Delvis | Godkänd |
| TEAM-18 | Snabb väg från laghändelse till event | team event lists | **Behåll** | Varje listpost öppnar samma auktoritativa EventDetails som huvudkalendern. | Grund finns | Godkänd |

## 6. Kalender, EventDetails, kallelser och närvaro

| ID | Tidigare funktion/beteende | Gammal källa | Märkning | Mål i rebuilden | Rebuildläge | Beslut |
|---|---|---|---|---|---|---|
| CAL-01 | Månad, vecka, tredagars- och dagvy | `calendar_surface.dart` | **Förbättra** | Första releasen erbjuder agenda/lista, månad, vecka och dag med gemensamma filter och datumlogik. | Grund finns | Godkänd |
| CAL-02 | Filter på lag och eventtyp | calendar surface | **Behåll** | Filter är konsekventa mellan vyer och bevaras begripligt per användarkontext. | Grund finns | Godkänd |
| CAL-03 | Skapa engångsevent | `create_event_sheet.dart` | **Förbättra** | Typ, tid, plats, ägande lag, audience och status valideras atomiskt. | Grund finns | Godkänd |
| CAL-04 | Återkommande event | create sheet/recurrence migrations | **Förbättra** | Serie är förstaklassobjekt; en förekomst kan ha override utan att serien korrumperas. | Grund finns | Godkänd |
| CAL-05 | Redigera förekomst eller framtida serie | event info/series RPC | **Förbättra** | Tydligt scopeval, revision och konflikt-/timezone-test. | Delvis | Godkänd |
| CAL-06 | Delade event mellan lag | `event_teams`, event team RPC | **Förbättra** | Primärt lag äger eventet; andra lag får explicita capabilities. | Grund finns | Godkänd |
| CAL-07 | Audience för players/leaders/guardians | event audience migrations | **Förbättra** | Audience styr synlighet/mottagare men ger aldrig automatiskt redigeringsrätt. | Grund finns | Godkänd |
| CAL-08 | Sparade platsförslag | `team_event_locations` | **Behåll** | Snabb återanvändning inom rätt lag/klubb utan att läcka andra tenants platser. | Grund finns | Godkänd |
| CAL-09 | Direkt radering av event och beroenden | event detail/delete paths | **Förbättra** | Opublicerade utkast och event utan verksamhetsberoenden kan raderas efter bekräftelse och konsekvenskontroll. Publicerade event eller event med kallelser, svar, närvaro eller annan historik hanteras normalt genom **Ställ in** eller **Arkivera** med auditerade statusövergångar. Permanent radering är ett separat skyddat administrations-/retentionflöde. | Mål beslutat | Godkänd |
| CAL-10 | EventDetails med Info, Trupp, Förberedelser, Analys | `event_detail_surface.dart` | **Förbättra** | Sammanhållen yta med flikarna **Info**, **Deltagare**, **Förberedelser** och **Uppföljning**. Deltagarfliken omfattar urval, kallelser, svar och närvaro; innehåll och handlingar anpassas efter roll och eventtyp. Mobilnavigationen ska hantera fliknamnen utan otydliga förkortningar. | Delvis | Godkänd |
| CAL-11 | Preliminär trupp och flera parallella squadkällor | squad/callup-tabeller och panels | **Förbättra** | En revisionerad squad draft är enda source of truth; alla urvalsmetoder fyller samma draft. | Delvis | Godkänd |
| CAL-12 | Skicka kallelser | event squad tab/functions | **Förbättra** | Send fryser draftversion, skapar callups atomiskt och skriver notification outbox. | Grund finns | Godkänd |
| CAL-13 | Sena tillägg och återkallade kallelser | callup paths | **Förbättra** | Late callups och cancel är explicita, auditerade transitioner som inte skriver över tidigare utskick. | Delvis | Godkänd |
| CAL-14 | Spelarens svar på kallelse | `respond_to_callup` | **Behåll** | Accepted/declined/pending visas konsekvent; decline reason kan vara strukturerad + fritext. | Grund finns | Godkänd |
| CAL-15 | Guardian svarar för barn | `guardian_respond_to_callup` | **Förbättra** | Acting-as är explicit, relation/capability verifieras och audit sparas. | Grund finns | Godkänd |
| CAL-16 | Påminnelse till obesvarade | reminder RPC/function | **Förbättra** | Behörig ledare kan påminna med cooldown, dedupe och separat leveransstatus. | Grund finns | Godkänd |
| CAL-17 | Närvaroregistrering | event squad tab/unmarked attendance | **Förbättra** | Separat state machine: unknown, present, late, partial, absent; sena ändringar auditeras. | Grund finns | Godkänd |
| CAL-18 | Svar via push-actiontoken | token RPC/push service | **Förbättra** | Scopead, kortlivad och single-use/idempotent token använder samma servertransition som appen. | Delvis | Godkänd |
| CAL-19 | Eventimport från fil/text | `import_events_sheet.dart` | **Senare** | Senare fas med preview, korrigering, dubblettskydd och batchresultat. | Uppskjuten | Godkänd |
| CAL-20 | Personliga/delade eventanteckningar | personal notes section | **Senare** | Senare fas med tydliga visibilitynivåer och retention. | Uppskjuten | Godkänd |
| CAL-21 | Taktiska bilagor | event tactic attachments | **Senare** | Senare fas med thread/event-bunden access, kort signerad URL och gemensam metadata-/objektretention. | Uppskjuten | Godkänd |
| CAL-22 | Match- och träningsworkspace | match/training workspace | **Senare** | Förbered gränssnitt och dataägande nu; full planering genomförs efter grundflödena. | Befintliga grundspår | Godkänd |

## 7. Inbox, meddelanden och notification center

| ID | Tidigare funktion/beteende | Gammal källa | Märkning | Mål i rebuilden | Rebuildläge | Beslut |
|---|---|---|---|---|---|---|
| MSG-01 | Inboxlista med sökning och unread | `messages_surface.dart`, inbox RPC | **Förbättra** | Stabil lista med sök/filter, senaste aktivitet, unread, mute och korrekt resync. | Grund finns | Godkänd |
| MSG-02 | Teamchat med medlemsdeltagande | team thread paths | **Förbättra** | Skapas automatiskt med laget och deltagande härleds dynamiskt från aktiva tillåtna relationer. | Delvis | Godkänd |
| MSG-03 | Ledarchat | staff/thread paths | **Förbättra** | Skapas automatiskt och kräver aktiv leader-capability vid både läsning och skickande. | Delvis | Godkänd |
| MSG-04 | Gruppkonversation | create group/thread participant UI | **Förbättra** | Explicit klubb-/lagscope, titel och deltagare; samma serverregel för sök, add och send. | Grund finns | Godkänd |
| MSG-05 | Direktkonversation | direct thread/new conversation | **Förbättra** | Endast tillåtna relationer; player-to-player är av som default. | Grund finns | Godkänd |
| MSG-06 | Ledarkontakt över klubbgräns | messageable members/äldre breda vägar | **Förbättra** | Dataminimerad verifierad ledarkatalog och rate-limitad request med accept/avvisa/blockera. | Ej komplett | Godkänd |
| MSG-07 | Broadcast | create broadcast sheet | **Förbättra** | Announcement är envägsinformation med egen readmodell och säker målgrupp. | Grund finns | Godkänd |
| MSG-08 | Meddelandehistorik, endast senaste 50 | `get_messages` | **Förbättra** | Paginering, deterministisk sortering och resync utan luckor eller dubbletter. | Delvis | Godkänd |
| MSG-09 | Skicka textmeddelande i realtime | thread detail/repository | **Förbättra** | Optimistisk men idempotent send, tydlig status, retry och serververifierad deltagarbehörighet. | Grund finns | Godkänd |
| MSG-10 | Markera läst och markera alla | read RPC/broadcast reads | **Förbättra** | Per-participant read state synkas och omfattar både messages och announcements. | Grund finns | Godkänd |
| MSG-11 | Mute och globala pushinställningar | mute/settings tables | **Behåll** | Fail-closed för frivilliga pushar och synkad inställning mellan enheter. | Grund finns | Godkänd |
| MSG-12 | Lokalt pin-state per enhet | SharedPreferences | **Förbättra** | Besluta om pin är enhetsspecifikt eller kontosynkat och gör beteendet tydligt. | Grund finns | Godkänd |
| MSG-13 | Bilagor med lagrad signerad URL | attachment upload/repository | **Förbättra** | Lagra objektidentitet; skapa kortlivad URL server-side vid auktoriserad läsning. | Delvis | Godkänd |
| MSG-14 | Soft delete/återkalla eget meddelande | thread detail/messages | **Förbättra** | Kort återkallelsefönster, begriplig tombstone och audit/retention enligt policy. | Grund finns | Godkänd |
| MSG-15 | Creator/leader kan radera tråd globalt | delete thread paths | **Förbättra** | Deltagare kan dölja eller lämna frivilliga trådar för egen del. Behörig ansvarig kan arkivera eller stänga en tråd utan att historiken försvinner. Global radering kräver två separata behöriga användare och, vid cross-club- eller integritetsärenden, TeamZone-granskning. Creator- eller ledarroll ensam ger aldrig rätt att radera allas historik. Genomförd radering ska bevara obrutna referenser, ordning, read state och neutrala tombstones där det behövs. | Mål beslutat | Godkänd |
| MSG-16 | Lämna frivillig tråd | leave thread RPC | **Behåll** | Döljer/lämnar för deltagaren utan att radera andras historik. | Grund finns | Godkänd |
| MSG-17 | Block/report och moderering | ofullständigt gammalt stöd | **Förbättra** | Krävs för cross-club request och innan eventuell player-to-player aktiveras. | Ej komplett | Godkänd |
| MSG-18 | Samlad notification center | notification center/providers | **Förbättra** | Samlar handlingsbara produktnotiser med säker preview, lässtatus och deep links. | Grund finns | Godkänd |
| MSG-19 | Watchpoints i notification center | provideraggregat | **Ta bort** | Watchpoint-items ersätts senare av AC-signaler; notification center behåller vanliga domännotiser. | Gammalt beroende | Godkänd |
| MSG-20 | Full meddelandebody/payload i push eller logg | push service/äldre loggning | **Ta bort** | Dataminimerad låsskärmspreview och automatisk redaction av token/payload/person-ID. | Säkerhetsgrund finns | Godkänd |

## 8. Publik klubbsajt och lagens officiella kanaler

| ID | Tidigare funktion/beteende | Gammal källa | Märkning | Mål i rebuilden | Rebuildläge | Beslut |
|---|---|---|---|---|---|---|
| PUB-01 | Sökbar offentlig klubbkatalog | public route `/`, `search_public_clubs` | **Förbättra** | Minimal katalog för verifierade/listade klubbar med begränsad sökning och enumerationsskydd. | Grund finns | Godkänd |
| PUB-02 | Publik klubbsida | route `/[clubSlug]` | **Förbättra** | Professionellt officiellt ansikte utåt med profil, navigation, nyheter, lag, event och partners. | Grund finns | Godkänd |
| PUB-03 | Publika lagsidor under klubben | route `/[clubSlug]/[teamSlug]` | **Förbättra** | Varje lag får en officiell kanal med lagprofil, nyheter och publicerade händelser. | Grund finns | Godkänd |
| PUB-04 | Klubb- och lagnyheter | news route/posts | **Förbättra** | Lätt redaktionellt CMS med utkast, preview, publicera/avpublicera, bild och rollstyrd publicist. | Delvis | Godkänd |
| PUB-05 | Offentlig event-/kalenderlista | public calendar/team events | **Förbättra** | Professionell lista och filter för publicerade event; ingen privat audience/callupdata exponeras. | Grund finns | Godkänd |
| PUB-06 | Partners/sponsorer | partners route/sponsor data | **Behåll** | Aktiva partners visas med godkända publicerade logotyper, länkar och ordning. | Grund finns | Godkänd |
| PUB-07 | Om klubben, kontakt och sociala länkar | about/team/contact routes | **Förbättra** | Redigerbar presentation, säkra länkar samt kontaktformulär med CAPTCHA, rate limit och retention. | Delvis | Godkänd |
| PUB-08 | Valfri publik trupp | `get_public_team_squad` | **Förbättra** | Minderåriga dolda som default; namn/bild/position/statistik kräver separata policy-/samtyckesfält. | Grund finns men ska hårdnas | Godkänd |
| PUB-09 | `teams.is_public` som enkel publiceringsflagga | gamla public RPC:er | **Ta bort** | Ersätt med private/listed/published och fältvis, auditerad publicering. | Mål beslutat | Godkänd |
| PUB-10 | Bred anon-EXECUTE mot SECURITY DEFINER-RPC:er | gamla public API:t | **Ta bort** | Dedikerat allowlistat public projection/API med maxlimit, rate limit och opaque ID/slug. | Säkerhetsgrund finns | Godkänd |
| PUB-11 | Standardadress för klubb | tidigare routebaserad sajt | **Förbättra** | Kanonisk standard är `teamzoneapp.se/{clubslug}` och ska fungera automatiskt i stor skala. | Grund finns | Godkänd |
| PUB-12 | Egen domän för betalande klubb | saknas komplett | **Nytt** | Premiumfunktion efter verifiering, DNS-guide, certifikat, canonical/redirect och supportflöde. | Senare driftarbete | Godkänd |
| PUB-13 | `clubslug.teamzoneapp.se` som premiumadress | saknas komplett | **Senare** | Kan erbjudas först efter wildcard DNS/TLS och automatiserad tenant-routing; inget manuellt klubbjobb. | Uppskjuten | Godkänd |
| PUB-14 | Live matchrapportering på klubb-/lagsida | saknas i gamla publika grundflödet | **Senare** | Senare fas med matchklocka, händelser, ställning, moderation och robust live/resync. | Uppskjuten | Godkänd |
| PUB-15 | Publik sajt med global `no-store` och svag releaseverifiering | gamla Next.js-sajten | **Ta bort** | Kontrollerad cache/invalidation, SEO, security headers, sitemap/robots och synthetic smoke-test. | Delvis | Godkänd |

## 9. Tvärgående UX och robusthet

| ID | Tidigare funktion/beteende | Gammal källa | Märkning | Mål i rebuilden | Rebuildläge | Beslut |
|---|---|---|---|---|---|---|
| UX-01 | Separata shells för leader/player/guardian | `ProductShell` och roll-shells | **Förbättra** | Gemensam designgrund men rollspecifik navigation, startsida, data och actions. | Grund finns | Godkänd |
| UX-02 | Lokala, varierande breakpoints | cross-cutting finding RESP-01 | **Ta bort** | Centrala breakpointtokens och verifierad mobil/tablet/desktop-matris. | Grund finns delvis | Godkänd |
| UX-03 | Fel som ibland blir tom UI eller rått backendfel | finding STATE-01 | **Ta bort** | Gemensam säker felmodell, särskilt empty state och tydlig retry. | Grund finns delvis | Godkänd |
| UX-04 | Realtime utan konsekvent status/resync | finding RT-01 | **Ta bort** | Alla kritiska kanaler visar anslutningsläge och gör deterministisk resync efter gap. | Delvis | Godkänd |
| UX-05 | Otydlig offlinepolicy | finding OFFLINE-01 | **Förbättra** | Varje mutation har policy: blockera, köa eller retry; stale data märks tydligt. | Delvis | Godkänd |
| UX-06 | Route och aktiv tenant kan skilja sig | finding NAV-01/NAV-02 | **Ta bort** | URL/deep link väljer exakt behörig kontext; refresh/back/forward återställer definierad vy. | Delvis | Godkänd |
| UX-07 | Språk och tema | settings/profile | **Behåll** | Konsekvent lokalisering, temastöd och inga hårdkodade blandade språk i kärnflöden. | Grund finns | Godkänd |
| UX-08 | Begränsad explicit tillgänglighetsverifiering | finding A11Y-01 | **Förbättra** | Tillgänglighet blir releasekrav och testas på kärnflöden, inte en senare kosmetisk kontroll. | Grund finns delvis | Godkänd |

## 10. Föreslagen leveransordning efter godkänd märkning

Den här ordningen ändrar inte den fastställda arbetsplanen utan gör nästa leveranssteg explicit:

1. [x] Godkänn/ändra märkningen i AUTH.
2. [x] Godkänn/ändra märkningen i HOME.
3. [x] Godkänn/ändra märkningen i TEAM.
4. [x] Godkänn/ändra märkningen i CAL.
5. [x] Godkänn/ändra märkningen i MSG.
6. [x] Godkänn/ändra märkningen i PUB.
7. [x] Godkänn/ändra märkningen i UX.
8. [x] Markera matrisen `FASTSTÄLLD` och lås första leveransens scope.
9. [x] Bryt ut godkända **Behåll/Förbättra/Nytt** till implementerbara arbetskort med beroenden och verifiering.
10. [ ] Fortsätt implementation enligt ordningen i `core_app_workplan.md`.

## 11. Spårbarhetskällor

### Tidigare app, skrivskyddat inventerad

- `C:/Dev/TeamZone/docs/audit_phase_1/02_functional_inventory.md`
- `C:/Dev/TeamZone/docs/audit_phase_1/03_runtime_navigation_and_state.md`
- `C:/Dev/TeamZone/docs/audit_deep_dives/01_identity_and_context/implementation_map.md`
- `C:/Dev/TeamZone/docs/audit_deep_dives/04_member_roster_and_organization_lifecycle/implementation_map.md`
- `C:/Dev/TeamZone/docs/audit_deep_dives/05_calendar_events_and_recurrence/implementation_map.md`
- `C:/Dev/TeamZone/docs/audit_deep_dives/06_callups_responses_and_attendance/implementation_map.md`
- `C:/Dev/TeamZone/docs/audit_deep_dives/09_messages_and_notifications/implementation_map.md`
- `C:/Dev/TeamZone/docs/audit_deep_dives/12_public_web_hosting_and_publishing/implementation_map.md`
- `C:/Dev/TeamZone/docs/audit_deep_dives/13_cross_cutting_client_quality/findings.md`
- `C:/Dev/TeamZone/docs/rebuild_spec/06_identity_role_context_decision.md`
- `C:/Dev/TeamZone/docs/rebuild_spec/07_person_roster_transfer_decision.md`
- `C:/Dev/TeamZone/docs/rebuild_spec/08_event_squad_callup_decision.md`
- `C:/Dev/TeamZone/docs/rebuild_spec/09_messaging_notifications_decision.md`
- `C:/Dev/TeamZone/docs/rebuild_spec/10_publication_privacy_hosting_decision.md`

### Rebuildens nuläge

- `README.md`
- `docs/implementation/slice_status.md`
- `docs/implementation/core_app_workplan.md`
- `docs/evidence/s01_local_implementation_2026-08-07.md`
- `docs/evidence/s02_roster_lifecycle_2026-08-07.md`
- `docs/evidence/s03_event_calendar_2026-08-08.md`
- `docs/evidence/s04_squad_callup_attendance_2026-08-08.md`
- `docs/evidence/s05_main_surfaces_2026-08-08.md`
- `docs/evidence/s06_messaging_progress_2026-08-08.md`
- `docs/evidence/s09_publication_fail_closed_baseline_2026-08-15.md`
- `docs/evidence/xux_foundation_2026-08-22.md`

## 12. Ändringslogg

| Datum | Ändring | Status |
|---|---|---|
| 2026-08-23 | Första uppmärkningen av gamla grundappsfunktioner och beslutade nya krav. | Utkast för gemensam genomgång |
| 2026-08-23 | AUTH-01–AUTH-15 godkända. AUTH-15 förtydligad: verifierad kontokoppling behålls, osäker automatisk matchning tas bort. | Avsnitt 3 godkänt |
| 2026-08-23 | HOME-01–HOME-12 godkända utan ändringar. | Avsnitt 4 godkänt |
| 2026-08-23 | TEAM-01, TEAM-02 och TEAM-10–TEAM-12 reviderade: kort fliknamn, ledarärenden på översikten, flexibla representationsbehörigheter, historikbevarande flytt samt robust dubbelgranskad radering/anonymisering. | Avsnitt 5 fortsatt under genomgång |
| 2026-08-23 | TEAM-01–TEAM-18 godkända, inklusive tidigare revideringar. | Avsnitt 5 godkänt |
| 2026-08-23 | CAL-01–CAL-22 godkända. CAL-09 ändrad till konsekvenskontrollerad radering/statuslivscykel och CAL-10 använder fliken Deltagare. | Avsnitt 6 godkänt |
| 2026-08-23 | MSG-01–MSG-20 godkända. MSG-15 ändrad till graderad trådlivscykel med dubbelgodkänd global radering och robusta tombstones/referenser. | Avsnitt 7 godkänt |
| 2026-08-23 | PUB-01–PUB-15 godkända utan ändringar. | Avsnitt 8 godkänt |
| 2026-08-23 | UX-01–UX-08 godkända utan ändringar. Samtliga avsnitt är genomgångna och matrisens omfattning är låst. | Matris fastställd |
| 2026-08-23 | Godkända punkter utbrutna i `core_app_delivery_cards.md` med beroenden, acceptanskriterier och verifieringsgrindar. | Leveranskort skapade |
