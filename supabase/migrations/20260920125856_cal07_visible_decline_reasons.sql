-- CAL-07 follow-up: expose a declined callup's reason only to actors who
-- may legitimately see it. The event squad projection intentionally does
-- not include response rows directly: callup responses contain private
-- availability information and must stay hidden from unrelated teammates.

create function internal.get_visible_decline_reasons_for_actor(target_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
 actor_id uuid:=auth.uid();
 event_row core.events%rowtype;
 can_manage boolean;
begin
 if actor_id is null then
  raise insufficient_privilege using message='unauthenticated';
 end if;

 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(target_event_id) then
  raise insufficient_privilege using message='not_found';
 end if;

 can_manage:=internal.actor_can_manage_squad(target_event_id);

 return coalesce((
  select jsonb_agg(jsonb_build_object(
   'person_id',callup.club_person_id,
   'decline_reason_code',latest_response.decline_reason_code,
   'decline_reason_text',latest_response.decline_reason_text
  ) order by callup.club_person_id)
  from core.callups callup
  join lateral(
   select response.decline_reason_code,response.decline_reason_text
   from core.callup_responses response
   where response.callup_id=callup.id
    and response.club_id=callup.club_id
    and response.response='declined'
   order by response.revision desc
   limit 1
  )latest_response on true
  where callup.event_id=target_event_id
   and callup.state='declined'
   and(
    can_manage or
    internal.actor_represents_club_person(callup.club_id,callup.club_person_id)
   )
 ),'[]'::jsonb);
end;
$$;

create or replace function api.get_event_squad(target_event_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $$
 select internal.get_event_squad_for_actor(target_event_id)||jsonb_build_object(
  'decline_reasons',internal.get_visible_decline_reasons_for_actor(target_event_id)
 )
$$;

revoke all on function internal.get_visible_decline_reasons_for_actor(uuid)
 from public,anon,authenticated;
grant execute on function internal.get_visible_decline_reasons_for_actor(uuid)
 to authenticated;
revoke all on function api.get_event_squad(uuid) from public,anon;
grant execute on function api.get_event_squad(uuid) to authenticated;

insert into internal.migration_provenance(
 migration_name,source_kind,source_reference
)values(
 '20260920125856_cal07_visible_decline_reasons','greenfield',
 'CAL-07 privacy-filtered decline reasons in event squad projection'
);

notify pgrst,'reload schema';
