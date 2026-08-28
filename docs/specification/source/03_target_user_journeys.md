# Prioriterade målanvändarresor

## J1 – Konto, väntrum och claim

1. Personen skapar konto och profil.
2. Utan relation visas ett begränsat väntrum.
3. Personen accepterar säker invite eller ansöker till klubb/lag.
4. Servern länkar atomiskt eventuell platshållar-roster och bevarar historik.
5. Capabilities/contexts uppdateras och rätt startsida visas.

Grind: fel invite, fel tenant, dubblettprofil och obehörig rolleskalering nekas.

## J2 – Ledarens event till uppföljning

1. Ledaren skapar engångs- eller serieevent för explicit ägande lag.
2. Audience och eventtyp styr synlighet och tillgängliga flikar.
3. Trupp/grupp/lag läggs i revisionerat utkast.
4. Send skapar callups och leveransjobb atomiskt.
5. Svar, reminders och attendance behåller actor och leveransstatus.
6. Förberedelse och uppföljning använder grunddata plus valfria modulprojektioner.

Grind: shared-team, guardian, cross-team player, retry och partial delivery testas.

## J3 – Spelare/vårdnadshavare svarar

1. Hem och push visar relevant callup.
2. Användaren svarar accepted/declined; decline reason är valfri.
3. Guardian acting-as child är explicit och auditerat.
4. Efter event registrerar ledare faktisk attendance.
5. Statistik uppdateras per lagrepresentation och total personprojektion.

Grind: expiry/replay, notification opt-out och fel barn/member nekas.

## J4 – Flera roller och lag

1. Hem aggregerar prioriterade uppgifter från behöriga contexts.
2. Kalender visar samlad vy med filter.
3. Inbox visar endast trådar personen har faktisk participantaccess till.
4. Varje mutation visar och skickar explicit target klubb/lag.

Grind: URL, synlig context och servertenant är alltid samma för mutationer.

## J5 – Match

1. Kallad/fryst matchday roster blir input till matchplan.
2. Ledare sparar plan med optimistic revision.
3. Livekommandon använder idempotenta command IDs och serverklocka.
4. Reconnect laddar full snapshot och härledd score/statistik.
5. Efter match visas analys utan att ändra historik tyst.

Grind: befintligt v2-kontrakt och regressioner ska bevaras.

## J6 – Publik klubb-/lagsajt

1. Behörig publicist väljer fält och lag som får publiceras.
2. Minderårigdata kräver beslutad policy/samtycke.
3. Public projection exponeras genom limiterat anon-API.
4. Besökaren navigerar klubb → lag → trupp/event/matcher.
5. Avpublicering invalidaterar cache och mediaåtkomst.

Grind: hidden, revoked consent, wildcard enumeration och Storageobjekt verifieras.

## J7 – Köp och entitlement

1. Behörig klubbköpare väljer plan/modul/web tool och target.
2. Checkout har idempotency key.
3. Signerad webhook dedupliceras och uppdaterar kanonisk subscription.
4. Servern härleder quota/entitlement fail-closed.
5. App och web tool ser samma entitlementversion.

Grind: duplicate, out-of-order, partial failure, grace och cancellation testas.

