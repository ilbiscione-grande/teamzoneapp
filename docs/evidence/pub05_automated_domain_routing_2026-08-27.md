# PUB-05 – automatisk domänrouting

Datum: 2026-08-27  
Status: lokalt genomfört, provider- och hosted verifiering återstår

## Levererat

- Standardadressen `teamzoneapp.se/{klubbslug}` förblir kostnadsfri, skalbar fallback.
- Premiumdomäner får globalt unik hostname-claim och capabilitystyrd begäran.
- DNS-ägarskap verifieras med 72-timmars engångstoken; domänobjektet lagrar SHA-256-hash.
- Kommersiellt godkännande, DNS-verifiering, provideraktivering och TLS-ready är separata tillstånd.
- Endast service-role får verifiera DNS och ändra provider-/TLS-tillstånd.
- En partiell unik indexregel tillåter högst en canonical domän per klubb.
- Datadriven resolver returnerar endast path, intern rewrite, HTTPS 308 eller not-found. Proxyvalidering failar stängt.
- Canonical metadata använder den verifierade custom-hostens ursprungliga externa path.
- TeamZone-subdomäner kan inte begäras: alla tre wildcardgrindar har databasvillkoret `false` tills en senare separat migration öppnar dem.
- DNS-/TLS-/canonical-/rollbackguiden finns i `docs/operations/pub05_domain_activation_guide.md`.
- Flutter-appen har capabilitystyrd självbetjäning för status, egen domän, engångs-TXT-instruktion och canonical-val. Kostnadsfri path-adress visas alltid som fallback.
- Den lokala, ej utrullade migrationen `20260828093026_pub05_domain_management_projection.sql` tenantfiltrerar status och exponerar wildcardtillgänglighet endast när samtliga tre runtimegrindar är sanna.
- Publiceringskommandona för PUB-03–PUB-05 är nu explicit allowlistade i den mätta kommandogatewayen; före rättningen hade runtime nekat dem med `operation_not_allowed`.

Supabase-säkerhetsgränsen styrde implementationen: tabellerna saknar direkta klientgrants, RLS är defense-in-depth, användarkommandon verifierar `auth.uid()` och capability, serviceövergångar har explicita grants och domänhändelser auditeras separat.

## Verifiering

- TypeScript/lint: godkänd.
- Full publiksajtssvit: 18/18 godkända efter canonical-korrigeringen.
- Next-produktionsbuild: godkänd och verifierar att Proxy inkluderas.
- Kontraktstest täcker ägarverifiering, TLS-grind, canonical uniqueness, 308, wildcardblockering och hostile routinginput.
- `dart analyze lib test`: godkänd utan anmärkningar den 2026-08-28.
- Riktade domän-, publicerings-, gateway-, lokalisering- och scope-tester: godkända.
- Full Flutter-regression: 277/277 tester godkända den 2026-08-28.

## Återstår

- PostgreSQL-runtime och advisors.
- Val och implementation av premium-entitlement utan hårdkodat paketnamn i domänmodellen.
- Provideradapter/worker för DNS-observation, hostinganslutning, certifikat och retry/rollback.
- Hosted certifikat-, redirect-, takeover- och kapacitetstest efter separat driftgodkännande.

Ingen DNS, TLS, hosting, Supabase live, webtools eller workspace ändrades.
