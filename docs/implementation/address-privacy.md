# Addresses and restricted personal data

Implemented 2026-10-02. Applies to accounts and their linked club-person records.
An authorized guardian can manage the child's account through the same view.
This is an application privacy setting, not a determination of legal status.

## User flow

Settings → Profile → Addresses and privacy. Select yourself or an account you are
currently authorized to represent. Add named addresses without a primary-address
requirement. Select an address, or no address, separately for each club.
Address labels are private; club readers get only their selected address.

Enable restricted access using a distinct, non-identifying team display name.
Private name and the explicitly chosen safe email/phone are stored outside general
profile and roster columns. The owner/guardian selects individual contacts in each
club who may read the safe contact details and that club's selected address.
Being a leader, club administrator or support administrator is not an automatic
grant to those values. A grant also requires fresh active club and leader rights.
Revoking a guardian relationship or explicit grant takes effect on the next read.

Disabling the setting restores the account name and existing club-record names
captured immediately before activation. Editing the alias/private name while
protected does not replace that snapshot. A new activation captures the current
names again. Older activations use the saved private name as a fallback; earlier
deactivations still showing the alias are repaired when that fallback is available.
Dates, contact values, photos and public consents are not restored. Re-enabling
clears previous contact grants. Sensitive values are
not included in audit metadata or notification payloads.

## Enforcement

- New tables have RLS and no direct client grants. Guarded RPCs use fresh database
  authorization, not client flags or user-editable JWT metadata.
- Existing account addresses migrate into private address rows with the previously
  effective club choices preserved. Club-specific legacy addresses remain separate
  options. New addresses and new clubs have no implicit sharing.
- Profile/club source address columns are cleared. Member contact and member-card
  reads resolve the club selection. Legacy account-address writes are rejected.
- Intake approval creates a new address option and selects it only for the intake's
  source club. Other residences/selections are preserved. Address revisions and
  selections participate in proposal conflict detection. Pre-upgrade proposals may
  require resubmission because their snapshot format predates this model.
- Protection masks structured source names, contacts and birth fields across linked
  records, including ended links and records sharing the canonical person identity.
  Private birth fields are retained in restricted bindings. New links inherit masks.
- Ordinary roster, event, match snapshot, search and member-card reads use the masked
  sources. Protected accounts are excluded from the cross-club directory and cannot
  receive cross-club contact requests through the old endpoint.
- Profile avatars are retired, pending contact proposals are cleared/rejected,
  publication consents are withdrawn and removal jobs queued. New active consents
  are rejected. Normal notification delivery to the protected account is suppressed.
- Intake updates cannot change protected account contacts. Use the private settings.

## Boundaries that require human handling

The system cannot reliably identify a person in historic free text, match notes,
group photos, independently uploaded news/media, screenshots or downloaded exports.
Review those separately before relying on restricted access. Already issued signed
image URLs can remain usable until their expiry (currently up to one hour).
Previously viewed/offline client data cannot be remotely recalled by this setting.

The public intake form is not a secure channel for protected details and says so
before its fields. People without accounts must first arrange a safe contact path;
the account settings do not create a protected identity record for an unrelated,
unlinked roster entry. No claim of automatic legal/GDPR compliance is made.

## Verification

- `supabase/tests/address_privacy.local.mjs`: real migration/functions, multiple
  residences and clubs, old API guards, stale writes, guardian/grant revocation,
  source masking, new/canonical links, consents, notifications, directory exclusion,
  intake approval preserving other addresses and RLS/grant checks.
- 16 profile widget tests pass, including address creation/club selection and
  explicit protection activation/cancellation. Flutter analyze has no issues.
- Public site: 59 tests and TypeScript check pass.
- Flutter release web and Next production builds pass. The final Flutter build
  includes the English strings added after the initial build.
- The migration and an activation/source-redaction check passed against the hosted
  schema inside a transaction that was fully rolled back, with no test data retained.
  A subsequent local check also verifies that explicit contact access stops when
  either the viewer's leader role or the subject's club account link ends.

## Activation status

The owner explicitly approved activation on 2026-10-02. Migration
`20261002120002_address_privacy_controls.sql` is installed in audit project
`hgcshgunvooyudvrcpig`. Hosted verification confirms RLS on all five new tables,
no direct client reads, no anonymous settings access and no legacy contact bypass.
The owner settings RPC also passed a transaction-scoped read check. Security
advisor reports only the existing leaked-password-protection warning and expected
deny-direct-access RLS informational findings.

Both web deployments completed successfully on 2026-10-02: Firebase Hosting
`teamzoneapp-b02a2` and App Hosting `teamzoneapp-public`. The downloaded JavaScript
from `app.teamzoneapp.se` matches the local release build, SHA-256
`46b2b9ac829ac602561a2c2517ffe83ab9f0159171bc93f31d92616815813f41`.
The public custom domain returned HTTP 200 after its completed rollout.
No Android device installation was performed.

Name restoration correction: `20261002120003_restore_name_after_privacy.sql`
installed 2026-10-02. SQL tests include distinct club names, repeated activation,
alias/private-name edits and legacy enabled/disabled profiles. Hosted verification
found no remaining disabled profiles still showing an alias where a saved original
name is available. The settings view refreshes names after a successful change.
The correction's Flutter analyze, profile tests, focused immediate-name-refresh
test and release web build passed. Firebase Hosting publication completed on
2026-10-02; the public Next site did not require another deployment for this fix.
