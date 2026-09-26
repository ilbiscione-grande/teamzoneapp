# PUB-03 – redaktionellt nyhetsflöde

Datum: 2026-08-27  
Status: lokalt genomfört, runtime- och UX-verifiering återstår

## Levererad gräns

- Capabilityn `publication.manage` krävs för att läsa, spara och ändra en artikel.
- Artiklar har revisionerade tillstånd: `draft`, `scheduled`, `published` och `unpublished`.
- Utkast kan riktas till klubbkanalen, en eller flera lagkanaler eller båda.
- Innehåll lagras som strukturerade block (`heading`, `paragraph`, `link`); rå HTML accepteras inte och publiksajten använder inte `dangerouslySetInnerHTML`.
- Publicering skapar en allowlistad publik projektion. Avpublicering tar bort projektionen i samma transaktion och köar invalidation för berörda vägar.
- Schemalagd publicering exponeras endast för `service_role`.
- Privata meddelandebilagor återanvänds inte för publikt material. Redaktörssvaret anger `media_status: not_configured`; säker publik bildvariant levereras tillsammans med PUB-04.
- Publiksajten har canonical artikelroute `/{clubSlug}/nyheter/{articleSlug}` med metadata och 404-beteende.
- Flutter-appen har en capabilitystyrd redaktörsyta för artikelöversikt, utkast, redigering, kanalval, schemaläggning, publicering och avpublicering.
- Den lokala, ej utrullade migrationen `20260828083753_pub03_editorial_list_for_actor.sql` ger redaktörsytan en tenantfiltrerad API-listning genom `publication.manage`.

## Verifiering

- `npm run lint`: godkänd.
- `npm test`: 12/12 godkända.
- `npm run build`: godkänd; dynamisk artikelroute ingår.
- Kontraktstest verifierar capability, revision, kanalval, tillstånd, strukturerade block, atomisk avpublicering, invalidationskö och att privata filobjekt inte kopplats till artiklar.
- Riktade Flutter-tester verifierar att en behörig redaktör kan skapa ett strukturerat klubbutkast, att obehöriga saknar redaktionsingång och att list-RPC:n är capability- och tenantstyrd.
- `dart analyze lib test`: godkänd utan anmärkningar den 2026-08-28.
- Full Flutter-regression: 272/272 tester godkända den 2026-08-28.

### Redaktionell UX-uppföljning 2026-09-25

- Ny artikel får ett föreslaget adressnamn från rubriken, inklusive å/ä/ö-normalisering och giltig slugform. Egenvald adress bevaras när rubriken ändras; redaktören kan begära ett nytt förslag.
- Osparad rubrik, ingress, text, avsändare och valda klubb-/lagkanaler kan förhandsgranskas i appen. Vyn är uttryckligen en lokal innehållsförhandsgranskning och varken sparar eller publicerar något.
- Fem riktade Flutter-tester passerar, inklusive automatisk adress, manuell override och osparad förhandsgranskning. Statisk analys av ändrade filer är ren. Ingen Supabase-liveändring eller publik aktivering gjordes.

### Utkastssparande: SQL-ambiguitet åtgärdad 2026-09-25

- Produktägaren fick ”Kontrollera anslutningen och försök igen” vid sparande. Skrivskyddade Edge-/Postgresloggar visar att `save_editorial_article` faktiskt nådde servern men misslyckades med SQLSTATE `42702`: `column reference "article_id" is ambiguous`.
- Den driftsatta funktionen har ett okvalificerat `article_id` i kanalraderingen samtidigt som en PL/pgSQL-variabel heter likadant. Lokal migration `20260925070651_pub03_disambiguate_editorial_draft_save.sql` ger variabeln eget namn och kvalificerar kolumnen. Behörighetskontroll, revision, idempotens och revisionshistorik behålls.
- Klienten visar nu ett sant sparfel i stället för ett påstående om anslutningsfel, och adressfältets minlängd matchar serverns 2-teckenskrav. PUB-03/FND-05 16/16 riktade tester och statisk analys passerar.
- Produktägaren godkände uttryckligen just denna migration för testprojektet `hgcshgunvooyudvrcpig`; den applicerades där som remote version `20260925073924` och den driftsatta funktionen kontrollerades efteråt. Den gamla tvetydiga referensen är borta, den kvalificerade kanalreferensen finns och `SECURITY DEFINER` är bevarat.
- Ett utkast skapades och ett befintligt utkast uppdaterades med samma databasfunktion under återställande SQL-transaktioner. Funktionen returnerade `draft`, revision 1 respektive 2 utan fel; kontroll efteråt visade 0 kvarvarande testartiklar. Fysisk verifiering via redaktörens gränssnitt återstår.
- Lokal Flutter-webb byggdes om efter klientändringen; `http://localhost:5000/editorial` svarade 200 och den nya sparfelstexten finns i serverad build. Produktägaren bekräftade därefter att utkastssparandet fungerar i gränssnittet.

### Publiceringsgrind och redaktörs-UX 2026-09-25

- Produktägaren verifierade att sparat utkast kan öppnas, redigeras och förhandsgranskas. Menyvalet ”Publicera nu” gav därefter det generiska anslutningsfelet. Edge-/Postgresloggar visar i stället `club_not_published` för publiceringskommandot.
- Skrivskyddad kontroll visar att testklubben Thomas klubb är `unofficial` och saknar en rad i `core.club_publication_settings`. Den befintliga `api.get_publication_domains` returnerar `club_published: false` för redaktörskontot. Den nuvarande PUB-02-implementeringen kräver officiell klubb, aktiv policybekräftelse och publicerad klubbsida. Produktägaren har därefter ändrat policyn: officiell status ska inte längre vara ett publiceringsvillkor (se PUB-02:s reviderade beslut). Nuvarande backendgrind kvarstår tills den byggts om och testats.
- Redigeringsvyn har nu en synlig ”Publicera nu”-knapp för sparade artiklar, en kontroll som kräver att osparade ändringar först sparas och en bekräftelsedialog. Både knappen och listmenyn kontrollerar den befintliga, capability-skyddade publiceringsstatusen före åtgärden och förklarar när klubbsidan inte är publicerad. Övriga fel beskrivs som publiceringsfel, inte som antagna nätverksfel.
- Riktade Flutter-tester: 8/8 godkända. Statisk analys av ändrade filer: utan anmärkning. Lokal webb ombyggd och `/editorial` svarar 200 med den nya publiceringskontrollen i builden. Ingen ny Supabase-liveändring eller klubbpublicering har gjorts; publicering av nyheten återstår tills klubbens publiceringsgrind har uppfyllts med separat godkännande.

## Återstår före full klarmarkering


- Säker publik bildvariant och dess avpublicering i PUB-04.
- PostgreSQL-runtime och advisors när lokal databas eller godkänd miljö finns.
- Hosted verifiering av schemaläggning och uppmätt cacheinvalidation mot fastställd SLA.
- Fysisk responsivitets- och flerrollsverifiering av redaktörsytan.
- Separat uttryckligt godkännande före ytterligare Supabase-liveändringar.

Endast den uttryckligen godkända SQL-migrationen ovan applicerades i Supabase testprojekt. Ingen separat produktionsprovisionering, webtools eller workspace utfördes.
