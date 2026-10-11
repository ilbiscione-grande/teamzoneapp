-- The team's match format (3v3, 5v5, 7v7, 9v9, 11v11), set under Laget →
-- Redigera lagprofil. Unset means 11v11. The app uses it for the default
-- length of a new match (a 5v5 match is shorter than an 11v11 match).
-- Readable by anyone who can see the team or plan its events; set by the
-- same people who may edit the team profile.
-- A new match workspace (match mode) also starts with the format's periods
-- instead of always 2×45; existing workspaces keep theirs, and the periods
-- can still be changed per match.

alter table core.teams add column if not exists match_format text;
alter table core.teams drop constraint if exists teams_match_format_check;
alter table core.teams add constraint teams_match_format_check
  check (match_format is null or match_format in ('3v3','5v5','7v7','9v9','11v11'));

create or replace function internal.get_team_match_format_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_row core.teams%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into team_row from core.teams where id=target_team_id;
 if team_row.id is null or not (
   internal.actor_has_capability(team_row.club_id,team_row.id,'team.roster.view')
   or internal.actor_has_capability(team_row.club_id,team_row.id,'event.manage')
   or internal.actor_has_capability(team_row.club_id,team_row.id,'club.memberships.manage')
   or internal.actor_has_capability(team_row.club_id,null,'club.memberships.manage'))
 then raise insufficient_privilege using message='not_found';end if;
 return jsonb_build_object('match_format',team_row.match_format,
  'effective',coalesce(team_row.match_format,'11v11'),
  'can_edit',internal.actor_has_capability(team_row.club_id,team_row.id,'team.roster.manage')
   or internal.actor_has_capability(team_row.club_id,team_row.id,'club.memberships.manage')
   or internal.actor_has_capability(team_row.club_id,null,'club.memberships.manage'));
end;$$;

create or replace function internal.set_team_match_format_for_actor(target_team_id uuid,new_format text,idempotency_key uuid)
returns text language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); team_row core.teams%rowtype; cached jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 if idempotency_key is null or new_format is null or new_format not in ('3v3','5v5','7v7','9v9','11v11')
 then raise invalid_parameter_value using message='invalid_match_format';end if;
 select d.result into cached from internal.command_deduplication d
 where d.actor_profile_id=actor_id and d.command_type='team.match_format.updated.v1'
  and d.idempotency_key=set_team_match_format_for_actor.idempotency_key;
 if cached is not null then return cached->>'match_format';end if;
 select * into team_row from core.teams where id=target_team_id and status='active' for update;
 if team_row.id is null or not (
   internal.actor_has_capability(team_row.club_id,team_row.id,'team.roster.manage')
   or internal.actor_has_capability(team_row.club_id,team_row.id,'club.memberships.manage')
   or internal.actor_has_capability(team_row.club_id,null,'club.memberships.manage'))
 then raise insufficient_privilege using message='not_found';end if;
 if team_row.match_format is distinct from new_format then
  update core.teams set match_format=new_format,revision=revision+1 where id=team_row.id;
 end if;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'team.match_format.updated.v1',jsonb_build_object('match_format',new_format));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(team_row.club_id,actor_id,'team.match_format.updated.v1','team',team_row.id,team_row.revision,
  jsonb_build_object('from',team_row.match_format,'to',new_format));
 return new_format;
end;$$;

create or replace function api.get_team_match_format(target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_team_match_format_for_actor(target_team_id)$$;

create or replace function api.set_team_match_format(target_team_id uuid,new_format text,idempotency_key uuid)
returns text language sql security invoker set search_path='' as
$$select internal.set_team_match_format_for_actor(target_team_id,new_format,idempotency_key)$$;

-- Periods per format (minutes each).
create or replace function internal.match_format_period_minutes(format text)
returns integer[] language sql immutable set search_path='' as $$
 select case format
  when '3v3' then array[10,10,10]
  when '5v5' then array[15,15,15]
  when '7v7' then array[20,20,20]
  when '9v9' then array[35,35]
  else array[45,45] end
$$;

create or replace function internal.ensure_match_workspace(target_event_id uuid)
returns core.match_workspaces language plpgsql security definer set search_path='' as $$
declare event_row core.events%rowtype; workspace core.match_workspaces%rowtype;
begin
 event_row:=internal.assert_match_manager(target_event_id);
 insert into core.match_workspaces(event_id,club_id,team_id,updated_by,period_minutes)
 values(event_row.id,event_row.club_id,event_row.owning_team_id,auth.uid(),
  internal.match_format_period_minutes((select team.match_format from core.teams team where team.id=event_row.owning_team_id)))
 on conflict(event_id) do nothing;
 insert into core.match_projections(event_id) values(event_row.id) on conflict(event_id) do nothing;
 select * into workspace from core.match_workspaces where event_id=target_event_id;
 return workspace;
end$$;

revoke all on function internal.match_format_period_minutes(text),internal.ensure_match_workspace(uuid)
 from public,anon,authenticated;

revoke all on function internal.get_team_match_format_for_actor(uuid),
 internal.set_team_match_format_for_actor(uuid,text,uuid),
 api.get_team_match_format(uuid),api.set_team_match_format(uuid,text,uuid) from public,anon;
grant execute on function internal.get_team_match_format_for_actor(uuid),
 internal.set_team_match_format_for_actor(uuid,text,uuid),
 api.get_team_match_format(uuid),api.set_team_match_format(uuid,text,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261020090000_team_match_format','greenfield','Team match format (default 11v11) for default match length'
where not exists(select 1 from internal.migration_provenance where migration_name='20261020090000_team_match_format');
notify pgrst,'reload schema';
