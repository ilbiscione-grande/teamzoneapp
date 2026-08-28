-- CAL-02: tenant-scoped saved locations and safe occurrence/forward/all editing.

create index if not exists event_locations_club_normalized_recent_idx
on core.event_locations(club_id,lower(btrim(name)),created_at desc);

create function internal.list_saved_event_locations_for_actor(target_club_id uuid,target_team_id uuid)
returns table(location_name text) language plpgsql stable security definer set search_path=''
as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'event.manage')
 then raise insufficient_privilege using message='not_found';end if;
 return query select distinct on(lower(btrim(location.name))) location.name
 from core.event_locations location where location.club_id=target_club_id
 order by lower(btrim(location.name)),location.created_at desc limit 100;
end;
$$;

create function internal.revise_event_v2_for_actor(target_event_id uuid,change_scope text,patch jsonb,
 expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();anchor core.events%rowtype;event_target core.events%rowtype;
 existing jsonb;new_revision bigint;new_location_id uuid;location_value text;
 audience_values text[];new_start timestamptz;new_end timestamptz;start_delta interval;
 anchor_new_start timestamptz;anchor_new_end timestamptz;new_duration interval;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='event.event.revise.v2'
  and internal.command_deduplication.idempotency_key=revise_event_v2_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into anchor from core.events where id=target_event_id for update;
 if anchor.id is null or not internal.actor_can_manage_event(anchor.id)
 then raise insufficient_privilege using message='not_found';end if;
 if anchor.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if change_scope not in('one','forward','all') or(anchor.recurrence_id is null and change_scope<>'one')
  or exists(select 1 from jsonb_object_keys(patch) key where key not in
   ('title','description','event_type','starts_at','ends_at','all_day','timezone','location_name','audience_types'))
  or(patch?'title' and length(btrim(patch->>'title')) not between 1 and 160)
  or(patch?'event_type' and patch->>'event_type' not in('training','match','meeting','activity'))
  or(patch?'timezone' and length(btrim(patch->>'timezone')) not between 1 and 80)
  or(patch?'location_name' and length(btrim(patch->>'location_name'))>160)
 then raise invalid_parameter_value using message='invalid_input';end if;

 if patch?'audience_types' then
  select array_agg(value) into audience_values
  from jsonb_array_elements_text(patch->'audience_types') value;
  if audience_values is null or cardinality(audience_values)=0
   or exists(select 1 from unnest(audience_values) value where value not in('players','leaders','guardians','club'))
   or cardinality(audience_values)<>(select count(distinct value) from unnest(audience_values) value)
  then raise invalid_parameter_value using message='invalid_audience';end if;
 end if;

 anchor_new_start:=case when patch?'starts_at' then(patch->>'starts_at')::timestamptz else anchor.starts_at end;
 anchor_new_end:=case when patch?'ends_at' then(patch->>'ends_at')::timestamptz
  when patch?'starts_at' then anchor.ends_at+(anchor_new_start-anchor.starts_at) else anchor.ends_at end;
 if anchor_new_end<=anchor_new_start then raise invalid_parameter_value using message='invalid_period';end if;
 start_delta:=anchor_new_start-anchor.starts_at;new_duration:=anchor_new_end-anchor_new_start;

 if patch?'location_name' then
  location_value:=nullif(btrim(patch->>'location_name'),'');
  if location_value is not null then
   select location.id into new_location_id from core.event_locations location
   where location.club_id=anchor.club_id and lower(btrim(location.name))=lower(location_value)
   order by location.created_at desc limit 1;
   if new_location_id is null then
    insert into core.event_locations(club_id,name,created_by)
    values(anchor.club_id,location_value,actor_id) returning id into new_location_id;
   end if;
  end if;
 end if;

 perform pg_advisory_xact_lock(hashtextextended('event-series:'||coalesce(anchor.recurrence_id,anchor.id)::text,0));
 if anchor.recurrence_id is not null and change_scope='all' and(patch?'starts_at' or patch?'timezone') then
  update core.recurrence_rules set local_start=anchor_new_start at time zone
    case when patch?'timezone' then btrim(patch->>'timezone') else timezone end,
   timezone=case when patch?'timezone' then btrim(patch->>'timezone') else timezone end,
   revision=revision+1 where id=anchor.recurrence_id;
 end if;
 perform 1 from core.events event_row where event_row.id=anchor.id
  or(anchor.recurrence_id is not null and event_row.recurrence_id=anchor.recurrence_id
   and(change_scope='all' or change_scope='forward' and event_row.occurrence_number>=anchor.occurrence_number))
  order by event_row.occurrence_number nulls first for update;
 for event_target in select event_row.* from core.events event_row where event_row.id=anchor.id
  or(anchor.recurrence_id is not null and event_row.recurrence_id=anchor.recurrence_id
   and(change_scope='all' or change_scope='forward' and event_row.occurrence_number>=anchor.occurrence_number))
  order by event_row.occurrence_number nulls first loop
  new_start:=case when patch?'starts_at' then event_target.starts_at+start_delta else event_target.starts_at end;
  new_end:=case when patch?'ends_at' then new_start+new_duration
   when patch?'starts_at' then event_target.ends_at+start_delta else event_target.ends_at end;
  if new_end<=new_start then raise invalid_parameter_value using message='invalid_period';end if;
  update core.events set title=case when patch?'title' then btrim(patch->>'title') else title end,
   description=case when patch?'description' then nullif(btrim(patch->>'description'),'') else description end,
   event_type=case when patch?'event_type' then patch->>'event_type' else event_type end,
   starts_at=new_start,ends_at=new_end,
   all_day=case when patch?'all_day' then(patch->>'all_day')::boolean else all_day end,
   timezone=case when patch?'timezone' then btrim(patch->>'timezone') else timezone end,
   location_id=case when patch?'location_name' then new_location_id else location_id end,
   updated_at=now(),revision=revision+1 where id=event_target.id returning revision into new_revision;
  if patch?'audience_types' then
   delete from core.event_audiences where event_id=event_target.id
    and(team_id=event_target.owning_team_id or team_id is null);
   insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
   select event_target.club_id,event_target.id,value,case when value='club' then null else event_target.owning_team_id end,actor_id
   from unnest(audience_values) value;
  end if;
  insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id)
  select event_target.club_id,event_target.id,new_revision,'revised',change_scope,internal.event_snapshot(current_row),actor_id
  from core.events current_row where current_row.id=event_target.id;
  insert into internal.domain_outbox(club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
  values(event_target.club_id,'event.event.revised.v1','event',event_target.id,new_revision,jsonb_build_object('scope',change_scope));
 end loop;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'event.event.revise.v2',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata) values(anchor.club_id,actor_id,'event.event.revise.v2','event',anchor.id,
  new_revision,jsonb_build_object('scope',change_scope,'fields',(select jsonb_agg(key) from jsonb_object_keys(patch) key));
 return new_revision;
end;
$$;

create function api.list_saved_event_locations(target_club_id uuid,target_team_id uuid)
returns table(location_name text) language sql stable security invoker set search_path=''
as $$select * from internal.list_saved_event_locations_for_actor(target_club_id,target_team_id)$$;
create function api.revise_event_v2(target_event_id uuid,change_scope text,patch jsonb,
 expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''
as $$select internal.revise_event_v2_for_actor(target_event_id,change_scope,patch,expected_revision,idempotency_key)$$;

revoke all on function internal.list_saved_event_locations_for_actor(uuid,uuid),
 internal.revise_event_v2_for_actor(uuid,text,jsonb,bigint,uuid),
 api.list_saved_event_locations(uuid,uuid),api.revise_event_v2(uuid,text,jsonb,bigint,uuid)
from public,anon,authenticated;
grant execute on function internal.list_saved_event_locations_for_actor(uuid,uuid),
 internal.revise_event_v2_for_actor(uuid,text,jsonb,bigint,uuid),
 api.list_saved_event_locations(uuid,uuid),api.revise_event_v2(uuid,text,jsonb,bigint,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827063902_cal02_event_editor_locations','greenfield','CAL-02 safe series editor and tenant-scoped location suggestions');
notify pgrst,'reload schema';
