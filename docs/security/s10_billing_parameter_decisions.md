# S10 billing parameter decisions

Approved by product owner: 2026-08-16  
Scope: TeamzoneApp v1, Sweden-first greenfield release

## PAR-BILL-02 – grace, downgrade and reactivation

- Grace lasts 14 days after payment failure or subscription termination.
- During grace, existing premium functionality remains usable, but the club
  cannot add teams or billable people beyond its quota.
- After grace, premium data remains available read-only and for export; all new
  premium writes are denied.
- Downgrade, over-quota state and payment failure never delete club data.
- Unknown, inconsistent or incompletely verified billing state always denies
  premium writes.
- Reactivation restores access to the existing data without reimport.
- Club administrators receive clear warnings throughout grace and read-only
  states.

This decision unlocks the S10A entitlement data specification.

## PAR-BILL-01 – versioned Swedish pricebook

The first version is `se.v1-draft` and is not checkout-eligible.

| Plan | Active teams | Billable people | Monthly | Annual |
|---|---:|---:|---:|---:|
| Free | 1 | 25 | SEK 0 | SEK 0 |
| Small | 3 | 75 | SEK 199 | SEK 1,990 |
| Medium | 10 | 250 | SEK 499 | SEK 4,990 |
| Large | 30 | 750 | SEK 999 | SEK 9,990 |
| Custom/XL | Contract | Contract | Quote | Quote |

- Customer-facing Swedish prices are represented as VAT-inclusive; minor units
  are stored as integers. Tax calculation remains a checkout/provider concern.
- Annual price equals ten monthly prices.
- A person is counted once per club. Active players, leaders and club
  functionaries count; guardians with no other operational role do not.
- Modules are bought once per club and apply to all its teams. Module prices and
  discounts remain absent until each module is release-ready.
- Existing subscriptions keep their pricebook version until an explicit,
  audited migration. Custom/XL can only originate from a server-approved quote.

Approved by product owner: 2026-08-16.

PAR-BILL-01 does not authorize checkout, a payment provider, webhook secrets or
commercial release. PAR-BILL-03 remains required before checkout.

## PAR-BILL-03 – sales channel and payment provider

- Club subscriptions are sold only through an authenticated TeamZone web
  checkout backed by Stripe Checkout.
- Checkout and subscription changes require an explicit club-scoped billing
  capability.
- Android and iOS contain no checkout, purchase button, price list, external
  purchase link or purchase call to action. They may consume an existing club
  entitlement and show neutral copy that billing is managed by a club admin.
- Players and guardians are never offered individual purchases.
- Flutter web may enter checkout only after server-side identity, capability,
  target-club and published-pricebook verification.
- The client never supplies price, product, entitlement or subscription state;
  the server maps a published pricebook offering to provider price references.
- Stripe webhook signatures, event deduplication, provider revision ordering and
  transactional entitlement recompute are mandatory.
- Checkout, webhook secrets and commercial activation require a separate pilot
  release gate. `se.v1-draft` remains non-published.

Approved by product owner: 2026-08-16.
