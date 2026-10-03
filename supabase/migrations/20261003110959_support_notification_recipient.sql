create table internal.support_notification_recipients (
  email text primary key check (
    email=lower(btrim(email)) and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  ),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id)
);
alter table internal.support_notification_recipients enable row level security;
revoke all on table internal.support_notification_recipients from public,anon,authenticated;

insert into internal.support_notification_recipients(email)
values('support@teamzoneapp.se');

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
  with recipient_rows as (
    select lower(user_row.email)::text email
    from internal.support_admins admin
    join auth.users user_row on user_row.id=admin.profile_id
    where admin.active and user_row.email is not null
    union
    select recipient.email
    from internal.support_notification_recipients recipient
    where recipient.active
  ), recipients as (
    select coalesce(array_agg(recipient_rows.email order by recipient_rows.email),array[]::text[]) emails
    from recipient_rows
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

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261003110959_support_notification_recipient','greenfield',
  'Dedicated support mailbox recipient without requiring a shared application login');

notify pgrst,'reload schema';
