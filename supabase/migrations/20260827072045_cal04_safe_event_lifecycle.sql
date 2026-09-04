alter table core.events add column if not exists archived_at timestamptz;
alter table core.events add column if not exists archived_by uuid references core.profiles(id);
alter table core.events add column if not exists archive_reason text;
do $$
begin
 if not exists(select 1 from pg_constraint where conname='events_archive_shape_check') then
  alter table core.events add constraint events_archive_shape_check check(
   (archived_at is null and archived_by is null and archive_reason is null)
   or(archived_at is not null and archived_by is not null
    and length(btrim(archive_reason)) between 3 and 500)
  );
 end if;
end $$;
create index if not exists events_archived_idx on core.events(archived_at,id) where archived_at is not null;

create or replace function internal.assert_event_primary_team()
returns trigger language plpgsql security definer set search_path='' as $$
declare target_event_id uuid:=coalesce(new.event_id,old.event_id);
begin
 if not exists(select 1 from core.events where id=target_event_id) then return null;end if;
 if not exists(select 1 from core.events event_row join core.event_teams event_team
  on event_team.event_id=event_row.id and event_team.club_id=event_row.club_id
  and event_team.team_id=event_row.owning_team_id and event_team.relation='primary'
  where event_row.id=target_event_id)
 then raise check_violation using message='event_primary_team_required';end if;
 return null;
end;$$;

create function internal.event_can_be_deleted_by_manager(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from core.events event_row where event_row.id=target_event_id
   and event_row.state='draft' and event_row.recurrence_id is null
   and event_row.revision=1 and event_row.archived_at is null
   and internal.actor_can_manage_event_sharing(event_row.id)
   and not exists(select 1 from core.event_teams relation where relation.event_id=event_row.id and relation.relation='shared')
   and not exists(select 1 from core.squad_revisions squad where squad.event_id=event_row.id)
   and not exists(select 1 from core.callups callup where callup.event_id=event_row.id)
   and not exists(select 1 from core.attendance_facts attendance where attendance.event_id=event_row.id)
   and not exists(select 1 from core.match_workspaces workspace where workspace.event_id=event_row.id)
   and not exists(select 1 from core.sponsor_pledges pledge where pledge.event_id=event_row.id)
 )
$$;

create or replace function internal.get_event_details_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;actions text[]:=array[]::text[];
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(event_row.id)
 then raise insufficient_privilege using message='not_found';end if;
 if event_row.archived_at is null then
  if internal.actor_can_manage_event(event_row.id) then actions:=actions||array['revise','cancel','complete'];end if;
  if internal.actor_can_manage_event_roster(event_row.id) then actions:=actions||array['manage_roster'];end if;
  if internal.actor_can_manage_event_sharing(event_row.id) then
   actions:=actions||array['manage_sharing'];
   if internal.event_can_be_deleted_by_manager(event_row.id) then actions:=actions||array['delete'];end if;
   if event_row.state in('cancelled','completed') then actions:=actions||array['archive'];end if;
  end if;
 end if;
 return internal.event_snapshot(event_row)||jsonb_build_object(
  'archived_at',event_row.archived_at,'archive_reason',event_row.archive_reason,
  'location',(select to_jsonb(location)-'created_by' from core.event_locations location where location.id=event_row.location_id),
  'teams',coalesce((select jsonb_agg(jsonb_build_object('team_id',team.id,'name',team.name,
   'relation',relation.relation,'capabilities',relation.capabilities) order by relation.relation,team.name)
   from core.event_teams relation join core.teams team on team.id=relation.team_id and team.club_id=relation.club_id
   where relation.event_id=event_row.id),'[]'::jsonb),
  'audiences',coalesce((select jsonb_agg(jsonb_build_object('type',audience.audience_type,
   'team_id',audience.team_id,'team_name',team.name) order by audience.audience_type,team.name nulls first)
   from core.event_audiences audience left join core.teams team on team.id=audience.team_id and team.club_id=audience.club_id
   where audience.event_id=event_row.id),'[]'::jsonb),'caller_actions',actions);
end;$$;

