# Roll- och situationskontrakt för grundappen

**Kontrakt:** FND-04  
**Status:** Fast  
**Gäller:** Hem, Laget, Kalender och Inbox

## 1. Styrande principer

1. Serverhärledda capabilities och objektscope avgör alltid åtkomst. Rollpaketet används för presentation och prioritering, aldrig som enda säkerhetsspärr.
2. Okänd, avslutad eller ofullständig roll ger ingen syntetisk player-vy och inga actions. Klienten visar ett begripligt fail-closed-läge.
3. Guardian agerar alltid uttryckligen för valt barn. Barnets identitet följer med varje relevant query och mutation; guardian blir aldrig implicit barn-actor.
4. Klubbfunktionär får endast de klubb-, team-, board-, ekonomi- eller publiceringsytor som ingår i tilldelade capabilities. Titeln ger ingen generell superaccess.
5. Minderårig-, kontakt-, hälso- och utvecklingsdata minimeras även när en generell yta får visas.
6. Mobil, tablet och desktop har samma behörighetsregler. Endast informationsprioritet, layout och primära actions förändras.

Rollnycklarna är `leader`, `player`, `guardian` och `club_functionary`. Övriga värden saknar kontrakt och ska nekas.

## 2. Hem

| Roll | Mål | Viktig information | Primära actions | Får inte visas utan capability/scope |
|---|---|---|---|---|
| Leader | Planera laget och agera på det som kräver uppmärksamhet | Nästa event, obesvarade kallelser, närvaroluckor, invites/ansökningar, brådskande meddelanden | Skapa event, ta närvaro, meddela laget | Klubbekonomi, styrelseärenden, andra lags privata data |
| Player | Förstå vad som händer härnäst och vad spelaren behöver göra | Egna event, kallelser, svar och förberedelser | Svara, öppna event, kontakta ledare | Adminärenden, andra spelares närvaro, rosterhantering |
| Guardian | Hantera rätt barns närmaste aktiviteter och åtgärder | Barnväljare, valt barns nästa event/kallelser, relevanta meddelanden | Svara för valt barn, öppna event, kontakta ledare | Andra barns data, lagets adminärenden, privat utvecklingsdata utan särskilt stöd |
| Club functionary | Se klubbens operativa läge och egna mandat | Klubbärenden, ansökningar, officiell status, publiceringsstatus, brådskande meddelanden | Granska ansökan, publicera nyhet, öppna klubbadmin | Coachinguppgifter, privat hälsoinformation, ej tilldelad ekonomi/styrelse |

## 3. Laget

Alla roller möter samma tre grundflikar: `Översikt`, `Trupp`, `Kalender`. Kalender är här en eventlista med tidigare/kommande och typfilter, inte en full kalendergrid.

| Roll | Mål | Viktig information | Primära actions | Får inte visas utan capability/scope |
|---|---|---|---|---|
| Leader | Förstå och administrera det egna laget | Lagbild, grundinfo, ledare, trupp, invites/ansökningar, eventlista | Hantera trupp, granska ansökan, skapa event | Global personradering, andra lags privata data |
| Player | Se det egna laget och tillåten laginformation | Lagbild, grundinfo, begränsad trupp, eventlista | Öppna lagkamrat/event | Oscopeade kontaktuppgifter, invites/ansökningar, rosterhantering |
| Guardian | Se barnets lag och praktisk information | Lagbild, grundinfo, begränsad trupp, eventlista | Öppna event, kontakta ledare | Rosterhantering, invites/ansökningar, andra barns kontaktuppgifter |
| Club functionary | Överblicka klubbens lag inom mandat | Lagbild, grundinfo, truppsammanfattning, invites/ansökningar, eventlista | Granska ansökan, hantera lag om capability finns | Känsliga spelardetaljer och coachinganteckningar |

## 4. Kalender och EventDetails

| Roll | Mål | Viktig information | Primära actions | Får inte visas utan capability/scope |
|---|---|---|---|---|
| Leader | Planera, kalla och genomföra aktiviteter | Lagevent, svar, deltagarstatus, närvaro | Skapa/redigera event, hantera deltagare, ta närvaro | Redigering av annat lags event, privat hälsodata |
| Player | Se egna aktiviteter och förbereda sig | Egna event/kallelser och förberedelser | Svara, öppna EventDetails | Skapa/redigera event, ta närvaro |
| Guardian | Se och svara för uttryckligen valt barn | Barnväljare, valt barns event och kallelser | Svara för barn, öppna EventDetails | Skapa/redigera event, ta närvaro |
| Club functionary | Överblicka klubbaktiviteter utan implicit coachroll | Klubbevent, möten, publiceringsstatus | Skapa klubbevent om capability finns, öppna event | Lageventredigering, deltagarurval och närvaro utan teamcapability |

## 5. Inbox

| Roll | Mål | Viktig information | Primära actions | Får inte visas utan capability/scope |
|---|---|---|---|---|
| Leader | Kommunicera med laget och hantera svar | Team-/ledartrådar, unread, announcements | Meddela lag/ledare, skapa announcement | Klubbroadcast och orelaterade privata trådar |
| Player | Ta emot laginformation och kontakta tillåtna mottagare | Egna trådar, announcements, unread | Kontakta ledare, svara i tillåten tråd | Player-to-player direct som default, ledartrådar, broadcast |
| Guardian | Ta emot barnrelaterad information och kontakta ledare | Barnscopeade trådar, announcements, unread | Kontakta ledare, svara i tillåten tråd | Player-direct, ledartrådar, andra barns trådar |
| Club functionary | Hantera klubbkommunikation inom mandat | Klubbtrådar, kontaktförfrågningar, announcements, unread | Publicera announcement, svara på kontaktförfrågan | Ledar-/teamprivata trådar och player-direct utan separat relation |

## 6. Situationskontrakt

| Situation | Leader | Player | Guardian | Club functionary | Layoutregel |
|---|---|---|---|---|---|
| Mobil under aktivitet | Pågående event, närvaro, brådskande meddelanden | Nästa action, svar, eventinfo | Barnväljare, svar, eventinfo | Brådskande klubbärenden, approvals, meddelanden | En kolumn, stora snabba actions; dölj inte behörig funktion men nedprioritera bulk/komplex planering |
| Tablet vid planering | Eventplanering, deltagarurval, träningsplan | Schema, förberedelser, laginfo | Barnens schema, svar, laginfo | Klubbschema, ansökningar, innehållsplanering | Master/detail där det hjälper; planering får mer arbetsyta |
| Desktop/web-administration | Rosteradmin, serieplanering, kommunikationsöversikt | Historik, schema, egna uppgifter | Barnöversikt, historik, kontaktinställningar | Klubbadmin, ansökningar, publicering, auditöversikt | Tät flerkolumnslayout och bulkactions endast med capability |

## 7. Kontraktsnycklar och användning

Den maskinläsbara motsvarigheten finns i `lib/src/core/product/role_situation_contract.dart`. Featurekorten ska använda samma nycklar i tester och hänvisa till detta dokument:

- HOME-01–HOME-05 använder avsnitt 2 och 6.
- TEAM-01–TEAM-09 använder avsnitt 3 och 6.
- CAL-01–CAL-09 använder avsnitt 4 och 6.
- MSG-01–MSG-08 använder avsnitt 5 och 6.

När en ny action införs ska dess positiva roll/scope och minst en negativ roll/scope testas. Om capability saknas ska actionen vara frånvarande eller disabled med en begriplig förklaring; UI-frånvaro ersätter aldrig serverkontrollen.
