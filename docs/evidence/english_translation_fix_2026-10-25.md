# Engelska översättningar efter manuellt språkpass

Datum: 2026-10-25. Uppföljning av EN-01–EN-04 i
[det manuella språkpasset](english_acceptance_2026-10-25.md).

## Ändring

Systemtexter i assistenten, gemensamma aktivitetsförberedelser, KPI-mål,
Team Development Plan och Match har kopplats till appens valda språk.
Det omfattar bland annat standardnamn och inställningar i assistenten,
uppgiftstyper och åtgärder, material-/filsektioner, inbyggda nyckeltal,
målgränser och ja/nej-värden, säsongsprogress, mål- och principformulär,
matchhändelser och statistik i efteranalysen.

Inbyggda nyckeltal identifieras med katalognyckeln. Egna nyckeltal,
aktivitets- och säsongsnamn, materialnamn, spelarnamn, assistentens egna
namn och anteckningar bevaras. Matchplanens mallknappar infogar ny text
på valt språk; redan skriven matchplan skrivs inte om.
Platshållare ersätts i ett enda steg så att innehåll med exempelvis
`{total}` inte tolkas som en ny systemplatshållare.

Det engelska matchprovet hittade dessutom ett överflöde i efteranalysens
filter vid 390 pixlars bredd. Rubrik och filter kan nu brytas över flera
rader, och motståndarfiltret har begränsad bredd med ellips för långa namn.

## Verifiering

Fem nya engelska widgetprov täcker:

- Assistentens standardnamn och personliga inställningar.
- Uppgiftskort och visningsinställningar, inklusive språkbyte i en öppen vy.
- Aktivitetsförberedelser med inbyggt och eget nyckeltal samt material.
- TDP:s säsong, delning, spelprinciper, nya mål, avstämning och målstatus.
- Matchlistan och efteranalys med statistik, svenska personnamn och anteckningar.

De svenska assistentproven väljer nu svenska uttryckligen. De ska inte
förlita sig på hårdkodade svenska texter när MaterialApp använder engelska.
Språkgrinden kontrollerar även parametriserade översättningsmallar.
Den verifierar dessutom dynamiska etiketter från TDP:s enumvärden,
assistentens uppgiftstyper/områden/feedbackskäl och Lives händelsetyper,
resultatval och sekundära spelarroller.

Riktad regression: **80 tester godkända**. Helkörningen omfattade **818
tester**, varav 817 passerade. Den återstående engelska träningsregressionen
visade en dubbelöversättning i valkomponenten som Träning och TDP delar.
Komponenten tar åter emot färdiga visningsetiketter; TDP översätter vid
anropet, liksom Träning redan gjorde.

Efter rättningen passerade ett nytt, sekventiellt omprov av hela Träning-,
TDP- och språkgrindssviterna: **19/19 tester godkända**, inklusive den tidigare
felande engelska träningsplaneringen. Alla testfall har därmed passerat
mellan helkörning och riktade omprov. Ingen ny komplett helkörning gjordes
efter den sista komponenträttningen. Statisk analys: **inga fynd**.

## Avgränsning

Rättningen är publicerad till audit och har granskats manuellt i den befintliga
engelska ledarsessionen. Omprovet hittade ytterligare mindre systemtexter som
rättats i en komplettering. Revisioner, kontroller och återstående acceptans
finns i [release och omprov](english_release_2026-10-25.md).
