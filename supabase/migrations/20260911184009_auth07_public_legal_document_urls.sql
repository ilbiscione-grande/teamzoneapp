-- AUTH-07 routes the currently accepted legal document versions to the
-- dedicated public pages. The version deliberately remains unchanged: these
-- pages are clearly marked placeholder drafts and do not constitute a new
-- material legal version.

update internal.legal_document_versions
set public_url = case document_type
  when 'terms' then 'https://public.teamzoneapp.se/villkor'
  when 'privacy' then 'https://public.teamzoneapp.se/integritet'
end
where version = '2026-08-24'
  and active
  and document_type in ('terms', 'privacy');

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
)
values(
  '20260911184009_auth07_public_legal_document_urls',
  'greenfield',
  'AUTH-07 public placeholder routes without changing the accepted legal version'
);
