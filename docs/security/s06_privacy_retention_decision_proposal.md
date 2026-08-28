# S06 privacy, retention and safeguarding proposal

Date: 2026-08-08  
Scope: PAR-PRIV-01 and PAR-PRIV-03  
Status: **approved 2026-08-08 for S06 implementation**

Approval authority: the project owner explicitly approved PAR-PRIV-01 and
PAR-PRIV-03 in all listed roles in the Codex task on 2026-08-08. This approval
authorizes implementation in the greenfield TeamzoneApp project only; it does
not authorize Teamzone6/live changes or production release.

## Decision needed

The product owner, privacy/data owner and legal/security approvers must sign the
matrix and safeguards below before S06 stores message bodies, attachments,
cross-club requests, reports or moderation evidence. A DPIA screening must be
recorded before activation; if screening indicates likely high risk, the DPIA
must be completed before processing starts.

The proposal follows purpose limitation, data minimisation, storage limitation,
privacy by default and the higher risk associated with children's data. Exact
legal basis, controller/processor roles, data-subject information and handling
of statutory preservation requests remain legal decisions.

## Proposed PAR-PRIV-01 retention matrix

Durations are maximum defaults, counted from the stated trigger. A club may
choose a shorter period, never a longer one without a new approved policy.

| Data class | Proposed maximum | Trigger and deletion outcome |
|---|---:|---|
| Active thread message body | 12 months | Rolling from message creation; hard erase body after expiry unless a specific legal hold/report applies |
| Closed/left voluntary thread history | 90 days | From thread closure or participant departure; participant loses send immediately, historical read follows approved thread policy |
| Recalled message visible body | Immediate | Replace participant projection with recalled state; keep restricted prior version for 30 days for dispute handling |
| Message edit versions | 30 days | From superseding revision; then erase body and retain only non-reversible integrity hash plus minimal audit metadata |
| Ordinary attachments | Same expiry as owning message | Object and metadata deleted together; a message may not outlive its object-policy reference silently |
| Unfinalized staged upload | 24 hours | From staging; orphan cleanup removes object and metadata |
| Signed download URL | 5 minutes | Never stored as durable message data; regenerate only after current thread access check |
| Push preview/payload | 24 hours | From enqueue; payload contains no attachment URL and minimal text preview, preferably disabled for minors by default |
| Delivery attempt metadata | 30 days | From final attempt; retain channel/state/sanitized code, no raw token, body or provider payload |
| Read marker | Thread/message retention | Monotonic marker; delete no later than the thread data it describes and within 30 days after account erasure completion |
| Mute preference | Active membership + 30 days | Delete after membership/thread lifecycle ends; failure to read preference means muted/fail-closed |
| Operational security audit | 24 months | Minimal actor/action/object/revision/reason; no ordinary message body or attachment copy |
| Deleted-object tombstone | 30 days | Opaque object ID, deletion time and result only; then erase |
| Backup copy | 35 days | Encrypted, access-restricted, not restored selectively; expiry resumes automatically after disaster recovery |

### Legal hold exception

- Hold is a separate case record with purpose, scope, authorized requester,
  start, review date and release decision; it is never a generic permanent flag.
- Access is restricted to designated moderation/legal roles and every access is
  audited. Held material is excluded from ordinary deletion only while the hold
  remains valid.
- Review every 90 days. On release, apply the original expiry immediately plus a
  maximum 30-day deletion window.
- Police preservation or other statutory duties override these product defaults
  only when legal records the authority, scope and required duration.

## Proposed PAR-PRIV-03 safeguarding rules

### Default communication model

- Player-to-player direct messaging is disabled for all players in v1, not only
  users known to be minors.
- Players may use their team chat and contact their own active guardians and
  active team leaders. The same server helper governs discovery, create/add and
  every send.
- Team and leader chats derive participants from current temporal relations.
  Ended relations revoke send access immediately; history follows retention.
- Cross-club discovery and requests are available only to active, verified adult
  leader accounts. “Adult” and verification source must be approved and supplied
  by trusted server data before activation; self-declared client metadata is not
  sufficient.

### Cross-club request

- Directory result exposes display name, club, team and leader function only;
  no email, phone, exact birth date, internal profile ID or roster details.
