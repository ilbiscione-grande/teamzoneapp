# Möten och aktiviteter på personlig startsida

Användaren preciserade att endast inloggade användare med behörighet i det egna laget ska se möten och aktiviteter. Publikt följande ger inte tillgång.

Den personliga startsidan har en separat kalendersektion för kommande 90 dagar. Klienten hämtar egna lagkontexter via `api.get_my_contexts` och kalendern via befintlig `api.list_calendar_page`. Kalenderfunktionen kontrollerar både att kontexterna tillhör anroparen och `internal.actor_can_read_event` för varje händelse. Gränssnittet begränsar därefter vyn till schemalagda möten/aktiviteter vars ägande lag finns bland användarens egna lag. Klubbkontexter utan lag används inte. Delade händelser från andra ägande lag visas inte i denna vy.

Privata uppgifter hämtas med användarens JWT och no-store, inte av den publika serverrenderingen. Utloggning och kontobyte döljer uppgifterna och gamla förfrågningar ignoreras. Ingen ny databasmigration behövs för kalenderdelen.

Verifiering: 44 webbtester godkända inklusive följare utan lag, egen lagavgränsning, inställda händelser, paginering och återkallad behörighet. TypeScript-kontroll utan fel. Produktionsbygge godkänt med webpack i den isolerade releasekatalogen; Turbopack kunde inte följa katalogens lokala node_modules-junction. Hosted kalenderanrop med authenticated-roll fungerar, och anon saknar execute-rättighet. Ingen inloggad webbläsarsession användes i verifieringen.

Publicering till enbart App Hosting-backend `teamzoneapp-public` i `teamzoneapp-b02a2` slutförd. Den lokala utvecklingsservern använder också de nya komponenterna.
