-- CAL-03: expose only whether an event is shared, without leaking recipient
-- team identities into the compact calendar projection.

create function internal.list_calendar_page_v2_for_actor(
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
  score_opponent integer,
  is_shared boolean
)
language sql stable security definer set search_path='' as $$
  select page.*,
    exists(
      select 1
      from core.event_teams relation
      where relation.event_id=page.event_id
        and relation.relation='shared'
    ) as is_shared
  from internal.list_calendar_page_for_actor(
    context_ids,range_start,range_end,page_cursor,page_limit
  ) page
$$;

create function api.list_calendar_page_v2(
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
  score_opponent integer,
  is_shared boolean
)
language sql stable security invoker set search_path='' as $$
  select * from internal.list_calendar_page_v2_for_actor(
    context_ids,range_start,range_end,page_cursor,page_limit
  )
$$;

revoke all on function internal.list_calendar_page_v2_for_actor(
  uuid[],timestamptz,timestamptz,text,integer
) from public,anon,authenticated;
revoke all on function api.list_calendar_page_v2(
  uuid[],timestamptz,timestamptz,text,integer
) from public,anon;
grant execute on function internal.list_calendar_page_v2_for_actor(
  uuid[],timestamptz,timestamptz,text,integer
) to authenticated;
grant execute on function api.list_calendar_page_v2(
  uuid[],timestamptz,timestamptz,text,integer
) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260919160416_cal03_calendar_shared_marker','greenfield','CAL-03 recipient-minimized shared-event marker');
notify pgrst,'reload schema';