- First contact is a structured request with an allowlisted reason and optional
  maximum 160-character text. No attachment, link or repeated message is allowed
  before acceptance.
- Limit per requester: 3 requests per 24 hours, 10 per rolling 30 days, at most
  one pending request per requester/target pair. Pending requests expire after
  14 days.
- Target can accept, decline, block or report. Only accept creates an active
  direct thread. Decline reveals no reason to requester.
- Declined/expired request content is erased after 30 days; minimal abuse-rate
  counters are pseudonymized and retained for 90 days.

### Block, report and moderation

- Block takes effect atomically for discovery, new requests, participant add,
  send and notifications in both directions. Unknown/block lookup failure is
  treated as blocked.
- Block remains until the blocker removes it. After removal, retain only a
  pseudonymized abuse-prevention marker for 90 days; never notify the blocked
  person that a block exists.
- Report immediately freezes the reported item from ordinary user mutation,
  captures the minimum necessary immutable evidence and removes direct contact
  pending moderator review. It does not automatically establish wrongdoing.
- Reports have a proposed 12-month review maximum, extendable only by documented
  legal hold or active investigation. Restricted report evidence is erased 30
  days after final resolution when no hold remains.
- Moderators require a distinct `message.moderate` capability, reason codes and
  auditable access. Club leadership alone does not grant global body access.
- UI must provide age-appropriate plain-language block/report help and Swedish
  escalation guidance. Imminent danger is directed to 112; other suspected crime
  to Polisen via 114 14/police station. TeamZone does not promise emergency
  monitoring.

## Technical gates derived from the proposal

1. Messaging, uploads and cross-club requests remain feature-disabled until the
   approval record and DPIA outcome are stored in release evidence.
2. Private Storage bucket only. Object access calls the same active-thread helper
   as message reads; no bucket-wide `authenticated` read policy.
3. Recipient resolution returns opaque choices and create/add/send re-evaluate
   the same helper transactionally. Known foreign UUIDs return `not_found`.
4. Notification preview is minimal and mute lookup is fail-closed.
5. Retention jobs are idempotent, checkpointed and auditable. Object/metadata
   reconciliation treats every orphan or withdrawn-but-readable URL as failure.
6. Realtime carries thread ID and revision invalidation only, never message body,
   report evidence or signed file URL.
7. Backups, exports, support access and incident response must use the same data
   classes; deleting only the primary row is not sufficient compliance.

## Approval record to complete

| Role | Name | Decision/date | Required confirmation |
|---|---|---|---|
| Product owner | Project owner | Approved 2026-08-08 | Product behavior and operational ownership accepted |
| Privacy/data owner | Project owner | Approved 2026-08-08 | Purposes, minimisation, retention and data-subject handling accepted |
| Legal | Project owner | Approved 2026-08-08 | Legal basis, minors, preservation/erasure and notices accepted |
| Security/trust & safety | Project owner | Approved 2026-08-08 | Abuse model, moderation access, escalation and incident controls accepted |
| Technical owner | Project owner | Approved 2026-08-08 | Jobs, Storage, authorization, observability and deletion SLO implementable |

No duration was changed during approval. Any later change requires a new dated
decision and, where risk changes materially, renewed DPIA screening.

## Sources reviewed

- IMY: Grundläggande principer enligt GDPR
  (`https://www.imy.se/verksamhet/dataskydd/det-har-galler-enligt-gdpr/grundlaggande-principer`)
- IMY: Konsekvensbedömning enligt GDPR
  (`https://www.imy.se/verksamhet/dataskydd/det-har-galler-enligt-gdpr/konsekvensbedomning/`)
- IMY: När ska en konsekvensbedömning genomföras?
  (`https://www.imy.se/verksamhet/dataskydd/det-har-galler-enligt-gdpr/konsekvensbedomning/nar-ska-en-konsekvensbedomning-genomforas/`)
- GDPR, articles 5, 25 and 35 via EUR-Lex
  (`https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32016R0679`)
- Polismyndigheten: Sexuella övergrepp mot barn på nätet
  (`https://polisen.se/utsatt-for-brott/polisanmalan/hat-hot-och-vald/sexuella-overgrepp-mot-barn-pa-natet/`)
