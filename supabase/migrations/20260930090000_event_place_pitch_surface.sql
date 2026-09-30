-- CAL-12: an event's place is a facility plus an optional pitch and an
-- optional surface, all free text. The whole combination is one saved place
-- (core.event_locations), so it can be picked again as a unit. Lists and
-- home views show "Facility · Pitch"; the event itself carries all three.

alter table core.event_locations
  add column if not exists pitch text,
  add column if not exists surface text;
alter table core.event_locations
  add constraint event_locations_pitch_length check (pitch is null or length(pitch) between 1 and 80),
  add constraint event_locations_surface_length check (surface is null or length(surface) between 1 and 80);

create or replace function internal.event_place_label(place_name text,place_pitch text)
returns text language sql immutable set search_path='' as $$
  select nullif(concat_ws(' · ',nullif(btrim(place_name),''),nullif(btrim(place_pitch),'')),'')
$$;

-- Finds the club's saved place with exactly this facility, pitch and surface
-- (case-insensitive), or saves it.
create or replace function internal.resolve_event_place(target_club_id uuid,place_name text,
 place_pitch text,place_surface text,actor_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare normalized_name text:=nullif(btrim(place_name),'');
 normalized_pitch text:=nullif(btrim(place_pitch),''); normalized_surface text:=nullif(btrim(place_surface),'');
 place_id uuid;
begin
 if normalized_name is null then return null; end if;
 if length(normalized_name)>160 or length(normalized_pitch)>80 or length(normalized_surface)>80 then
  raise invalid_parameter_value using message='invalid_input';
 end if;
 select location.id into place_id from core.event_locations location
 where location.club_id=target_club_id and lower(btrim(location.name))=lower(normalized_name)
  and lower(coalesce(location.pitch,''))=lower(coalesce(normalized_pitch,''))
  and lower(coalesce(location.surface,''))=lower(coalesce(normalized_surface,''))
 order by location.created_at desc limit 1;
 if place_id is null then
  insert into core.event_locations(club_id,name,pitch,surface,created_by)
  values(target_club_id,normalized_name,normalized_pitch,normalized_surface,actor_id) returning id into place_id;
 end if;
 return place_id;
end$$;

-- Create: pitch and surface travel in typed_fields next to the other extras.
create or replace function internal.create_event_v2_for_actor(target_club_id uuid, target_team_id uuid, new_title text, new_description text, new_event_type text, new_state text, new_starts_at timestamp with time zone, new_ends_at timestamp with time zone, new_all_day boolean, new_timezone text, audience_types text[], location_name text, recurrence_frequency text, recurrence_interval integer, recurrence_count integer, typed_fields jsonb, idempotency_key uuid)
 returns uuid language plpgsql security definer set search_path='' as $function$
declare first_event_id uuid; recurrence uuid; normalized jsonb; place_id uuid;
 place_pitch text:=nullif(btrim(coalesce(typed_fields,'{}'::jsonb)->>'location_pitch'),'');
 place_surface text:=nullif(btrim(coalesce(typed_fields,'{}'::jsonb)->>'location_surface'),'');
begin
  normalized := internal.normalized_event_type_fields(new_event_type,
    coalesce(typed_fields,'{}'::jsonb)-array['location_pitch','location_surface']);
  first_event_id := internal.create_event_for_actor(
    target_club_id,target_team_id,new_title,new_description,new_event_type,new_state,
    -- The place is resolved below as a whole combination, so the base
    -- command does not save a name-only place of its own.
    new_starts_at,new_ends_at,new_all_day,new_timezone,audience_types,null,
    recurrence_frequency,recurrence_interval,recurrence_count,idempotency_key
  );
  select recurrence_id into recurrence from core.events where id=first_event_id;
  if nullif(btrim(location_name),'') is not null then
    place_id := internal.resolve_event_place(target_club_id,location_name,place_pitch,place_surface,auth.uid());
  end if;
  update core.events set
    location_id=case when place_id is null then location_id else place_id end,
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
$function$;

-- Revise: location_pitch/location_surface in the patch; unspecified parts
-- keep the event's current value.
create or replace function internal.revise_event_v3_for_actor(target_event_id uuid, change_scope text, patch jsonb, expected_revision bigint, idempotency_key uuid)
 returns bigint language plpgsql security definer set search_path='' as $function$
declare
  anchor core.events%rowtype;
  current_place core.event_locations%rowtype;
  target_type text;
  typed_fields jsonb;
  normalized jsonb;
  base_patch jsonb;
  new_revision bigint;
  place_changed boolean;
  place_id uuid;
begin
  if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if patch is null or jsonb_typeof(patch) <> 'object' then
    raise invalid_parameter_value using message='invalid_input';
  end if;
  select * into anchor from core.events where id=target_event_id;
  if anchor.id is null or not internal.actor_can_manage_event(anchor.id) then
    raise insufficient_privilege using message='not_found';
  end if;
  select * into current_place from core.event_locations where id=anchor.location_id;
  place_changed := patch?'location_name' or patch?'location_pitch' or patch?'location_surface';
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
    'opponent_name','home_away','match_notes','meeting_purpose','meeting_agenda',
    'location_name','location_pitch','location_surface'
  ];
  new_revision := internal.revise_event_v2_for_actor(
    target_event_id,change_scope,base_patch,expected_revision,idempotency_key
  );
  if place_changed then
    place_id := internal.resolve_event_place(anchor.club_id,
      case when patch?'location_name' then patch->>'location_name' else current_place.name end,
      case when patch?'location_pitch' then patch->>'location_pitch' else current_place.pitch end,
      case when patch?'location_surface' then patch->>'location_surface' else current_place.surface end,
      auth.uid());
  end if;
  update core.events event_row set
    location_id=case when place_changed then place_id else event_row.location_id end,
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
$function$;

