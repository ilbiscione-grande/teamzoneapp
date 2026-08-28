# S08 development, signals and Assistant Coach baseline

Date: 2026-08-15  
Target: greenfield TeamzoneApp only

## Authorized foundation

- Revisioned team/player development plans and actions with tenant-bound
  subjects, provenance, ordinary capabilities, audit and idempotent commands.
- Versioned signal definitions/facts and stale/semantic-class query contracts,
  initially inactive and limited to transparent raw facts.
- Assistant Coach v1 as a deterministic explanation/preview layer. Any mutation
  must be confirmed and executed by the ordinary authorized domain command.
- No dependency on workspaces or webtools.

## Enforced parameter gates

- `PAR-METHOD-02` is unresolved: injury clearance, suspension and dismissal
  dataspec/commands are not created.
- `PAR-METHOD-01` is unresolved: workload, attendance and watchpoint thresholds
  are not activated; no medical or physiological conclusion is produced.
- `PAR-PRIV-04` is unresolved: self-rating/check-in collection is disabled and
  cannot influence ranking or selection.
- `PAR-AI-01/02` are unresolved: no model provider, prompt, generative output or
  sensitive data processing is enabled.

These gates block only their named feature areas. They do not block the safe
development-plan foundation or explicit fail-closed API contracts.

## Implemented 2026-08-15

- `20260815092734_s08_development_plan_foundation.sql` deployed plan/action
  storage, tenant FKs, deny-by-default RLS, read projection and idempotent,
  audited create-plan/add-action commands with optimistic revision checks.
- `20260815093458_s08_rule_based_assistant_preview.sql` deployed versioned
  definitions and a deterministic preview of attendance/match raw counts.
  Database checks prevent non-raw definitions from becoming active.
- No automatic `development.manage` grant was deployed. Role assignment remains
  an explicit authorization step before hosted or physical mutation tests.
- Flutter now has an Utveckling surface that labels the preview as rule-based,
  shows raw-fact chips, and states which sensitive/derived features are off.
- `20260815093928_s08_advisor_hardening.sql` adds explicit API-only deny
  policies and covering FK indexes. Verification returned zero active non-raw
  signals, no authenticated direct plan select, and no anon preview execute.
- Flutter analyze is clean, 35/35 tests pass, and the debug APK built and
  installed successfully on Xiaomi Mi9 (`7243fa4b`).
- After explicit user approval, `development.manage` was granted only to the
  active team-leader assignment for `coach.emilson@gmail.com`. A hosted
  transaction verified deterministic preview, create-plan/add-action replay,
  stale-revision rejection and denial for the ungranted Thomas account; all
  matrix test writes were rolled back.

## Physical closure

Xiaomi Mi9 (`7243fa4b`) passed the authenticated walkthrough as the approved
coach account:

- Utveckling rendered the deterministic raw facts: one attendance registration,
  two own goals and one opponent goal.
- The UI explicitly stated that workload thresholds, self-rating, medical
  conclusions and generative AI are disabled.
- Team-plan creation persisted and refreshed immediately.
- Manual action creation persisted inside the plan and returned to the refreshed
  development surface.

Two client defects found during the walkthrough were corrected: premature
controller disposal caused `_dependents.isEmpty` red screens, and successful
writes were initially misreported while parsing/reloading the RPC response.
The final build separates command success from projection refresh and shows
success only after the command completes.

S08 is closed for the authorized fail-closed scope. PAR-METHOD-01/02,
PAR-PRIV-04 and PAR-AI-01/02 continue to block only their named extensions.
