# Personlig dashboard

Status: användaren godkände aktiveringen. Migrationen `20260926062708_pub09_personal_dashboard_content.sql` är tillämpad i testprojektet hgcshgunvooyudvrcpig. Dashboarden är publicerad på public.teamzoneapp.se.

Dashboarden innehåller:

- Överblickskort och genvägar till egna lag och följda lag/klubbar.
- Månadskalender och agenda för kommande 90 dagar. Filtrering på laggrupp, datum och match/träning/möte/aktivitet.
- Egna lags kalender hämtas via befintligt behörighetsstyrt list_calendar_page, oberoende av följande eller publicering. Endast eget ägande lag och tillåtna händelser inkluderas.
- Andra lag betyder följda lag och lag under följda klubbar. Endast publicerade matcher/träningar inkluderas därifrån, aldrig möten/aktiviteter.
- Nyheter från egna lag/klubbar automatiskt utan att användaren behöver följa sig själv; separat filter för andra följda lag. Högst 12 senaste nyheter per grupp.
- Egna avslutade matchresultat från senaste 90 dagarnas behörighetsstyrda kalender, kompletterat med publicerade resultat. Andra lags resultat är enbart publicerade resultat. Dubbletter slås samman med den behörighetsstyrda uppgiften först.
- Utfällbar matchrapport för egna avslutade matcher via befintligt get_match_v2_snapshot. Rapporter visar registrerade mål, kort, byten och periodmarkeringar; inga privata skadeanteckningar eller taktiska texter renderas. Rapporterna är registrerade händelser, inte genererad redaktionell text.

Nytt RPC-anrop get_personal_dashboard_content är ett autentiserat läsanrop. Egna lag bestäms server-side via get_my_contexts_for_actor. Det läser endast redan publika projektioner för nyheter/resultat/följda lag, respekterar publiceringsgrinden och publicerade föräldrasidor och ändrar ingen användardata. Privata kalenderanrop och matchrapporter använder redan existerande behörighetskontroller. Kontobyte/utloggning döljer tidigare kontoresultat; inga privata uppgifter serverrenderas i publikt HTML.

Verifiering:

- 48 Node-tester godkända; TypeScript utan fel.
- Isolerade PostgreSQL-tester verifierar egna nyheter/resultat utan följande, separat åtkomst för andra konton, andra lag först efter följande, deduplicering samt publicerings- och anonymitetsgrindar.
- Produktionsbygge godkänt i `.tmp-personal-home-release` med webpack (isoleringens node_modules-junction fungerar inte med Turbopack).
- Browsergranskning av separat lokal exempelmiljö `http://localhost:5002/`, tydligt märkt påhittade exempeldata. Träningsfilter, samlad kalender, följda lags nyheter och öppning av matchrapport verifierade.
- Exempelmiljön `.tmp-dashboard-preview` har en fristående mock för konto/data och ingår aldrig i release. Releasekatalogen har den riktiga PersonalAccount-komponenten och ordinarie säkerhetskonfiguration.

Hosted verifiering under authenticated-roll och full rollback: dashboardläsningen hittar två egna lag och en nyhet. Befintligt privat kalenderanrop hittar 10 matcher och 15 träningar i intervallet, varav två matcher är avslutade. Security advisors är oförändrade mot baslinjen (41 INFO och tidigare lösenordsskyddsvarning). Utloggad localhost-sida svarar 200 och innehåller ingen privat dashboard i serverrenderad HTML.

Publicering slutförd för enbart App Hosting-backend teamzoneapp-public. Behörighetsstyrt matchrapportanrop verifierat mot avslutad match med sex registrerade fakta.
