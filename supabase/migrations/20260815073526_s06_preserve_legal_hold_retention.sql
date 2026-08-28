-- Legal hold must suspend both content retention and attachment cleanup.
create or replace function internal.claim_expired_message_files(batch_size integer default 100)
returns table(id uuid,bucket_id text,object_key text)
language plpgsql
security definer
set search_path=''
as $$
begin
  return query
  with claimed as (
    select file.id
    from core.file_objects file
    join core.message_threads thread on thread.id = file.thread_id
    where file.state in ('staged','active','withdrawn')
      and file.expires_at <= now()
      and thread.state <> 'legal_hold'
    order by file.expires_at,file.id
    for update of file skip locked
    limit greatest(1,least(batch_size,500))
  )
  update core.file_objects file
  set state='deleting',revision=revision+1
  from claimed
  where file.id=claimed.id
  returning file.id,file.bucket_id,file.object_key;
end;
$$;

create or replace function internal.apply_message_retention(batch_size integer default 500)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare version_count integer; message_count integer;
begin
  with target as (
    select version.id
    from audit.message_versions version
    join core.message_threads thread on thread.id=version.thread_id
    where version.body_snapshot is not null
      and version.erase_body_at<=now()
      and thread.state<>'legal_hold'
    order by version.erase_body_at
    limit greatest(1,least(batch_size,1000))
    for update of version skip locked
  )
  update audit.message_versions version
  set body_snapshot=null
  from target
  where version.id=target.id;
  get diagnostics version_count=row_count;

  with target as (
    select message.id
    from core.messages message
    join core.message_threads thread on thread.id=message.thread_id
    where message.expires_at<=now()
      and message.state<>'moderated'
      and thread.state<>'legal_hold'
    order by message.expires_at
    limit greatest(1,least(batch_size,1000))
    for update of message skip locked
  )
  update core.messages message
  set body='[expired]',state='moderated',revision=revision+1
  from target
  where message.id=target.id;
  get diagnostics message_count=row_count;

  return jsonb_build_object('versions_erased',version_count,'messages_erased',message_count);
end;
$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815073526_s06_preserve_legal_hold_retention','greenfield',null);
