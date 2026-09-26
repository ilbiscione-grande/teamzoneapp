-- CAL-04: make retained event archives visible and reversibly restorable.

create function internal.list_archived_events_for_actor(
  context_ids uuid[],
  page_limit integer default 200
)
returns table(
  event_id uuid,
  club_id uuid,
  owning_team_id uuid,
  team_name text,
  title text,
  event_type text,
  state text,
  starts_at timestamptz,
  ends_at timestamptz,
  all_day boolean,
  timezone text,
  location_name text,
  revision bigint,
  match_state text,
  score_us integer,
  score_opponent integer,
  is_shared boolean,
  archived_at timestamptz,
  archive_reason text
)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  if context_ids is null or cardinality(context_ids)=0
    or cardinality(context_ids)>50 or page_limit not between 1 and 200
    or (select count(distinct value) from unnest(context_ids) value)<>cardinality(context_ids)
  then
    raise invalid_parameter_value using message='invalid_input';
  end if;
  if (select count(*) from internal.get_my_contexts_for_actor() context_row
      where context_row.context_id=any(context_ids))<>cardinality(context_ids)
  then
    raise insufficient_privilege using message='not_found';
  end if;

  return query
  select event_row.id,event_row.club_id,event_row.owning_team_id,team.name,
    event_row.title,event_row.event_type,event_row.state,event_row.starts_at,
    event_row.ends_at,event_row.all_day,event_row.timezone,location.name,
    event_row.revision,workspace.state,
    case when workspace.state='completed' then projection.score_us end,
    case when workspace.state='completed' then projection.score_opponent end,
    exists(select 1 from core.event_teams shared_relation
      where shared_relation.event_id=event_row.id and shared_relation.relation='shared'),
    event_row.archived_at,event_row.archive_reason
  from core.events event_row
  join core.teams team on team.id=event_row.owning_team_id and team.club_id=event_row.club_id
  left join core.event_locations location on location.id=event_row.location_id
    and location.club_id=event_row.club_id
  left join core.match_workspaces workspace on workspace.event_id=event_row.id
    and event_row.event_type='match'
  left join core.match_projections projection on projection.event_id=workspace.event_id
  where event_row.archived_at is not null
    and internal.actor_can_read_event(event_row.id)
    and exists(
      select 1 from internal.get_my_contexts_for_actor() context_row
      where context_row.context_id=any(context_ids)
        and context_row.club_id=event_row.club_id
        and (
          context_row.team_id is null
          or exists(select 1 from core.event_teams scoped_team
            where scoped_team.event_id=event_row.id and scoped_team.team_id=context_row.team_id)
          or exists(select 1 from core.event_audiences scoped_audience
            where scoped_audience.event_id=event_row.id
              and (scoped_audience.team_id=context_row.team_id
                or scoped_audience.audience_type='club'))
        )
    )
  order by event_row.archived_at desc,event_row.id
  limit page_limit;
end;$$;

create function internal.restore_archived_event_for_actor(
  target_event_id uuid,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint language plpgsql security definer set search_path='' as $$
declare
  actor_id uuid:=auth.uid();
  event_row core.events%rowtype;
  new_revision bigint;
  existing jsonb;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  select result into existing from internal.command_deduplication
  where actor_profile_id=actor_id
    and command_type='event.event.archive_restore.v1'
    and internal.command_deduplication.idempotency_key=restore_archived_event_for_actor.idempotency_key;
  if existing is not null then return (existing->>'revision')::bigint; end if;

  select * into event_row from core.events where id=target_event_id for update;
  if event_row.id is null or event_row.archived_at is null
    or event_row.state not in('cancelled','completed')
    or not internal.actor_can_manage_event_sharing(event_row.id)
  then
    raise insufficient_privilege using message='not_found';
  end if;
  if event_row.revision<>expected_revision then
    raise serialization_failure using message='stale_revision';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('event-lifecycle:'||event_row.id::text,0));
  update core.events set archived_at=null,archived_by=null,archive_reason=null,
    updated_at=now(),revision=revision+1
  where id=event_row.id returning revision into new_revision;

  insert into core.event_revisions(
    club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id,reason
  )
  select event_row.club_id,event_row.id,new_revision,'revised','one',
    internal.event_snapshot(current_row),actor_id,'Återställd från arkiv'
  from core.events current_row where current_row.id=event_row.id;
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision
  ) values(
    event_row.club_id,actor_id,'event.event.archive_restore.v1','event',event_row.id,new_revision
  );
  insert into internal.domain_outbox(
    club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload
  ) values(
    event_row.club_id,'event.event.archive_restored.v1','event',event_row.id,new_revision,'{}'::jsonb
  );
  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values(
    actor_id,idempotency_key,'event.event.archive_restore.v1',jsonb_build_object('revision',new_revision)
  );
  return new_revision;
end;$$;

create function api.list_archived_events(
  context_ids uuid[],
  page_limit integer default 200
)
returns table(
  event_id uuid,club_id uuid,owning_team_id uuid,team_name text,title text,
  event_type text,state text,starts_at timestamptz,ends_at timestamptz,
  all_day boolean,timezone text,location_name text,revision bigint,
  match_state text,score_us integer,score_opponent integer,is_shared boolean,
  archived_at timestamptz,archive_reason text
)
language sql stable security invoker set search_path='' as $$
  select * from internal.list_archived_events_for_actor(context_ids,page_limit)
$$;

create function api.restore_archived_event(
  target_event_id uuid,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint language sql security invoker set search_path='' as $$
  select internal.restore_archived_event_for_actor(
    target_event_id,expected_revision,idempotency_key
  )
$$;

revoke all on function internal.list_archived_events_for_actor(uuid[],integer),
  internal.restore_archived_event_for_actor(uuid,bigint,uuid),
  api.list_archived_events(uuid[],integer),
  api.restore_archived_event(uuid,bigint,uuid)
from public,anon,authenticated;
grant execute on function internal.list_archived_events_for_actor(uuid[],integer),
  internal.restore_archived_event_for_actor(uuid,bigint,uuid),
  api.list_archived_events(uuid[],integer),
  api.restore_archived_event(uuid,bigint,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260919211602_cal04_archived_event_recovery',
  'greenfield',
  'CAL-04 visible retained archives and permission-checked recovery'
);
notify pgrst,'reload schema';
