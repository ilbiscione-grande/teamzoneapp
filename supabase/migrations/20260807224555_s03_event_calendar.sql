-- S03 greenfield event/calendar aggregate. Teamzone6 is not a source or target.

create table core.recurrence_rules (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  timezone text not null check (length(btrim(timezone)) between 1 and 80),
  frequency text not null check (frequency in ('daily', 'weekly')),
  interval_value integer not null default 1 check (interval_value between 1 and 52),
  local_start timestamp not null,
  occurrence_count integer check (occurrence_count between 2 and 104),
  until_local_date date,
  state text not null default 'active' check (state in ('active', 'ended')),
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  check ((occurrence_count is null) <> (until_local_date is null))
);

create table core.event_locations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  name text not null check (length(btrim(name)) between 1 and 160),
  address text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  check ((latitude is null) = (longitude is null)),
  check (latitude is null or latitude between -90 and 90),
  check (longitude is null or longitude between -180 and 180)
);

create table core.events (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  owning_team_id uuid not null,
  recurrence_id uuid,
  occurrence_number integer,
  occurrence_key text,
  event_type text not null check (event_type in ('training', 'match', 'meeting', 'activity')),
  title text not null check (length(btrim(title)) between 1 and 160),
  description text,
  state text not null default 'draft' check (state in ('draft', 'scheduled', 'cancelled', 'completed')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  all_day boolean not null default false,
  timezone text not null check (length(btrim(timezone)) between 1 and 80),
  location_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  unique (id, club_id, owning_team_id),
  unique (recurrence_id, occurrence_key),
  foreign key (owning_team_id, club_id) references core.teams(id, club_id),
  foreign key (recurrence_id, club_id) references core.recurrence_rules(id, club_id),
  foreign key (location_id, club_id) references core.event_locations(id, club_id),
  check (ends_at > starts_at),
  check (
    (recurrence_id is null and occurrence_number is null and occurrence_key is null)
    or
    (recurrence_id is not null and occurrence_number is not null and occurrence_number > 0 and occurrence_key is not null)
  )
);

create table core.event_teams (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  event_id uuid not null,
  team_id uuid not null,
  relation text not null check (relation in ('primary', 'shared')),
  capabilities text[] not null default array[]::text[],
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (event_id, team_id),
  foreign key (event_id, club_id) references core.events(id, club_id) on delete cascade,
  foreign key (team_id, club_id) references core.teams(id, club_id),
  check (capabilities <@ array['view', 'manage_roster', 'co_manage']::text[]),
  check (relation <> 'primary' or capabilities @> array['view', 'co_manage']::text[])
);

create unique index event_teams_one_primary_idx
  on core.event_teams(event_id) where relation = 'primary';

create table core.event_audiences (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  event_id uuid not null,
  audience_type text not null check (audience_type in ('players', 'leaders', 'guardians', 'club')),
  team_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  unique (event_id, audience_type, team_id),
  foreign key (event_id, club_id) references core.events(id, club_id) on delete cascade,
  foreign key (team_id, club_id) references core.teams(id, club_id),
  check ((audience_type = 'club' and team_id is null) or (audience_type <> 'club' and team_id is not null))
);

create table core.event_revisions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  event_id uuid not null,
  event_revision bigint not null check (event_revision > 0),
  action text not null check (action in ('created', 'revised', 'transitioned')),
  scope text not null check (scope in ('one', 'forward', 'all')),
  snapshot jsonb not null,
  actor_profile_id uuid not null references core.profiles(id),
  reason text,
  created_at timestamptz not null default now(),
  unique (event_id, event_revision),
  foreign key (event_id, club_id) references core.events(id, club_id) on delete cascade
);

create table internal.domain_outbox (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  event_type text not null check (event_type ~ '^[a-z]+\.[a-z_]+\.[a-z_]+\.v[0-9]+$'),
  aggregate_type text not null,
  aggregate_id uuid not null,
  aggregate_revision bigint not null check (aggregate_revision > 0),
  payload jsonb not null default '{}'::jsonb,
  state text not null default 'pending' check (state in ('pending', 'processing', 'delivered', 'failed', 'dead_letter')),
  created_at timestamptz not null default now(),
  unique (event_type, aggregate_id, aggregate_revision)
);

