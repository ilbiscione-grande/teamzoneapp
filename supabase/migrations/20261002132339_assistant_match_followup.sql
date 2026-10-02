-- Extend the authorized leader projection. No new access grants or writes.
do $migration$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.get_leader_home_for_actor(uuid)'::regprocedure);
 patched:=replace(definition, ')task)', $tasks$
 union all
 select case when workspace.state='completed' then 'missing_match_report' else 'missing_match_result' end,
   4,case when workspace.state='completed' then 'Matchrapport saknas' else 'Slutresultat saknas' end,
   1,'/calendar?event='||event_row.id::text
 from core.events event_row
 left join core.match_workspaces workspace on workspace.event_id=event_row.id
 left join core.match_reports report on report.event_id=event_row.id
 where event_row.club_id=context_row.club_id and event_row.owning_team_id=context_row.team_id
   and event_row.event_type='match' and event_row.state in('scheduled','completed')
   and event_row.archived_at is null
   and event_row.ends_at<observed_at and event_row.ends_at>=observed_at-interval '7 days'
   and internal.actor_has_capability(context_row.club_id,context_row.team_id,'match.live')
   and internal.actor_has_event_capability(event_row.id,'match.live')
   and (workspace.state is distinct from 'completed' or nullif(btrim(report.body),'') is null)
 )task)$tasks$);
 if patched=definition then raise exception 'leader task contract changed'; end if;
 execute patched;
end;
$migration$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261002132339_assistant_match_followup.sql','greenfield',
 'Assistant match follow-up: last seven days, missing final result or written report, scoped match.live');
notify pgrst,'reload schema';
