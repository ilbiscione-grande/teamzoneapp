create table core.event_callup_visibility(
  event_id uuid primary key,
  club_id uuid not null,
  show_to_members boolean not null default false,
  revision bigint not null default 1 check(revision>0),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references core.profiles(id),
  foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade
);
alter table core.event_callup_visibility enable row level security;
revoke all on table core.event_callup_visibility from public,anon,authenticated;

create function internal.actor_represents_club_person(
  target_club_id uuid,target_club_person_id uuid
)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(
  select 1 from core.person_account_links link
  where link.profile_id=auth.uid() and link.club_id=target_club_id
   and link.club_person_id=target_club_person_id and link.state='active'
 ) or exists(
  select 1 from core.person_account_links link
  join core.guardian_relations relation
   on relation.club_id=link.club_id
   and relation.guardian_person_id=link.club_person_id
   and relation.child_person_id=target_club_person_id
   and relation.state='active' and relation.starts_at<=now()
   and(relation.ends_at is null or relation.ends_at>now())
  where link.profile_id=auth.uid() and link.club_id=target_club_id
   and link.state='active'
 )
$$;

create function internal.set_event_callup_visibility_for_actor(
  target_event_id uuid,new_show_to_members boolean,expected_revision bigint,
  idempotency_key uuid
)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;
 current_row core.event_callup_visibility%rowtype;existing jsonb;new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication
 where actor_profile_id=actor_id and command_type='event.callup_visibility.set.v1'
  and internal.command_deduplication.idempotency_key=set_event_callup_visibility_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_manage_squad(target_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 perform pg_advisory_xact_lock(hashtextextended(target_event_id::text,0));
 select * into current_row from core.event_callup_visibility
 where event_id=target_event_id for update;
 if current_row.event_id is null then
  if expected_revision<>0 then raise serialization_failure using message='stale_revision';end if;
  insert into core.event_callup_visibility(event_id,club_id,show_to_members,updated_by)
  values(target_event_id,event_row.club_id,new_show_to_members,actor_id)
  returning revision into new_revision;
 else
  if current_row.revision<>expected_revision
  then raise serialization_failure using message='stale_revision';end if;
  update core.event_callup_visibility set show_to_members=new_show_to_members,
   revision=revision+1,updated_at=now(),updated_by=actor_id
  where event_id=target_event_id returning revision into new_revision;
 end if;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'event.callup_visibility.set.v1',
  jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,
  aggregate_id,aggregate_revision,metadata)
 values(event_row.club_id,actor_id,'event.callup_visibility.set.v1',
  'event_callup_visibility',target_event_id,new_revision,
  jsonb_build_object('show_to_members',new_show_to_members));
 return new_revision;
end;$$;

create or replace function internal.get_event_squad_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;squad core.squad_revisions%rowtype;
 can_manage boolean;show_to_members boolean;visibility_revision bigint;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(target_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 can_manage:=internal.actor_can_manage_squad(target_event_id);
 select visibility.show_to_members,visibility.revision
 into show_to_members,visibility_revision
 from core.event_callup_visibility visibility where visibility.event_id=target_event_id;
 show_to_members:=coalesce(show_to_members,false);
 visibility_revision:=coalesce(visibility_revision,0);
 select * into squad from core.squad_revisions where event_id=target_event_id
 order by revision desc limit 1;
 return jsonb_build_object('event_id',target_event_id,'squad_revision_id',squad.id,
  'squad_revision',squad.revision,'squad_state',coalesce(squad.state,'empty'),
  'selection_source',squad.selection_source,
  'selection_context',coalesce(squad.selection_context,'{}'::jsonb),
  'dispatch_kind',coalesce(squad.dispatch_kind,'initial'),
  'show_callups_to_members',show_to_members,
  'callup_visibility_revision',visibility_revision,
  'members',coalesce((select jsonb_agg(jsonb_build_object(
   'person_id',member.club_person_id,'name',person.display_name,
   'selection_state',member.selection_state,'source',member.source)
   order by person.display_name)
   from core.squad_members member join core.club_people person on person.id=member.club_person_id
   where member.squad_revision_id=squad.id and(
    can_manage or show_to_members or
    internal.actor_represents_club_person(event_row.club_id,member.club_person_id)
   )),'[]'::jsonb),
  'callups',coalesce((select jsonb_agg(jsonb_build_object(
   'callup_id',callup.id,'person_id',callup.club_person_id,'name',person.display_name,
   'state',callup.state,'revision',callup.revision,'expires_at',callup.expires_at,
   'delivery_state',case when can_manage then coalesce(sent.state,'pending') else 'hidden' end,
   'last_reminded_at',case when can_manage then callup.last_reminded_at else null end,
   'reminder_count',case when can_manage then callup.reminder_count else 0 end,
   'reminder_delivery_state',case when can_manage then reminder.state else null end,
   'can_respond',(response_context->>'can_respond')::boolean,
   'acting_as_person_id',response_context->>'acting_as_person_id',
   'response_role',response_context->>'response_role') order by person.display_name)
   from core.callups callup join core.club_people person on person.id=callup.club_person_id
   cross join lateral internal.actor_callup_response_context(callup.id)response(response_context)
   left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id
    and event_type in('callup.callup.sent.v1','callup.callup.late_sent.v1')
    order by created_at desc limit 1)sent on can_manage
   left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id
    and event_type='callup.callup.reminded.v2' order by created_at desc limit 1)reminder on can_manage
   where callup.event_id=target_event_id and(
    can_manage or show_to_members or
    internal.actor_represents_club_person(event_row.club_id,callup.club_person_id)
   )),'[]'::jsonb),
  'attendance',coalesce((select jsonb_agg(jsonb_build_object(
   'person_id',callup.club_person_id,'name',person.display_name,
   'status',coalesce(attendance.status,'unknown'),'minutes',attendance.minutes,
   'revision',coalesce(attendance.revision,0)) order by person.display_name)
   from core.callups callup join core.club_people person on person.id=callup.club_person_id
   left join core.attendance_facts attendance
    on attendance.event_id=callup.event_id and attendance.club_person_id=callup.club_person_id
   where callup.event_id=target_event_id and callup.state<>'cancelled' and(
    can_manage or internal.actor_represents_club_person(event_row.club_id,callup.club_person_id)
   )),'[]'::jsonb),
  'caller_actions',case when can_manage
   then array['save_squad','lock_squad','send_callups','cancel_callup',
    'remind_callup','set_callup_visibility']::text[]
   else array[]::text[] end||case when internal.actor_can_manage_attendance(target_event_id)
   then array['record_attendance']::text[] else array[]::text[] end);
end;$$;

create function api.set_event_callup_visibility(
 event_id uuid,show_to_members boolean,expected_revision bigint,idempotency_key uuid
)returns bigint language sql security invoker set search_path=''
as $$select internal.set_event_callup_visibility_for_actor(
 event_id,show_to_members,expected_revision,idempotency_key)$$;

revoke all on function internal.actor_represents_club_person(uuid,uuid),
 internal.set_event_callup_visibility_for_actor(uuid,boolean,bigint,uuid),
 api.set_event_callup_visibility(uuid,boolean,bigint,uuid)
 from public,anon,authenticated;
grant execute on function internal.set_event_callup_visibility_for_actor(uuid,boolean,bigint,uuid),
 api.set_event_callup_visibility(uuid,boolean,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260902104510_cal10_callup_roster_visibility','greenfield',
 'CAL-10 private-by-default server-filtered callup visibility');
notify pgrst,'reload schema';
