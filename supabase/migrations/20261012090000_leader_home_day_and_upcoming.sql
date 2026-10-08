-- Hem for leaders follows the day: one card for what is happening now or
-- next, the rest of today, then the coming days. The home projection now
-- carries the leader's own callup on every listed event (so it can be
-- answered right there) and a short list of upcoming events.
--
-- The existing projection is kept as get_leader_home_base_for_actor and
-- extended here; later patches to the task list belong in the base.

create or replace function internal.home_my_callup(target_event_id uuid,target_person_id uuid,observed_at timestamptz)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('callup_id',callup.id,'state',callup.state,'revision',callup.revision,
  'expires_at',callup.expires_at,
  'can_respond',callup.state in('pending','accepted','declined') and callup.expires_at>observed_at)
 from core.callups callup
 where target_person_id is not null and callup.event_id=target_event_id
  and callup.club_person_id=target_person_id and callup.state<>'cancelled'
 order by callup.created_at desc limit 1
$$;

alter function internal.get_leader_home_for_actor(uuid) rename to get_leader_home_base_for_actor;

create function internal.get_leader_home_for_actor(target_context_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 base jsonb := internal.get_leader_home_base_for_actor(target_context_id);
 context_row record;
 my_person_id uuid;
 observed_at timestamptz := statement_timestamp();
begin
 select * into context_row from internal.get_my_contexts_for_actor() where context_id=target_context_id;
 select link.club_person_id into my_person_id from core.person_account_links link
 where link.profile_id=auth.uid() and link.club_id=context_row.club_id and link.state='active' limit 1;
 return base || jsonb_build_object(
  'today_events',coalesce((
   select jsonb_agg(item.value||jsonb_build_object('my_callup',
     internal.home_my_callup((item.value->>'event_id')::uuid,my_person_id,observed_at)) order by item.ordinality)
   from jsonb_array_elements(base->'today_events') with ordinality item),'[]'::jsonb),
  'upcoming_events',coalesce((
   select jsonb_agg(row_value order by starts_at,event_id) from(
    select event_row.id event_id,event_row.title,event_row.event_type,event_row.state,event_row.starts_at,event_row.ends_at,
     internal.event_place_label(location.name,location.pitch) location_name,location.address,
     internal.home_my_callup(event_row.id,my_person_id,observed_at) my_callup
    from core.events event_row
    join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
    left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
    where event_row.club_id=context_row.club_id and relation.team_id=context_row.team_id
     and event_row.state='scheduled' and event_row.archived_at is null
     and (event_row.starts_at at time zone event_row.timezone)::date>(observed_at at time zone event_row.timezone)::date
     and event_row.starts_at<observed_at+interval '14 days'
    order by event_row.starts_at,event_row.id limit 6) row_value),'[]'::jsonb));
end$$;

revoke all on function internal.home_my_callup(uuid,uuid,timestamptz),internal.get_leader_home_for_actor(uuid)
 from public,anon,authenticated;
grant execute on function internal.home_my_callup(uuid,uuid,timestamptz),internal.get_leader_home_for_actor(uuid)
 to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261012090000_leader_home_day_and_upcoming','greenfield',
  'Leader home: own callup on today''s events and upcoming events');
notify pgrst,'reload schema';