create index events_calendar_idx on core.events(starts_at, id) where state <> 'cancelled';
create index events_club_time_idx on core.events(club_id, starts_at, id);
create index events_owner_time_idx on core.events(owning_team_id, starts_at, id);
create index event_teams_team_idx on core.event_teams(team_id, event_id);
create index event_audiences_team_idx on core.event_audiences(team_id, event_id);
create index event_revisions_event_idx on core.event_revisions(event_id, event_revision desc);
create index domain_outbox_pending_idx on internal.domain_outbox(state, created_at) where state in ('pending', 'failed');

create function internal.event_snapshot(target_event core.events)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'id', target_event.id,
    'club_id', target_event.club_id,
    'owning_team_id', target_event.owning_team_id,
    'recurrence_id', target_event.recurrence_id,
    'occurrence_number', target_event.occurrence_number,
    'event_type', target_event.event_type,
    'title', target_event.title,
    'description', target_event.description,
    'state', target_event.state,
    'starts_at', target_event.starts_at,
    'ends_at', target_event.ends_at,
    'all_day', target_event.all_day,
    'timezone', target_event.timezone,
    'location_id', target_event.location_id,
    'revision', target_event.revision
  );
$$;

create function internal.actor_can_read_event(target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from core.events event_row
    join core.event_teams event_team on event_team.event_id = event_row.id and event_team.club_id = event_row.club_id
    join core.person_account_links link on link.profile_id = auth.uid() and link.club_id = event_row.club_id and link.state = 'active'
    join core.assignments assignment on assignment.club_person_id = link.club_person_id and assignment.club_id = link.club_id
    where event_row.id = target_event_id
      and assignment.state = 'active' and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
      and (
        assignment.team_id = event_team.team_id
        or exists (
          select 1 from core.event_audiences audience
          where audience.event_id = event_row.id and audience.club_id = event_row.club_id
            and (audience.team_id = assignment.team_id or audience.audience_type = 'club')
            and (
              audience.audience_type = 'club'
              or audience.audience_type = 'players' and assignment.role_package in ('player', 'guest')
              or audience.audience_type = 'leaders' and assignment.role_package in ('leader', 'club_functionary')
              or audience.audience_type = 'guardians' and assignment.role_package = 'guardian'
            )
        )
      )
  );
$$;

create function internal.actor_can_manage_event(target_event_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from core.events event_row
    join core.event_teams event_team on event_team.event_id = event_row.id and event_team.club_id = event_row.club_id
    where event_row.id = target_event_id
      and (
        (event_team.relation = 'primary' and internal.actor_has_capability(event_row.club_id, event_team.team_id, 'event.manage'))
        or
        (event_team.relation = 'shared' and event_team.capabilities @> array['co_manage']::text[] and internal.actor_has_capability(event_row.club_id, event_team.team_id, 'event.manage'))
      )
  );
$$;

create function internal.assert_event_primary_team()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target_event_id uuid := coalesce(new.event_id, old.event_id);
begin
  if not exists (
    select 1 from core.events event_row
    join core.event_teams event_team
      on event_team.event_id = event_row.id and event_team.club_id = event_row.club_id
     and event_team.team_id = event_row.owning_team_id and event_team.relation = 'primary'
    where event_row.id = target_event_id
  ) then
    raise check_violation using message = 'event_primary_team_required';
  end if;
  return null;
end;
$$;

create constraint trigger event_primary_team_guard
after insert or update or delete on core.event_teams
deferrable initially deferred for each row execute function internal.assert_event_primary_team();

