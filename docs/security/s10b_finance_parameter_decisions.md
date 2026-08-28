# S10B finance parameter decisions

Approved by the product owner on 2026-08-17.

## PAR-FIN-01

TeamZone v1 provides confidential internal cash tracking and export only. It is
not represented as a legal bookkeeping system. No automated deletion or legal
retention claim is introduced before a separate finance/legal verification.

## PAR-FIN-02

Reversals, mandate changes and entries of at least SEK 10,000 require approval
by two different authorized people. The initiator cannot supply either
high-risk approval. Lower-value entries require one explicit economy
capability. All decisions require a reason and immutable audit metadata.

## Still closed

PAR-FIN-03 remains open. No automatic payment confirmation, fee run, reminder
state transition or pledge settlement may be activated.
