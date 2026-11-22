-- Enkäter, easier sharing and statistics (product owner, 2026-11-22):
--
--   phone, email  a personal link carries the player's phone and email for
--                 the team's leaders (the same contact the profile shows
--                 them), so a link is sent by text message, WhatsApp or
--                 email straight to the player;
--   reminder      a leader reminds the players with an account who have not
--                 answered (team.survey.reminded.v1, at most once per link
--                 in 12 hours);
--   my surveys    the signed-in person's own open survey links, for a card
--                 on the home page;
--   averages      a player's answers come with the team's average for each
--                 scale question.

alter table core.team_survey_invites add column reminded_at timestamptz;

create or replace function internal.get_team_survey_for_actor(target_survey_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare survey core.team_surveys; leads boolean;
begin
 survey:=internal.team_survey_for_actor(target_survey_id,false);
 leads:=internal.actor_leads_team(survey.club_id,survey.team_id);
 return jsonb_build_object('id',survey.id,'team_id',survey.team_id,'title',survey.title,'intro',survey.intro,
  'questions',survey.questions,'state',survey.state,'open_token',survey.open_token,
  'created_at',survey.created_at,'updated_at',survey.updated_at,
  'can_edit',internal.tdp_can_edit(survey.club_id),
  'invites',coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',invite.id,
    'person_id',invite.club_person_id,'name',person.display_name,'token',invite.token,
    'notified_at',invite.notified_at,'reminded_at',invite.reminded_at,
    'has_account',account.id is not null,
    'phone',case when leads then coalesce(account.phone,person.phone) end,
    'email',case when leads then coalesce(account.contact_email,person.contact_email) end,
    'answered_at',(select response.updated_at from core.team_survey_responses response where response.invite_id=invite.id)))
    order by person.display_name,invite.id)
   from core.team_survey_invites invite join core.club_people person on person.id=invite.club_person_id
   left join lateral (select profile.id,profile.phone,profile.contact_email from core.person_account_links link
     join core.profiles profile on profile.id=link.profile_id
     where link.club_person_id=invite.club_person_id and link.state='active'
     order by link.created_at desc limit 1) account on true
   where invite.survey_id=survey.id),'[]'::jsonb),
  'responses',coalesce((select jsonb_agg(jsonb_build_object('id',response.id,'invite_id',response.invite_id,
    'person_id',response.club_person_id,'person_name',person.display_name,
    'respondent_name',response.respondent_name,'answers',response.answers,
    'submitted_at',response.submitted_at,'updated_at',response.updated_at)
    order by response.submitted_at,response.id)
   from core.team_survey_responses response left join core.club_people person on person.id=response.club_person_id
   where response.survey_id=survey.id),'[]'::jsonb),
  'players',coalesce((select jsonb_agg(jsonb_build_object('person_id',player.person_id,'name',player.name,
    'has_account',player.has_account) order by player.name,player.person_id)
   from internal.team_survey_players(survey.team_id) player),'[]'::jsonb));
end$$;

-- A reminder to the players with an account who have not answered. Only
-- while the survey is open; a link reminded in the last 12 hours waits.
create or replace function internal.remind_team_survey_for_actor(target_survey_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare survey core.team_surveys; due uuid[];
begin
 survey:=internal.team_survey_for_actor(target_survey_id,true);
 if survey.state<>'open' then raise check_violation using message='survey_not_open'; end if;
 select coalesce(array_agg(invite.id),'{}') into due from core.team_survey_invites invite
 where invite.survey_id=survey.id
  and (invite.reminded_at is null or invite.reminded_at<now()-interval '12 hours')
  and not exists(select 1 from core.team_survey_responses response where response.invite_id=invite.id)
  and exists(select 1 from core.person_account_links link where link.club_person_id=invite.club_person_id
   and link.state='active' and link.profile_id is distinct from auth.uid());
 if cardinality(due)>0 and to_regclass('internal.notification_outbox') is not null then
  execute $sql$
   insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,aggregate_id,
    recipient_profile_id,recipient_person_id,payload_ref)
   select $1,gen_random_uuid(),'team.survey.reminded.v1','team_survey',$2,link.profile_id,invite.club_person_id,
    jsonb_build_object('invite_id',invite.id,'survey_id',$2)
   from core.team_survey_invites invite
   join core.person_account_links link on link.club_person_id=invite.club_person_id and link.state='active'
   where invite.id=any($3) and link.profile_id is distinct from auth.uid()
   on conflict do nothing$sql$ using survey.club_id,survey.id,due;
 end if;
 update core.team_survey_invites set reminded_at=now(),notified_at=coalesce(notified_at,now()) where id=any(due);
 perform internal.team_survey_audit(survey,'team.survey.reminded.v1',jsonb_build_object('count',cardinality(due)));
 return internal.get_team_survey_for_actor(survey.id)||jsonb_build_object('reminded',cardinality(due));
end$$;

-- The signed-in person's own links to open surveys, unanswered first.
create or replace function internal.list_my_team_surveys_for_actor()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('survey_id',survey.id,'title',survey.title,
   'team_id',survey.team_id,'team_name',team.name,'token',invite.token,
   'answered_at',response.updated_at,'created_at',invite.created_at)
   order by response.id is not null,invite.created_at desc,invite.id)
  from core.team_survey_invites invite
  join core.team_surveys survey on survey.id=invite.survey_id and survey.state='open'
  join core.teams team on team.id=survey.team_id
  left join core.team_survey_responses response on response.invite_id=invite.id
  where exists(select 1 from core.person_account_links link where link.club_person_id=invite.club_person_id
   and link.state='active' and link.profile_id=auth.uid())),'[]'::jsonb);
end$$;

-- A player's answers, each with the team's average for the scale
-- questions and how many have answered the survey.
create or replace function internal.get_player_survey_answers_for_actor(target_team_id uuid,target_person_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.team_survey_club(target_team_id,false);
 return coalesce((select jsonb_agg(jsonb_build_object('survey_id',survey.id,'response_id',response.id,
   'title',survey.title,'state',survey.state,'questions',survey.questions,'answers',response.answers,
   'submitted_at',response.submitted_at,'updated_at',response.updated_at,
   'response_count',(select count(*) from core.team_survey_responses other where other.survey_id=survey.id),
   'averages',coalesce((select jsonb_object_agg(question->>'id',
      (select round(avg((other.answers->>(question->>'id'))::numeric),2)
       from core.team_survey_responses other where other.survey_id=survey.id
        and jsonb_typeof(other.answers->(question->>'id'))='number'))
     from jsonb_array_elements(survey.questions) question where question->>'kind'='scale'),'{}'::jsonb))
   order by response.updated_at desc,response.id)
  from core.team_survey_responses response join core.team_surveys survey on survey.id=response.survey_id
  where survey.team_id=target_team_id and response.club_person_id=target_person_id),'[]'::jsonb);
end$$;

create function api.remind_team_survey(target_survey_id uuid) returns jsonb language sql security invoker
 set search_path='' as $$select internal.remind_team_survey_for_actor(target_survey_id)$$;
create function api.list_my_team_surveys() returns jsonb language sql stable security invoker
 set search_path='' as $$select internal.list_my_team_surveys_for_actor()$$;

revoke all on function internal.remind_team_survey_for_actor(uuid),internal.list_my_team_surveys_for_actor(),
 api.remind_team_survey(uuid),api.list_my_team_surveys() from public,anon,authenticated;
grant execute on function internal.remind_team_survey_for_actor(uuid),internal.list_my_team_surveys_for_actor(),
 api.remind_team_survey(uuid),api.list_my_team_surveys() to authenticated;

notify pgrst,'reload schema';
