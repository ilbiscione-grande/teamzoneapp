-- CAL-11 follow-up: callup responses.
--
-- (1) A leader can themselves be called up (the "kallade ledare" bucket
--     cal11 introduced) but had no way to respond at all — the response
--     path (actor_callup_response_context / respond_callup_for_actor)
--     only ever recognized the callup owner themselves or an active
--     guardian. Extended both to also allow whoever can already manage
--     the event's squad (the same capability that already gates
--     remind/cancel) to record a response on a roster member's behalf —
--     covers the whole roster (players and leaders alike), not just
--     players, matching how remind/cancel already apply uniformly.
-- (2) get_event_squad_for_actor's 'roster' key gains can_respond/
--     response_role per person (same fields the 'callups' key already
--     carries), so the Deltagare tab can decide whether to offer respond
--     controls for a given row.
-- (3) get_leader_home_for_actor's next_event gains a my_callup object
--     (own callup only, same can_respond gate as the player home's
--     own_callups already uses) so a leader's own pending callup is
--     visible — and respondable — from the "nästa" card on Home, same
--     as the player home already offers.

create or replace function internal.actor_callup_response_context(target_callup_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((
  select case
   when exists(select 1 from core.person_account_links link where link.profile_id=auth.uid()
    and link.club_id=callup.club_id and link.club_person_id=callup.club_person_id and link.state='active')
   then jsonb_build_object('can_respond',true,'acting_as_person_id',null,'response_role','self')
   when exists(select 1 from core.person_account_links link join core.guardian_relations relation
    on relation.club_id=link.club_id and relation.guardian_person_id=link.club_person_id
    and relation.child_person_id=callup.club_person_id and relation.state='active'
    and relation.starts_at<=now() and(relation.ends_at is null or relation.ends_at>now())
    where link.profile_id=auth.uid() and link.club_id=callup.club_id and link.state='active')
   then jsonb_build_object('can_respond',true,'acting_as_person_id',callup.club_person_id,'response_role','guardian')
   when internal.actor_can_manage_squad(callup.event_id)
   then jsonb_build_object('can_respond',true,'acting_as_person_id',callup.club_person_id,'response_role','manager')
   else jsonb_build_object('can_respond',false,'acting_as_person_id',null,'response_role',null) end
  from core.callups callup where callup.id=target_callup_id),
  jsonb_build_object('can_respond',false,'acting_as_person_id',null,'response_role',null))
$$;

create or replace function internal.respond_callup_for_actor(target_callup_id uuid,new_response text,acting_as_person_id uuid,decline_reason_code text,decline_reason_text text,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();callup core.callups%rowtype;actor_person uuid;new_revision bigint;existing jsonb;
 reason_code text:=nullif(btrim(decline_reason_code),'');reason_text text:=nullif(btrim(decline_reason_text),'');
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='callup.response.recorded.v2'
  and internal.command_deduplication.idempotency_key=respond_callup_for_actor.idempotency_key;
 if existing is not null then return(existing->>'revision')::bigint;end if;
 select * into callup from core.callups where id=target_callup_id for update;
 if callup.id is null then raise insufficient_privilege using message='not_found';end if;
 select link.club_person_id into actor_person from core.person_account_links link
  where link.profile_id=actor_id and link.club_id=callup.club_id and link.state='active' limit 1;
 if actor_person=callup.club_person_id then
  if acting_as_person_id is not null then raise insufficient_privilege using message='invalid_acting_as';end if;
 elsif acting_as_person_id=callup.club_person_id and (
   exists(select 1 from core.guardian_relations relation
    where relation.club_id=callup.club_id and relation.guardian_person_id=actor_person
     and relation.child_person_id=callup.club_person_id and relation.state='active'
     and relation.starts_at<=now() and(relation.ends_at is null or relation.ends_at>now()))
   or internal.actor_can_manage_squad(callup.event_id)
 ) then null;
 else raise insufficient_privilege using message='not_found';end if;
 if callup.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if callup.state not in('pending','accepted','declined') or callup.expires_at<=now()
  or new_response not in('accepted','declined','tentative')
 then raise invalid_parameter_value using message='invalid_state';end if;
 if new_response='declined' then
  if reason_code not in('illness','injury','unavailable','transport','other')
   or(reason_code='other' and(reason_text is null or length(reason_text) not between 2 and 500))
   or(reason_code<>'other' and reason_text is not null)
  then raise invalid_parameter_value using message='invalid_decline_reason';end if;
 elsif reason_code is not null or reason_text is not null then
  raise invalid_parameter_value using message='unexpected_decline_reason';
 end if;
 new_revision:=callup.revision+1;
 insert into core.callup_responses(club_id,callup_id,response,decline_reason_code,decline_reason_text,
  actor_profile_id,acting_as_person_id,revision) values(callup.club_id,callup.id,new_response,reason_code,
   reason_text,actor_id,acting_as_person_id,new_revision);
 update core.callups set state=case when new_response='tentative' then 'pending' else new_response end,
  revision=new_revision where id=callup.id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'callup.response.recorded.v2',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,acting_as_person_id,command_type,aggregate_type,
  aggregate_id,aggregate_revision,metadata) values(callup.club_id,actor_id,acting_as_person_id,
   'callup.response.recorded.v2','callup',callup.id,new_revision,jsonb_build_object('response',new_response,
    'decline_reason_code',reason_code));return new_revision;
end;$$;

create or replace function internal.get_event_squad_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype;squad core.squad_revisions%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(target_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 select * into squad from core.squad_revisions where event_id=target_event_id order by revision desc limit 1;
 return jsonb_build_object('event_id',target_event_id,'squad_revision_id',squad.id,
  'squad_revision',squad.revision,'squad_state',coalesce(squad.state,'empty'),
  'selection_source',squad.selection_source,'selection_context',coalesce(squad.selection_context,'{}'::jsonb),
  'dispatch_kind',coalesce(squad.dispatch_kind,'initial'),
  'members',coalesce((select jsonb_agg(jsonb_build_object('person_id',member.club_person_id,
   'name',person.display_name,'selection_state',member.selection_state,'source',member.source)order by person.display_name)
   from core.squad_members member join core.club_people person on person.id=member.club_person_id
   where member.squad_revision_id=squad.id),'[]'::jsonb),
  'callups',coalesce((select jsonb_agg(jsonb_build_object('callup_id',callup.id,
   'person_id',callup.club_person_id,'name',person.display_name,'state',callup.state,
   'revision',callup.revision,'expires_at',callup.expires_at,'delivery_state',coalesce(sent.state,'pending'),
   'last_reminded_at',callup.last_reminded_at,'reminder_count',callup.reminder_count,
   'reminder_delivery_state',reminder.state,'can_respond',(response_context->>'can_respond')::boolean,
   'acting_as_person_id',response_context->>'acting_as_person_id','response_role',response_context->>'response_role')
   order by person.display_name) from core.callups callup join core.club_people person on person.id=callup.club_person_id
   cross join lateral internal.actor_callup_response_context(callup.id)response(response_context)
   left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id
    and event_type in('callup.callup.sent.v1','callup.callup.late_sent.v1') order by created_at desc limit 1)sent on true
   left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id
    and event_type='callup.callup.reminded.v2' order by created_at desc limit 1)reminder on true
   where callup.event_id=target_event_id),'[]'::jsonb),
  'attendance',coalesce((select jsonb_agg(jsonb_build_object('person_id',callup.club_person_id,
   'name',person.display_name,'status',coalesce(attendance.status,'unknown'),'minutes',attendance.minutes,
   'revision',coalesce(attendance.revision,0))order by person.display_name) from core.callups callup
   join core.club_people person on person.id=callup.club_person_id left join core.attendance_facts attendance
    on attendance.event_id=callup.event_id and attendance.club_person_id=callup.club_person_id
   where callup.event_id=target_event_id and callup.state<>'cancelled'),'[]'::jsonb),
  'roster',coalesce((select jsonb_agg(jsonb_build_object(
   'person_id',assignment.club_person_id,'name',person.display_name,
   'team_id',assignment.team_id,'team_name',team.name,'role_package',assignment.role_package,
   'in_draft',member.club_person_id is not null,
   'callup_id',callup.id,'callup_state',callup.state,
   'callup_expires_at',callup.expires_at,'callup_last_reminded_at',callup.last_reminded_at,
   'attendance_status',attendance.status,'attendance_revision',coalesce(attendance.revision,0),
   'can_respond',(roster_response.response_context->>'can_respond')::boolean,
   'response_role',roster_response.response_context->>'response_role')
   order by team.created_at,assignment.role_package desc,person.display_name)
   from core.assignments assignment
   join core.club_people person on person.id=assignment.club_person_id and person.club_id=assignment.club_id
   join core.teams team on team.id=assignment.team_id and team.club_id=assignment.club_id
   join core.event_teams relation on relation.event_id=target_event_id and relation.club_id=assignment.club_id
    and relation.team_id=assignment.team_id
   left join core.squad_members member on member.squad_revision_id=squad.id and member.club_person_id=assignment.club_person_id
   left join core.callups callup on callup.event_id=target_event_id and callup.club_person_id=assignment.club_person_id
    and callup.state<>'cancelled'
   left join core.attendance_facts attendance on attendance.event_id=target_event_id
    and attendance.club_person_id=assignment.club_person_id
   left join lateral internal.actor_callup_response_context(callup.id)roster_response(response_context) on true
   where assignment.club_id=event_row.club_id and assignment.state='active'
    and assignment.role_package in('player','leader') and person.status='active'
    and assignment.starts_at<=event_row.starts_at and(assignment.ends_at is null or assignment.ends_at>event_row.starts_at)
  ),'[]'::jsonb),
  'caller_actions',case when internal.actor_can_manage_squad(target_event_id)
   then array['save_squad','lock_squad','send_callups','cancel_callup','remind_callup']::text[]
   else array[]::text[] end||case when internal.actor_can_manage_attendance(target_event_id)
   then array['record_attendance']::text[] else array[]::text[] end);
