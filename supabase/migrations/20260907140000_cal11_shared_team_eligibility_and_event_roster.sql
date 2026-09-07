-- CAL-11: EventDetails' Deltagare tab rebuild, backend groundwork.
--
-- (1) person_eligibility_at_event only ever checked the event's single
--     owning_team_id, so a shared event (e.g. P10 and P11 training
--     together via core.event_teams) never actually surfaced the shared
--     team's roster as eligible/selectable — a real gap the new UI would
--     otherwise have silently inherited. Fixed to check every team in
--     core.event_teams (primary and shared alike; sharing implies
--     participation, so no capability filter here — that's a separate
--     concern already handled by internal.actor_can_manage_event_roster).
-- (2) list_squad_candidates now also returns team_id/team_name/role_package
--     per candidate, and orders by the team's created_at (oldest team
--     first, per product decision) then name — needed for the new
--     search/select UI to group and sort candidates by team.
-- (3) get_event_squad_for_actor gains a new 'roster' key: every active
--     player/leader assignment across the event's team(s), left-joined
--     against the current squad draft/callup/attendance so the client can
--     render one merged list (kallade/okallade x spelare/ledare) instead
--     of just the members who happen to already be selected or called.

create or replace function internal.person_eligibility_at_event(target_event_id uuid,target_person_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(
  (select jsonb_build_object('kind','team_assignment','id',assignment.id,'team_id',assignment.team_id,'starts_at',assignment.starts_at,'ends_at',assignment.ends_at)
   from core.events event_row
   join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   join core.team_assignments assignment on assignment.club_id=event_row.club_id and assignment.team_id=relation.team_id
   where event_row.id=target_event_id and assignment.club_person_id=target_person_id and assignment.state='active'
    and assignment.starts_at<=event_row.starts_at and (assignment.ends_at is null or assignment.ends_at>event_row.starts_at)
   order by (relation.relation='primary') desc,assignment.starts_at desc limit 1),
  (select jsonb_build_object('kind',eligibility.kind,'id',eligibility.id,'team_id',eligibility.team_id,
    'starts_at',eligibility.starts_at,'ends_at',eligibility.ends_at,'validity_kind',eligibility.validity_kind)
   from core.events event_row
   join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   join core.play_eligibilities eligibility on eligibility.club_id=event_row.club_id and eligibility.team_id=relation.team_id
   where event_row.id=target_event_id and eligibility.club_person_id=target_person_id and eligibility.state='active'
    and eligibility.starts_at<=event_row.starts_at
    and (eligibility.ends_at is null or eligibility.ends_at>event_row.starts_at)
    and (eligibility.review_due_at is null or eligibility.review_due_at>event_row.starts_at)
   order by (relation.relation='primary') desc,eligibility.starts_at desc,eligibility.id limit 1)
 );
$$;

-- Postgres refuses CREATE OR REPLACE across a changed OUT-parameter list
-- for a RETURNS TABLE function, so the widened candidate projection needs
-- an explicit drop first (both the internal function and its api wrapper,
-- which shares the same signature change).
drop function if exists api.list_squad_candidates(uuid);
drop function if exists internal.list_squad_candidates_for_actor(uuid);

create function internal.list_squad_candidates_for_actor(target_event_id uuid)
returns table(person_id uuid,name text,eligibility_kind text,team_id uuid,team_name text,role_package text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_can_manage_squad(target_event_id) then raise insufficient_privilege using message='not_found'; end if;
 return query
 with eligible as (
   select person.id as eligible_person_id,person.display_name as eligible_name,
     internal.person_eligibility_at_event(target_event_id,person.id) as eligibility
   from core.club_people person
   join core.events event_row on event_row.id=target_event_id and event_row.club_id=person.club_id
   where person.status='active'
 )
 select eligible.eligible_person_id,eligible.eligible_name,eligible.eligibility->>'kind',
   (eligible.eligibility->>'team_id')::uuid,team.name,assignment.role_package
 from eligible
 left join core.teams team on team.id=(eligible.eligibility->>'team_id')::uuid
 left join core.assignments assignment on assignment.club_person_id=eligible.eligible_person_id
   and assignment.team_id=(eligible.eligibility->>'team_id')::uuid and assignment.state='active'
   and assignment.role_package in ('player','leader')
 where eligible.eligibility is not null
 order by team.created_at nulls last,eligible.eligible_name,eligible.eligible_person_id;
end; $$;

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
   'callup_id',callup.id,'callup_state',callup.state,'attendance_status',attendance.status)
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
   where assignment.club_id=event_row.club_id and assignment.state='active'
    and assignment.role_package in('player','leader') and person.status='active'
    and assignment.starts_at<=event_row.starts_at and(assignment.ends_at is null or assignment.ends_at>event_row.starts_at)
  ),'[]'::jsonb),
  'caller_actions',case when internal.actor_can_manage_squad(target_event_id)
   then array['save_squad','lock_squad','send_callups','cancel_callup','remind_callup']::text[]
   else array[]::text[] end||case when internal.actor_can_manage_attendance(target_event_id)
   then array['record_attendance']::text[] else array[]::text[] end);
end;$$;

create function api.list_squad_candidates(target_event_id uuid)
returns table(person_id uuid,name text,eligibility_kind text,team_id uuid,team_name text,role_package text)
language sql stable security invoker set search_path='' as $$select * from internal.list_squad_candidates_for_actor(target_event_id)$$;

revoke all on function internal.list_squad_candidates_for_actor(uuid) from public,anon,authenticated;
grant execute on function internal.list_squad_candidates_for_actor(uuid) to authenticated;
revoke all on function api.list_squad_candidates(uuid) from public,anon;
grant execute on function api.list_squad_candidates(uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260907140000_cal11_shared_team_eligibility_and_event_roster','greenfield','CAL-11 EventDetails Deltagare tab rebuild — backend groundwork');
notify pgrst,'reload schema';
