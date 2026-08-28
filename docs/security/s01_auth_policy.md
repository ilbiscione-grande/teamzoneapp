# S01 hosted Auth policy

Decision date: 2026-08-07

Scope: greenfield Supabase project `TeamzoneApp`. This policy does not authorize
or describe any change to Teamzone6.

## Password baseline

- Email confirmation remains required before first sign-in.
- Minimum password length is 12 characters.
- Lowercase, uppercase, digit and symbol are all required.
- Password changes require both a recently created session and the current
  password.
- Supabase leaked-password protection is required before production use. It is
  unavailable on the current Free audit project because Supabase limits that
  control to Pro and above.
- The public signup endpoint was verified to reject a weak password with
  `weak_password` and HTTP 422. Supabase Admin user creation intentionally
  bypasses end-user password policy and is not a valid policy test surface.

## MFA and step-up

- TOTP MFA is enabled as an available factor.
- Supabase Enhanced MFA Security remains enabled: a user who has enrolled a
  factor must reach AAL2 within 15 minutes of initial sign-in.
- S01 does not require every ordinary user to enroll MFA.
- Future super-admin, billing, economy, key-management and other high-risk
  commands must require a fresh AAL2 session in their server-side command
  authorization. A client-only MFA check is insufficient.
- No authorization or step-up decision may use `user_metadata`. Actor identity
  comes from the verified session and domain authorization comes from server
  assignments/capabilities.

## Release gate

Production Auth release is blocked until leaked-password protection is enabled
on a supporting plan and the first high-risk command slice defines its exact
AAL2 freshness/recovery contract.
