-- The assistant tells leaders about new contact details sent through a
-- team's contact update page (the task kind team_contact_details, read from
-- the existing intake overview). Only the settings change here: the new kind
-- can be hidden like the others.

alter table internal.assistant_task_preferences
  drop constraint if exists assistant_task_preferences_hidden_kinds_check;
alter table internal.assistant_task_preferences
  add constraint assistant_task_preferences_hidden_kinds_check check (hidden_kinds <@ array[
    'pending_callups','missing_callups','missing_attendance','missing_match_result',
    'missing_match_report','unfinished_preparation','calendar_conflict','personal_calendar_conflict',
    'team_representation_requests','team_representation_available','team_contact_details',
    'inbox_messages','inbox_notices'
  ]::text[]);

create or replace function internal.set_assistant_task_preferences_v3_for_actor(
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
     'missing_match_result','missing_match_report','unfinished_preparation','calendar_conflict','personal_calendar_conflict',
     'team_representation_requests','team_representation_available','team_contact_details',
     'inbox_messages','inbox_notices']::text[]
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
   raise sqlstate 'PT409' using message='revision_conflict';
 end if;
 update internal.assistant_task_preferences p set
   hidden_kinds=normalized,
   current_team_only=set_assistant_task_preferences_v3_for_actor.current_team_only,
   welcome_message_visible=set_assistant_task_preferences_v3_for_actor.welcome_message_visible,
   revision=current_row.revision+1
 where p.profile_id=actor;
 return internal.get_assistant_task_preferences_for_actor();
end $$;

notify pgrst, 'reload schema';