create function internal.list_calendar_for_actor(
  context_ids uuid[], range_start timestamptz, range_end timestamptz, page_limit integer default 100
)
returns table(
  event_id uuid, club_id uuid, owning_team_id uuid, team_name text, title text, event_type text,
  state text, starts_at timestamptz, ends_at timestamptz, all_day boolean, timezone text,
  location_name text, revision bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if context_ids is null or cardinality(context_ids) = 0 or cardinality(context_ids) > 50
     or range_end <= range_start or range_end > range_start + interval '400 days'
     or page_limit not between 1 and 200
  then raise invalid_parameter_value using message = 'invalid_input'; end if;
  if (select count(distinct value) from unnest(context_ids) value) <> cardinality(context_ids)
  then raise invalid_parameter_value using message = 'invalid_input'; end if;
  if (select count(*) from internal.get_my_contexts_for_actor() context_row where context_row.context_id = any(context_ids)) <> cardinality(context_ids)
  then raise insufficient_privilege using message = 'not_found'; end if;

  return query
  select distinct on (event_row.id)
    event_row.id, event_row.club_id, event_row.owning_team_id, team.name, event_row.title,
    event_row.event_type, event_row.state, event_row.starts_at, event_row.ends_at,
    event_row.all_day, event_row.timezone, location.name, event_row.revision
  from core.events event_row
  join core.teams team on team.id = event_row.owning_team_id and team.club_id = event_row.club_id
  left join core.event_locations location on location.id = event_row.location_id and location.club_id = event_row.club_id
  where event_row.starts_at < range_end and event_row.ends_at > range_start
    and internal.actor_can_read_event(event_row.id)
    and exists (
      select 1 from internal.get_my_contexts_for_actor() context_row
      where context_row.context_id = any(context_ids)
        and context_row.club_id = event_row.club_id
        and (context_row.team_id is null or exists (
          select 1 from core.event_teams scoped_team where scoped_team.event_id = event_row.id and scoped_team.team_id = context_row.team_id
        ) or exists (
          select 1 from core.event_audiences scoped_audience where scoped_audience.event_id = event_row.id
            and (scoped_audience.team_id = context_row.team_id or scoped_audience.audience_type = 'club')
        ))
    )
  order by event_row.id, event_row.starts_at, event_row.id
  limit page_limit;
end;
$$;

create function internal.get_event_details_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare event_row core.events%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into event_row from core.events where id = target_event_id;
  if event_row.id is null or not internal.actor_can_read_event(event_row.id)
  then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.event_snapshot(event_row) || jsonb_build_object(
    'location', (select to_jsonb(location) - 'created_by' from core.event_locations location where location.id = event_row.location_id),
    'teams', coalesce((select jsonb_agg(jsonb_build_object('team_id', team.id, 'name', team.name, 'relation', relation.relation, 'capabilities', relation.capabilities) order by relation.relation, team.name) from core.event_teams relation join core.teams team on team.id = relation.team_id and team.club_id = relation.club_id where relation.event_id = event_row.id), '[]'::jsonb),
    'audiences', coalesce((select jsonb_agg(jsonb_build_object('type', audience.audience_type, 'team_id', audience.team_id) order by audience.audience_type, audience.team_id) from core.event_audiences audience where audience.event_id = event_row.id), '[]'::jsonb),
    'caller_actions', case when internal.actor_can_manage_event(event_row.id)
      then array['revise', 'cancel', 'complete']::text[] else array[]::text[] end
  );
end;
$$;

create function internal.create_event_for_actor(
  target_club_id uuid, target_team_id uuid, new_title text, new_description text,
  new_event_type text, new_state text, new_starts_at timestamptz, new_ends_at timestamptz,
  new_all_day boolean, new_timezone text, audience_types text[], location_name text,
  recurrence_frequency text, recurrence_interval integer, recurrence_count integer,
  idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); new_event_id uuid; new_recurrence_id uuid; new_location_id uuid; existing_result jsonb;
declare occurrence_index integer; occurrence_start timestamptz; occurrence_end timestamptz; duration_value interval;
declare effective_count integer := coalesce(recurrence_count, 1);
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id, target_team_id, 'event.manage')
  then raise insufficient_privilege using message = 'not_found'; end if;
  if not exists(select 1 from core.teams where id = target_team_id and club_id = target_club_id and status = 'active')
     or length(btrim(new_title)) not between 1 and 160 or new_ends_at <= new_starts_at
     or new_event_type not in ('training','match','meeting','activity') or new_state not in ('draft','scheduled')
     or length(btrim(new_timezone)) not between 1 and 80
     or audience_types is null or cardinality(audience_types) = 0
     or exists(select 1 from unnest(audience_types) value where value not in ('players','leaders','guardians','club'))
     or (recurrence_frequency is not null and (recurrence_frequency not in ('daily','weekly') or recurrence_interval not between 1 and 52 or recurrence_count not between 2 and 104))
  then raise invalid_parameter_value using message = 'invalid_input'; end if;
  select result into existing_result from internal.command_deduplication
    where actor_profile_id = actor_id and command_type = 'event.event.create.v1'
      and internal.command_deduplication.idempotency_key = create_event_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'event_id')::uuid; end if;

  if nullif(btrim(location_name), '') is not null then
    insert into core.event_locations(club_id,name,created_by) values(target_club_id,btrim(location_name),actor_id) returning id into new_location_id;
  end if;
  if recurrence_frequency is not null then
    insert into core.recurrence_rules(club_id,timezone,frequency,interval_value,local_start,occurrence_count,created_by)
    values(target_club_id,new_timezone,recurrence_frequency,recurrence_interval,new_starts_at at time zone new_timezone,recurrence_count,actor_id)
    returning id into new_recurrence_id;
  end if;

  duration_value := new_ends_at - new_starts_at;
  for occurrence_index in 1..effective_count loop
    occurrence_start := case
      when recurrence_frequency = 'daily' then ((new_starts_at at time zone new_timezone) + make_interval(days => (occurrence_index - 1) * recurrence_interval)) at time zone new_timezone
      when recurrence_frequency = 'weekly' then ((new_starts_at at time zone new_timezone) + make_interval(days => (occurrence_index - 1) * recurrence_interval * 7)) at time zone new_timezone
      else new_starts_at end;
    occurrence_end := occurrence_start + duration_value;
    insert into core.events(club_id,owning_team_id,recurrence_id,occurrence_number,occurrence_key,event_type,title,description,state,starts_at,ends_at,all_day,timezone,location_id,created_by)
    values(target_club_id,target_team_id,new_recurrence_id,case when new_recurrence_id is null then null else occurrence_index end,case when new_recurrence_id is null then null else occurrence_index::text end,new_event_type,btrim(new_title),nullif(btrim(new_description),''),new_state,occurrence_start,occurrence_end,new_all_day,new_timezone,new_location_id,actor_id)
    returning id into new_event_id;
    insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
    values(target_club_id,new_event_id,target_team_id,'primary',array['view','co_manage'],actor_id);
    insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
    select target_club_id,new_event_id,value,case when value='club' then null else target_team_id end,actor_id from unnest(audience_types) value;
    insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id)
    select target_club_id,new_event_id,1,'created',case when new_recurrence_id is null then 'one' else 'all' end,internal.event_snapshot(event_row),actor_id from core.events event_row where event_row.id=new_event_id;
    insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
    values(target_club_id,actor_id,'event.event.create.v1','event',new_event_id,1,jsonb_build_object('recurrence_id',new_recurrence_id));
    insert into internal.domain_outbox(club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload)
    values(target_club_id,'event.event.created.v1','event',new_event_id,1,jsonb_build_object('starts_at',occurrence_start));
    if occurrence_index = 1 then
      insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
      values(actor_id,idempotency_key,'event.event.create.v1',jsonb_build_object('event_id',new_event_id));
    end if;
  end loop;
  return (select (result->>'event_id')::uuid from internal.command_deduplication where actor_profile_id=actor_id and internal.command_deduplication.idempotency_key=create_event_for_actor.idempotency_key and command_type='event.event.create.v1');
