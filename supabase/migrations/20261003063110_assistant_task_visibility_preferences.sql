create table internal.assistant_task_preferences (
 profile_id uuid primary key references core.profiles(id) on delete cascade,
 hidden_kinds text[] not null default '{}',
 revision bigint not null default 0 check(revision>=0),
 check(hidden_kinds <@ array['pending_callups','missing_callups','missing_attendance',
   'missing_match_result','missing_match_report','unfinished_preparation','calendar_conflict','personal_calendar_conflict']::text[])
);
alter table internal.assistant_task_preferences enable row level security;
create policy own_preferences on internal.assistant_task_preferences to authenticated
 using(profile_id=(select auth.uid())) with check(profile_id=(select auth.uid()));
revoke all on internal.assistant_task_preferences from public,anon,authenticated;

create function internal.get_assistant_task_preferences_for_actor()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select jsonb_build_object('hidden_kinds',p.hidden_kinds,'revision',p.revision) into result
 from internal.assistant_task_preferences p where p.profile_id=actor;
 return coalesce(result,'{"hidden_kinds":[],"revision":0}'::jsonb);
end $$;

create function internal.set_assistant_task_preferences_for_actor(hidden_kinds text[],expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); current_row internal.assistant_task_preferences; normalized text[];
begin
 if actor is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if hidden_kinds is null or expected_revision is null or expected_revision<0
   or array_position(hidden_kinds,null) is not null
   or not hidden_kinds <@ array['pending_callups','missing_callups','missing_attendance',
     'missing_match_result','missing_match_report','unfinished_preparation','calendar_conflict','personal_calendar_conflict']::text[]
 then raise invalid_parameter_value using message='invalid_preferences'; end if;
 select coalesce(array_agg(distinct value order by value),'{}'::text[]) into normalized from unnest(hidden_kinds) value;
 insert into internal.assistant_task_preferences(profile_id) values(actor) on conflict do nothing;
 select * into current_row from internal.assistant_task_preferences where profile_id=actor for update;
 -- An identical retry after a lost response is safe and does not advance revision.
 if current_row.hidden_kinds=normalized then return internal.get_assistant_task_preferences_for_actor(); end if;
 if current_row.revision<>expected_revision then raise serialization_failure using message='revision_conflict'; end if;
 update internal.assistant_task_preferences set hidden_kinds=normalized,revision=current_row.revision+1 where profile_id=actor;
 return internal.get_assistant_task_preferences_for_actor();
end $$;
create function api.get_assistant_task_preferences() returns jsonb language sql stable security invoker set search_path='' as $$
 select internal.get_assistant_task_preferences_for_actor() $$;
create function api.set_assistant_task_preferences(hidden_kinds text[],expected_revision bigint) returns jsonb language sql security invoker set search_path='' as $$
 select internal.set_assistant_task_preferences_for_actor(hidden_kinds,expected_revision) $$;
revoke all on function internal.get_assistant_task_preferences_for_actor(),internal.set_assistant_task_preferences_for_actor(text[],bigint),
 api.get_assistant_task_preferences(),api.set_assistant_task_preferences(text[],bigint) from public,anon,authenticated;
grant execute on function internal.get_assistant_task_preferences_for_actor(),internal.set_assistant_task_preferences_for_actor(text[],bigint),
 api.get_assistant_task_preferences(),api.set_assistant_task_preferences(text[],bigint) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261003063110_assistant_task_visibility_preferences.sql','greenfield','Account-private task visibility preferences; optimistic concurrency and safe identical retry');
notify pgrst,'reload schema';
