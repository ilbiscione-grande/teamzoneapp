-- Queue support cases that were already open when the email outbox was added.
insert into internal.support_email_outbox(case_type,case_id,case_revision)
select 'club_verification',request.id,request.revision
from core.club_verification_requests request where request.status='pending'
on conflict(case_type,case_id,case_revision) do nothing;

insert into internal.support_email_outbox(case_type,case_id,case_revision)
select 'protected_name',support_case.id,support_case.revision
from internal.protected_name_support_cases support_case
where support_case.status in ('pending','in_review')
on conflict(case_type,case_id,case_revision) do nothing;

insert into internal.support_email_outbox(case_type,case_id,case_revision)
select 'login_email_change',request.id,1
from core.login_email_change_requests request where request.state='pending'
on conflict(case_type,case_id,case_revision) do nothing;

insert into internal.support_email_outbox(case_type,case_id,case_revision)
select 'person_erasure',request.id,request.revision
from internal.global_person_erasure_requests request where request.state='requested'
on conflict(case_type,case_id,case_revision) do nothing;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261003100000_support_email_open_case_backfill','greenfield',
  'One-time queueing of support cases open before support email notifications');
