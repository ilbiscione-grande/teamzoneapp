-- Account-private overlap projection. No actor/profile argument and no leader bypass.
create function internal.get_personal_calendar_conflicts_for_actor()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); observed_at timestamptz:=statement_timestamp(); result jsonb;
begin
 if actor is null then raise insufficient_privilege using message='unauthenticated'; end if;
 with contexts as materialized (select * from internal.get_my_contexts_for_actor()),
 own_events as materialized (
   select distinct on(e.id) e.id,e.club_id,e.owning_team_id,e.starts_at,e.ends_at,
     c.context_id,c.team_id,callup.state response,
     jsonb_build_object('event_id',e.id,'context_id',c.context_id,'response',callup.state) detail
   from core.person_account_links link
   join core.callups callup on callup.club_person_id=link.club_person_id and callup.club_id=link.club_id
   join core.events e on e.id=callup.event_id and e.club_id=callup.club_id
   join core.event_teams relation on relation.event_id=e.id and relation.club_id=e.club_id
   join contexts c on c.club_id=e.club_id and c.team_id=relation.team_id
   where link.profile_id=actor and link.state='active'
     and c.role_package in('leader','player')
     and callup.state in('accepted','pending')
     and e.state='scheduled' and e.archived_at is null
     and e.ends_at>observed_at and e.starts_at<observed_at+interval '7 days'
     and internal.actor_can_read_event(e.id)
   order by e.id,(relation.team_id=e.owning_team_id) desc,(c.role_package='leader') desc,c.context_id
 ), pairs as (
   select a.id,a.starts_at,a.context_id,a.detail first_event,b.detail second_event,
     a.response='accepted' and b.response='accepted' confirmed,
     '/calendar?event='||a.id::text||'&overlap='||b.id::text route
   from own_events a join own_events b on a.id<b.id
     and a.starts_at<b.ends_at and b.starts_at<a.ends_at
     and (a.club_id<>b.club_id or a.owning_team_id<>b.owning_team_id)
 )
 select jsonb_build_object('generated_at',observed_at,'tasks',coalesce(jsonb_agg(
   jsonb_build_object('kind','personal_calendar_conflict','priority',0,'count',1,
    'title',case when p.confirmed then 'Du är dubbelbokad' else 'Möjlig personlig krock' end,
    'route',p.route,'context_id',p.context_id,'first_event',p.first_event,'second_event',p.second_event,
    'assistant_state',coalesce((select jsonb_build_object('status',d.status,'until_at',d.until_at)
      from internal.assistant_task_dispositions d where d.profile_id=actor
      and d.kind='personal_calendar_conflict' and d.route=p.route
      and (d.status='archived' or d.until_at>observed_at)),'{}'::jsonb))
   order by p.starts_at,p.id),'[]'::jsonb)) into result from pairs p;
 return result;
end $$;

create function api.get_personal_calendar_conflicts()
returns jsonb language sql stable security invoker set search_path='' as $$
 select internal.get_personal_calendar_conflicts_for_actor()
$$;
revoke all on function internal.get_personal_calendar_conflicts_for_actor(),api.get_personal_calendar_conflicts() from public,anon,authenticated;
grant execute on function internal.get_personal_calendar_conflicts_for_actor(),api.get_personal_calendar_conflicts() to authenticated;

-- Reuse private snooze/archive storage, validating personal tasks against their
-- own projection instead of requiring access to a leader's task projection.
do $migration$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.set_assistant_task_state_for_actor(uuid,text,text,text,integer)'::regprocedure);
 patched:=replace(definition,'projection:=internal.get_leader_home_for_actor(context_id);',
 $patch$if task_kind='personal_calendar_conflict' then
   projection:=internal.get_personal_calendar_conflicts_for_actor();
   if not exists(select 1 from jsonb_array_elements(projection->'tasks') t
     where t->>'route'=task_route and t->>'context_id'=context_id::text)
   then raise insufficient_privilege using message='not_found'; end if;
 else
   projection:=internal.get_leader_home_for_actor(context_id);
 end if;$patch$);
 if patched=definition then raise exception 'assistant disposition contract changed'; end if;
 execute patched;
end;
$migration$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261002185842_assistant_personal_calendar_conflicts.sql','greenfield','Account-private own callup overlaps across teams and clubs; no guardian or leader expansion');
notify pgrst,'reload schema';
