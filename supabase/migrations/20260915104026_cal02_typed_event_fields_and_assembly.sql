alter table core.events
  add column assembly_minutes_before integer,
  add column training_theme text,
  add column training_focus text,
  add column training_plan text,
  add column opponent_name text,
  add column home_away text,
  add column match_notes text,
  add column meeting_purpose text,
  add column meeting_agenda text;

alter table core.events
  add constraint events_assembly_minutes_before_check
    check (assembly_minutes_before between 0 and 1440),
  add constraint events_home_away_check
    check (home_away is null or home_away in ('home', 'away')),
  add constraint events_typed_text_lengths_check
    check (
      char_length(coalesce(training_theme, '')) <= 160
      and char_length(coalesce(training_focus, '')) <= 1000
      and char_length(coalesce(training_plan, '')) <= 10000
      and char_length(coalesce(opponent_name, '')) <= 160
      and char_length(coalesce(match_notes, '')) <= 10000
      and char_length(coalesce(meeting_purpose, '')) <= 1000
      and char_length(coalesce(meeting_agenda, '')) <= 10000
    );

comment on column core.events.assembly_minutes_before is
  'Editable gathering offset before starts_at. Defaults are assigned by event type in the command contract.';
comment on column core.events.training_theme is
  'Training-only short theme.';
comment on column core.events.training_focus is
  'Training-only focus description.';
comment on column core.events.training_plan is
  'Training-only session plan.';
comment on column core.events.opponent_name is
  'Match-only opponent display name.';
comment on column core.events.home_away is
  'Match-only venue side: home or away.';
comment on column core.events.match_notes is
  'Match-only preparation notes.';
comment on column core.events.meeting_purpose is
  'Meeting-only purpose.';
comment on column core.events.meeting_agenda is
  'Meeting-only agenda.';

create or replace function internal.event_snapshot(target_event core.events)
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
    'revision', target_event.revision,
    'assembly_minutes_before', target_event.assembly_minutes_before,
    'training_theme', target_event.training_theme,
    'training_focus', target_event.training_focus,
    'training_plan', target_event.training_plan,
    'opponent_name', target_event.opponent_name,
    'home_away', target_event.home_away,
    'match_notes', target_event.match_notes,
    'meeting_purpose', target_event.meeting_purpose,
    'meeting_agenda', target_event.meeting_agenda
  );
$$;

create function internal.normalized_event_type_fields(
  target_type text,
  fields jsonb,
  existing_event core.events default null
) returns jsonb language plpgsql immutable security invoker set search_path = '' as $$
declare
  assembly integer;
begin
  if fields is null or jsonb_typeof(fields) <> 'object'
    or exists (
      select 1 from jsonb_object_keys(fields) key
      where key not in (
        'assembly_minutes_before','training_theme','training_focus','training_plan',
        'opponent_name','home_away','match_notes','meeting_purpose','meeting_agenda'
      )
    ) then
    raise invalid_parameter_value using message = 'invalid_typed_fields';
  end if;

  assembly := case
    when fields ? 'assembly_minutes_before'
      then (fields ->> 'assembly_minutes_before')::integer
    when existing_event.id is not null then existing_event.assembly_minutes_before
    when target_type = 'match' then 75
    when target_type = 'meeting' then 5
    else 15
  end;
  if assembly is null or assembly not between 0 and 1440 then
    raise invalid_parameter_value using message = 'invalid_assembly';
  end if;

  if target_type = 'match' and (
    nullif(btrim(fields->>'opponent_name'),'') is null
    or coalesce(nullif(fields->>'home_away','') not in ('home','away'),true)
  ) then
    raise invalid_parameter_value using message = 'invalid_match_fields';
  end if;

  return jsonb_build_object(
    'assembly_minutes_before', assembly,
    'training_theme', case when target_type='training' then nullif(btrim(fields->>'training_theme'),'') end,
    'training_focus', case when target_type='training' then nullif(btrim(fields->>'training_focus'),'') end,
    'training_plan', case when target_type='training' then nullif(btrim(fields->>'training_plan'),'') end,
    'opponent_name', case when target_type='match' then nullif(btrim(fields->>'opponent_name'),'') end,
    'home_away', case when target_type='match' then nullif(fields->>'home_away','') end,
    'match_notes', case when target_type='match' then nullif(btrim(fields->>'match_notes'),'') end,
    'meeting_purpose', case when target_type='meeting' then nullif(btrim(fields->>'meeting_purpose'),'') end,
    'meeting_agenda', case when target_type='meeting' then nullif(btrim(fields->>'meeting_agenda'),'') end
  );
