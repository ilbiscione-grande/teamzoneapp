alter table internal.assistant_task_preferences
 add column welcome_message_visible boolean not null default true;

create or replace function internal.get_assistant_task_preferences_for_actor()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); result jsonb;
begin
 if actor is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select jsonb_build_object(
   'hidden_kinds',p.hidden_kinds,
   'revision',p.revision,
   'current_team_only',p.current_team_only,
   'welcome_message_visible',p.welcome_message_visible
 ) into result
 from internal.assistant_task_preferences p where p.profile_id=actor;
 return coalesce(result,'{"hidden_kinds":[],"revision":0,"current_team_only":false,"welcome_message_visible":true}'::jsonb);
end $$;

-- Older setters stay available and only update their own fields, so installed
-- clients cannot accidentally turn the welcome message back on.
create function internal.set_assistant_task_preferences_v3_for_actor(
 hidden_kinds text[],expected_revision bigint,current_team_only boolean,welcome_message_visible boolean
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); current_row internal.assistant_task_preferences; normalized text[];
begin
 if actor is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if current_team_only is null or welcome_message_visible is null or hidden_kinds is null
   or expected_revision is null or expected_revision<0
   or array_position(hidden_kinds,null) is not null
   or not hidden_kinds <@ array['pending_callups','missing_callups','missing_attendance',
     'missing_match_result','missing_match_report','unfinished_preparation','calendar_conflict','personal_calendar_conflict']::text[]
 then raise invalid_parameter_value using message='invalid_preferences'; end if;
 select coalesce(array_agg(distinct value order by value),'{}'::text[])
 into normalized from unnest(hidden_kinds) value;
 insert into internal.assistant_task_preferences(profile_id) values(actor) on conflict do nothing;
 select * into current_row from internal.assistant_task_preferences where profile_id=actor for update;
 if current_row.hidden_kinds=normalized
   and current_row.current_team_only=current_team_only
   and current_row.welcome_message_visible=welcome_message_visible
 then return internal.get_assistant_task_preferences_for_actor(); end if;
 if current_row.revision<>expected_revision then
   raise serialization_failure using message='revision_conflict';
 end if;
 update internal.assistant_task_preferences p set
   hidden_kinds=normalized,
   current_team_only=set_assistant_task_preferences_v3_for_actor.current_team_only,
   welcome_message_visible=set_assistant_task_preferences_v3_for_actor.welcome_message_visible,
   revision=current_row.revision+1
 where p.profile_id=actor;
 return internal.get_assistant_task_preferences_for_actor();
end $$;

create function api.set_assistant_task_preferences_v3(
 hidden_kinds text[],expected_revision bigint,current_team_only boolean,welcome_message_visible boolean
)
returns jsonb language sql security invoker set search_path='' as $$
 select internal.set_assistant_task_preferences_v3_for_actor(
   hidden_kinds,expected_revision,current_team_only,welcome_message_visible
 ) $$;

revoke all on function
 internal.set_assistant_task_preferences_v3_for_actor(text[],bigint,boolean,boolean),
 api.set_assistant_task_preferences_v3(text[],bigint,boolean,boolean)
from public,anon,authenticated;
grant execute on function
 internal.set_assistant_task_preferences_v3_for_actor(text[],bigint,boolean,boolean),
 api.set_assistant_task_preferences_v3(text[],bigint,boolean,boolean)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
 '20261003083806_assistant_welcome_message_visibility.sql',
 'greenfield',
 'Account-synced dismissible assistant welcome message; legacy setters preserve the preference'
);
notify pgrst,'reload schema';
