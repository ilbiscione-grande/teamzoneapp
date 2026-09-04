alter table audit.attendance_revisions add column if not exists change_kind text not null default 'initial'
 check(change_kind in('initial','correction','late_correction'));
alter table audit.attendance_revisions add column if not exists correction_reason text;
do $$
begin
 if not exists(select 1 from pg_constraint where conname='attendance_revision_reason_check') then
  alter table audit.attendance_revisions add constraint attendance_revision_reason_check check(
   (change_kind='late_correction' and correction_reason is not null
    and length(btrim(correction_reason)) between 3 and 500)
   or(change_kind<>'late_correction' and correction_reason is null)
  );
 end if;
end $$;

create or replace function internal.actor_can_correct_late_attendance(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from core.events event_row join core.event_teams relation
  on relation.event_id=event_row.id and relation.club_id=event_row.club_id
  where event_row.id=target_event_id and(relation.relation='primary'
   or relation.capabilities&&array['manage_roster','co_manage']::text[])
   and internal.actor_has_capability(event_row.club_id,relation.team_id,'event.attendance.correct_late'))
$$;

create or replace function internal.record_attendance_v2_for_actor(target_event_id uuid,changes jsonb,
 correction_reason text,idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;change jsonb;person_id uuid;
 old_row core.attendance_facts%rowtype;saved_row core.attendance_facts%rowtype;new_revision bigint;
 result jsonb;count_value integer:=0;is_late boolean;change_kind_value text;reason_value text:=nullif(btrim(correction_reason),'');
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select dedupe.result into result from internal.command_deduplication dedupe where dedupe.actor_profile_id=actor_id
  and dedupe.command_type='attendance.bulk.recorded.v2'
  and dedupe.idempotency_key=record_attendance_v2_for_actor.idempotency_key;
 if result is not null then return result;end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or event_row.archived_at is not null
  or not internal.actor_can_manage_attendance(target_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 if jsonb_typeof(changes)<>'array' or jsonb_array_length(changes) not between 1 and 100
  or(select count(distinct item->>'person_id') from jsonb_array_elements(changes)item)<>jsonb_array_length(changes)
 then raise invalid_parameter_value using message='invalid_input';end if;
 is_late:=now()>event_row.ends_at+interval'24 hours';
 if is_late and(not internal.actor_can_correct_late_attendance(target_event_id)
  or reason_value is null or length(reason_value) not between 3 and 500)
 then raise insufficient_privilege using message='late_correction_not_allowed';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-attendance:'||target_event_id::text,0));
 if exists(select 1 from jsonb_array_elements(changes)item where
  item->>'status' not in('unknown','present','late','partial','absent')
  or jsonb_typeof(item->'expected_revision')<>'number'
  or coalesce(length(item->>'note'),0)>500
  or(item->>'status' in('late','partial') and(
    not(item?'minutes') or(item->>'minutes')::integer not between 1 and 1440))
  or(item->>'status' not in('late','partial') and item->>'minutes' is not null)
  or not exists(select 1 from core.callups callup where callup.event_id=target_event_id
    and callup.club_person_id=(item->>'person_id')::uuid and callup.state<>'cancelled')
  or coalesce((select fact.revision from core.attendance_facts fact where fact.event_id=target_event_id
    and fact.club_person_id=(item->>'person_id')::uuid),0)<>(item->>'expected_revision')::bigint)
 then raise serialization_failure using message='invalid_or_stale_attendance';end if;
 for change in select value from jsonb_array_elements(changes) loop
  person_id:=(change->>'person_id')::uuid;
  select * into old_row from core.attendance_facts where event_id=target_event_id
   and club_person_id=person_id for update;
  new_revision:=coalesce(old_row.revision+1,1);
  change_kind_value:=case when is_late then 'late_correction'
   when old_row.id is null then 'initial' else 'correction' end;
  insert into core.attendance_facts(club_id,event_id,club_person_id,status,minutes,note,revision,recorded_by)
  values(event_row.club_id,target_event_id,person_id,change->>'status',
   case when change->>'status' in('late','partial') then(change->>'minutes')::integer end,
   nullif(btrim(change->>'note'),''),new_revision,actor_id)
  on conflict(event_id,club_person_id) do update set status=excluded.status,minutes=excluded.minutes,
   note=excluded.note,revision=excluded.revision,recorded_at=now(),recorded_by=excluded.recorded_by
  returning * into saved_row;
  insert into audit.attendance_revisions(club_id,attendance_id,event_id,club_person_id,status,
   minutes,note,revision,actor_profile_id,change_kind,correction_reason)
  values(event_row.club_id,saved_row.id,target_event_id,person_id,saved_row.status,saved_row.minutes,
   saved_row.note,new_revision,actor_id,change_kind_value,
   case when is_late then reason_value end);
  count_value:=count_value+1;
 end loop;
 result:=jsonb_build_object('updated',count_value,'late_correction',is_late,
  'present',(select count(*) from core.attendance_facts where event_id=target_event_id and status='present'),
  'late',(select count(*) from core.attendance_facts where event_id=target_event_id and status='late'),
  'partial',(select count(*) from core.attendance_facts where event_id=target_event_id and status='partial'),
  'absent',(select count(*) from core.attendance_facts where event_id=target_event_id and status='absent'),
  'unknown',(select count(*) from core.attendance_facts where event_id=target_event_id and status='unknown'));
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'attendance.bulk.recorded.v2',result);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,reason,metadata) values(event_row.club_id,actor_id,'attendance.bulk.recorded.v2',
   'event',event_row.id,event_row.revision,case when is_late then reason_value end,
   jsonb_build_object('updated',count_value,'late_correction',is_late));return result;
exception when invalid_text_representation or numeric_value_out_of_range then
 raise invalid_parameter_value using message='invalid_input';
end;$$;

create or replace function api.record_attendance_v2(target_event_id uuid,changes jsonb,correction_reason text,
 idempotency_key uuid) returns jsonb language sql security invoker set search_path=''
as $$select internal.record_attendance_v2_for_actor(target_event_id,changes,correction_reason,idempotency_key)$$;

create or replace function internal.get_attendance_permissions_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;is_late boolean;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(target_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 is_late:=now()>event_row.ends_at+interval'24 hours';
 return jsonb_build_object('late_window',is_late,
  'can_record',internal.actor_can_manage_attendance(target_event_id),
  'can_correct_late',internal.actor_can_correct_late_attendance(target_event_id));
end;$$;
create or replace function api.get_attendance_permissions(target_event_id uuid) returns jsonb
language sql stable security invoker set search_path=''
as $$select internal.get_attendance_permissions_for_actor(target_event_id)$$;

revoke all on function internal.actor_can_correct_late_attendance(uuid),
 internal.record_attendance_v2_for_actor(uuid,jsonb,text,uuid),
 internal.get_attendance_permissions_for_actor(uuid),api.record_attendance_v2(uuid,jsonb,text,uuid),
 api.get_attendance_permissions(uuid) from public,anon,authenticated;
grant execute on function internal.record_attendance_v2_for_actor(uuid,jsonb,text,uuid),
 internal.get_attendance_permissions_for_actor(uuid),api.record_attendance_v2(uuid,jsonb,text,uuid),
 api.get_attendance_permissions(uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827075525_cal08_atomic_attendance','greenfield','CAL-08 atomic revisioned attendance with late-correction boundary');
notify pgrst,'reload schema';
