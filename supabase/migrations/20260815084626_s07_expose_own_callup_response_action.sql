create or replace function internal.get_event_squad_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype; squad core.squad_revisions%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(target_event_id) then raise insufficient_privilege using message='not_found'; end if;
 select * into squad from core.squad_revisions where event_id=target_event_id order by revision desc limit 1;
 return jsonb_build_object(
  'event_id',target_event_id,'squad_revision_id',squad.id,'squad_revision',squad.revision,'squad_state',coalesce(squad.state,'empty'),
  'members',coalesce((select jsonb_agg(jsonb_build_object('person_id',member.club_person_id,'name',person.display_name,'selection_state',member.selection_state,'source',member.source) order by person.display_name) from core.squad_members member join core.club_people person on person.id=member.club_person_id where member.squad_revision_id=squad.id),'[]'::jsonb),
  'callups',coalesce((select jsonb_agg(jsonb_build_object('callup_id',callup.id,'person_id',callup.club_person_id,'name',person.display_name,'state',callup.state,'revision',callup.revision,'expires_at',callup.expires_at,'delivery_state',coalesce(outbox.state,'pending'),'can_respond',exists(select 1 from core.person_account_links link where link.profile_id=auth.uid() and link.club_id=callup.club_id and link.club_person_id=callup.club_person_id and link.state='active')) order by person.display_name) from core.callups callup join core.club_people person on person.id=callup.club_person_id left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id order by created_at desc limit 1)outbox on true where callup.event_id=target_event_id),'[]'::jsonb),
  'attendance',coalesce((select jsonb_agg(jsonb_build_object('person_id',callup.club_person_id,'name',person.display_name,'status',coalesce(attendance.status,'unknown'),'minutes',attendance.minutes,'revision',coalesce(attendance.revision,0)) order by person.display_name) from core.callups callup join core.club_people person on person.id=callup.club_person_id left join core.attendance_facts attendance on attendance.event_id=callup.event_id and attendance.club_person_id=callup.club_person_id where callup.event_id=target_event_id and callup.state<>'cancelled'),'[]'::jsonb),
  'caller_actions',case when internal.actor_can_manage_squad(target_event_id) then array['save_squad','lock_squad','send_callups','cancel_callup','remind_callup']::text[] else array[]::text[] end || case when internal.actor_can_manage_attendance(target_event_id) then array['record_attendance']::text[] else array[]::text[] end
 );
end; $$;

revoke all on function internal.get_event_squad_for_actor(uuid) from public,anon;
grant execute on function internal.get_event_squad_for_actor(uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815084626_s07_expose_own_callup_response_action','greenfield','S07 physical verification: self-service callup response');

notify pgrst,'reload schema';
