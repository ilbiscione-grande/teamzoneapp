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

## Verifiering

- `npm run lint`: godkänd.
- `npm test`: 12/12 godkända.
- `npm run build`: godkänd; dynamisk artikelroute ingår.
- Kontraktstest verifierar capability, revision, kanalval, tillstånd, strukturerade block, atomisk avpublicering, invalidationskö och att privata filobjekt inte kopplats till artiklar.

## Återstår före full klarmarkering

- Autentiserad redaktörsyta i Flutter för skapa/redigera/preview/status/kanalval.
- Säker publik bildvariant och dess avpublicering i PUB-04.
- PostgreSQL-runtime och advisors när lokal databas eller godkänd miljö finns.
- Hosted verifiering av schemaläggning och uppmätt cacheinvalidation mot fastställd SLA.
- Separat uttryckligt godkännande före eventuell Supabase-liveändring.

Ingen livepush, driftsättning, webtools eller workspace utfördes.
