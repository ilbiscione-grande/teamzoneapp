# S07 Match Space v2 baseline

Date: 2026-08-15  
Source: read-only local TeamZone workspace  
Target: greenfield TeamzoneApp only

## Frozen write contract

The verified v2 backend exposes ten command RPC signatures. S07 preserves the
names, argument order/defaults, return types and semantics behind TeamzoneApp's
`api` schema:

- `save_match_plan_v2(uuid,uuid,bigint,text,jsonb,jsonb,text,text,text,text,text,text,jsonb) -> bigint`
- `record_match_event_v2(uuid,uuid,integer,text,text,uuid,uuid,jsonb) -> uuid`
- `update_match_event_v2(uuid,uuid,integer,text,uuid,uuid,jsonb) -> void`
- `void_match_event_v2(uuid,uuid) -> void`
- `adjust_match_score_v2(uuid,uuid,text,integer,integer) -> void`
- `adjust_match_kpi_v2(uuid,uuid,text,text,integer,integer) -> void`
- `transition_match_clock_v2(uuid,uuid,text) -> void`
- `complete_match_v2(uuid,uuid,integer) -> void`
- `set_match_button_config_v2(uuid,uuid,bigint,jsonb,jsonb) -> bigint`
- `reset_match_v2(uuid,uuid) -> void`

Parameter names retain the frozen `p_` names from the verified contract.

## Frozen semantics

- `match_commands` is append-only and command ID is the idempotency key.
- Reuse of a command ID is allowed only for the identical actor, event, command
  type and payload; otherwise it fails.
- Match mutations serialize per event and return the stored result on retry.
- Plans/config use expected revision. Projection revisions are server-owned.
- States are `planning`, `live`, `completed`; clock actions are `start`,
  `pause`, `resume`, `unlock`. Fulltime blocks ordinary live commands.
- Timeline facts are never hard-deleted. Corrections use update revision or
  void, with actor and timestamps.
- Score and player/KPI statistics are derived only from active facts, including
  explicit `score_adjustment` facts. Negative score is rejected.
- Match roster membership is validated against the frozen matchday roster.
- Authenticated clients receive SELECT/projections and RPC EXECUTE only; they
  cannot insert, update or delete commands, facts, projections or statistics.

## Frozen regression evidence

The prior verified rollback matrices covered initial/stale plan revisions,
start/double-start, duplicate command retry, scorer and bench statistics, KPI
retry, scored-to-missed edit, logged score adjustment, foreign-team member and
tenant denial, direct-write denial, atomic fulltime, reset with retained voided
history, payload-mismatched command reuse and negative-score denial.

S07 adds greenfield event/team binding, accepted-callup roster freezing,
cursor/full resync, offline-gap replay, auditable unlock reason and feature-flag
fallback without weakening any frozen regression above.

No TeamZone database or live environment was accessed or changed while creating
this baseline.

## Adapter progress

- Greenfield event/team workspaces, frozen roster revisions, append-only command
  log, plans, facts and derived projections are deployed with RLS deny defaults.
- Roster freeze copies accepted S04 callups, supersedes prior snapshots only as
  an explicit revision, and returns the stored result for an identical retry.
- The v2 snapshot is authorized through S03 event visibility and contains a
  deterministic `(created_at, command_id)` resync cursor.
- A rolled-back hosted matrix passed event/team binding, roster freeze, duplicate
  command retry, snapshot/cursor and authenticated direct-write denial. No test
  workspace or match remained afterward.
- All ten frozen v2 mutation RPCs are deployed in the `api` schema. A rolled-back
  regression passed plan revision/retry, start, fact retry, derived score,
  negative-score denial, edit, KPI/config, fulltime lock, reasoned unlock, void
  and reset with retained command/fact-version history.
- Unlock has an additive reasoned RPC and requires `match.unlock`. No persistent
  assignment received that capability automatically; the regression grant was
  transaction-local and rolled back.
- The Flutter calendar opens Match Space for match events. The client always
  reloads a full server snapshot after commands and app resume, exposes
  roster-freeze/start/pause/resume/goals/fulltime/reasoned-unlock, disables
  controls while pending and retries failures with the same command UUID.
- `MATCH_SPACE_V2=false` selects a compact read-only fallback that consumes the
  same v2 snapshot rather than a parallel backend or data model.
- `flutter analyze` reports no issues and all 32 Flutter tests pass. A debug APK
  built with TeamzoneApp's active publishable key and was installed and launched
  successfully on the Xiaomi Mi 9.

## Physical closure

- A leader created a new match after the minimum role grants were corrected;
  roster and event creation were verified against the new TeamzoneApp project.
- The recipient-facing callup response was added with server-projected
  `can_respond`; Thomas accepted only his own callup and a leader then froze the
  accepted match roster as roster revision 1.
- The Xiaomi Mi 9 walkthrough passed start, visible clock, goal and derived
  1–0 score, period pause/resume, fulltime lock, reasoned privileged unlock and
  retry with the identical command UUID.
- The temporary `match.unlock` grant used for the physical check was revoked
  immediately afterward; no permanent unlock capability remains.
- Match facts are visible as a minute-labelled timeline. Raw resync cursor data
  is no longer exposed and authorization denial is distinguished from network
  failure.
- Match timing is modeled as 2–8 configurable periods. The default is 2×45;
  an isolated hosted rollback verified 3×20 end-period/pause/resume behavior
  and cumulative 20:00/40:00 clock anchoring without changing the physical
  test match.

S07 is closed. No TeamZone/live system or database was modified.
