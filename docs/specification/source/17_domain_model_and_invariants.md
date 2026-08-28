# Steg 2A – domänmodell och invariants

**Status: produktgodkänd och tekniskt/säkerhetsmässigt reviewad med villkor 2026-08-07. Separat implementationstillstånd krävs.**

## Modellens kärna

| Begrepp | Betydelse | Ägare/source of truth |
|---|---|---|
| Account | Supabase Auth-identitet och session | `auth.users` |
| Profile | Kontots globala, minimala appidentitet | Identity |
| Club | Tenant och kommersiell/billingmässig kund | Club |
| Club person | Klubbägd representation av en människa, även utan konto | Roster |
| Account link | Verifierad koppling mellan profile och club person | Identity/Roster |
| Team | Verksamhetsenhet under exakt en klubb | Club |
| Assignment | Temporal roll/capabilityrelation för club person i klubb eller lag | Authorization |
| Guardian relation | Temporal, auditerad acting-as-relation till club person | Safeguarding |
| Context | Härledd läsvy av account + club/team + capabilities; aldrig egen behörighetskälla | Identity |
| Entitlement | Serverhärledd rätt för en klubb att använda plan/modul | Billing |

Ett konto kan länkas till flera `club_person`, även mellan klubbar. En `club_person` tillhör exakt en klubb. Historiska fakta pekar på den representation som deltog när fakta skapades och flyttas inte vid transfer.

## Domängränser

| Domän | Äger | Får referera till | Får inte göra |
|---|---|---|---|
| Identity/Authorization | profile, account link, assignment, capability projection | club/team/person | Lagra UI-roll som authorizationfact |
| Club/Roster | club, team, club person, eligibility, transfer/loan | profile via verifierad link | Radera globalt konto när lagrelation avslutas |
| Event | event, recurrence, event team/audience/location | club/team | Tolka audience som editbehörighet |
| Squad/Callup | squad revision, eligibility snapshot, callup, response, attendance | event/person/guardian actor | Skapa callup via parallell direktväg |
| Messaging | thread, participant, message, read/mute/block/report | profile/person/context | Härleda recipients bredare än threadaccess |
| Notification | outbox, delivery attempt, device endpoint, preference | domänevent | Ändra domänstatus när leverans misslyckas |
| Match | match command log, match facts, projection | event/squad snapshot | Hard-delete historiska matchkommandon |
| Development/Signals | planer, check-in, signal fact/provenance | person/team/event stats | Presentera proxy som medicinsk diagnos |
| Publication | consent, publication, public projection | club/team/media | Exponera intern tabell direkt till anon |
| Billing | customer, subscription, pricebook ref, entitlement projection | club | Låta klient eller webhookpayload ge access direkt |
| Economy/Board | ledger, obligation, pledge, mandate/approval | club/team/person | Uppdatera saldo som fristående fact |
| Integration | tenant link, external reference, sync attempt | explicit owner-system-ID | Skriva direkt i annat systems tabeller |

## Globala invariants

1. Varje tenantägd rad har en entydig `club_id`; team- och eventkopplingar måste matcha den via FK/constraint eller atomiskt kommando.
2. Klient-ID:n används som uppslag, aldrig som bevis på tenant, actor, roll eller entitlement.
3. Authorization utvärderar `auth.uid()` → aktiv account link/assignment → capability → objektrelation → transition.
4. Okänd roll, status, capability, entitlement eller revision nekas.
5. Skrivningar med flera facts sker i en transaktion och producerar audit/outbox atomiskt.
6. Kommandon som kan återförsökas har unik `(actor_profile_id, idempotency_key, command_type)` och stabilt resultat.
7. Revisionsskyddade aggregates kräver `expected_revision`; stale revision ändrar ingenting.
8. Historik korrigeras med revision, void eller reversal; inga osynliga overwrite/hard-delete i auditdomäner.
9. Actor och `acting_as_person_id` lagras separat. Guardian får aldrig bli implicit barn-actor.
10. Tid lagras som `timestamptz`; lokal timezone och all-day-semantik lagras explicit där domänen kräver det.
11. PII/media exponeras endast genom dataklassad projektion. Identifierare är inte i sig publiceringssamtycke.
12. Storage metadata och objekt skapas/raderas som en livscykel och delar tenant, owner, visibility och retention class.
13. Entitlement kan öppna en klubbmodul men ersätter aldrig personens capability eller objektscope.
14. Realtime är invalidation/transport, inte source of truth; reconnect följs av versionerad resync.

## Capabilitymodell

Capabilities är namespacade actions, exempelvis:

- `club.read`, `club.admin`, `club.people.manage`, `club.board.read`;
- `team.read`, `team.manage`, `team.roster.manage`, `team.event.manage`;
- `event.read`, `event.manage`, `event.squad.manage`, `event.attendance.manage`;
- `message.thread.create`, `message.send`, `message.moderate`;
- `match.command`, `match.unlock`;
- `development.team.manage`, `development.player.manage`, `health.clearance.manage`;
- `economy.read`, `economy.post`, `economy.approve`;
- `publication.manage`, `billing.manage`, `integration.manage`.

Rollnamn är versionerade UI-paket som projicerar capabilities. Servern kontrollerar alltid capability och scope. `super_admin` är ett separat, starkt auditerat systemmandat och syntetiseras inte som vanliga lagmedlemskap.

## Huvudtillståndsmaskiner

| Aggregate | Tillstånd | Tillåtna huvudövergångar |
|---|---|---|
| Assignment | pending, active, suspended, ended | pending→active/ended; active→suspended/ended; suspended→active/ended |
| Transfer | draft, source_approved, target_approved, completed, rejected, cancelled | completion kräver båda sidors godkännande och giltig revision |
| Event | draft, scheduled, cancelled, completed | scheduled kan revideras; completed/cancelled kräver explicit reopen capability |
| Squad | draft, locked, sent, superseded | endast aktiv revision kan låsas/skickas |
| Callup | draft, sent, cancelled, expired | response är separat fact; resend skapar leveransförsök |
| Response | pending, accepted, declined, tentative | actor/acting-as och revision sparas |
| Attendance | unknown, present, late, partial, absent | explicit ledarcommand; `unknown` är aldrig absent |
| Thread | requested, active, rejected, blocked, archived | cross-club first contact kräver request/accept |
| Match | scheduled, live, paused, fulltime, abandoned | endast v2 commandmodell; unlock är separat auditerat command |
| Subscription | pending, trialing, active, grace, read_only, ended, unknown | providerrevision får inte backa state; unknown fail-closed |
| Publication | private, listed, published, withdrawn | public projection byggs endast för published + giltigt samtycke |

## Aggregategränser och transaktioner

- `club_person` + account claim/link är en atomisk claim-aggregate.
- Eventserie är template/recurrence plus individuella occurrences; scope för en/denna-och-framåt/alla blir explicit command.
- Squadrevision + members + eligibility snapshots låses tillsammans innan callups skapas.
- Callupdomänändring och notification outbox skrivs tillsammans; leverans sker separat.
- Message + attachment metadata + outbox commitas tillsammans; binärt objekt måste vara verifierat stagingobjekt före commit.
- Match command + revision + facts + outbox är en transaktion.
- Billing provider event + subscription projection + entitlementoutbox är en idempotent transaktion.
- Ledgerpost + eventuell reversal/approval + audit är en transaktion; balans är projektion.

## Parameterberoenden

Öppna P0-parametrar i `16_open_parameter_backlog.md` begränsar endast berörda delkontrakt. Tills de beslutas gäller dokumenterad säker standard: privat/avstängt, minsta data, fail-closed och ingen automatisk högriskmutation.