end;
$$;

create function internal.revise_event_for_actor(target_event_id uuid, change_scope text, patch jsonb, expected_revision bigint, idempotency_key uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); anchor core.events%rowtype; target core.events%rowtype; new_revision bigint; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='event.event.revise.v1' and internal.command_deduplication.idempotency_key=revise_event_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
  select * into anchor from core.events where id=target_event_id for update;
  if anchor.id is null or not internal.actor_can_manage_event(anchor.id) then raise insufficient_privilege using message='not_found'; end if;
  if anchor.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if change_scope not in ('one','forward','all') or (anchor.recurrence_id is null and change_scope<>'one')
     or exists(select 1 from jsonb_object_keys(patch) key where key not in ('title','description','starts_at','ends_at','location_id'))
  then raise invalid_parameter_value using message='invalid_input'; end if;

  for target in select * from core.events event_row where event_row.id=anchor.id or (anchor.recurrence_id is not null and event_row.recurrence_id=anchor.recurrence_id and (change_scope='all' or change_scope='forward' and event_row.occurrence_number>=anchor.occurrence_number)) order by event_row.occurrence_number nulls first for update loop
    update core.events set
      title=coalesce(nullif(btrim(patch->>'title'),''),title),
      description=case when patch ? 'description' then nullif(btrim(patch->>'description'),'') else description end,
      starts_at=case when patch ? 'starts_at' then (patch->>'starts_at')::timestamptz else starts_at end,
      ends_at=case when patch ? 'ends_at' then (patch->>'ends_at')::timestamptz else ends_at end,
      location_id=case when patch ? 'location_id' then (patch->>'location_id')::uuid else location_id end,
      updated_at=now(), revision=revision+1
    where id=target.id returning revision into new_revision;
    insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id)
    select target.club_id,target.id,new_revision,'revised',change_scope,internal.event_snapshot(event_row),actor_id from core.events event_row where event_row.id=target.id;
    insert into internal.domain_outbox(club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload) values(target.club_id,'event.event.revised.v1','event',target.id,new_revision,jsonb_build_object('scope',change_scope));
  end loop;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'event.event.revise.v1',jsonb_build_object('revision',new_revision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata) values(anchor.club_id,actor_id,'event.event.revise.v1','event',anchor.id,new_revision,jsonb_build_object('scope',change_scope));
  return new_revision;
