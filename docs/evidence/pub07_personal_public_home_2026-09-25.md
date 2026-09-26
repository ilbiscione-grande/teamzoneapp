# PUB-07 – personlig publik startsida

Status: godkänd, migrerad och publicerad i testprojektets befintliga publika webb.
Utloggad läsning är verifierad. Kontots följ/avfölj/flöde är verifierat i hosted
rollback-test; fysisk inloggning med användarens konto återstår.

Produktägaren vill kunna följa klubbar och framför allt lag och se genvägar,
senaste nyheter och resultat på den gemensamma publika startsidan. På frågan om
lagring valde produktägaren **Kopplat till ett konto**.

Produktägaren godkände aktiveringen och förtydligade att publika lagsidor måste
kunna läsas utan inloggning. Detta är ett bestående produktkrav: autentisering
krävs endast för personligt följande och kontots startsida. Ingen inloggningsgrind
får läggas framför publika klubb-/lagsidor, sökning eller publicerade nyheter.

## Implementerat

- Gemensamma `/` blir Min startsida efter inloggning med befintligt TeamZone-konto.
  Registrering och lösenordsåterställning hänvisar till befintliga appen.
- Följ/Sluta följa på publicerade klubb- och lagsidor, sökresultat och egna genvägar.
- Privata följlistor per `auth.uid()`, högst 100 kanaler. Ingen klubbmedlemskap
  krävs för att följa publik information. Följande ger inga interna behörigheter.
- Samlat flöde, senaste först, med filter Allt/Nyheter/Resultat, manuell
  uppdatering och markörbaserad hämtning av äldre inlägg. Dubletter över klubb-
  och lagkanaler tas bort. Följd klubb omfattar dess offentliga kanalers innehåll;
  följt lag omfattar innehåll riktat till laget.
- Avpublicerade kanaler och deras innehåll filtreras bort vid hämtning. Det
  sparade följandet bevaras och återkommer om samma kanal återpubliceras.
  Kontoborttagning raderar följlistan genom FK-cascade.
- Appens befintliga publiceringsdialog har separat, avstängt standardval för
  slutresultat. Endast avslutade matcher kan väljas. Lagets poäng visas först.
- Resultat publiceras som godkänd ögonblicksbild, utan spelare, statistik eller
  livehändelser. Korrigering, återöppning, borttagning eller avpublicering rensar
  resultatprojektionen. Ett rättat resultat kräver nytt publiceringsval.
- Lagets publika sida visar senaste tio publicerade slutresultat.

## Tekniskt och verifiering

`20260925203332_pub07_account_follows_and_feed.sql` lägger till följande och
kontospecifikt flöde. `20260925203446_pub07_explicit_public_match_results.sql`
lägger till resultatprojektion, rensningstriggers, ny bakåtkompatibel
publiceringssignatur samt utökad hanteringsvy. Befintliga klientanrop utan det
nya valfria argumentet fortsätter att fungera, med resultatpublicering avstängd.

Inloggning återanvänder `auth-password-sign-in`. Endast dess CORS-lista utökas
med `https://public.teamzoneapp.se` och `http://localhost:5001`. Inga nycklar
roteras. Webbläsaren får endast projektets befintliga aktiva publishable key.
Privilegierad servernyckel lämnar aldrig servern. Personliga svar hämtas direkt
med kontots JWT och no-store, aldrig i gemensamt cachad HTML. Kontobyte och
utloggning tömmer klientens flöde; sena svar ignoreras. Publikt innehåll följer
befintlig runtimegrind. Inga meddelanden, pushnotiser eller e-postutskick införs.

Verifierat:

- 40/40 Node-tester och TypeScript-kontroll.
- Isolerat Next-produktionsbygge i `.tmp-personal-home-release`.
- Flutter analyze utan anmärkningar; 12/12 riktade publiceringstester.
- `node supabase/tests/pub07_personal_home.local.mjs` passerar i isolerad PGlite
  med riktiga migrationsfunktioner, projektionstabeller och rate-limiter.
  Harnessens core-tabeller är minimala fixturer och capabilityfunktionen är en
  kontrollerad tillståndsfixtur; full hosted integrationskontroll återstår.
