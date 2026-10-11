-- Match format and periods per match event, chosen in the event editor
-- (when creating and when editing). Without a choice the team's format
-- applies (internal.match_format_period_minutes; unset team = 11v11).
-- Match mode starts a new workspace with the event's periods. While the
-- match is still being planned, a change in the editor also updates the
-- workspace; once it has started, periods are changed in match mode only.

create table if not exists core.event_match_settings (
  event_id uuid primary key references core.events(id) on delete cascade,
  club_id uuid not null,
  match_format text not null
    check (match_format in ('3v3','5v5','7v7','9v9','11v11')),
  period_minutes integer[] not null
    check (cardinality(period_minutes) between 1 and 8 and 0 < all(period_minutes) and 120 >= all(period_minutes)),
  updated_at timestamptz not null default now(),
  updated_by uuid not null
);
alter table core.event_match_settings enable row level security;
revoke all on core.event_match_settings from public, anon, authenticated;

-- What the editor shows: the event's own choice, else the team default;
-- the workspace's periods once match mode has them.
create or replace function internal.get_event_match_settings_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype; settings core.event_match_settings%rowtype;
 workspace core.match_workspaces%rowtype; team_format text;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(event_row.id)
 then raise insufficient_privilege using message='not_found';end if;
 select * into settings from core.event_match_settings where event_id=event_row.id;
 select * into workspace from core.match_workspaces where event_id=event_row.id;
 select coalesce(team.match_format,'11v11') into team_format from core.teams team where team.id=event_row.owning_team_id;
 return jsonb_build_object(
  'match_format',coalesce(settings.match_format,team_format,'11v11'),
  'period_minutes',to_jsonb(coalesce(workspace.period_minutes,settings.period_minutes,
    internal.match_format_period_minutes(team_format))),
  'is_set',settings.event_id is not null,
  'locked',coalesce(workspace.state in ('live','completed'),false));
end;$$;

create or replace function internal.set_event_match_settings_for_actor(target_event_id uuid,new_format text,
 new_period_minutes integer[],change_scope text,idempotency_key uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); anchor core.events%rowtype; target core.events%rowtype; cached jsonb;
 changed integer:=0;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 if idempotency_key is null or new_format is null or new_format not in ('3v3','5v5','7v7','9v9','11v11')
  or new_period_minutes is null or cardinality(new_period_minutes) not between 1 and 8
  or array_position(new_period_minutes,null) is not null
  or exists(select 1 from unnest(new_period_minutes) value where value not between 1 and 120)
  or change_scope not in ('one','forward','all')
 then raise invalid_parameter_value using message='invalid_match_settings';end if;
 select d.result into cached from internal.command_deduplication d
 where d.actor_profile_id=actor_id and d.command_type='event.match_settings.updated.v1'
  and d.idempotency_key=set_event_match_settings_for_actor.idempotency_key;
 if cached is not null then return (cached->>'changed')::integer;end if;
 select * into anchor from core.events where id=target_event_id;
 if anchor.id is null or anchor.event_type<>'match' or not internal.actor_can_manage_event(anchor.id)
 then raise insufficient_privilege using message='not_found';end if;
 for target in select * from core.events event_row
  where event_row.id=anchor.id or (anchor.recurrence_id is not null and change_scope<>'one'
   and event_row.recurrence_id=anchor.recurrence_id and event_row.event_type='match'
   and (change_scope='all' or event_row.occurrence_number>=anchor.occurrence_number))
  order by event_row.starts_at
 loop
  if not internal.actor_can_manage_event(target.id) then continue;end if;
  insert into core.event_match_settings(event_id,club_id,match_format,period_minutes,updated_by)
  values(target.id,target.club_id,new_format,new_period_minutes,actor_id)
  on conflict(event_id) do update set match_format=excluded.match_format,
   period_minutes=excluded.period_minutes,updated_at=now(),updated_by=actor_id;
  -- A match still being planned follows; a started one keeps its clock.
  update core.match_workspaces set period_minutes=new_period_minutes,revision=revision+1
  where event_id=target.id and state='planning' and period_minutes<>new_period_minutes;
  changed:=changed+1;
 end loop;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'event.match_settings.updated.v1',jsonb_build_object('changed',changed));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(anchor.club_id,actor_id,'event.match_settings.updated.v1','event',anchor.id,anchor.revision,
  jsonb_build_object('match_format',new_format,'period_minutes',to_jsonb(new_period_minutes),
   'scope',change_scope,'changed',changed));
 return changed;
end;$$;

-- New workspaces: the event's periods, else the team format's.
create or replace function internal.ensure_match_workspace(target_event_id uuid)
returns core.match_workspaces language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype; workspace core.match_workspaces%rowtype;
begin
 event_row:=internal.assert_match_manager(target_event_id);
 insert into core.match_workspaces(event_id,club_id,team_id,updated_by,period_minutes)
 values(event_row.id,event_row.club_id,event_row.owning_team_id,auth.uid(),
  coalesce((select settings.period_minutes from core.event_match_settings settings where settings.event_id=event_row.id),
   internal.match_format_period_minutes((select team.match_format from core.teams team where team.id=event_row.owning_team_id))))
 on conflict(event_id) do nothing;
 insert into core.match_projections(event_id) values(event_row.id) on conflict(event_id) do nothing;
 select * into workspace from core.match_workspaces where event_id=target_event_id;
 return workspace;
end$$;

create or replace function api.get_event_match_settings(target_event_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_event_match_settings_for_actor(target_event_id)$$;

create or replace function api.set_event_match_settings(target_event_id uuid,new_format text,
 new_period_minutes integer[],change_scope text,idempotency_key uuid)
returns integer language sql security invoker set search_path='' as
$$select internal.set_event_match_settings_for_actor(target_event_id,new_format,new_period_minutes,change_scope,idempotency_key)$$;

revoke all on function internal.ensure_match_workspace(uuid) from public,anon,authenticated;
revoke all on function internal.get_event_match_settings_for_actor(uuid),
 internal.set_event_match_settings_for_actor(uuid,text,integer[],text,uuid),
 api.get_event_match_settings(uuid),api.set_event_match_settings(uuid,text,integer[],text,uuid) from public,anon;
grant execute on function internal.get_event_match_settings_for_actor(uuid),
 internal.set_event_match_settings_for_actor(uuid,text,integer[],text,uuid),
 api.get_event_match_settings(uuid),api.set_event_match_settings(uuid,text,integer[],text,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261021090000_event_match_settings','greenfield','Match format and periods per match event, set in the event editor'
where not exists(select 1 from internal.migration_provenance where migration_name='20261021090000_event_match_settings');
notify pgrst,'reload schema';
