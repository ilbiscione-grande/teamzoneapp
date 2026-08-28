# X-OPS-01 key rotation runbook

1. Open a separately approved secure change window and name the exact target.
2. Create the replacement credential in the provider; do not revoke the old one.
3. Store it in the target secret manager, never in source, chat, logs or evidence.
4. Deploy/restart only where the provider requires it.
5. Verify signed Auth, Data, Storage, Realtime and Edge traffic on the new key.
6. Observe the agreed compatibility window and check rollback readiness.
7. Revoke the old key, verify again, and record key identifier/fingerprint only.

If verification fails, restore the prior reference and keep the old credential
active. Secret values must never be copied into this runbook or CI output.