-- Saved places as whole combinations, most recently used first.
create or replace function internal.list_saved_event_places_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'event.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 return coalesce((
  select jsonb_agg(jsonb_build_object('name',place.name,'pitch',place.pitch,'surface',place.surface)
   order by place.last_used desc)
  from (
   -- One entry per combination (older events created a row per event),
   -- spelled as most recently saved, ranked by latest use.
   select (array_agg(location.name order by location.created_at desc))[1] as name,
    (array_agg(location.pitch order by location.created_at desc))[1] as pitch,
    (array_agg(location.surface order by location.created_at desc))[1] as surface,
    max(greatest(location.created_at,coalesce(used.last_event,location.created_at))) as last_used
   from core.event_locations location
   left join lateral (select max(event_row.updated_at) as last_event from core.events event_row
    where event_row.location_id=location.id) used on true
   where location.club_id=target_club_id
   group by lower(btrim(location.name)),lower(coalesce(location.pitch,'')),lower(coalesce(location.surface,''))
   order by last_used desc limit 100
  ) place
 ),'[]'::jsonb);
end$$;

create or replace function api.list_saved_event_places(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select internal.list_saved_event_places_for_actor(target_club_id,target_team_id)
$$;

-- Lists and home views show "Facility · Pitch" wherever they showed the name.
do $patch$
declare fn text; def text; patched text;
begin
 foreach fn in array array[
  'internal.list_calendar_for_actor','internal.list_calendar_page_for_actor',
  'internal.list_archived_events_for_actor','internal.get_leader_home_for_actor',
  'internal.get_player_home_for_actor','internal.get_guardian_home_for_actor'
 ] loop
  select pg_get_functiondef(p.oid) into def from pg_proc p
  where p.oid=(select min(p2.oid) from pg_proc p2 join pg_namespace n on n.oid=p2.pronamespace
   where n.nspname||'.'||p2.proname=fn);
  if def is null then raise exception 'function % not found',fn; end if;
  patched:=replace(def,'location.name','internal.event_place_label(location.name,location.pitch)');
  if patched=def then raise exception 'no place name in %',fn; end if;
  execute patched;
 end loop;
end
$patch$;

revoke all on function internal.event_place_label(text,text),
 internal.resolve_event_place(uuid,text,text,text,uuid),
 internal.list_saved_event_places_for_actor(uuid,uuid),api.list_saved_event_places(uuid,uuid)
 from public,anon,authenticated;
grant execute on function internal.event_place_label(text,text),
 internal.list_saved_event_places_for_actor(uuid,uuid),api.list_saved_event_places(uuid,uuid)
 to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260930090000_event_place_pitch_surface','greenfield',
 'CAL-12 place as facility, pitch and surface; saved as one reusable combination');
notify pgrst,'reload schema';
