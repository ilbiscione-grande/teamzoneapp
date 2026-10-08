-- Hem shows why a callup was declined ("Avböjt – Sjukdom"). The leader's
-- own callup on every listed event (including the next event) now carries
-- the decline reason of its current answer, like the player home already
-- does for own_callups/child_callups.

create or replace function internal.home_my_callup(target_event_id uuid,target_person_id uuid,observed_at timestamptz)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('callup_id',callup.id,'state',callup.state,'revision',callup.revision,
  'expires_at',callup.expires_at,
  'can_respond',callup.state in('pending','accepted','declined') and callup.expires_at>observed_at,
  'decline_reason_code',case when callup.state='declined' then reason.decline_reason_code end,
  'decline_reason_text',case when callup.state='declined' then reason.decline_reason_text end)
 from core.callups callup
 left join lateral (
  select response.decline_reason_code,response.decline_reason_text
  from core.callup_responses response
  where response.callup_id=callup.id and response.revision=callup.revision and response.response='declined'
  limit 1) reason on true
 where target_person_id is not null and callup.event_id=target_event_id
  and callup.club_person_id=target_person_id and callup.state<>'cancelled'
 order by callup.created_at desc limit 1
$$;

create or replace function internal.get_leader_home_for_actor(target_context_id uuid)
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
  'next_event',case when jsonb_typeof(base->'next_event')='object' then
   (base->'next_event')||jsonb_build_object('my_callup',
    internal.home_my_callup((base->'next_event'->>'event_id')::uuid,my_person_id,observed_at)) end,
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

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261012120000_home_callup_decline_reason','greenfield',
  'Leader home callups carry the decline reason');
notify pgrst,'reload schema';
