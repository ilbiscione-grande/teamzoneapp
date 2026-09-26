-- TEAM-01 presents completed match results in the team event list. The score
-- is exposed only after the match workspace has reached completed state and
-- only through the existing actor-readable calendar boundary.

drop function api.list_calendar_page(uuid[],timestamptz,timestamptz,text,integer);
drop function internal.list_calendar_page_for_actor(uuid[],timestamptz,timestamptz,text,integer);

create function internal.list_calendar_page_for_actor(
  context_ids uuid[],
  range_start timestamptz,
  range_end timestamptz,
  page_cursor text,
  page_limit integer default 100
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
  event_cursor text,
  match_state text,
  score_us integer,
  score_opponent integer
)
language plpgsql stable security definer set search_path='' as $$
declare
  cursor_value text;
  cursor_starts_at timestamptz;
  cursor_event_id uuid;
begin
  if auth.uid() is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  if context_ids is null or cardinality(context_ids)=0 or cardinality(context_ids)>50
    or range_end<=range_start or range_end>range_start+interval '400 days'
    or page_limit not between 1 and 200
  then
    raise invalid_parameter_value using message='invalid_input';
  end if;
  if (select count(distinct value) from unnest(context_ids) value)<>cardinality(context_ids) then
    raise invalid_parameter_value using message='invalid_input';
  end if;
  if (
    select count(*)
    from internal.get_my_contexts_for_actor() context_row
    where context_row.context_id=any(context_ids)
  )<>cardinality(context_ids) then
    raise insufficient_privilege using message='not_found';
  end if;
  if nullif(page_cursor,'') is not null then
    begin
      cursor_value:=convert_from(decode(page_cursor,'base64'),'utf8');
      if cursor_value!~'^[^|]+\|[0-9a-fA-F-]{36}$' then
        raise invalid_text_representation;
      end if;
      cursor_starts_at:=split_part(cursor_value,'|',1)::timestamptz;
      cursor_event_id:=split_part(cursor_value,'|',2)::uuid;
    exception when others then
      raise invalid_parameter_value using message='invalid_cursor';
    end;
  end if;

  return query
  select
    event_row.id,
    event_row.club_id,
    event_row.owning_team_id,
    team.name,
    event_row.title,
    event_row.event_type,
    event_row.state,
    event_row.starts_at,
    event_row.ends_at,
    event_row.all_day,
    event_row.timezone,
    location.name,
    event_row.revision,
    encode(convert_to(event_row.starts_at::text||'|'||event_row.id::text,'utf8'),'base64'),
    workspace.state,
    case when workspace.state='completed' then projection.score_us end,
    case when workspace.state='completed' then projection.score_opponent end
  from core.events event_row
  join core.teams team
    on team.id=event_row.owning_team_id and team.club_id=event_row.club_id
  left join core.event_locations location
    on location.id=event_row.location_id and location.club_id=event_row.club_id
  left join core.match_workspaces workspace
    on workspace.event_id=event_row.id and event_row.event_type='match'
  left join core.match_projections projection
    on projection.event_id=workspace.event_id
  where event_row.archived_at is null
    and event_row.starts_at<range_end
    and event_row.ends_at>range_start
    and (cursor_starts_at is null or (event_row.starts_at,event_row.id)>(cursor_starts_at,cursor_event_id))
    and internal.actor_can_read_event(event_row.id)
    and exists(
      select 1
      from internal.get_my_contexts_for_actor() context_row
      where context_row.context_id=any(context_ids)
        and context_row.club_id=event_row.club_id
        and (
          context_row.team_id is null
          or exists(
            select 1 from core.event_teams scoped_team
            where scoped_team.event_id=event_row.id
              and scoped_team.team_id=context_row.team_id
          )
          or exists(
            select 1 from core.event_audiences scoped_audience
            where scoped_audience.event_id=event_row.id
              and (
                scoped_audience.team_id=context_row.team_id
                or scoped_audience.audience_type='club'
              )
          )
        )
    )
  order by event_row.starts_at,event_row.id
  limit page_limit;
end;
$$;

create function api.list_calendar_page(
  context_ids uuid[],
  range_start timestamptz,
  range_end timestamptz,
  page_cursor text default null,
  page_limit integer default 100
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
  event_cursor text,
  match_state text,
  score_us integer,
  score_opponent integer
)
language sql stable security invoker set search_path='' as $$
  select * from internal.list_calendar_page_for_actor(
    context_ids,
    range_start,
    range_end,
    page_cursor,
    page_limit
  );
$$;

revoke all on function
  internal.list_calendar_page_for_actor(uuid[],timestamptz,timestamptz,text,integer),
  api.list_calendar_page(uuid[],timestamptz,timestamptz,text,integer)
from public,anon,authenticated;
grant execute on function
  internal.list_calendar_page_for_actor(uuid[],timestamptz,timestamptz,text,integer),
  api.list_calendar_page(uuid[],timestamptz,timestamptz,text,integer)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260912054644_team01_calendar_match_results',
  'greenfield',
  'TEAM-01 completed match scores in actor-readable calendar projection'
);
