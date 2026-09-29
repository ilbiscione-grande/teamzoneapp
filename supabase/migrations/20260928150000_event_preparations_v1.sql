-- Förberedelser v1: a small per-event workspace (focus, material, tasks,
-- agenda, one note, files). Not a planning system: no progress, priorities,
-- deadlines or inventory. Items carry `source`/`source_ref` so a future
-- training or match module can contribute entries without replacing them.
-- Writes follow the event manager boundary; reads follow event visibility.
-- Files use a private bucket and per-file visibility enforced by RLS on
-- storage.objects, so knowing an id or object key never grants access.

create table core.event_preparation_items(
 id uuid primary key,
 club_id uuid not null,
 event_id uuid not null,
 kind text not null check(kind in('focus','material','task','agenda')),
 label text not null check(length(btrim(label)) between 1 and 200),
 done boolean not null default false,
 assignee_club_person_id uuid,
 position integer not null default 0,
 source text not null default 'manual' check(source in('manual','module')),
 source_ref text check(source_ref is null or length(source_ref)<=200),
 revision bigint not null default 1 check(revision>0),
 created_at timestamptz not null default now(),
 created_by uuid not null references core.profiles(id),
 updated_at timestamptz not null default now(),
 updated_by uuid not null references core.profiles(id),
 foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade,
 foreign key(assignee_club_person_id,club_id) references core.club_people(id,club_id),
 check(assignee_club_person_id is null or kind='task'),
 check(not done or kind in('material','task','agenda'))
);
create index event_preparation_items_event_idx on core.event_preparation_items(event_id,kind,position,created_at);
create index event_preparation_items_suggest_idx on core.event_preparation_items(club_id,kind,updated_at desc);
create index event_preparation_items_assignee_idx on core.event_preparation_items(assignee_club_person_id);

create table core.event_preparation_notes(
 event_id uuid primary key,
 club_id uuid not null,
 body text not null default '' check(length(body)<=10000),
 revision bigint not null default 1 check(revision>0),
 updated_at timestamptz not null default now(),
 updated_by uuid not null references core.profiles(id),
 foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade
);

create table core.event_files(
 id uuid primary key,
 club_id uuid not null,
 event_id uuid not null,
 owner_profile_id uuid not null references core.profiles(id),
 bucket_id text not null default 'event-files' check(bucket_id='event-files'),
 object_key text not null unique,
 original_name text not null check(length(btrim(original_name)) between 1 and 160),
 mime_type text not null,
 size_bytes bigint not null check(size_bytes between 1 and 20971520),
 visibility text not null default 'participants' check(visibility in('participants','leaders','selected')),
 state text not null default 'staged' check(state in('staged','active','deleted')),
 revision bigint not null default 1 check(revision>0),
 created_at timestamptz not null default now(),
 finalized_at timestamptz,
 deleted_at timestamptz,
 deleted_by uuid references core.profiles(id),
 foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade,
 check((state='active' and finalized_at is not null) or state<>'active'),
 check((state='deleted' and deleted_at is not null) or state<>'deleted')
);
create index event_files_event_idx on core.event_files(event_id,state,created_at);
create index event_files_owner_idx on core.event_files(owner_profile_id);

create table core.event_file_viewers(
 file_id uuid not null references core.event_files(id) on delete cascade,
 club_id uuid not null,
 club_person_id uuid not null,
 primary key(file_id,club_person_id),
 foreign key(club_person_id,club_id) references core.club_people(id,club_id)
);
create index event_file_viewers_person_idx on core.event_file_viewers(club_person_id);

