-- The reviewed terms and privacy policy. Everyone accepts them anew at their
-- next sign-in. Run when the public site shows these texts.
update internal.legal_document_versions
set active = false
where active and document_type in ('terms', 'privacy');

insert into internal.legal_document_versions (
  document_type, version, public_url, material_change, active, published_at
) values
  ('terms', '2026-11-06', 'https://public.teamzoneapp.se/villkor', true, true, now()),
  ('privacy', '2026-11-06', 'https://public.teamzoneapp.se/integritet', true, true, now());