- SQL-tester: två kontons isolering, följ/avfölj/idempotens, maxgräns, inga
  medlemskapskrav, nekad obehörig publicering, nollpoäng, aktivt resultatval,
  rättning/återöppning/avpublicering, deduplicering, pagination, ofullständig
  markör, privat förälder, kontoborttagning och runtime av.
- Lokal utloggad startvy visuellt kontrollerad. Funktionsflaggan är fortsatt av
  lokalt; inloggad webbvy och verkligt konto över flera enheter är ännu inte
  verifierade. Gamla lokala browserfliken hamnade tillfälligt på anslutningsfel
  vid Next-omstart; en ny flik och HTTP-kontroll visade fungerande startsida.

## Konkret aktivering efter godkännande

1. Tillämpa enbart de två PUB-07-migrationerna i `hgcshgunvooyudvrcpig` och
   kontrollera funktioner, behörigheter och säkerhetsrådgivare.
2. Publicera enbart ändringen av `auth-password-sign-in` till samma testprojekt.
3. Publicera den byggda webbversionen till befintliga `teamzoneapp-public` i
   Firebase-projektet `teamzoneapp-b02a2`. Den förberedda apphosting.yaml har
   publishable key, SUPABASE_URL även under BUILD för CSP, och funktionsflagga 1.
4. Aktivera motsvarande lokal webbflagga och ladda om lokala Flutter-appen så
   resultatvalet kan provas. Separat distribution av Flutter till externa
   appanvändare ingår inte i denna webbpublicering.
5. Verifiera inloggning, följ Thomas lag, återbesök, separat kontosession,
   avföljande och publicerat innehåll. Användaren loggar in själv; inga lösenord
   ska efterfrågas i chatten. Publicera inte verkliga nyheter/resultat enbart för
   att fylla flödet utan uttryckligt val från behörig publicerare.

Funktionsflaggan kan stängas av och föregående webbversion återställas utan att
radera följlistor. Gamla TeamZone-projektet, andra databaser, DNS och global
runtimeinställning ska inte ändras. Kontofunktionerna är avsedda för den
gemensamma publika domänen; separat kontoöverföring/SSO till klubbars egna
domäner ingår inte.

## Genomförd aktivering

- Båda PUB-07-migrationerna tillämpades framgångsrikt i `hgcshgunvooyudvrcpig`.
- Hosted transaktionstest med verklig authenticated-roll och befintlig
  publicerares identitet verifierade följ Thomas lag, hämta personligt flöde
  och avfölj. Full rollback; inga testföljanden lämnades kvar.
- Auth-funktionen publicerades som version 3 med befintlig `verify_jwt=false`;
  lösenordsverifieringen är oförändrad. CORS-preflight från public.teamzoneapp.se
  gav 200 och exakt tillåtet Origin.
- Firebase rollout av endast `teamzoneapp-public` lyckades. Account-config
  gav 200, enabled=true och enbart publishable key till webbläsaren. Lokal
  funktionsflagga är också på och Flutter-servern startades om på port 5000.
- Externa Thomas lag visades i webbläsaren utan inloggning med namn, åldersklass,
  översikt, nyheter och kalender. Följ-länken leder till valfri inloggning;
  lagsidan själv har ingen inloggningsgrind.
- Säkerhetsrådgivaren visar samma 41 tidigare RLS-informationsnotiser och
  tidigare varning om lösenordsskydd, inga nya PUB-07-fynd. Referenser:
  [RLS](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
  och [lösenordsskydd](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
- Användaren har ombetts logga in själv i den lokala startsidan för fysisk
  kontoverifiering. Inga lösenord har hämtats eller efterfrågats i chatten.
