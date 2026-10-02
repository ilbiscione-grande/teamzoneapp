# Personal calendar conflicts across teams and clubs

## Scope

Account-private assistant cards compare the signed-in person's own pending and
accepted callups across different owning teams/clubs during the next seven days.
This includes matches, training, meetings and activities with an own callup.
Being a leader or team member alone is not a personal booking. Guardian-linked
children's schedules are not merged into the adult's schedule. Travel time is
not inferred. Existing same-team leader conflict cards remain separate.

Two accepted calls show “Du är dubbelbokad”; otherwise “Möjlig personlig krock”.
Both club/team labels, times, places and own response states appear on expansion.
The active badge includes personal cards for players as well as leaders.
The action picker opens either event's participant view using that event's own
context. Existing response controls handle the user's own callup. Time editing
is offered only with that context's event.manage capability, event revise action
and primary/co-managing relationship, rechecked on entry. Snooze/archive/restore
remain private and scoped to the exact pair; they never change calendar events.

## Authorization and database

Migration `20261002185842_assistant_personal_calendar_conflicts.sql` was created
with the CLI and applied only to audit project `hgcshgunvooyudvrcpig`.
The new RPC has no actor parameter: auth.uid(), active person_account_links,
current player/leader contexts and actor_can_read_event gate every event.
Only active own accepted/pending callups qualify. Canonical event IDs deduplicate
pairs and multiple roles. Cancelled/archived events, ended events, declined/
cancelled/expired calls, touching boundaries and events outside seven days are
excluded. Existing person-account and callup indexes are reused.

No cross-club comparison is added to leader projections or notifications.
Only this account may retrieve or archive its personal pair. Anonymous execute
is revoked; exposed API wrapper is security invoker, internal function uses
security definer with empty search_path and explicit authenticated actor checks.
The disposition command revalidates the live personal projection for this kind.
No additional table or direct table grant was introduced.

## Validation

- PGlite executes the actual migration and command: response states, role/pair
  deduplication, archive/snooze/restore, seven-day range, touching boundaries,
  cancelled/archived events, revoked event/context/account access, guardian
  exclusion, account isolation despite leader access and anonymous ACL passed.
- Hosted smoke query ran the projection with an existing account inside a
  rolled-back transaction; shape and authenticated/anonymous ACL passed.
  No user event, callup or response was changed by verification.
- Security advisor baseline unchanged: 55 informational private-table policy
  notices and the existing leaked-password-protection warning.
- 48 focused Flutter tests passed. Additional player integration checks opening
  the second club and responding as self, with no time-edit action.
- Client drops the whole personal batch on an event read failure, reports an
  incomplete check and suppresses an inaccurate badge count. Fresh event reads
  recheck overlap; a delayed permission change is still enforced by domain RPCs.

References consulted: [Supabase database functions](https://supabase.com/docs/guides/database/functions)
and current changelog. No SDK/API convention change was needed.

Local web build targets the audit backend. No hosting deployment or phone install.
