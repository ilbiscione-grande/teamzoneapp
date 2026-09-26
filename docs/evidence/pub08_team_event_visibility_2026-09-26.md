# Lagets gemensamma publiceringsval

Status: aktiverat i testprojektet hgcshgunvooyudvrcpig efter användarens godkännande. Ingen publiceringspreferens har ändrats åt användaren. Appservern på localhost:5000 har kompilerats om med laginställningarna.

Inställningar → Laginställningar → lagets namn öppnar val för matchresultat och träningstider. Behöriga lagledare och publiceringsansvariga kan spara valen för hela laget. Sparandet använder versionskontroll och avvisar inaktuella klienter.

Resultat publiceras automatiskt för avslutade matcher och följer rättningar. Återöppning tar bort resultatet tills matchen avslutas igen. Träningstider visas för befintliga och framtida schemalagda träningar, med den neutrala rubriken Träning. Interna träningsanteckningar och deltagaruppgifter ingår inte. Avstängning döljer respektive innehåll; redan separat publicerad matchinformation kan finnas kvar utan resultat. Avbokade och arkiverade händelser visas inte.

Privata föräldrasidor förblir privata. Återpublicering återställer lagets sparade val. Äldre klienters eventpublicering kan inte kringgå sparade lagval. Nya val är avstängda som standard; äldre individuella val ersätts först när laginställningarna sparas.

Migration: `20260926012847_pub08_team_event_visibility.sql`. Den lägger till en privat RLS-skyddad preferenstabell, behörighetskontrollerade RPC-anrop och synkronisering till befintliga publika projektioner. Ingen generell migrationspush krävs. Befintlig publik webb och följarflöde läser redan dessa projektioner.

Verifiering:

- 18 Flutter-tester godkända, inklusive hela navigeringen och sparandet samt regression för falskt anslutningsfel vid eventpublicering.
- Isolerade PostgreSQL-tester: behörigheter, standardval, befintliga resultat, framtida träningar, rättningar, återöppning, avslut, avstängning, revisionskonflikter, äldre klient, avbokning och privat/återpublicerat lag.
- Hosted verifiering med full rollback bekräftar publicering av avslutade resultat och schemalagda träningar samt avstängning av båda.
- Hosted test upptäckte den verkliga köns unika nyckel. Följdmigrationen `20260926060124_pub08_invalidation_queue_keys.sql` återställer ett befintligt invalidationsjobb till pending och nollställer leveransförsöken. Befintlig trigger rensar gamla leveranslås. Båda migrationerna har tillämpats; den lokala testmodellen inkluderar nu den unika nyckeln.
- Befintlig security advisor-baslinje: 41 INFO för RLS utan policy och tidigare lösenordsskyddsvarning. Ny tabell har explicit deny-policy och inga direkta klientgrants.

Det tidigare anslutningsfelet var en Flutter setState-callback som returnerade en Future efter lyckad publicering. Den returnerar nu void. Matchdialogens textfält äger sin controller så att dialogstängning inte använder en redan stängd controller. Denna rättning har laddats på localhost:5000 före laginställningsändringen.