alter table core.event_preparation_items enable row level security;
alter table core.event_preparation_notes enable row level security;
alter table core.event_files enable row level security;
alter table core.event_file_viewers enable row level security;
create policy event_preparation_items_no_direct_access on core.event_preparation_items for all to authenticated using(false) with check(false);
create policy event_preparation_notes_no_direct_access on core.event_preparation_notes for all to authenticated using(false) with check(false);
create policy event_files_no_direct_access on core.event_files for all to authenticated using(false) with check(false);
create policy event_file_viewers_no_direct_access on core.event_file_viewers for all to authenticated using(false) with check(false);
revoke all on core.event_preparation_items,core.event_preparation_notes,core.event_files,core.event_file_viewers from public,anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('event-files','event-files',false,20971520,array[
 'application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv',
 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
 'application/vnd.openxmlformats-officedocument.presentationml.presentation'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Leaders of the event: anyone who may manage it or its roster, plus active
-- leader/functionary assignments on one of the event's teams (a leader
-- without event.manage still sees leader-only files).
create function internal.actor_is_event_leader(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
  internal.actor_can_manage_event(target_event_id)
  or internal.actor_can_manage_event_roster(target_event_id)
  or exists(
   select 1 from core.events event_row
   join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   join core.person_account_links link on link.profile_id=auth.uid() and link.club_id=event_row.club_id and link.state='active'
   join core.assignments assignment on assignment.club_person_id=link.club_person_id and assignment.club_id=link.club_id
    and assignment.team_id=relation.team_id
   where event_row.id=target_event_id and assignment.state='active'
    and assignment.role_package in('leader','club_functionary')
    and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())))
$$;

create function internal.actor_can_edit_event_preparation(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from core.events event_row where event_row.id=target_event_id and event_row.archived_at is null)
  and internal.actor_can_manage_event(target_event_id)
$$;

-- People a task or file can target: the event's own team members, called-up
-- people and people with recorded attendance (walk-ins).
create function internal.event_person_is_relevant(target_event_id uuid,target_person_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from core.events event_row
  join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
  join core.assignments assignment on assignment.team_id=relation.team_id and assignment.club_id=event_row.club_id
  where event_row.id=target_event_id and assignment.club_person_id=target_person_id and assignment.state='active'
   and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now()))
 or exists(select 1 from core.callups callup where callup.event_id=target_event_id
  and callup.club_person_id=target_person_id and callup.state<>'cancelled')
 or exists(select 1 from core.attendance_facts fact where fact.event_id=target_event_id
  and fact.club_person_id=target_person_id)
$$;

create function internal.actor_can_view_event_file(target_file_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from core.event_files file
  where file.id=target_file_id and file.state='active'
   and internal.actor_can_read_event(file.event_id)
   and (internal.actor_is_event_leader(file.event_id)
    or file.visibility='participants'
    or (file.visibility='selected' and exists(
     select 1 from core.event_file_viewers viewer where viewer.file_id=file.id and (
      internal.actor_owns_club_person(file.club_id,viewer.club_person_id)
      or exists(
       select 1 from core.guardian_relations relation
       join core.person_account_links link on link.club_person_id=relation.guardian_person_id
        and link.club_id=relation.club_id and link.profile_id=auth.uid() and link.state='active'
       where relation.club_id=file.club_id and relation.child_person_id=viewer.club_person_id
        and relation.state='active' and relation.starts_at<=now()
        and (relation.ends_at is null or relation.ends_at>now())))))))
$$;

