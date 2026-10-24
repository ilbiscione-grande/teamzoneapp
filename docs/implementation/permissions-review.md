# Översyn av behörigheterna – att göra

**Status: planerad, inte påbörjad. Beslutad av produktägaren 2026-10-24 att göras vid ett senare tillfälle.**

Behörigheterna har vuxit fram område för område: ledarbehörigheter per lag (TEAM-10), publicering (PUB-02), styrelse och ekonomi via styrelseuppdrag, och nu klubbens behörigheter (`20261208090000_club_permissions.sql`). Varje del fungerar, men helheten behöver ses över innan release, så att det är begripligt för klubbarna vem som får göra vad och var det ändras.

## Det vi vet idag

- **Grunden håller:** all behörighet är tilldelningar (`core.capability_grants`) på en persons roll i klubben eller laget, och `internal.actor_has_capability` läser bara dem, aldrig rollnamn eller styrelseposter.
- **Många behörigheter:** 25 klubbomfattande behörigheter är i bruk (styrelse, ekonomi, publicering, medlemmar, anslag, moderering, fakturering, skydd och hela lagpanelen på klubbnivå).
- **Tre ställen att dela ut, med olika regler:**
  - Lagets ledare och behörigheter (lagpanelen, `team.leaders.manage`).
  - Klubbens behörigheter (fyra områden, `club.memberships.manage`).
  - Styrelseuppdrag (styrelse och ekonomi).
  - Resten saknar gränssnitt: fakturering (`club.billing.manage`), skydd (`club.safeguarding.manage`), moderering (`message.moderate`) och lagpanelen på klubbnivå.
- **Engångsutdelning:** publicering gavs 2026-08 till alla som då hade `club.memberships.manage`. Nya klubbar får behörigheterna genom sina mallar, men det har inte gåtts igenom samlat.
- **Styrelseposter ger inte behörighet:** en ordförande får inte rätt att besluta om lagsidor eller medlemmar av sin post. Det måste delas ut i Klubbens behörigheter.
- **Domartillsättning** (`club.referees.manage`) används i appen, men ingen hade tilldelningen när klubbens behörigheter byggdes.
- **Klubbbehörigheter på lagroller:** en klubbomfattande tilldelning (t.ex. `economy.read`) kan sitta på en lagroll. Servern räknar ihop alla ens roller i klubben, men sidorna läser bara den öppnade kontextens behörigheter. Därför kan ens kontext på klubbnivå sakna klubbens ekonomi, trots att man har den. Assistenten öppnar därför styrelse och ekonomi i den kontext som har behörigheten (2026-10-24).
- **Mallar tillämpas inte av sig själva:** en titel som Huvudtränare föreslår en mall i lagpanelen, men behörigheterna ges först när någon trycker Använd och sparar. Exempel 2026-10-24: P2012:s ledare hade bara Live och matchplan och kunde därför bara spara matchrapporten som utkast. Att publicera rapporten kräver `publication.manage`, som ingår i Huvudtränare-mallen. Översynen ska avgöra om en titel ska ge sin mall direkt, och om publicering av lagets egna matchrapporter ska följa matchbehörigheten i stället för Publicera.
- **Klienten** visar och döljer funktioner med `contextValue.can(...)`, som läses från kontexten. Servern avgör alltid, men det som visas kan avvika från det som går att göra tills kontexten laddas om.

## Det översynen ska ge

1. En samlad karta över alla behörigheter: vad var och en tillåter, vem som har den som standard och var den delas ut.
2. Ett beslut om vilka roller och mallar nya klubbar och lag får, och om styrelseposter ska ge behörigheter.
3. Ett gränssnitt (eller få) där klubben ser och ändrar behörigheter samlat, i stället för tre spridda ställen, inklusive de som saknar gränssnitt idag.
4. Spärrar som gäller överallt: man delar bara ut det man har, och ingen klubb eller inget lag kan bli utan den som förvaltar behörigheterna.
5. Att klientens synlighet följer servern direkt efter en ändring.
6. Underlag till produktägaren som ett eget beslutspaket innan något byggs.
