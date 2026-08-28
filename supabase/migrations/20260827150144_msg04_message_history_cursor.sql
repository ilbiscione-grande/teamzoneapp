-- MSG-04 stable revision cursor for gap-free message history.

create or replace function internal.list_messages_for_actor(target_thread_id uuid,before_revision bigint default null,page_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not internal.actor_can_access_thread(target_thread_id,false)
 then raise insufficient_privilege using message='not_found';end if;
 if before_revision is not null and before_revision<1
  or page_limit not between 1 and 100
 then raise invalid_parameter_value using message='invalid_page';end if;
 return(with candidate as(
  select message.id,message.revision,message.state,
   case when message.state='sent' then message.body else null end body,
   message.created_at,profile.display_name sender_name,message.sender_profile_id=auth.uid() mine
  from core.messages message join core.profiles profile on profile.id=message.sender_profile_id
  where message.thread_id=target_thread_id and(before_revision is null or message.revision<before_revision)
  order by message.revision desc,message.id desc limit page_limit+1
 ),page as(select * from candidate order by revision desc,id desc limit page_limit)
 select jsonb_build_object(
  'schema_version',2,
  'thread_id',target_thread_id,
  'messages',coalesce((select jsonb_agg(row_value order by revision,id)from page row_value),'[]'::jsonb),
  'has_more',(select count(*)>page_limit from candidate),
  'next_before_revision',case when(select count(*)>page_limit from candidate)then(select min(revision)from page)end
 ));
end;$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827150144_msg04_message_history_cursor','greenfield','MSG-04 stable revision cursor with explicit continuation');
notify pgrst,'reload schema';
