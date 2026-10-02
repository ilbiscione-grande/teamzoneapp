create table internal.assistant_task_dispositions(
 profile_id uuid not null references core.profiles(id) on delete cascade,
 kind text not null, route text not null,
 status text not null check(status in('snoozed','archived')),
 until_at timestamptz,
 primary key(profile_id,kind,route),
 check((status='snoozed' and until_at is not null) or (status='archived' and until_at is null))
);
alter table internal.assistant_task_dispositions enable row level security;
create policy own_dispositions on internal.assistant_task_dispositions to authenticated
 using(profile_id=(select auth.uid())) with check(profile_id=(select auth.uid()));
revoke all on internal.assistant_task_dispositions from public,anon,authenticated;

do $migration$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.get_leader_home_for_actor(uuid)'::regprocedure);
 patched:=replace(definition,'jsonb_agg(task order by priority,kind)',
 $patch$jsonb_agg(to_jsonb(task)||jsonb_build_object('assistant_state',coalesce((
   select jsonb_build_object('status',d.status,'until_at',d.until_at)
   from internal.assistant_task_dispositions d
   where d.profile_id=actor_id and d.kind=task.kind and d.route=task.route
     and (d.status='archived' or d.until_at>observed_at)
 ),'{}'::jsonb)) order by priority,kind)$patch$);
 if patched=definition then raise exception 'leader tasks aggregate changed'; end if;
 execute patched;
end;
$migration$;

create function internal.set_assistant_task_state_for_actor(context_id uuid,task_kind text,task_route text,new_status text,snooze_minutes integer default null)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); projection jsonb;
begin
 if actor is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if new_status is null or new_status not in('active','snoozed','archived')
   or (new_status='snoozed' and (snooze_minutes is null or snooze_minutes not between 1 and 10080))
   or (new_status<>'snoozed' and snooze_minutes is not null)
 then raise invalid_parameter_value using message='invalid_task_state'; end if;
 projection:=internal.get_leader_home_for_actor(context_id);
 if not exists(select 1 from jsonb_array_elements(projection->'tasks') t
   where t->>'kind'=task_kind and t->>'route'=task_route)
 then raise insufficient_privilege using message='not_found'; end if;
 if new_status='active' then
   delete from internal.assistant_task_dispositions where profile_id=actor and kind=task_kind and route=task_route;
 else
   insert into internal.assistant_task_dispositions(profile_id,kind,route,status,until_at)
   values(actor,task_kind,task_route,new_status,case when new_status='snoozed' then now()+make_interval(mins=>snooze_minutes) end)
   on conflict(profile_id,kind,route) do update set status=excluded.status,until_at=excluded.until_at;
 end if;
end $$;
create function api.set_assistant_task_state(context_id uuid,task_kind text,task_route text,new_status text,snooze_minutes integer default null)
returns void language sql security invoker set search_path='' as $$
 select internal.set_assistant_task_state_for_actor(context_id,task_kind,task_route,new_status,snooze_minutes) $$;
revoke all on function internal.set_assistant_task_state_for_actor(uuid,text,text,text,integer) from public,anon,authenticated;
grant execute on function internal.set_assistant_task_state_for_actor(uuid,text,text,text,integer) to authenticated;
revoke all on function api.set_assistant_task_state(uuid,text,text,text,integer) from public,anon,authenticated;
grant execute on function api.set_assistant_task_state(uuid,text,text,text,integer) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261002142418_assistant_task_disposition.sql','greenfield','Private account-scoped assistant snooze/archive/restore; live task authorization');
notify pgrst,'reload schema';
