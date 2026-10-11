-- Monthly event series ("Varje månad"). The editor now offers Dagligen,
-- Varje vecka, Varannan vecka (weekly, interval 2) and Varje månad; the
-- "Varje N" field is gone, so the interval is always 1 except biweekly.
-- create_event_for_actor is recreated unchanged apart from 'monthly':
-- the same day of the month, clamped to the month's last day (Jan 31 →
-- Feb 28/29), in the event's own time zone.

alter table core.recurrence_rules drop constraint if exists recurrence_rules_frequency_check;
alter table core.recurrence_rules add constraint recurrence_rules_frequency_check
  check (frequency in ('daily', 'weekly', 'monthly'));

create or replace function internal.create_event_for_actor(
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
     or (recurrence_frequency is not null and (recurrence_frequency not in ('daily','weekly','monthly') or recurrence_interval not between 1 and 52 or recurrence_count not between 2 and 104))
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
      when recurrence_frequency = 'monthly' then ((new_starts_at at time zone new_timezone) + make_interval(months => (occurrence_index - 1) * recurrence_interval)) at time zone new_timezone
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

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261019090000_monthly_event_series','greenfield',
 'Monthly event series; the editor drops the free interval field');
notify pgrst,'reload schema';