create or replace function internal.transition_event_for_actor(target_event_id uuid,target_state text,
 expected_revision bigint,reason text,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;new_revision bigint;existing_result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='event.event.transition.v1'
  and internal.command_deduplication.idempotency_key=transition_event_for_actor.idempotency_key;
 if existing_result is not null then return(existing_result->>'revision')::bigint;end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or event_row.archived_at is not null or not internal.actor_can_manage_event(event_row.id)
 then raise insufficient_privilege using message='not_found';end if;
 if event_row.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if not((event_row.state='draft' and target_state in('scheduled','cancelled'))
  or(event_row.state='scheduled' and target_state in('cancelled','completed'))
  or(event_row.state='cancelled' and target_state='scheduled'))
 then raise check_violation using message='invalid_transition';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-lifecycle:'||event_row.id::text,0));
 if target_state='cancelled' then
  update core.callup_response_tokens token set state='revoked'
   where token.state='issued' and exists(select 1 from core.callups callup
    where callup.id=token.callup_id and callup.event_id=event_row.id and callup.state<>'cancelled');
  with cancelled as(
   update core.callups set state='cancelled',cancelled_at=now(),revision=revision+1
   where event_id=event_row.id and state<>'cancelled'
   returning id,club_id,club_person_id
  )
  insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,
   aggregate_id,recipient_profile_id,recipient_person_id,payload_ref)
  select cancelled.club_id,gen_random_uuid(),'callup.callup.cancelled.v1','callup',cancelled.id,
   link.profile_id,cancelled.club_person_id,jsonb_build_object('callup_id',cancelled.id,
    'event_id',event_row.id,'reason',nullif(btrim(reason),''))
  from cancelled left join core.person_account_links link on link.club_id=cancelled.club_id
   and link.club_person_id=cancelled.club_person_id and link.state='active';
 end if;
 update core.events set state=target_state,updated_at=now(),revision=revision+1
 where id=event_row.id returning revision into new_revision;
 insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id,reason)
 select event_row.club_id,event_row.id,new_revision,'transitioned','one',internal.event_snapshot(current_row),
  actor_id,nullif(btrim(reason),'') from core.events current_row where current_row.id=event_row.id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'event.event.transition.v1',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,reason) values(event_row.club_id,actor_id,'event.event.transition.v1','event',
   event_row.id,new_revision,nullif(btrim(reason),''));
 insert into internal.domain_outbox(club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
 values(event_row.club_id,'event.event.transitioned.v1','event',event_row.id,new_revision,
  jsonb_build_object('state',target_state));
 return new_revision;
end;$$;

create function internal.delete_event_draft_for_actor(target_event_id uuid,expected_revision bigint,
 idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;existing jsonb;result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select internal.command_deduplication.result into existing from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='event.event.delete_draft.v1'
   and internal.command_deduplication.idempotency_key=delete_event_draft_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or not internal.event_can_be_deleted_by_manager(event_row.id)
 then raise insufficient_privilege using message='not_found';end if;
 if event_row.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-lifecycle:'||event_row.id::text,0));
 result:=jsonb_build_object('event_id',event_row.id,'deleted',true);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata) values(event_row.club_id,actor_id,'event.event.delete_draft.v1','event',
   event_row.id,event_row.revision,jsonb_build_object('state',event_row.state));
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'event.event.delete_draft.v1',result);
 delete from core.events where id=event_row.id;
 return result;
end;$$;

create function internal.archive_event_for_actor(target_event_id uuid,expected_revision bigint,
 reason text,idempotency_key uuid) returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;new_revision bigint;existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='event.event.archive.v1'
  and internal.command_deduplication.idempotency_key=archive_event_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or not internal.actor_can_manage_event_sharing(event_row.id)
  or event_row.archived_at is not null or event_row.state not in('cancelled','completed')
 then raise insufficient_privilege using message='not_found';end if;
 if event_row.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if reason is null or length(btrim(reason)) not between 3 and 500
 then raise invalid_parameter_value using message='invalid_reason';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-lifecycle:'||event_row.id::text,0));
 update core.events set archived_at=now(),archived_by=actor_id,archive_reason=btrim(reason),
  updated_at=now(),revision=revision+1 where id=event_row.id returning revision into new_revision;
 insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id,reason)
 select event_row.club_id,event_row.id,new_revision,'revised','one',internal.event_snapshot(current_row),actor_id,btrim(reason)
 from core.events current_row where current_row.id=event_row.id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,reason) values(event_row.club_id,actor_id,'event.event.archive.v1','event',event_row.id,new_revision,btrim(reason));
 insert into internal.domain_outbox(club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
 values(event_row.club_id,'event.event.archived.v1','event',event_row.id,new_revision,'{}'::jsonb);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'event.event.archive.v1',jsonb_build_object('revision',new_revision));
 return new_revision;
end;$$;

create function internal.purge_archived_event(target_event_id uuid,retention_days integer default 365)
returns boolean language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype;
begin
 if retention_days<365 then raise invalid_parameter_value using message='retention_too_short';end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null then return false;end if;
 if event_row.archived_at is null or event_row.archived_at>now()-make_interval(days=>retention_days)
  or exists(select 1 from core.sponsor_pledges pledge where pledge.event_id=event_row.id)
  or exists(select 1 from core.match_workspaces workspace where workspace.event_id=event_row.id)
 then raise check_violation using message='event_not_purgeable';end if;
 delete from core.events where id=event_row.id;return true;
end;$$;

