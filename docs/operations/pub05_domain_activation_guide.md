# PUB-05 – domänaktivering och automatisk routing

Detta är ett förberedande körkort. Det ger inte tillstånd att ändra DNS, TLS, hosting eller produktion.

## Standardadress

Standardadressen är alltid `https://teamzoneapp.se/{klubbslug}`. Den kräver ingen klubbunik provisionering och är canonical tills en aktiv premiumdomän uttryckligen väljs.

## Egen premiumdomän

1. Behörig publicist begär en unik hostname. Systemet normaliserar den, reserverar den atomiskt och visar TXT-namn, engångstoken och routingmål.
2. Kommersiellt system godkänner entitlement utan att PUB-05 hårdkodar paketnamn eller pris.
3. Klubben publicerar TXT-posten `_teamzone-verify.<hostname>` med engångstoken och följer DNS-guiden för routingmålet.
4. Serviceworker läser DNS externt och skickar den observerade token till verifieringskommandot. Token lagras endast hashad i domänobjektet och löper ut efter 72 timmar.
5. Hostingadapter startar provideraktivering och registrerar providerreferens. Domänen kan inte bli `active` innan TLS är `ready`.
6. Efter oberoende HTTPS-, certifikat- och tenant-smoke kan publicisten välja domänen som canonical. Endast en canonical domän tillåts per klubb.
7. Path-adressen och övriga aktiva alias svarar därefter med permanent `308` till canonical. Avaktivering tar bort canonical-status och faller tillbaka till path-adressen.

## TeamZone-premiumsubdomän

`{klubbslug}.teamzoneapp.se` är strukturellt blockerad. Den får öppnas först genom en senare migration efter att samtliga tre globala grindar verifierats:

1. wildcard-DNS är aktiv och kapacitetstestad;
2. wildcard-TLS är aktivt och certifikatförnyelse testad;
3. automatisk hostname→tenant-routing, rollback, övervakning och kostnadsgrind är godkända.

Ingen normal klubbaktivering får skapa en manuell hosting-/certifikatkoppling för en TeamZone-subdomän.

## Fel och rollback

- En hostname är globalt unik; dubblett ger neutralt `hostname_unavailable`.
- Okänd eller inaktiv host failar med 404 och `no-store`.
- Osäker redirect, okänd route eller backendfel failar stängt.
- TLS-/providerfel flyttar domänen till `failed` med sanitiserad felkod.
- `disabled` tar bort canonical-status; path-adressen förblir återställningsväg.
- Alla domänövergångar har append-only auditspår.

## Separat releasegrind

Före faktisk aktivering krävs uttryckligt godkännande för DNS/hosting/TLS, en bestämd premium-entitlement, provideradapter, worker, monitorering, supportflöde och rollbackövning.
