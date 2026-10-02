-- Existing authorized leader tasks only; no AI, grants or new write surface.
do $migration$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.get_leader_home_for_actor(uuid)'::regprocedure);
 patched:=replace(definition, ')task)', $tasks$
 union all
 select 'calendar_conflict',0,'Aktiviteter överlappar',1,
   '/calendar?event='||a.id::text||'&overlap='||b.id::text
 from core.event_teams ra
 join core.events a on a.id=ra.event_id and a.club_id=ra.club_id
 join core.event_teams rb on rb.club_id=ra.club_id and rb.team_id=ra.team_id
 join core.events b on b.id=rb.event_id and b.club_id=rb.club_id and a.id<b.id
 where ra.club_id=context_row.club_id and ra.team_id=context_row.team_id
   and internal.actor_has_capability(context_row.club_id,context_row.team_id,'event.manage')
   and a.state='scheduled' and b.state='scheduled'
   and a.archived_at is null and b.archived_at is null
   and a.ends_at>observed_at and b.ends_at>observed_at
   and a.starts_at<observed_at+interval '7 days' and b.starts_at<observed_at+interval '7 days'
   and a.starts_at<b.ends_at and b.starts_at<a.ends_at
   and internal.actor_can_read_event(a.id) and internal.actor_can_read_event(b.id)
 union all
 select 'unfinished_preparation',5,'Förberedelser återstår',count(*)::integer,
   '/calendar?event='||event_row.id::text
 from core.events event_row
 join core.event_preparation_items item on item.event_id=event_row.id and item.club_id=event_row.club_id
 where event_row.club_id=context_row.club_id and event_row.owning_team_id=context_row.team_id
   and event_row.state='scheduled' and event_row.archived_at is null
   and event_row.starts_at>observed_at and event_row.starts_at<=observed_at+interval '48 hours'
   and internal.actor_has_capability(context_row.club_id,context_row.team_id,'event.logistics')
   and internal.actor_has_event_capability(event_row.id,'event.logistics')
   and internal.actor_can_read_event(event_row.id)
   and not item.done
   and (item.kind='task' or (item.kind='material' and event_row.event_type in('match','training')))
 group by event_row.id
 )task)$tasks$);
 if patched=definition then raise exception 'leader task contract changed'; end if;
 execute patched;
end;
$migration$;
-- Existing event_teams (event_id,team_id) and preparation event index are reused.
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261002135847_assistant_conflicts_preparation.sql','greenfield',
 'Assistant: visible same-team overlaps within seven days, existing unfinished materials/tasks within 48 hours');
notify pgrst,'reload schema';