exception when invalid_text_representation then
  raise invalid_parameter_value using message = 'invalid_assembly';
end;
$$;

create function internal.create_event_v2_for_actor(
  target_club_id uuid, target_team_id uuid, new_title text, new_description text,
  new_event_type text, new_state text, new_starts_at timestamptz, new_ends_at timestamptz,
  new_all_day boolean, new_timezone text, audience_types text[], location_name text,
  recurrence_frequency text, recurrence_interval integer, recurrence_count integer,
  typed_fields jsonb, idempotency_key uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare first_event_id uuid; recurrence uuid; normalized jsonb;
begin
  normalized := internal.normalized_event_type_fields(new_event_type,coalesce(typed_fields,'{}'::jsonb));
  first_event_id := internal.create_event_for_actor(
    target_club_id,target_team_id,new_title,new_description,new_event_type,new_state,
    new_starts_at,new_ends_at,new_all_day,new_timezone,audience_types,location_name,
    recurrence_frequency,recurrence_interval,recurrence_count,idempotency_key
  );
  select recurrence_id into recurrence from core.events where id=first_event_id;
  update core.events set
    assembly_minutes_before=(normalized->>'assembly_minutes_before')::integer,
    training_theme=normalized->>'training_theme', training_focus=normalized->>'training_focus',
    training_plan=normalized->>'training_plan', opponent_name=normalized->>'opponent_name',
    home_away=normalized->>'home_away', match_notes=normalized->>'match_notes',
    meeting_purpose=normalized->>'meeting_purpose', meeting_agenda=normalized->>'meeting_agenda'
  where id=first_event_id or (recurrence is not null and recurrence_id=recurrence);
  update core.event_revisions revision set snapshot=internal.event_snapshot(event_row)
  from core.events event_row
  where revision.event_id=event_row.id and revision.event_revision=1
    and (event_row.id=first_event_id or (recurrence is not null and event_row.recurrence_id=recurrence));
  return first_event_id;
end;
$$;

create function api.create_event_v2(
  target_club_id uuid, target_team_id uuid, new_title text, new_description text,
  new_event_type text, new_state text, new_starts_at timestamptz, new_ends_at timestamptz,
  new_all_day boolean, new_timezone text, audience_types text[], location_name text default null,
  recurrence_frequency text default null, recurrence_interval integer default null,
  recurrence_count integer default null, typed_fields jsonb default '{}'::jsonb,
  idempotency_key uuid default gen_random_uuid()
) returns uuid language sql security invoker set search_path='' as $$
  select internal.create_event_v2_for_actor(
    target_club_id,target_team_id,new_title,new_description,new_event_type,new_state,
    new_starts_at,new_ends_at,new_all_day,new_timezone,audience_types,location_name,
    recurrence_frequency,recurrence_interval,recurrence_count,typed_fields,idempotency_key
  );
$$;

revoke all on function internal.normalized_event_type_fields(text,jsonb,core.events) from public,anon,authenticated;
revoke all on function internal.create_event_v2_for_actor(uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,text,text[],text,text,integer,integer,jsonb,uuid) from public,anon,authenticated;
revoke all on function api.create_event_v2(uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,text,text[],text,text,integer,integer,jsonb,uuid) from public,anon;
grant execute on function api.create_event_v2(uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,text,text[],text,text,integer,integer,jsonb,uuid) to authenticated;

create function internal.revise_event_v3_for_actor(
  target_event_id uuid, change_scope text, patch jsonb,
  expected_revision bigint, idempotency_key uuid
) returns bigint language plpgsql security definer set search_path='' as $$
declare
  anchor core.events%rowtype;
  target_type text;
  typed_fields jsonb;
  normalized jsonb;
  base_patch jsonb;
  new_revision bigint;
begin
  if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if patch is null or jsonb_typeof(patch) <> 'object' then
    raise invalid_parameter_value using message='invalid_input';
  end if;
  select * into anchor from core.events where id=target_event_id;
  if anchor.id is null or not internal.actor_can_manage_event(anchor.id) then
    raise insufficient_privilege using message='not_found';
  end if;
  target_type := case when patch?'event_type' then patch->>'event_type' else anchor.event_type end;
  typed_fields := jsonb_build_object(
    'assembly_minutes_before', coalesce(patch->'assembly_minutes_before',to_jsonb(anchor.assembly_minutes_before)),
    'training_theme', coalesce(patch->'training_theme',to_jsonb(anchor.training_theme)),
    'training_focus', coalesce(patch->'training_focus',to_jsonb(anchor.training_focus)),
    'training_plan', coalesce(patch->'training_plan',to_jsonb(anchor.training_plan)),
    'opponent_name', coalesce(patch->'opponent_name',to_jsonb(anchor.opponent_name)),
    'home_away', coalesce(patch->'home_away',to_jsonb(anchor.home_away)),
    'match_notes', coalesce(patch->'match_notes',to_jsonb(anchor.match_notes)),
    'meeting_purpose', coalesce(patch->'meeting_purpose',to_jsonb(anchor.meeting_purpose)),
    'meeting_agenda', coalesce(patch->'meeting_agenda',to_jsonb(anchor.meeting_agenda))
  );
  normalized := internal.normalized_event_type_fields(target_type,typed_fields,anchor);
  base_patch := patch - array[
    'assembly_minutes_before','training_theme','training_focus','training_plan',
    'opponent_name','home_away','match_notes','meeting_purpose','meeting_agenda'
  ];
  new_revision := internal.revise_event_v2_for_actor(
    target_event_id,change_scope,base_patch,expected_revision,idempotency_key
  );
  update core.events event_row set
    assembly_minutes_before=(normalized->>'assembly_minutes_before')::integer,
    training_theme=normalized->>'training_theme', training_focus=normalized->>'training_focus',
    training_plan=normalized->>'training_plan', opponent_name=normalized->>'opponent_name',
    home_away=normalized->>'home_away', match_notes=normalized->>'match_notes',
    meeting_purpose=normalized->>'meeting_purpose', meeting_agenda=normalized->>'meeting_agenda'
  where event_row.id=anchor.id or (
    anchor.recurrence_id is not null and event_row.recurrence_id=anchor.recurrence_id
    and (change_scope='all' or change_scope='forward' and event_row.occurrence_number>=anchor.occurrence_number)
  );
  update core.event_revisions revision set snapshot=internal.event_snapshot(event_row)
  from core.events event_row
  where revision.event_id=event_row.id and revision.event_revision=event_row.revision
    and (event_row.id=anchor.id or (
      anchor.recurrence_id is not null and event_row.recurrence_id=anchor.recurrence_id
      and (change_scope='all' or change_scope='forward' and event_row.occurrence_number>=anchor.occurrence_number)
    ));
  return new_revision;
end;
$$;

create function api.revise_event_v3(
  target_event_id uuid, change_scope text, patch jsonb,
  expected_revision bigint, idempotency_key uuid
) returns bigint language sql security invoker set search_path='' as $$
  select internal.revise_event_v3_for_actor(target_event_id,change_scope,patch,expected_revision,idempotency_key)
$$;

revoke all on function internal.revise_event_v3_for_actor(uuid,text,jsonb,bigint,uuid) from public,anon,authenticated;
revoke all on function api.revise_event_v3(uuid,text,jsonb,bigint,uuid) from public,anon;
grant execute on function api.revise_event_v3(uuid,text,jsonb,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260915104026_cal02_typed_event_fields_and_assembly','greenfield','CAL-02 typed event fields and gathering time');
notify pgrst,'reload schema';
