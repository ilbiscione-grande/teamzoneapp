-- A generic trigger must not bind a column that is absent from one of its
-- source tables. JSON projection safely defaults the login-email case to 1.
create or replace function internal.enqueue_support_email()
returns trigger language plpgsql security definer set search_path=''
as $$
declare next_type text; next_revision bigint;
begin
  next_type:=case tg_table_name
    when 'club_verification_requests' then 'club_verification'
    when 'protected_name_support_cases' then 'protected_name'
    when 'login_email_change_requests' then 'login_email_change'
    when 'global_person_erasure_requests' then 'person_erasure'
  end;
  next_revision:=coalesce((to_jsonb(new)->>'revision')::bigint,1);
  insert into internal.support_email_outbox(case_type,case_id,case_revision)
  values(next_type,new.id,next_revision)
  on conflict(case_type,case_id,case_revision) do nothing;
  return new;
end
$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261003101010_support_email_trigger_revision_fix','greenfield',
  'Generic support email trigger safely supports request tables without a revision column');