end;
$$;

create function internal.transition_event_for_actor(target_event_id uuid, target_state text, expected_revision bigint, reason text, idempotency_key uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); event_row core.events%rowtype; new_revision bigint; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing_result from internal.command_deduplication where actor_profile_id=actor_id and command_type='event.event.transition.v1' and internal.command_deduplication.idempotency_key=transition_event_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
  select * into event_row from core.events where id=target_event_id for update;
  if event_row.id is null or not internal.actor_can_manage_event(event_row.id) then raise insufficient_privilege using message='not_found'; end if;
  if event_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
  if not ((event_row.state='draft' and target_state in ('scheduled','cancelled')) or (event_row.state='scheduled' and target_state in ('cancelled','completed')) or (event_row.state='cancelled' and target_state='scheduled'))
  then raise check_violation using message='invalid_transition'; end if;
  update core.events set state=target_state,updated_at=now(),revision=revision+1 where id=event_row.id returning revision into new_revision;
  insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id,reason)
  select event_row.club_id,event_row.id,new_revision,'transitioned','one',internal.event_snapshot(current_row),actor_id,nullif(btrim(reason),'') from core.events current_row where current_row.id=event_row.id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'event.event.transition.v1',jsonb_build_object('revision',new_revision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason) values(event_row.club_id,actor_id,'event.event.transition.v1','event',event_row.id,new_revision,nullif(btrim(reason),''));
  insert into internal.domain_outbox(club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload) values(event_row.club_id,'event.event.transitioned.v1','event',event_row.id,new_revision,jsonb_build_object('state',target_state));
  return new_revision;
end;
$$;

alter table core.recurrence_rules enable row level security;
alter table core.event_locations enable row level security;
alter table core.events enable row level security;
alter table core.event_teams enable row level security;
alter table core.event_audiences enable row level security;
alter table core.event_revisions enable row level security;