end;$$;

create or replace function internal.get_leader_home_for_actor(target_context_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();context_row record;observed_at timestamptz:=statement_timestamp();
 can_manage_squad boolean;can_record_attendance boolean;my_person_id uuid;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into context_row from internal.get_my_contexts_for_actor()where context_id=target_context_id;
 if context_row.context_id is null or context_row.role_package<>'leader'or context_row.team_id is null
 then raise insufficient_privilege using message='not_found';end if;
 can_manage_squad:=internal.actor_has_capability(context_row.club_id,context_row.team_id,'event.squad.manage');
 can_record_attendance:=internal.actor_has_capability(context_row.club_id,context_row.team_id,'event.attendance.manage');
 select link.club_person_id into my_person_id from core.person_account_links link
  where link.profile_id=actor_id and link.club_id=context_row.club_id and link.state='active' limit 1;
 return jsonb_build_object(
  'schema_version',1,'generated_at',observed_at,'role_package','leader','context_id',target_context_id,
  'today_events',coalesce((select jsonb_agg(row_value order by starts_at,event_id)from(
   select event_row.id event_id,event_row.title,event_row.event_type,event_row.state,event_row.starts_at,event_row.ends_at,
    location.name location_name,location.address
   from core.events event_row join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
   where event_row.club_id=context_row.club_id and relation.team_id=context_row.team_id and event_row.state<>'cancelled'
    and(event_row.starts_at at time zone event_row.timezone)::date=(observed_at at time zone event_row.timezone)::date
   order by event_row.starts_at,event_row.id limit 8)row_value),'[]'::jsonb),
  'next_event',(select jsonb_build_object('event_id',event_row.id,'title',event_row.title,'event_type',event_row.event_type,
   'state',event_row.state,'starts_at',event_row.starts_at,'ends_at',event_row.ends_at,'location_name',location.name,'address',location.address,
   'my_callup',(select jsonb_build_object('callup_id',callup.id,'state',callup.state,'revision',callup.revision,
     'expires_at',callup.expires_at,
     'can_respond',callup.state in('pending','accepted','declined')and callup.expires_at>observed_at)
    from core.callups callup where callup.event_id=event_row.id and callup.club_person_id=my_person_id
     and callup.state<>'cancelled' order by callup.created_at desc limit 1))
   from core.events event_row join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
   where event_row.club_id=context_row.club_id and relation.team_id=context_row.team_id and event_row.state='scheduled'
    and event_row.starts_at>=observed_at order by event_row.starts_at,event_row.id limit 1),
  'tasks',coalesce((select jsonb_agg(task order by priority,kind)from(
   select 'pending_callups'kind,1 priority,'Obesvarade kallelser'title,count(*)::integer count,
    '/calendar?event='||callup.event_id::text route
   from core.callups callup join core.events event_row on event_row.id=callup.event_id and event_row.club_id=callup.club_id
   where can_manage_squad and event_row.owning_team_id=context_row.team_id and event_row.starts_at>=observed_at
    and event_row.state='scheduled'and callup.state='pending'
   group by callup.event_id having count(*)>0
   union all
   select 'missing_attendance',2,'Närvaro saknas',count(*)::integer,'/calendar?event='||callup.event_id::text
   from core.callups callup join core.events event_row on event_row.id=callup.event_id and event_row.club_id=callup.club_id
   left join core.attendance_facts fact on fact.event_id=callup.event_id and fact.club_person_id=callup.club_person_id
   where can_record_attendance and event_row.owning_team_id=context_row.team_id
    and event_row.ends_at<observed_at and event_row.ends_at>=observed_at-interval'7 days'
    and event_row.state in('scheduled','completed')and callup.state='accepted'and fact.id is null
   group by callup.event_id having count(*)>0)task),'[]'::jsonb),
  'planning_actions',jsonb_build_array(
   jsonb_build_object('kind','create_event','title','Planera aktivitet','route','/calendar','enabled',
    internal.actor_has_capability(context_row.club_id,context_row.team_id,'event.manage')),
   jsonb_build_object('kind','manage_team','title','Hantera laget','route','/team','enabled',
    internal.actor_has_capability(context_row.club_id,context_row.team_id,'club.memberships.manage')),
   jsonb_build_object('kind','open_inbox','title','Öppna inkorgen','route','/inbox','enabled',true)
  )
 );
end$$;
