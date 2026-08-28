# S02 roster lifecycle evidence

Date: 2026-08-07, closed 2026-08-08  
Target: greenfield Supabase project `TeamzoneApp` (`hgcshgunvooyudvrcpig`)  
Legacy boundary: Teamzone6 was not read or changed.

## Delivered

- Stable global `persons` separated from tenant-owned `club_people`.
- Temporal home-team assignments, typed play eligibilities, guardian relation
  storage, hashed single-use roster invites and two-sided transfer cases.
- Composite tenant foreign keys, temporal overlap rejection and history-safe
  transfer completion.
- Minimal roster query plus idempotent create, invite, claim, assignment-end and
  request/decide/complete-transfer commands.
- Flutter roster list/detail safe states, capability-adapted management affordance
  and an actionable invite-claim flow from the waiting room.
- Approved guardian policy: only `club.safeguarding.manage` can issue a
  seven-day-or-shorter invite; the linked guardian account must accept it;
  direct relation creation remains denied.
- A safeguarding-marked transfer requires source, target and active guardian
  approval before completion.

## Hosted verification

| Check | Result |
|---|---|
| Migration parity | 6/6 S02 local filenames match hosted migration history |
| Schema/API inventory | Guardian invite table and issue/accept API added to the verified S02 inventory |
| Transactional matrix | Passed and rolled back |
| Idempotency | Duplicate roster-create key created one person and one audit event |
| Claim race/replay | First claim passed; consumed token retry denied |
| Tenant isolation | Cross-club roster query returned fail-closed denial |
| Temporal rule | Overlapping active home assignment denied |
| Transfer | Adult flow requires source + target; safeguarding flow remained requested after both clubs and required guardian as third approval |
| Guardian policy | Wrong account denied; linked guardian accepted once; token replay denied; direct relation creation denied |
| Test residue | Auth users, clubs, guardian invites/relations and transfer cases all verified at zero |
| Security Advisor | No findings |
| Performance Advisor | No missing-FK-index findings; only expected unused-index INFO notices on the empty greenfield tables |
| Flutter analyze | No issues found |
| Flutter tests | 12/12 passed |

## Migrations

1. `20260807220144_s02_roster_lifecycle.sql`
2. `20260807220425_s02_ensure_person_identity.sql`
3. `20260807220513_s02_qualify_token_hash.sql`
4. `20260807220626_s02_fix_transfer_decision.sql`
5. `20260807220905_s02_advisor_hardening.sql`
6. `20260807221647_s02_guardian_policy.sql`

The separate corrective migrations preserve the exact hosted history and make a
fresh replay converge on the verified schema.

## S02 closure

The product owner approved the conservative PRD-07 policy on 2026-08-08.
Guardian acceptance is exposed in the waiting room and roster surface with
sanitized errors. The relation, acting guardian and child are audit-attributed;
minor data remains private and cannot be activated by the child account.

Greenfield migration/backfill and rollback to legacy reads are not applicable.
Roll-forward uses repository migrations; rollback is recreation of the empty
greenfield project. This does not authorize changes to Teamzone6.