create policy recurrence_rules_select_event_access on core.recurrence_rules for select to authenticated using (exists(select 1 from core.events event_row where event_row.recurrence_id=recurrence_rules.id and internal.actor_can_read_event(event_row.id)));
create policy event_locations_select_event_access on core.event_locations for select to authenticated using (exists(select 1 from core.events event_row where event_row.location_id=event_locations.id and internal.actor_can_read_event(event_row.id)));
create policy events_select_relation on core.events for select to authenticated using ((select internal.actor_can_read_event(id)));
create policy event_teams_select_event_access on core.event_teams for select to authenticated using ((select internal.actor_can_read_event(event_id)));
create policy event_audiences_select_event_access on core.event_audiences for select to authenticated using ((select internal.actor_can_read_event(event_id)));
create policy event_revisions_select_event_access on core.event_revisions for select to authenticated using ((select internal.actor_can_read_event(event_id)));

revoke all on all tables in schema core, internal from public, anon, authenticated;
revoke all on all sequences in schema core, internal from public, anon, authenticated;
revoke all on function internal.event_snapshot(core.events), internal.actor_can_read_event(uuid), internal.actor_can_manage_event(uuid), internal.assert_event_primary_team(), internal.list_calendar_for_actor(uuid[],timestamptz,timestamptz,integer), internal.get_event_details_for_actor(uuid), internal.create_event_for_actor(uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,text,text[],text,text,integer,integer,uuid), internal.revise_event_for_actor(uuid,text,jsonb,bigint,uuid), internal.transition_event_for_actor(uuid,text,bigint,text,uuid) from public, anon, authenticated;
grant execute on function internal.list_calendar_for_actor(uuid[],timestamptz,timestamptz,integer), internal.get_event_details_for_actor(uuid), internal.create_event_for_actor(uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,text,text[],text,text,integer,integer,uuid), internal.revise_event_for_actor(uuid,text,jsonb,bigint,uuid), internal.transition_event_for_actor(uuid,text,bigint,text,uuid) to authenticated;

create function api.list_calendar(context_ids uuid[],range_start timestamptz,range_end timestamptz,page_limit integer default 100)
returns table(event_id uuid,club_id uuid,owning_team_id uuid,team_name text,title text,event_type text,state text,starts_at timestamptz,ends_at timestamptz,all_day boolean,timezone text,location_name text,revision bigint)
language sql stable security invoker set search_path='' as $$ select * from internal.list_calendar_for_actor(context_ids,range_start,range_end,page_limit); $$;
create function api.get_event_details(target_event_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select internal.get_event_details_for_actor(target_event_id); $$;
create function api.create_event(target_club_id uuid,target_team_id uuid,new_title text,new_description text,new_event_type text,new_state text,new_starts_at timestamptz,new_ends_at timestamptz,new_all_day boolean,new_timezone text,audience_types text[],location_name text default null,recurrence_frequency text default null,recurrence_interval integer default null,recurrence_count integer default null,idempotency_key uuid default gen_random_uuid()) returns uuid language sql security invoker set search_path='' as $$ select internal.create_event_for_actor(target_club_id,target_team_id,new_title,new_description,new_event_type,new_state,new_starts_at,new_ends_at,new_all_day,new_timezone,audience_types,location_name,recurrence_frequency,recurrence_interval,recurrence_count,idempotency_key); $$;
create function api.revise_event(target_event_id uuid,change_scope text,patch jsonb,expected_revision bigint,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$ select internal.revise_event_for_actor(target_event_id,change_scope,patch,expected_revision,idempotency_key); $$;
create function api.transition_event(target_event_id uuid,target_state text,expected_revision bigint,reason text,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$ select internal.transition_event_for_actor(target_event_id,target_state,expected_revision,reason,idempotency_key); $$;

revoke all on function api.list_calendar(uuid[],timestamptz,timestamptz,integer), api.get_event_details(uuid), api.create_event(uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,text,text[],text,text,integer,integer,uuid), api.revise_event(uuid,text,jsonb,bigint,uuid), api.transition_event(uuid,text,bigint,text,uuid) from public, anon;
grant execute on function api.list_calendar(uuid[],timestamptz,timestamptz,integer), api.get_event_details(uuid), api.create_event(uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,text,text[],text,text,integer,integer,uuid), api.revise_event(uuid,text,jsonb,bigint,uuid), api.transition_event(uuid,text,bigint,text,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260807224555_s03_event_calendar','greenfield',null);

notify pgrst, 'reload schema';
