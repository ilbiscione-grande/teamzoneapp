create or replace function internal.claim_support_email_batch(batch_size integer default 20)
returns table(
  outbox_id uuid,case_type text,case_id uuid,attempt_count integer,
  received_at timestamptz,recipient_emails text[]
)
language plpgsql security definer set search_path=''
as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise insufficient_privilege using message='service_role_required';
  end if;
  return query
  with recipients as (
    select coalesce(
      array_agg(recipient.email order by recipient.email),
      array[]::text[]
    ) emails
    from internal.support_notification_recipients recipient
    where recipient.active
  ), claimed as (
    select queue.id from internal.support_email_outbox queue
    where queue.state in ('pending','failed') and queue.available_at<=now()
      and queue.attempt_count<5
    order by queue.created_at,queue.id
    for update skip locked limit greatest(1,least(batch_size,100))
  ), updated as (
    update internal.support_email_outbox queue set
      state='processing',attempt_count=queue.attempt_count+1,updated_at=now()
    from claimed where queue.id=claimed.id
    returning queue.id,queue.case_type,queue.case_id,queue.attempt_count,queue.created_at
  )
  select updated.id,updated.case_type,updated.case_id,updated.attempt_count,
    updated.created_at,recipients.emails
  from updated cross join recipients;
end
$$;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
)
values(
  '20261003135312_restrict_support_email_to_notification_recipients',
  'greenfield',
  'Support email recipients come only from the dedicated notification recipient registry'
);

notify pgrst,'reload schema';