create function internal.actor_can_read_event_file_object(target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select target_bucket='event-files' and exists(
  select 1 from core.event_files file where file.bucket_id=target_bucket and file.object_key=target_key
   and internal.actor_can_view_event_file(file.id))
$$;

create function internal.actor_can_upload_event_file_object(target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select target_bucket='event-files' and exists(
  select 1 from core.event_files file where file.bucket_id=target_bucket and file.object_key=target_key
   and file.owner_profile_id=auth.uid() and file.state='staged'
   and internal.actor_can_edit_event_preparation(file.event_id))
$$;

create function internal.actor_can_delete_event_file_object(target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path='' as $$
 select target_bucket='event-files' and exists(
  select 1 from core.event_files file where file.bucket_id=target_bucket and file.object_key=target_key
   and file.state in('staged','deleted') and internal.actor_can_manage_event(file.event_id))
$$;

create policy event_files_insert on storage.objects for insert to authenticated with check(
 bucket_id='event-files' and owner_id=(select auth.uid()::text)
 and internal.actor_can_upload_event_file_object(bucket_id,name));
create policy event_files_select on storage.objects for select to authenticated using(
 bucket_id='event-files' and internal.actor_can_read_event_file_object(bucket_id,name));
create policy event_files_delete on storage.objects for delete to authenticated using(
 bucket_id='event-files' and internal.actor_can_delete_event_file_object(bucket_id,name));

create function internal.event_preparation_item_json(item core.event_preparation_items)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',item.id,'kind',item.kind,'label',item.label,'done',item.done,
  'assignee_person_id',item.assignee_club_person_id,
  'assignee_name',(select person.display_name from core.club_people person where person.id=item.assignee_club_person_id),
  'position',item.position,'source',item.source,'source_ref',item.source_ref,
  'revision',item.revision,'updated_at',item.updated_at)
$$;

create function internal.event_file_json(file core.event_files,include_viewers boolean)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',file.id,'name',file.original_name,'mime_type',file.mime_type,
  'size_bytes',file.size_bytes,'visibility',file.visibility,'revision',file.revision,
  'created_at',file.created_at,'uploaded_by',file.owner_profile_id,
  'viewer_count',(select count(*) from core.event_file_viewers viewer where viewer.file_id=file.id),
  'viewer_ids',case when include_viewers then coalesce((select jsonb_agg(viewer.club_person_id order by viewer.club_person_id)
   from core.event_file_viewers viewer where viewer.file_id=file.id),'[]'::jsonb) else '[]'::jsonb end)
$$;

create function internal.get_event_preparation_for_actor(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare can_edit boolean; leader boolean; note_row core.event_preparation_notes%rowtype;
begin
 if auth.uid() is null or not internal.actor_can_read_event(p_event_id) then
  raise insufficient_privilege using message='not_found'; end if;
 can_edit:=internal.actor_can_edit_event_preparation(p_event_id);
 leader:=internal.actor_is_event_leader(p_event_id);
 select * into note_row from core.event_preparation_notes where event_id=p_event_id;
 return jsonb_build_object('event_id',p_event_id,'can_edit',can_edit,
  'items',coalesce((select jsonb_agg(internal.event_preparation_item_json(item) order by item.kind,item.position,item.created_at,item.id)
   from core.event_preparation_items item where item.event_id=p_event_id),'[]'::jsonb),
  'note',jsonb_build_object('body',coalesce(note_row.body,''),'revision',coalesce(note_row.revision,0),'updated_at',note_row.updated_at),
  'files',coalesce((select jsonb_agg(internal.event_file_json(file,leader) order by file.created_at,file.id)
   from core.event_files file where file.event_id=p_event_id and file.state='active'
    and internal.actor_can_view_event_file(file.id)),'[]'::jsonb));
end$$;

create function internal.assert_event_preparation_editor(p_event_id uuid)
returns core.events language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype;
begin
 select * into event_row from core.events where id=p_event_id;
 if auth.uid() is null or event_row.id is null or not internal.actor_can_edit_event_preparation(p_event_id) then
  raise insufficient_privilege using message='not_found'; end if;
 perform pg_advisory_xact_lock(hashtextextended('event_preparation:'||p_event_id::text,0));
 return event_row;
end$$;

create function internal.save_event_preparation_item_for_actor(p_event_id uuid,p_item_id uuid,p_kind text,
 p_label text,p_assignee_person_id uuid,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype; item core.event_preparation_items%rowtype; clean text:=btrim(coalesce(p_label,''));
begin
 event_row:=internal.assert_event_preparation_editor(p_event_id);
 if p_item_id is null or p_expected_revision is null or p_kind not in('focus','material','task','agenda')
  or length(clean) not between 1 and 200 or (p_assignee_person_id is not null and p_kind<>'task') then
  raise invalid_parameter_value using message='invalid_item'; end if;
 select * into item from core.event_preparation_items where id=p_item_id for update;
 if item.id is not null and (item.event_id<>p_event_id or item.kind<>p_kind) then
  raise invalid_parameter_value using message='invalid_item'; end if;
 -- The requested content is already stored: a retry or a concurrent
 -- identical edit. Return it instead of reporting a conflict.
 if item.id is not null and item.label=clean and item.assignee_club_person_id is not distinct from p_assignee_person_id then
  return internal.event_preparation_item_json(item); end if;
 if p_assignee_person_id is not null and not internal.event_person_is_relevant(p_event_id,p_assignee_person_id) then
  raise invalid_parameter_value using message='invalid_assignee'; end if;
 if item.id is null then
  if p_expected_revision<>0 then raise serialization_failure using message='stale_revision'; end if;
  if (select count(*) from core.event_preparation_items where event_id=p_event_id)>=300 then
   raise check_violation using message='too_many_items'; end if;
  insert into core.event_preparation_items(id,club_id,event_id,kind,label,assignee_club_person_id,position,created_by,updated_by)
  values(p_item_id,event_row.club_id,p_event_id,p_kind,clean,p_assignee_person_id,
   coalesce((select max(position)+1 from core.event_preparation_items where event_id=p_event_id and kind=p_kind),0),auth.uid(),auth.uid())
  returning * into item;
 else
  if item.revision<>p_expected_revision then raise serialization_failure using message='stale_revision'; end if;
  update core.event_preparation_items set label=clean,assignee_club_person_id=p_assignee_person_id,
   revision=revision+1,updated_at=now(),updated_by=auth.uid() where id=p_item_id returning * into item;
 end if;
 return internal.event_preparation_item_json(item);
end$$;

-- Checking is target-state idempotent: two leaders ticking the same box both
-- succeed and neither undoes the other.
create function internal.set_event_preparation_item_done_for_actor(p_item_id uuid,p_done boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item core.event_preparation_items%rowtype; target_event uuid;
begin
 select event_id into target_event from core.event_preparation_items where id=p_item_id;
 if target_event is null then raise insufficient_privilege using message='not_found'; end if;
 perform internal.assert_event_preparation_editor(target_event);
 select * into item from core.event_preparation_items where id=p_item_id for update;
 if p_done is null or item.kind='focus' then raise invalid_parameter_value using message='invalid_item'; end if;
 if item.done<>p_done then
  update core.event_preparation_items set done=p_done,revision=revision+1,updated_at=now(),updated_by=auth.uid()
  where id=p_item_id returning * into item;
 end if;
 return internal.event_preparation_item_json(item);
end$$;

create function internal.delete_event_preparation_item_for_actor(p_event_id uuid,p_item_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform internal.assert_event_preparation_editor(p_event_id);
 delete from core.event_preparation_items where id=p_item_id and event_id=p_event_id;
end$$;

create function internal.reorder_event_preparation_items_for_actor(p_event_id uuid,p_kind text,p_item_ids uuid[])
returns void language plpgsql security definer set search_path='' as $$
begin
 perform internal.assert_event_preparation_editor(p_event_id);
 if p_item_ids is null or cardinality(p_item_ids)>300 or array_position(p_item_ids,null) is not null
  or (select count(distinct value) from unnest(p_item_ids) value)<>cardinality(p_item_ids)
  or exists(select 1 from unnest(p_item_ids) value where not exists(
   select 1 from core.event_preparation_items item where item.id=value and item.event_id=p_event_id and item.kind=p_kind)) then
  raise invalid_parameter_value using message='invalid_order'; end if;
 update core.event_preparation_items item set position=ordered.ordinality-1,revision=revision+1,updated_at=now(),updated_by=auth.uid()
 from unnest(p_item_ids) with ordinality ordered(id,ordinality)
 where item.id=ordered.id and item.position<>ordered.ordinality-1;
 -- Items created concurrently and missing from the list keep their relative order after it.
 update core.event_preparation_items item set position=cardinality(p_item_ids)+ranked.rank
 from(select id,row_number() over(order by position,created_at,id) rank from core.event_preparation_items
  where event_id=p_event_id and kind=p_kind and not(id=any(p_item_ids))) ranked
 where item.id=ranked.id;
end$$;

create function internal.save_event_preparation_note_for_actor(p_event_id uuid,p_body text,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype; note_row core.event_preparation_notes%rowtype; clean text:=coalesce(p_body,'');
begin
 event_row:=internal.assert_event_preparation_editor(p_event_id);
 if length(clean)>10000 or p_expected_revision is null then raise invalid_parameter_value using message='invalid_note'; end if;
 select * into note_row from core.event_preparation_notes where event_id=p_event_id for update;
 if note_row.event_id is not null and note_row.body=clean then
  return jsonb_build_object('body',note_row.body,'revision',note_row.revision,'updated_at',note_row.updated_at); end if;
 if coalesce(note_row.revision,0)<>p_expected_revision then raise serialization_failure using message='stale_revision'; end if;
 insert into core.event_preparation_notes(event_id,club_id,body,updated_by) values(p_event_id,event_row.club_id,clean,auth.uid())
 on conflict(event_id) do update set body=excluded.body,revision=core.event_preparation_notes.revision+1,
  updated_at=now(),updated_by=excluded.updated_by
 returning * into note_row;
 return jsonb_build_object('body',note_row.body,'revision',note_row.revision,'updated_at',note_row.updated_at);
end$$;

-- "Tidigare använda": labels this team used before for the same kind, most
-- recent first. Reuses existing entries instead of a separate library.
create function internal.list_event_preparation_suggestions_for_actor(p_event_id uuid,p_kind text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;
begin
 select * into event_row from core.events where id=p_event_id;
 if event_row.id is null or not internal.actor_can_edit_event_preparation(p_event_id) or p_kind not in('focus','material') then
  raise insufficient_privilege using message='not_found'; end if;
 return coalesce((select jsonb_agg(label order by last_used desc) from(
  select min(item.label) label,max(item.updated_at) last_used from core.event_preparation_items item
  join core.events other on other.id=item.event_id and other.club_id=item.club_id
  where item.club_id=event_row.club_id and other.owning_team_id=event_row.owning_team_id and item.kind=p_kind
  group by lower(item.label) order by max(item.updated_at) desc limit 16) recent),'[]'::jsonb);
end$$;

create function internal.assert_event_file_viewers(p_event_id uuid,p_visibility text,p_person_ids uuid[])
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if p_visibility not in('participants','leaders','selected') then raise invalid_parameter_value using message='invalid_visibility'; end if;
 if p_visibility='selected' and (p_person_ids is null or cardinality(p_person_ids) not between 1 and 200
  or array_position(p_person_ids,null) is not null) then raise invalid_parameter_value using message='invalid_visibility'; end if;
 if p_visibility='selected' and exists(select 1 from unnest(p_person_ids) value
  where not internal.event_person_is_relevant(p_event_id,value)) then
  raise invalid_parameter_value using message='invalid_visibility'; end if;
end$$;

create function internal.replace_event_file_viewers(p_file_id uuid,p_club_id uuid,p_visibility text,p_person_ids uuid[])
returns void language plpgsql security definer set search_path='' as $$
begin
 delete from core.event_file_viewers where file_id=p_file_id;
 if p_visibility='selected' then
  insert into core.event_file_viewers(file_id,club_id,club_person_id)
  select distinct p_file_id,p_club_id,value from unnest(p_person_ids) value;
 end if;
end$$;

create function internal.stage_event_file_for_actor(p_event_id uuid,p_file_id uuid,p_file_name text,p_mime_type text,
 p_size_bytes bigint,p_visibility text,p_person_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype; file core.event_files%rowtype; clean text:=btrim(coalesce(p_file_name,''));
begin
 event_row:=internal.assert_event_preparation_editor(p_event_id);
 select * into file from core.event_files where id=p_file_id;
 if file.id is not null then
  if file.event_id<>p_event_id or file.owner_profile_id<>auth.uid() or file.original_name<>clean or file.size_bytes<>p_size_bytes then
   raise unique_violation using message='file_id_reused'; end if;
  return jsonb_build_object('file_id',file.id,'bucket_id',file.bucket_id,'object_key',file.object_key,'state',file.state);
 end if;
 if p_file_id is null or length(clean) not between 1 and 160 or p_size_bytes not between 1 and 20971520
  or p_mime_type not in('application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv',
   'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
   'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
   'application/vnd.openxmlformats-officedocument.presentationml.presentation') then
  raise invalid_parameter_value using message='invalid_file'; end if;
 perform internal.assert_event_file_viewers(p_event_id,p_visibility,p_person_ids);
 if (select count(*) from core.event_files where event_id=p_event_id and state<>'deleted')>=50 then
  raise check_violation using message='too_many_files'; end if;
 insert into core.event_files(id,club_id,event_id,owner_profile_id,object_key,original_name,mime_type,size_bytes,visibility)
 values(p_file_id,event_row.club_id,p_event_id,auth.uid(),
  event_row.club_id::text||'/'||p_event_id::text||'/'||p_file_id::text,clean,p_mime_type,p_size_bytes,p_visibility)
 returning * into file;
 perform internal.replace_event_file_viewers(file.id,file.club_id,p_visibility,p_person_ids);
 return jsonb_build_object('file_id',file.id,'bucket_id',file.bucket_id,'object_key',file.object_key,'state',file.state);
end$$;

create function internal.finalize_event_file_for_actor(p_file_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare file core.event_files%rowtype;
begin
 select * into file from core.event_files where id=p_file_id;
 if file.id is null or file.owner_profile_id<>auth.uid() then raise insufficient_privilege using message='not_found'; end if;
 perform internal.assert_event_preparation_editor(file.event_id);
 select * into file from core.event_files where id=p_file_id for update;
 if file.state='staged' then
  if not exists(select 1 from storage.objects object where object.bucket_id=file.bucket_id and object.name=file.object_key
   and (object.metadata->>'size')::bigint=file.size_bytes) then
   raise invalid_parameter_value using message='upload_missing'; end if;
  update core.event_files set state='active',finalized_at=now(),revision=revision+1 where id=p_file_id returning * into file;
 elsif file.state<>'active' then raise invalid_parameter_value using message='invalid_file'; end if;
 return internal.event_file_json(file,true);
end$$;

create function internal.set_event_file_visibility_for_actor(p_file_id uuid,p_visibility text,p_person_ids uuid[],p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare file core.event_files%rowtype; current_ids uuid[];
begin
 select * into file from core.event_files where id=p_file_id;
 if file.id is null then raise insufficient_privilege using message='not_found'; end if;
 perform internal.assert_event_preparation_editor(file.event_id);
 select * into file from core.event_files where id=p_file_id for update;
 if file.state<>'active' then raise insufficient_privilege using message='not_found'; end if;
 perform internal.assert_event_file_viewers(file.event_id,p_visibility,p_person_ids);
 select coalesce(array_agg(club_person_id order by club_person_id),'{}') into current_ids from core.event_file_viewers where file_id=p_file_id;
 if file.visibility=p_visibility and (p_visibility<>'selected' or current_ids=(
  select array_agg(distinct value order by value) from unnest(p_person_ids) value)) then
  return internal.event_file_json(file,true); end if;
 if file.revision<>p_expected_revision then raise serialization_failure using message='stale_revision'; end if;
 update core.event_files set visibility=p_visibility,revision=revision+1 where id=p_file_id returning * into file;
 perform internal.replace_event_file_viewers(file.id,file.club_id,p_visibility,p_person_ids);
 return internal.event_file_json(file,true);
end$$;

create function internal.delete_event_file_for_actor(p_file_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare file core.event_files%rowtype;
begin
 select * into file from core.event_files where id=p_file_id;
 if file.id is null then raise insufficient_privilege using message='not_found'; end if;
 perform internal.assert_event_preparation_editor(file.event_id);
 update core.event_files set state='deleted',deleted_at=coalesce(deleted_at,now()),deleted_by=coalesce(deleted_by,auth.uid()),
  revision=case when state='deleted' then revision else revision+1 end
 where id=p_file_id returning * into file;
 return jsonb_build_object('bucket_id',file.bucket_id,'object_key',file.object_key);
end$$;

-- Short-lived download authorization; storage RLS re-checks the same rule
-- when the signed URL is created.
create function internal.authorize_event_file_for_actor(p_file_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare file core.event_files%rowtype;
begin
 if not internal.actor_can_view_event_file(p_file_id) then raise insufficient_privilege using message='not_found'; end if;
 select * into file from core.event_files where id=p_file_id;
 return jsonb_build_object('bucket_id',file.bucket_id,'object_key',file.object_key,'expires_in_seconds',120,
  'name',file.original_name,'mime_type',file.mime_type);
end$$;

create function api.get_event_preparation(p_event_id uuid) returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_event_preparation_for_actor(p_event_id)$$;
create function api.save_event_preparation_item(p_event_id uuid,p_item_id uuid,p_kind text,p_label text,p_assignee_person_id uuid,p_expected_revision bigint)
returns jsonb language sql security invoker set search_path='' as
$$select internal.save_event_preparation_item_for_actor(p_event_id,p_item_id,p_kind,p_label,p_assignee_person_id,p_expected_revision)$$;
create function api.set_event_preparation_item_done(p_item_id uuid,p_done boolean) returns jsonb language sql security invoker set search_path='' as
$$select internal.set_event_preparation_item_done_for_actor(p_item_id,p_done)$$;
create function api.delete_event_preparation_item(p_event_id uuid,p_item_id uuid) returns void language sql security invoker set search_path='' as
$$select internal.delete_event_preparation_item_for_actor(p_event_id,p_item_id)$$;
create function api.reorder_event_preparation_items(p_event_id uuid,p_kind text,p_item_ids uuid[]) returns void language sql security invoker set search_path='' as
$$select internal.reorder_event_preparation_items_for_actor(p_event_id,p_kind,p_item_ids)$$;
create function api.save_event_preparation_note(p_event_id uuid,p_body text,p_expected_revision bigint) returns jsonb language sql security invoker set search_path='' as
$$select internal.save_event_preparation_note_for_actor(p_event_id,p_body,p_expected_revision)$$;
create function api.list_event_preparation_suggestions(p_event_id uuid,p_kind text) returns jsonb language sql stable security invoker set search_path='' as
$$select internal.list_event_preparation_suggestions_for_actor(p_event_id,p_kind)$$;
create function api.stage_event_file(p_event_id uuid,p_file_id uuid,p_file_name text,p_mime_type text,p_size_bytes bigint,p_visibility text,p_person_ids uuid[])
returns jsonb language sql security invoker set search_path='' as
$$select internal.stage_event_file_for_actor(p_event_id,p_file_id,p_file_name,p_mime_type,p_size_bytes,p_visibility,p_person_ids)$$;
create function api.finalize_event_file(p_file_id uuid) returns jsonb language sql security invoker set search_path='' as
$$select internal.finalize_event_file_for_actor(p_file_id)$$;
create function api.set_event_file_visibility(p_file_id uuid,p_visibility text,p_person_ids uuid[],p_expected_revision bigint)
returns jsonb language sql security invoker set search_path='' as
$$select internal.set_event_file_visibility_for_actor(p_file_id,p_visibility,p_person_ids,p_expected_revision)$$;
create function api.delete_event_file(p_file_id uuid) returns jsonb language sql security invoker set search_path='' as
$$select internal.delete_event_file_for_actor(p_file_id)$$;
create function api.authorize_event_file(p_file_id uuid) returns jsonb language sql stable security invoker set search_path='' as
$$select internal.authorize_event_file_for_actor(p_file_id)$$;

-- Multi-user freshness: invalidate-only broadcasts (no payload data) on a
-- private per-event topic, readable by whoever may read the event. Clients
-- refetch the authorized projection, as the calendar and inbox already do.
create function internal.broadcast_event_live_invalidation()
returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid:=coalesce(new.event_id,old.event_id);
begin
 perform realtime.send(jsonb_build_object('event_id',target),'invalidate','event:live:'||target::text,true);
 return null;
end$$;
create trigger event_preparation_items_live after insert or update or delete on core.event_preparation_items
for each row execute function internal.broadcast_event_live_invalidation();
create trigger event_preparation_notes_live after insert or update or delete on core.event_preparation_notes
for each row execute function internal.broadcast_event_live_invalidation();
create trigger event_files_live after insert or update or delete on core.event_files
for each row execute function internal.broadcast_event_live_invalidation();

create function internal.actor_can_subscribe_event_live_topic(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and internal.actor_can_read_event(target_event_id)
$$;
create policy teamzone_event_live_broadcast_select on realtime.messages for select to authenticated using(
 realtime.messages.extension='broadcast' and (select realtime.topic()) ~ '^event:live:[0-9a-fA-F-]{36}$'
 and internal.actor_can_subscribe_event_live_topic(substring((select realtime.topic()) from '^event:live:([0-9a-fA-F-]{36})$')::uuid));

revoke all on function internal.actor_is_event_leader(uuid),internal.actor_can_edit_event_preparation(uuid),
 internal.event_person_is_relevant(uuid,uuid),internal.actor_can_view_event_file(uuid),
 internal.actor_can_read_event_file_object(text,text),internal.actor_can_upload_event_file_object(text,text),
 internal.actor_can_delete_event_file_object(text,text),internal.event_preparation_item_json(core.event_preparation_items),
 internal.event_file_json(core.event_files,boolean),internal.get_event_preparation_for_actor(uuid),
 internal.assert_event_preparation_editor(uuid),
 internal.save_event_preparation_item_for_actor(uuid,uuid,text,text,uuid,bigint),
 internal.set_event_preparation_item_done_for_actor(uuid,boolean),internal.delete_event_preparation_item_for_actor(uuid,uuid),
 internal.reorder_event_preparation_items_for_actor(uuid,text,uuid[]),internal.save_event_preparation_note_for_actor(uuid,text,bigint),
 internal.list_event_preparation_suggestions_for_actor(uuid,text),internal.assert_event_file_viewers(uuid,text,uuid[]),
 internal.replace_event_file_viewers(uuid,uuid,text,uuid[]),
 internal.stage_event_file_for_actor(uuid,uuid,text,text,bigint,text,uuid[]),internal.finalize_event_file_for_actor(uuid),
 internal.set_event_file_visibility_for_actor(uuid,text,uuid[],bigint),internal.delete_event_file_for_actor(uuid),
 internal.authorize_event_file_for_actor(uuid),internal.broadcast_event_live_invalidation(),
 internal.actor_can_subscribe_event_live_topic(uuid) from public,anon,authenticated;
-- Storage and realtime policies evaluate these as the calling user.
grant execute on function internal.actor_can_read_event_file_object(text,text),internal.actor_can_upload_event_file_object(text,text),
 internal.actor_can_delete_event_file_object(text,text),internal.actor_can_subscribe_event_live_topic(uuid) to authenticated;
grant execute on function internal.get_event_preparation_for_actor(uuid),
 internal.save_event_preparation_item_for_actor(uuid,uuid,text,text,uuid,bigint),
 internal.set_event_preparation_item_done_for_actor(uuid,boolean),internal.delete_event_preparation_item_for_actor(uuid,uuid),
 internal.reorder_event_preparation_items_for_actor(uuid,text,uuid[]),internal.save_event_preparation_note_for_actor(uuid,text,bigint),
 internal.list_event_preparation_suggestions_for_actor(uuid,text),
 internal.stage_event_file_for_actor(uuid,uuid,text,text,bigint,text,uuid[]),internal.finalize_event_file_for_actor(uuid),
 internal.set_event_file_visibility_for_actor(uuid,text,uuid[],bigint),internal.delete_event_file_for_actor(uuid),
 internal.authorize_event_file_for_actor(uuid) to authenticated;
revoke all on function api.get_event_preparation(uuid),api.save_event_preparation_item(uuid,uuid,text,text,uuid,bigint),
 api.set_event_preparation_item_done(uuid,boolean),api.delete_event_preparation_item(uuid,uuid),
 api.reorder_event_preparation_items(uuid,text,uuid[]),api.save_event_preparation_note(uuid,text,bigint),
 api.list_event_preparation_suggestions(uuid,text),api.stage_event_file(uuid,uuid,text,text,bigint,text,uuid[]),
 api.finalize_event_file(uuid),api.set_event_file_visibility(uuid,text,uuid[],bigint),api.delete_event_file(uuid),
 api.authorize_event_file(uuid) from public,anon;
grant execute on function api.get_event_preparation(uuid),api.save_event_preparation_item(uuid,uuid,text,text,uuid,bigint),
 api.set_event_preparation_item_done(uuid,boolean),api.delete_event_preparation_item(uuid,uuid),
 api.reorder_event_preparation_items(uuid,text,uuid[]),api.save_event_preparation_note(uuid,text,bigint),
 api.list_event_preparation_suggestions(uuid,text),api.stage_event_file(uuid,uuid,text,text,bigint,text,uuid[]),
 api.finalize_event_file(uuid),api.set_event_file_visibility(uuid,text,uuid[],bigint),api.delete_event_file(uuid),
 api.authorize_event_file(uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260928150000_event_preparations_v1','greenfield','Förberedelser v1: items, note, files with per-file visibility');
notify pgrst,'reload schema';
