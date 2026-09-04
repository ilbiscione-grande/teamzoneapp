create function internal.actor_can_manage_event_sharing(target_event_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(
  select 1 from core.events event_row
  join core.event_teams relation on relation.event_id=event_row.id
   and relation.club_id=event_row.club_id and relation.relation='primary'
  where event_row.id=target_event_id
   and internal.actor_has_capability(event_row.club_id,relation.team_id,'event.manage')
 )
$$;

create function internal.actor_can_manage_event_roster(target_event_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(
  select 1 from core.events event_row
  join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
  where event_row.id=target_event_id
   and internal.actor_has_capability(event_row.club_id,relation.team_id,'event.manage')
   and(relation.relation='primary' or relation.relation='shared'
    and relation.capabilities&&array['manage_roster','co_manage']::text[])
 )
$$;

create or replace function internal.actor_can_manage_squad(target_event_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$select internal.actor_can_manage_event_roster(target_event_id)$$;

create or replace function internal.actor_can_manage_attendance(target_event_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$select internal.actor_can_manage_event_roster(target_event_id)$$;

create or replace function internal.get_event_details_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype; actions text[]:=array[]::text[];
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(event_row.id)
 then raise insufficient_privilege using message='not_found';end if;
 if internal.actor_can_manage_event(event_row.id) then actions:=actions||array['revise','cancel','complete'];end if;
 if internal.actor_can_manage_event_roster(event_row.id) then actions:=actions||array['manage_roster'];end if;
 if internal.actor_can_manage_event_sharing(event_row.id) then actions:=actions||array['manage_sharing'];end if;
 return internal.event_snapshot(event_row)||jsonb_build_object(
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

create function internal.get_event_sharing_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_manage_event_sharing(event_row.id)
 then raise insufficient_privilege using message='not_found';end if;
 return jsonb_build_object('event_id',event_row.id,'revision',event_row.revision,
  'teams',coalesce((select jsonb_agg(jsonb_build_object('team_id',team.id,'name',team.name,
   'capabilities',coalesce(relation.capabilities,array[]::text[]),'selected',relation.id is not null) order by team.name)
   from core.teams team left join core.event_teams relation on relation.event_id=event_row.id
    and relation.team_id=team.id and relation.relation='shared'
   where team.club_id=event_row.club_id and team.id<>event_row.owning_team_id and team.status='active'),'[]'::jsonb),
  'audiences',coalesce((select jsonb_agg(jsonb_build_object('type',audience.audience_type,
   'team_id',audience.team_id) order by audience.team_id,audience.audience_type)
   from core.event_audiences audience where audience.event_id=event_row.id),'[]'::jsonb));
end;$$;

create function internal.update_event_sharing_for_actor(target_event_id uuid,shared_teams jsonb,
 audience_entries jsonb,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); event_row core.events%rowtype; item jsonb; caps text[];
 new_revision bigint; existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='event.sharing.update.v1'
  and internal.command_deduplication.idempotency_key=update_event_sharing_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or not internal.actor_can_manage_event_sharing(event_row.id)
 then raise insufficient_privilege using message='not_found';end if;
 if event_row.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if shared_teams is null or jsonb_typeof(shared_teams)<>'array' or jsonb_array_length(shared_teams)>50
  or audience_entries is null or jsonb_typeof(audience_entries)<>'array' or jsonb_array_length(audience_entries)>200
 then raise invalid_parameter_value using message='invalid_input';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-sharing:'||event_row.id::text,0));
 create temporary table if not exists pg_temp.cal03_shared(team_id uuid primary key,capabilities text[] not null) on commit drop;
 truncate pg_temp.cal03_shared;
 for item in select value from jsonb_array_elements(shared_teams) loop
  caps:=array(select distinct value from jsonb_array_elements_text(coalesce(item->'capabilities','[]'::jsonb)) value order by value);
  if not(item?'team_id') or caps is null or not(caps<@array['view','manage_roster','co_manage']::text[])
   or not(caps@>array['view']::text[]) or not exists(select 1 from core.teams team
    where team.id=(item->>'team_id')::uuid and team.club_id=event_row.club_id
     and team.id<>event_row.owning_team_id and team.status='active')
  then raise invalid_parameter_value using message='invalid_shared_team';end if;
  insert into pg_temp.cal03_shared values((item->>'team_id')::uuid,caps);
 end loop;
 if exists(select 1 from jsonb_array_elements(audience_entries) entry
  where entry->>'type' not in('players','leaders','guardians','club')
   or(entry->>'type'='club' and entry->>'team_id' is not null)
   or(entry->>'type'<>'club' and(not(entry?'team_id') or
    (entry->>'team_id')::uuid<>event_row.owning_team_id and not exists(
     select 1 from pg_temp.cal03_shared shared where shared.team_id=(entry->>'team_id')::uuid))))
 then raise invalid_parameter_value using message='invalid_audience';end if;
 delete from core.event_audiences where event_id=event_row.id
  and(team_id<>event_row.owning_team_id or team_id is null);
 delete from core.event_teams where event_id=event_row.id and relation='shared';
 insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
 select event_row.club_id,event_row.id,team_id,'shared',capabilities,actor_id from pg_temp.cal03_shared;
 insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
 select event_row.club_id,event_row.id,entry->>'type',
  case when entry->>'type'='club' then null else(entry->>'team_id')::uuid end,actor_id
 from jsonb_array_elements(audience_entries) entry on conflict do nothing;
 update core.events set revision=revision+1,updated_at=now() where id=event_row.id returning revision into new_revision;
 insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id)
 select event_row.club_id,event_row.id,new_revision,'revised','one',internal.event_snapshot(current_row),actor_id
 from core.events current_row where current_row.id=event_row.id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(event_row.club_id,actor_id,'event.sharing.update.v1','event',event_row.id,new_revision,
  jsonb_build_object('shared_team_count',jsonb_array_length(shared_teams)));
 insert into internal.domain_outbox(club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
 values(event_row.club_id,'event.sharing.updated.v1','event',event_row.id,new_revision,'{}'::jsonb);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'event.sharing.update.v1',jsonb_build_object('revision',new_revision));
 return new_revision;
exception when invalid_text_representation then raise invalid_parameter_value using message='invalid_input';
end;$$;

create function api.get_event_sharing(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path=''
as $$select internal.get_event_sharing_for_actor(target_event_id)$$;
create function api.update_event_sharing(target_event_id uuid,shared_teams jsonb,audience_entries jsonb,
 expected_revision bigint,idempotency_key uuid) returns bigint
language sql security invoker set search_path=''
as $$select internal.update_event_sharing_for_actor(target_event_id,shared_teams,audience_entries,expected_revision,idempotency_key)$$;

revoke all on function internal.actor_can_manage_event_sharing(uuid),internal.actor_can_manage_event_roster(uuid),
 internal.get_event_sharing_for_actor(uuid),internal.update_event_sharing_for_actor(uuid,jsonb,jsonb,bigint,uuid),
 api.get_event_sharing(uuid),api.update_event_sharing(uuid,jsonb,jsonb,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.actor_can_manage_event_sharing(uuid),internal.actor_can_manage_event_roster(uuid),
 internal.get_event_sharing_for_actor(uuid),internal.update_event_sharing_for_actor(uuid,jsonb,jsonb,bigint,uuid),
 api.get_event_sharing(uuid),api.update_event_sharing(uuid,jsonb,jsonb,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827070512_cal03_shared_event_access','greenfield','CAL-03 explicit shared-event capabilities and audience isolation');
notify pgrst,'reload schema';
