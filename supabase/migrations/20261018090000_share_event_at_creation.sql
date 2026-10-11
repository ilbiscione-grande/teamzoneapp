-- Share an event with other teams directly when it is created.
--
-- The editor lists the club's other active teams (list_shareable_teams) and,
-- right after create_event_v2, shares the new event — every occurrence of a
-- new series — with the chosen teams (share_new_event). Sharing itself goes
-- through internal.update_event_sharing_for_actor, so the CAL-03 rules,
-- revisions and audit stay the single source of truth. Shared teams get
-- "Kan se" and the same recipients (players/leaders/guardians) as the owning
-- team; finer levels are still set in the Dela event dialog afterwards.

create function internal.list_shareable_teams_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_row core.teams%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into team_row from core.teams where id=target_team_id;
 if team_row.id is null or not internal.actor_has_capability(team_row.club_id,team_row.id,'event.manage')
 then raise insufficient_privilege using message='not_found';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('team_id',team.id,'name',team.name) order by team.name)
  from core.teams team
  where team.club_id=team_row.club_id and team.id<>team_row.id and team.status='active'),'[]'::jsonb);
end;$$;

create function internal.share_new_event_for_actor(target_event_id uuid,team_ids uuid[],idempotency_key uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare anchor core.events%rowtype; event_row core.events%rowtype; shared jsonb; audiences jsonb;
 shared_count integer:=0;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into anchor from core.events where id=target_event_id;
 if anchor.id is null or not internal.actor_can_manage_event_sharing(anchor.id)
 then raise insufficient_privilege using message='not_found';end if;
 if team_ids is null or cardinality(team_ids)=0 then return 0;end if;
 if cardinality(team_ids)>50 then raise invalid_parameter_value using message='invalid_input';end if;
 shared:=(select jsonb_agg(jsonb_build_object('team_id',team_id,'capabilities',jsonb_build_array('view')))
  from (select distinct unnest(team_ids) team_id) chosen);
 -- The anchor and, for a new series, its other occurrences.
 for event_row in select * from core.events
  where id=anchor.id or (anchor.recurrence_id is not null and recurrence_id=anchor.recurrence_id)
  order by starts_at
 loop
  -- Keep the owning team's (and club-wide) recipients; give each shared team
  -- the owning team's recipient types.
  audiences:=coalesce((select jsonb_agg(entry) from (
    select jsonb_strip_nulls(jsonb_build_object('type',audience.audience_type,'team_id',audience.team_id)) entry
    from core.event_audiences audience where audience.event_id=event_row.id
    union all
    select jsonb_build_object('type',owner.audience_type,'team_id',chosen.team_id)
    from (select distinct audience_type from core.event_audiences
          where event_id=event_row.id and team_id=event_row.owning_team_id
           and audience_type in('players','leaders','guardians')) owner
    cross join (select distinct unnest(team_ids) team_id) chosen
   ) entries),'[]'::jsonb);
  perform internal.update_event_sharing_for_actor(event_row.id,shared,audiences,event_row.revision,
   md5(idempotency_key::text||event_row.id::text)::uuid);
  shared_count:=shared_count+1;
 end loop;
 return shared_count;
end;$$;

create function api.list_shareable_teams(target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.list_shareable_teams_for_actor(target_team_id)$$;

create function api.share_new_event(target_event_id uuid,team_ids uuid[],idempotency_key uuid)
returns integer language sql security invoker set search_path='' as
$$select internal.share_new_event_for_actor(target_event_id,team_ids,idempotency_key)$$;

revoke all on function internal.list_shareable_teams_for_actor(uuid),
 internal.share_new_event_for_actor(uuid,uuid[],uuid),
 api.list_shareable_teams(uuid),api.share_new_event(uuid,uuid[],uuid) from public,anon;
grant execute on function internal.list_shareable_teams_for_actor(uuid),
 internal.share_new_event_for_actor(uuid,uuid[],uuid),
 api.list_shareable_teams(uuid),api.share_new_event(uuid,uuid[],uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261018090000_share_event_at_creation','greenfield',
 'Share a new event (every occurrence of a new series) with other teams directly from the editor');
notify pgrst,'reload schema';
