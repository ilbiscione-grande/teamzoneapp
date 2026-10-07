# Nyhetsbilder

## Syfte

En nyhet kan ha en toppbild. Bilden laddas upp privat, bearbetas av
TeamZones egen Edge Function `public-media-worker` och blir publik först som en
ny WebP-fil på `/media/public/<slumpad nyckel>`. Originalet raderas efter
bearbetningen.

Bearbetningen:

1. avgör formatet från filens signatur (JPEG, PNG eller WebP); allt annat avvisas
2. läser bildens mått ur filhuvudet och avvisar bilder större än 8192 px per
   sida eller 40 megapixel innan något avkodas
3. avkodar med ImageMagick (WebAssembly, `@imagemagick/magick-wasm@0.0.42`)
4. vänder bilden rätt och tar bort all metadata, bland annat GPS-position
5. skalar till högst 2048 px och sparar som WebP

Webbläsaren och appen skalar redan ner och komprimerar bilden före
uppladdningen, men publiceringen bygger bara på serverns bearbetning.

## Flöde

| Steg | Var |
|---|---|
| Välj bild, förbered (rotation, max 2560 px, JPEG) | webb-admin eller appens nyhetsredaktion |
| `api.stage_public_media(club, 'editorial_hero', …)` | kräver `publication.manage` i klubben |
| Uppladdning till privata bucketen `public-media-source` | Storage-policy: egen, nyss förberedd fil |
| `api.set_editorial_article_hero(article, asset, alt, revision, key)` | revision, idempotens, audit |
| Anrop av `public-media-worker` | med användarens inloggning direkt efter uppladdningen |
| Variant i `public-media-variants`, `variant_state='ready'` | publik väg sätts på publicerad nyhet |

Workern tar upp till fem väntande bilder per anrop. Ett missat anrop plockas
upp av nästa. En bild som inte kan avkodas markeras som borttagen och blir
aldrig publik. En ersatt eller borttagen toppbild slutar levereras direkt,
och delade cachar har högst en timme gammal kopia.

## Driftsättning

1. Kör migrationen `20261007090000_editorial_hero_image.sql`.
2. Driftsätt funktionen med JWT-kontroll påslagen (standard):

   ```bash
   supabase functions deploy public-media-worker
   ```

3. Inga nya hemligheter behövs. `PUBLIC_MEDIA_PROVIDER_URL` och
   `PUBLIC_MEDIA_PROVIDER_KEY` används inte längre och kan tas bort.

## Driftkontroll

- Ladda upp en bild på en testnyhet. Listan ska visa "Bilden bearbetas" och
  efter en kort stund "Bild".
- `select purpose,scan_state,variant_state,count(*) from core.public_media_assets group by 1,2,3;`
  ska inte visa gamla rader med `variant_state='pending'`.
- Funktionens logg skriver `worker.completed` med antal klara, avvisade och
  misslyckade bilder, aldrig bildinnehåll eller personuppgifter.

## Felsökning

| Symtom | Trolig orsak |
|---|---|
| Bilden står kvar som "Bilden bearbetas" | funktionen är inte driftsatt eller anropet misslyckades; ett nytt anrop (ny uppladdning) tar upp kön |
| `worker_not_configured` (503) | ImageMagick kunde inte laddas, t.ex. för stor funktion eller ändrad paketlayout |
| "Bilden godkändes inte" | filen var inte en giltig JPEG/PNG/WebP eller var för stor |
| Bilden syns inte på nyhetssidan | nyheten publicerades innan bearbetningen; sidan uppdateras inom en minut när bilden blir klar |
