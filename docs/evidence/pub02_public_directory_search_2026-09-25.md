# Gemensam publik sökning

Status: användaren godkände migration och webbpublicering med ”ja”. Migrationen
är tillämpad i hgcshgunvooyudvrcpig. Webbpublicering och extern slutkontroll är klara.

Samma sökfält matchar publicerat klubbnamn, lagnamn, ort och åldersklass.
Ord kan kombineras över lagets och klubbens fält; varje ord matchas som prefix,
skiftlägesoberoende. Svenska tecken stöds. Klubb- och lagträffar har olika
märkning och länkar till respektive sida. Högst tio träffar visas, med uppmaning
att precisera sökningen när fler finns. Detta är inte stavningskorrigering eller
matchning inuti godtyckliga ord.

Migration: `supabase/migrations/20260925182837_pub02_public_directory_search.sql`.
Två genererade sökvektorer med GIN-index samt en ny service_role-begränsad RPC.
Den befintliga klubb-RPC:n behålls. Läsning sker enbart från publika projektioner.
Lag måste vara published och ha published förälder. Befintlig runtimegrind och
IP-baserad sökbegränsning återanvänds. Ny webbendpoint är
`/api/public/v1/directory/search?q=...`, alltid no-store.

Verifierat lokalt:

- 37/37 befintliga Node-tester och TypeScript-kontroll passerar.
- Isolerat produktionsbygge i `.tmp-public-search-release` passerar.
- Verklig PostgreSQL-körning via PGlite av migrationen och
  `supabase/tests/pub02_public_directory_search.sql` passerar. Testharnessen
  använder projektionstabeller och rate-limit-funktion från befintliga migrationer,
  en minimal runtimetabell och befintlig runtimefunktion. Inga hosted data ändras.
- Testerna täcker svenska tecken, skiftläge, prefix, kombinerade fält, åldersklass,
  listad klubb, dolt lag, icke-publicerad förälder, nollträffar, inga interna
  metadata i svaret, sidgräns, indatagränser, funktionsbehörigheter,
  20 sökningar/minut, avpublicering/borttagning av förälder och runtime av.
- Lokal maskins postgres/initdb kraschade vid initiering; PGlite användes därefter.

Förberedd leverans: tillämpa endast ovanstående migration i
`hgcshgunvooyudvrcpig`, verifiera med publicerade testdata, publicera endast
befintliga Firebase-backenden `teamzoneapp-public` i `teamzoneapp-b02a2` och
kontrollera sökningen på `public.teamzoneapp.se`. Produktionsprojekt och andra
Firebase-delar ingår inte. Runtimeinställningen ska inte ändras.

## Hosted verifiering efter godkännande

Migrationen `pub02_public_directory_search` tillämpades framgångsrikt.
Anrop till `api.public_search_directory` gav Thomas klubb och Thomas lag för
`Vetlanda`, samt enbart Thomas lag för `Thomas Vetlanda J18`.
Säkerhetsrådgivaren visar samma tidigare 41 informationsnotiser om RLS utan
policy och en tidigare varning om lösenordsskydd; inga nya sökrelaterade fynd.
Referenser: [RLS](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
och [lösenordsskydd](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Firebase rapporterade lyckad rollout av endast `teamzoneapp-public`.
I webbläsaren på `https://public.teamzoneapp.se/klubbar` gav `Vetlanda` två
synliga träffar: Thomas klubb och Thomas lag, med rätt separata länkar.
Externa API-anropet med `Thomas Vetlanda J18` gav HTTP 200, Cache-Control
`no-store` och en lagträff, Thomas lag. Även lokal webbläsarsökning med samma
kombination verifierades mot testprojektet.