create or replace function internal.list_calendar_page_for_actor(context_ids uuid[],range_start timestamptz,
 range_end timestamptz,page_cursor text,page_limit integer default 100)
returns table(event_id uuid,club_id uuid,owning_team_id uuid,team_name text,title text,event_type text,
 state text,starts_at timestamptz,ends_at timestamptz,all_day boolean,timezone text,location_name text,
 revision bigint,event_cursor text) language plpgsql stable security definer set search_path='' as $$
declare cursor_value text;cursor_starts_at timestamptz;cursor_event_id uuid;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if context_ids is null or cardinality(context_ids)=0 or cardinality(context_ids)>50
  or range_end<=range_start or range_end>range_start+interval '400 days' or page_limit not between 1 and 200
 then raise invalid_parameter_value using message='invalid_input';end if;
 if(select count(distinct value) from unnest(context_ids)value)<>cardinality(context_ids)
 then raise invalid_parameter_value using message='invalid_input';end if;
 if(select count(*) from internal.get_my_contexts_for_actor() context_row where context_row.context_id=any(context_ids))<>cardinality(context_ids)
 then raise insufficient_privilege using message='not_found';end if;
 if nullif(page_cursor,'') is not null then begin
  cursor_value:=convert_from(decode(page_cursor,'base64'),'utf8');
  if cursor_value!~'^[^|]+\|[0-9a-fA-F-]{36}$' then raise invalid_text_representation;end if;
  cursor_starts_at:=split_part(cursor_value,'|',1)::timestamptz;cursor_event_id:=split_part(cursor_value,'|',2)::uuid;
 exception when others then raise invalid_parameter_value using message='invalid_cursor';end;end if;
 return query select event_row.id,event_row.club_id,event_row.owning_team_id,team.name,event_row.title,
  event_row.event_type,event_row.state,event_row.starts_at,event_row.ends_at,event_row.all_day,event_row.timezone,
  location.name,event_row.revision,encode(convert_to(event_row.starts_at::text||'|'||event_row.id::text,'utf8'),'base64')
 from core.events event_row join core.teams team on team.id=event_row.owning_team_id and team.club_id=event_row.club_id
 left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
 where event_row.archived_at is null and event_row.starts_at<range_end and event_row.ends_at>range_start
  and(cursor_starts_at is null or(event_row.starts_at,event_row.id)>(cursor_starts_at,cursor_event_id))
  and internal.actor_can_read_event(event_row.id) and exists(select 1 from internal.get_my_contexts_for_actor() context_row
   where context_row.context_id=any(context_ids) and context_row.club_id=event_row.club_id
    and(context_row.team_id is null or exists(select 1 from core.event_teams scoped_team
     where scoped_team.event_id=event_row.id and scoped_team.team_id=context_row.team_id)
     or exists(select 1 from core.event_audiences scoped_audience where scoped_audience.event_id=event_row.id
      and(scoped_audience.team_id=context_row.team_id or scoped_audience.audience_type='club'))))
 order by event_row.starts_at,event_row.id limit page_limit;
end;$$;

create function api.delete_event_draft(target_event_id uuid,expected_revision bigint,idempotency_key uuid)
returns jsonb language sql security invoker set search_path=''
as $$select internal.delete_event_draft_for_actor(target_event_id,expected_revision,idempotency_key)$$;
create function api.archive_event(target_event_id uuid,expected_revision bigint,reason text,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''
as $$select internal.archive_event_for_actor(target_event_id,expected_revision,reason,idempotency_key)$$;
create function api.purge_archived_event(target_event_id uuid,retention_days integer default 365)
returns boolean language sql security invoker set search_path=''
as $$select internal.purge_archived_event(target_event_id,retention_days)$$;

revoke all on function internal.event_can_be_deleted_by_manager(uuid),
 internal.delete_event_draft_for_actor(uuid,bigint,uuid),internal.archive_event_for_actor(uuid,bigint,text,uuid),
 internal.purge_archived_event(uuid,integer),api.delete_event_draft(uuid,bigint,uuid),
 api.archive_event(uuid,bigint,text,uuid),api.purge_archived_event(uuid,integer) from public,anon,authenticated;
grant execute on function internal.event_can_be_deleted_by_manager(uuid),
 internal.delete_event_draft_for_actor(uuid,bigint,uuid),internal.archive_event_for_actor(uuid,bigint,text,uuid),
 api.delete_event_draft(uuid,bigint,uuid),api.archive_event(uuid,bigint,text,uuid) to authenticated;
grant execute on function internal.purge_archived_event(uuid,integer),api.purge_archived_event(uuid,integer) to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827072045_cal04_safe_event_lifecycle','greenfield','CAL-04 safe deletion, atomic cancellation and retention-only purge');
notify pgrst,'reload schema';
