-- Enkäter in Säsongsplanering (decided by the product owner 2026-11-22):
-- a team's leaders write a short survey, for instance before individual
-- player talks, and share it by link. The answers are kept as a basis for
-- the talks and the player's development later.
--
--   who writes   the team's leaders with Säsongsplanering
--                (development.manage, module.team_development);
--   links        a personal link per invited player (the answers belong to
--                the player at once; registered players also get a
--                notification), and an optional open link where one writes
--                one's name (a leader can then link the answer to a player);
--   answering    on Webtools' page /enkat/<token>, no account needed; the
--                page's server calls the service-only functions below;
--   who sees     the team's leaders with Säsongsplanering, never the other
--                players. A personal link shows its own earlier answers, so
--                they can be changed while the survey is open;
--   kept         until the leaders delete the answer or the survey.

create table core.team_surveys(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 team_id uuid not null references core.teams(id) on delete cascade,
 title text not null check(length(title) between 1 and 120 and title=btrim(title)),
 intro text not null default '' check(length(intro)<=2000),
 questions jsonb not null default '[]'::jsonb check(jsonb_typeof(questions)='array'),
 state text not null default 'draft' check(state in('draft','open','closed')),
 open_token text unique check(open_token ~ '^[a-f0-9]{32}$'),
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index team_surveys_team on core.team_surveys(team_id,created_at desc);

create table core.team_survey_invites(
 id uuid primary key default gen_random_uuid(),
 survey_id uuid not null references core.team_surveys(id) on delete cascade,
 club_person_id uuid not null references core.club_people(id) on delete cascade,
 token text not null unique default md5(random()::text||clock_timestamp()::text||gen_random_uuid()::text)
  check(token ~ '^[a-f0-9]{32}$'),
 notified_at timestamptz,
 created_at timestamptz not null default now(),
 unique(survey_id,club_person_id)
);

create table core.team_survey_responses(
 id uuid primary key default gen_random_uuid(),
 survey_id uuid not null references core.team_surveys(id) on delete cascade,
 invite_id uuid unique references core.team_survey_invites(id) on delete cascade,
 club_person_id uuid references core.club_people(id) on delete set null,
 respondent_name text check(respondent_name is null or length(respondent_name) between 2 and 120),
 answers jsonb not null check(jsonb_typeof(answers)='object'),
 ip_hash text,
 submitted_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(invite_id is not null or respondent_name is not null)
);
create index team_survey_responses_survey on core.team_survey_responses(survey_id,submitted_at);
create index team_survey_responses_person on core.team_survey_responses(club_person_id) where club_person_id is not null;
create index team_survey_responses_ip on core.team_survey_responses(ip_hash,submitted_at) where ip_hash is not null;

alter table core.team_surveys enable row level security;
alter table core.team_survey_invites enable row level security;
alter table core.team_survey_responses enable row level security;
revoke all on core.team_surveys,core.team_survey_invites,core.team_survey_responses from public,anon,authenticated;

-- The questions, checked and cleaned. Each is
--   {id, kind, label, required, options?, low?, high?}
-- kind: text (one line), long_text, scale (1-5, with optional words for 1
-- and 5), single or multi (2-12 options). At most 30 questions.
create or replace function internal.team_survey_questions(input jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare question jsonb; result jsonb:='[]'::jsonb; ids text[]:='{}'; kind text; label text; options jsonb;
 option jsonb; cleaned jsonb; option_texts text[];
begin
 if input is null or jsonb_typeof(input)<>'array' or jsonb_array_length(input)>30 then
  raise invalid_parameter_value using message='invalid_questions'; end if;
 for question in select value from jsonb_array_elements(input) loop
  if jsonb_typeof(question)<>'object' or coalesce(question->>'id','') !~ '^[a-z0-9]{4,16}$'
   or (question->>'id')=any(ids) then raise invalid_parameter_value using message='invalid_questions'; end if;
  ids:=ids||(question->>'id');
  kind:=question->>'kind';
  label:=regexp_replace(btrim(coalesce(question->>'label','')),'[ \t]+',' ','g');
  if kind is null or kind not in('text','long_text','scale','single','multi')
   or length(label) not between 1 and 300 then
   raise invalid_parameter_value using message='invalid_questions'; end if;
  cleaned:=jsonb_build_object('id',question->>'id','kind',kind,'label',label,
   'required',coalesce((question->>'required')::boolean,false));
  if kind in('single','multi') then
   options:=question->'options';
   if options is null or jsonb_typeof(options)<>'array' or jsonb_array_length(options) not between 2 and 12 then
    raise invalid_parameter_value using message='invalid_options'; end if;
   option_texts:='{}';
   for option in select value from jsonb_array_elements(options) loop
    if jsonb_typeof(option)<>'string' or length(btrim(option#>>'{}')) not between 1 and 100
     or lower(btrim(option#>>'{}'))=any(array(select lower(t) from unnest(option_texts) t)) then
     raise invalid_parameter_value using message='invalid_options'; end if;
    option_texts:=option_texts||btrim(option#>>'{}');
   end loop;
   cleaned:=cleaned||jsonb_build_object('options',to_jsonb(option_texts));
  elsif kind='scale' then
   if length(btrim(coalesce(question->>'low','')))>40 or length(btrim(coalesce(question->>'high','')))>40 then
    raise invalid_parameter_value using message='invalid_questions'; end if;
   cleaned:=cleaned||jsonb_build_object('low',btrim(coalesce(question->>'low','')),
    'high',btrim(coalesce(question->>'high','')));
  end if;
  result:=result||jsonb_build_array(cleaned);
 end loop;
 return result;
end$$;

-- One answer per question id, checked against the questions; unknown ids
-- and empty answers are left out. A required question must be answered.
create or replace function internal.team_survey_answers(questions jsonb,input jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare question jsonb; answer jsonb; result jsonb:='{}'::jsonb; value text; picked text[]; options text[];
begin
 if input is null or jsonb_typeof(input)<>'object' then
  raise invalid_parameter_value using message='invalid_answers'; end if;
 for question in select q from jsonb_array_elements(questions) q loop
  answer:=input->(question->>'id');
  if answer is not null and jsonb_typeof(answer)<>'null' then
   options:=array(select jsonb_array_elements_text(coalesce(question->'options','[]'::jsonb)));
   case question->>'kind'
    when 'text','long_text' then
     if jsonb_typeof(answer)<>'string' then raise invalid_parameter_value using message='invalid_answers'; end if;
     value:=btrim(answer#>>'{}');
     if length(value)>(array[300,4000])[(question->>'kind'='long_text')::int+1] then
      raise invalid_parameter_value using message='answer_too_long'; end if;
     if value<>'' then result:=result||jsonb_build_object(question->>'id',value); end if;
    when 'scale' then
     if jsonb_typeof(answer)<>'number' or (answer#>>'{}') !~ '^[1-5]$' then
      raise invalid_parameter_value using message='invalid_answers'; end if;
     result:=result||jsonb_build_object(question->>'id',(answer#>>'{}')::int);
    when 'single' then
     if jsonb_typeof(answer)<>'string' or not (answer#>>'{}')=any(options) then
      raise invalid_parameter_value using message='invalid_answers'; end if;
     result:=result||jsonb_build_object(question->>'id',answer#>>'{}');
    when 'multi' then
     if jsonb_typeof(answer)<>'array' then raise invalid_parameter_value using message='invalid_answers'; end if;
     picked:=array(select distinct jsonb_array_elements_text(answer));
     if exists(select 1 from unnest(picked) p where not p=any(options)) then
      raise invalid_parameter_value using message='invalid_answers'; end if;
     -- In the questions' order.
     picked:=array(select o from unnest(options) with ordinality as t(o,n) where o=any(picked) order by n);
     if cardinality(picked)>0 then result:=result||jsonb_build_object(question->>'id',to_jsonb(picked)); end if;
   end case;
  end if;
  if coalesce((question->>'required')::boolean,false) and not result ? (question->>'id') then
   raise invalid_parameter_value using message='answer_required'; end if;
 end loop;
 return result;
end$$;

-- The team's club for a leader with Säsongsplanering; with [edit], also
-- one who may change it (the module is not read-only).
create or replace function internal.team_survey_club(target_team_id uuid,edit boolean)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare club uuid;
begin
 club:=internal.tdp_team_club(target_team_id);
 if edit and not internal.tdp_can_edit(club) then raise insufficient_privilege using message='read_only'; end if;
 return club;
end$$;

create or replace function internal.team_survey_for_actor(target_survey_id uuid,edit boolean)
returns core.team_surveys language plpgsql stable security definer set search_path='' as $$
declare survey core.team_surveys;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into survey from core.team_surveys where id=target_survey_id;
 if survey.id is null then raise insufficient_privilege using message='not_found'; end if;
 perform internal.team_survey_club(survey.team_id,edit);
 return survey;
end$$;

-- The team's active players.
create or replace function internal.team_survey_players(target_team_id uuid)
returns table(person_id uuid,name text,has_account boolean) language sql stable security definer set search_path='' as $$
 select person.id,person.display_name,exists(select 1 from core.person_account_links link
   where link.club_person_id=person.id and link.state='active')
 from core.club_people person join core.teams team on team.id=target_team_id and team.club_id=person.club_id
 where person.status='active' and exists(select 1 from core.assignments assignment
  where assignment.club_id=person.club_id and assignment.team_id=target_team_id
   and assignment.club_person_id=person.id and assignment.role_package='player' and assignment.state='active'
   and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now()))
$$;

create or replace function internal.list_team_surveys_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare club uuid;
begin
 club:=internal.team_survey_club(target_team_id,false);
 return jsonb_build_object('can_edit',internal.tdp_can_edit(club),
  'surveys',coalesce((select jsonb_agg(jsonb_build_object('id',survey.id,'title',survey.title,'state',survey.state,
    'question_count',jsonb_array_length(survey.questions),
    'invited',(select count(*) from core.team_survey_invites invite where invite.survey_id=survey.id),
    'answered',(select count(*) from core.team_survey_responses response where response.survey_id=survey.id),
    'open_link',survey.open_token is not null,
    'created_at',survey.created_at,'updated_at',survey.updated_at) order by survey.created_at desc)
   from core.team_surveys survey where survey.team_id=target_team_id),'[]'::jsonb));
end$$;

create or replace function internal.get_team_survey_for_actor(target_survey_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare survey core.team_surveys;
begin
 survey:=internal.team_survey_for_actor(target_survey_id,false);
 return jsonb_build_object('id',survey.id,'team_id',survey.team_id,'title',survey.title,'intro',survey.intro,
  'questions',survey.questions,'state',survey.state,'open_token',survey.open_token,
  'created_at',survey.created_at,'updated_at',survey.updated_at,
  'can_edit',internal.tdp_can_edit(survey.club_id),
  'invites',coalesce((select jsonb_agg(jsonb_build_object('id',invite.id,'person_id',invite.club_person_id,
    'name',person.display_name,'token',invite.token,'notified_at',invite.notified_at,
    'has_account',exists(select 1 from core.person_account_links link
      where link.club_person_id=invite.club_person_id and link.state='active'),
    'answered_at',(select response.updated_at from core.team_survey_responses response where response.invite_id=invite.id))
    order by person.display_name,invite.id)
   from core.team_survey_invites invite join core.club_people person on person.id=invite.club_person_id
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

create or replace function internal.team_survey_audit(survey core.team_surveys,command text,metadata jsonb)
returns void language sql security definer set search_path='' as $$
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(survey.club_id,auth.uid(),command,'team_survey',survey.id,1,coalesce(metadata,'{}'::jsonb)||
  jsonb_build_object('team_id',survey.team_id))
$$;

-- A new survey when [target_survey_id] is null. The questions cannot be
-- changed once someone has answered; the title and the intro can.
create or replace function internal.save_team_survey_for_actor(target_team_id uuid,target_survey_id uuid,
 new_title text,new_intro text,new_questions jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare club uuid; survey core.team_surveys;
 clean_title text:=regexp_replace(btrim(coalesce(new_title,'')),'\s+',' ','g');
 clean_intro text:=btrim(coalesce(new_intro,'')); clean_questions jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 club:=internal.team_survey_club(target_team_id,true);
 if length(clean_title) not between 1 and 120 then raise invalid_parameter_value using message='invalid_title'; end if;
 if length(clean_intro)>2000 then raise invalid_parameter_value using message='invalid_intro'; end if;
 clean_questions:=internal.team_survey_questions(new_questions);
 if target_survey_id is null then
  if (select count(*) from core.team_surveys s where s.team_id=target_team_id)>=200 then
   raise invalid_parameter_value using message='too_many_surveys'; end if;
  insert into core.team_surveys(club_id,team_id,title,intro,questions,created_by)
  values(club,target_team_id,clean_title,clean_intro,clean_questions,auth.uid()) returning * into survey;
  perform internal.team_survey_audit(survey,'team.survey.created.v1','{}'::jsonb);
 else
  select * into survey from core.team_surveys s where s.id=target_survey_id and s.team_id=target_team_id for update;
  if survey.id is null then raise insufficient_privilege using message='not_found'; end if;
  if survey.questions<>clean_questions and exists(select 1 from core.team_survey_responses r where r.survey_id=survey.id) then
   raise check_violation using message='survey_has_answers'; end if;
  update core.team_surveys s set title=clean_title,intro=clean_intro,questions=clean_questions,updated_at=now()
  where s.id=survey.id;
 end if;
 return internal.get_team_survey_for_actor(survey.id);
end$$;

-- Registered players hear of their personal link when the survey is open
-- (once per invite). The notification itself is drawn in the next
-- migration; nothing is queued where there is no outbox.
create or replace function internal.team_survey_notify(target_survey_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare survey core.team_surveys;
begin
 select * into survey from core.team_surveys where id=target_survey_id;
 if survey.id is null or survey.state<>'open' or to_regclass('internal.notification_outbox') is null then return; end if;
 execute $sql$
  insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,aggregate_id,
   recipient_profile_id,recipient_person_id,payload_ref)
  select $1,gen_random_uuid(),'team.survey.invited.v1','team_survey',$2,link.profile_id,invite.club_person_id,
   jsonb_build_object('invite_id',invite.id,'survey_id',$2)
  from core.team_survey_invites invite
  join core.person_account_links link on link.club_person_id=invite.club_person_id and link.state='active'
  where invite.survey_id=$2 and invite.notified_at is null and link.profile_id is distinct from auth.uid()
  on conflict do nothing$sql$ using survey.club_id,survey.id;
 update core.team_survey_invites set notified_at=now() where survey_id=survey.id and notified_at is null
  and exists(select 1 from core.person_account_links link where link.club_person_id=team_survey_invites.club_person_id
   and link.state='active');
end$$;

create or replace function internal.set_team_survey_state_for_actor(target_survey_id uuid,new_state text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare survey core.team_surveys;
begin
 survey:=internal.team_survey_for_actor(target_survey_id,true);
 if new_state not in('open','closed') then raise invalid_parameter_value using message='invalid_state'; end if;
 if new_state='open' and jsonb_array_length(survey.questions)=0 then
  raise check_violation using message='survey_without_questions'; end if;
 if survey.state<>new_state then
  update core.team_surveys set state=new_state,updated_at=now() where id=survey.id;
  perform internal.team_survey_audit(survey,'team.survey.'||new_state||'.v1','{}'::jsonb);
  perform internal.team_survey_notify(survey.id);
 end if;
 return internal.get_team_survey_for_actor(survey.id);
end$$;

create or replace function internal.set_team_survey_open_link_for_actor(target_survey_id uuid,enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare survey core.team_surveys;
begin
 survey:=internal.team_survey_for_actor(target_survey_id,true);
 if enabled and survey.open_token is null then
  update core.team_surveys set open_token=md5(random()::text||clock_timestamp()::text||gen_random_uuid()::text),
   updated_at=now() where id=survey.id;
 elsif not enabled and survey.open_token is not null then
  update core.team_surveys set open_token=null,updated_at=now() where id=survey.id;
 end if;
 return internal.get_team_survey_for_actor(survey.id);
end$$;

-- Personal links for the team's players; a player already invited keeps
-- the link they have.
create or replace function internal.invite_team_survey_players_for_actor(target_survey_id uuid,person_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare survey core.team_surveys;
begin
 survey:=internal.team_survey_for_actor(target_survey_id,true);
 if person_ids is null or cardinality(person_ids)=0 or cardinality(person_ids)>100 then
  raise invalid_parameter_value using message='invalid_people'; end if;
 if exists(select 1 from unnest(person_ids) p where p not in(select player.person_id
   from internal.team_survey_players(survey.team_id) player)) then
  raise check_violation using message='invite_needs_player_role'; end if;
 insert into core.team_survey_invites(survey_id,club_person_id)
 select survey.id,p from unnest(person_ids) p on conflict(survey_id,club_person_id) do nothing;
 perform internal.team_survey_notify(survey.id);
 return internal.get_team_survey_for_actor(survey.id);
end$$;

-- A personal link stops working. Not once the player has answered: the
-- answer is deleted first.
create or replace function internal.remove_team_survey_invite_for_actor(target_invite_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare invite core.team_survey_invites; survey core.team_surveys;
begin
 select * into invite from core.team_survey_invites where id=target_invite_id;
 if invite.id is null then raise insufficient_privilege using message='not_found'; end if;
 survey:=internal.team_survey_for_actor(invite.survey_id,true);
 if exists(select 1 from core.team_survey_responses r where r.invite_id=invite.id) then
  raise check_violation using message='invite_answered'; end if;
 delete from core.team_survey_invites where id=invite.id;
 return internal.get_team_survey_for_actor(survey.id);
end$$;

-- An answer from the open link is linked to one of the team's players (or
-- unlinked again with null).
create or replace function internal.link_team_survey_response_for_actor(target_response_id uuid,target_person_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare response core.team_survey_responses; survey core.team_surveys;
begin
 select * into response from core.team_survey_responses where id=target_response_id;
 if response.id is null then raise insufficient_privilege using message='not_found'; end if;
 survey:=internal.team_survey_for_actor(response.survey_id,true);
 if response.invite_id is not null then raise check_violation using message='personal_answer'; end if;
 if target_person_id is not null and target_person_id not in(select player.person_id
   from internal.team_survey_players(survey.team_id) player) then
  raise check_violation using message='link_needs_player_role'; end if;
 update core.team_survey_responses set club_person_id=target_person_id where id=response.id;
 return internal.get_team_survey_for_actor(survey.id);
end$$;

create or replace function internal.delete_team_survey_response_for_actor(target_response_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare response core.team_survey_responses; survey core.team_surveys;
begin
 select * into response from core.team_survey_responses where id=target_response_id;
 if response.id is null then raise insufficient_privilege using message='not_found'; end if;
 survey:=internal.team_survey_for_actor(response.survey_id,true);
 delete from core.team_survey_responses where id=response.id;
 perform internal.team_survey_audit(survey,'team.survey.answer_deleted.v1',jsonb_build_object('response_id',response.id));
 return internal.get_team_survey_for_actor(survey.id);
end$$;

create or replace function internal.delete_team_survey_for_actor(target_survey_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare survey core.team_surveys;
begin
 survey:=internal.team_survey_for_actor(target_survey_id,true);
 delete from core.team_surveys where id=survey.id;
 perform internal.team_survey_audit(survey,'team.survey.deleted.v1',jsonb_build_object('title',survey.title));
end$$;

-- A player's answers in the team's surveys, newest first: for the
-- player's page and the talk.
create or replace function internal.get_player_survey_answers_for_actor(target_team_id uuid,target_person_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.team_survey_club(target_team_id,false);
 return coalesce((select jsonb_agg(jsonb_build_object('survey_id',survey.id,'response_id',response.id,
   'title',survey.title,'state',survey.state,'questions',survey.questions,'answers',response.answers,
   'submitted_at',response.submitted_at,'updated_at',response.updated_at)
   order by response.updated_at desc,response.id)
  from core.team_survey_responses response join core.team_surveys survey on survey.id=response.survey_id
  where survey.team_id=target_team_id and response.club_person_id=target_person_id),'[]'::jsonb);
end$$;

-- Public side, for Webtools' server only (service role). A token is a
-- personal link or a survey's open link.
create or replace function internal.public_get_team_survey(public_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare invite core.team_survey_invites; survey core.team_surveys; team_name text; club_name text;
 person_name text; answers jsonb;
begin
 if current_user not in('service_role','postgres') then raise insufficient_privilege using message='service_role_required'; end if;
 if coalesce(public_token,'') !~ '^[a-f0-9]{32}$' then return jsonb_build_object('not_found',true); end if;
 select * into invite from core.team_survey_invites i where i.token=public_token;
 if invite.id is not null then
  select * into survey from core.team_surveys s where s.id=invite.survey_id;
  select person.display_name into person_name from core.club_people person where person.id=invite.club_person_id;
  select r.answers into answers from core.team_survey_responses r where r.invite_id=invite.id;
 else
  select * into survey from core.team_surveys s where s.open_token=public_token;
 end if;
 if survey.id is null or survey.state='draft' then return jsonb_build_object('not_found',true); end if;
 select team.name,club.name into team_name,club_name from core.teams team join core.clubs club on club.id=team.club_id
 where team.id=survey.team_id;
 return jsonb_build_object('kind',case when invite.id is null then 'open' else 'personal' end,
  'title',survey.title,'intro',survey.intro,'questions',survey.questions,'state',survey.state,
  'team_name',team_name,'club_name',club_name,'person_name',person_name,'answers',answers);
end$$;

create or replace function internal.public_submit_team_survey(public_token text,respondent_name text,
 answers jsonb,ip_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare invite core.team_survey_invites; survey core.team_surveys; cleaned jsonb;
 name text:=regexp_replace(btrim(coalesce(respondent_name,'')),'\s+',' ','g');
begin
 if current_user not in('service_role','postgres') then raise insufficient_privilege using message='service_role_required'; end if;
 if coalesce(public_token,'') !~ '^[a-f0-9]{32}$' then return jsonb_build_object('not_found',true); end if;
 select * into invite from core.team_survey_invites i where i.token=public_token;
 if invite.id is not null then
  select * into survey from core.team_surveys s where s.id=invite.survey_id for update;
 else
  select * into survey from core.team_surveys s where s.open_token=public_token for update;
 end if;
 if survey.id is null or survey.state='draft' then return jsonb_build_object('not_found',true); end if;
 if survey.state='closed' then return jsonb_build_object('closed',true); end if;
 cleaned:=internal.team_survey_answers(survey.questions,answers);
 if invite.id is not null then
  insert into core.team_survey_responses(survey_id,invite_id,club_person_id,answers)
  values(survey.id,invite.id,invite.club_person_id,cleaned)
  on conflict(invite_id) do update set answers=excluded.answers,updated_at=now();
 else
  if length(name) not between 2 and 120 then raise invalid_parameter_value using message='name_required'; end if;
  if ip_hash is null or length(ip_hash)<16 then raise invalid_parameter_value using message='invalid_request'; end if;
  if (select count(*) from core.team_survey_responses r where r.ip_hash=public_submit_team_survey.ip_hash
      and r.submitted_at>now()-interval '1 hour')>=10
   or (select count(*) from core.team_survey_responses r where r.survey_id=survey.id and r.invite_id is null)>=300 then
   raise invalid_parameter_value using message='rate_limited'; end if;
  insert into core.team_survey_responses(survey_id,respondent_name,answers,ip_hash)
  values(survey.id,name,cleaned,ip_hash);
 end if;
 return jsonb_build_object('accepted',true);
end$$;

create function api.list_team_surveys(target_team_id uuid) returns jsonb language sql stable security invoker
 set search_path='' as $$select internal.list_team_surveys_for_actor(target_team_id)$$;
create function api.get_team_survey(target_survey_id uuid) returns jsonb language sql stable security invoker
 set search_path='' as $$select internal.get_team_survey_for_actor(target_survey_id)$$;
create function api.save_team_survey(target_team_id uuid,target_survey_id uuid,new_title text,new_intro text,
 new_questions jsonb) returns jsonb language sql security invoker set search_path='' as
 $$select internal.save_team_survey_for_actor(target_team_id,target_survey_id,new_title,new_intro,new_questions)$$;
create function api.set_team_survey_state(target_survey_id uuid,new_state text) returns jsonb language sql
 security invoker set search_path='' as $$select internal.set_team_survey_state_for_actor(target_survey_id,new_state)$$;
create function api.set_team_survey_open_link(target_survey_id uuid,enabled boolean) returns jsonb language sql
 security invoker set search_path='' as $$select internal.set_team_survey_open_link_for_actor(target_survey_id,enabled)$$;
create function api.invite_team_survey_players(target_survey_id uuid,person_ids uuid[]) returns jsonb language sql
 security invoker set search_path='' as $$select internal.invite_team_survey_players_for_actor(target_survey_id,person_ids)$$;
create function api.remove_team_survey_invite(target_invite_id uuid) returns jsonb language sql
 security invoker set search_path='' as $$select internal.remove_team_survey_invite_for_actor(target_invite_id)$$;
create function api.link_team_survey_response(target_response_id uuid,target_person_id uuid) returns jsonb
 language sql security invoker set search_path='' as
 $$select internal.link_team_survey_response_for_actor(target_response_id,target_person_id)$$;
create function api.delete_team_survey_response(target_response_id uuid) returns jsonb language sql
 security invoker set search_path='' as $$select internal.delete_team_survey_response_for_actor(target_response_id)$$;
create function api.delete_team_survey(target_survey_id uuid) returns void language sql
 security invoker set search_path='' as $$select internal.delete_team_survey_for_actor(target_survey_id)$$;
create function api.get_player_survey_answers(target_team_id uuid,target_person_id uuid) returns jsonb
 language sql stable security invoker set search_path='' as
 $$select internal.get_player_survey_answers_for_actor(target_team_id,target_person_id)$$;
create function api.public_get_team_survey(public_token text) returns jsonb language sql stable
 security invoker set search_path='' as $$select internal.public_get_team_survey(public_token)$$;
create function api.public_submit_team_survey(public_token text,respondent_name text,answers jsonb,ip_hash text)
 returns jsonb language sql security invoker set search_path='' as
 $$select internal.public_submit_team_survey(public_token,respondent_name,answers,ip_hash)$$;

revoke all on function internal.team_survey_questions(jsonb),internal.team_survey_answers(jsonb,jsonb),
 internal.team_survey_club(uuid,boolean),internal.team_survey_for_actor(uuid,boolean),
 internal.team_survey_players(uuid),internal.list_team_surveys_for_actor(uuid),
 internal.get_team_survey_for_actor(uuid),internal.team_survey_audit(core.team_surveys,text,jsonb),
 internal.save_team_survey_for_actor(uuid,uuid,text,text,jsonb),internal.team_survey_notify(uuid),
 internal.set_team_survey_state_for_actor(uuid,text),internal.set_team_survey_open_link_for_actor(uuid,boolean),
 internal.invite_team_survey_players_for_actor(uuid,uuid[]),internal.remove_team_survey_invite_for_actor(uuid),
 internal.link_team_survey_response_for_actor(uuid,uuid),internal.delete_team_survey_response_for_actor(uuid),
 internal.delete_team_survey_for_actor(uuid),internal.get_player_survey_answers_for_actor(uuid,uuid),
 internal.public_get_team_survey(text),internal.public_submit_team_survey(text,text,jsonb,text),
 api.list_team_surveys(uuid),api.get_team_survey(uuid),api.save_team_survey(uuid,uuid,text,text,jsonb),
 api.set_team_survey_state(uuid,text),api.set_team_survey_open_link(uuid,boolean),
 api.invite_team_survey_players(uuid,uuid[]),api.remove_team_survey_invite(uuid),
 api.link_team_survey_response(uuid,uuid),api.delete_team_survey_response(uuid),api.delete_team_survey(uuid),
 api.get_player_survey_answers(uuid,uuid),api.public_get_team_survey(text),
 api.public_submit_team_survey(text,text,jsonb,text)
 from public,anon,authenticated;
grant execute on function internal.list_team_surveys_for_actor(uuid),internal.get_team_survey_for_actor(uuid),
 internal.save_team_survey_for_actor(uuid,uuid,text,text,jsonb),internal.set_team_survey_state_for_actor(uuid,text),
 internal.set_team_survey_open_link_for_actor(uuid,boolean),internal.invite_team_survey_players_for_actor(uuid,uuid[]),
 internal.remove_team_survey_invite_for_actor(uuid),internal.link_team_survey_response_for_actor(uuid,uuid),
 internal.delete_team_survey_response_for_actor(uuid),internal.delete_team_survey_for_actor(uuid),
 internal.get_player_survey_answers_for_actor(uuid,uuid),
 api.list_team_surveys(uuid),api.get_team_survey(uuid),api.save_team_survey(uuid,uuid,text,text,jsonb),
 api.set_team_survey_state(uuid,text),api.set_team_survey_open_link(uuid,boolean),
 api.invite_team_survey_players(uuid,uuid[]),api.remove_team_survey_invite(uuid),
 api.link_team_survey_response(uuid,uuid),api.delete_team_survey_response(uuid),api.delete_team_survey(uuid),
 api.get_player_survey_answers(uuid,uuid)
 to authenticated;
grant execute on function internal.public_get_team_survey(text),internal.public_submit_team_survey(text,text,jsonb,text),
 api.public_get_team_survey(text),api.public_submit_team_survey(text,text,jsonb,text)
 to service_role;

notify pgrst,'reload schema';
