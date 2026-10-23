-- Webtools Tacticsboard, live lessons, step 4: questions on the pitch and a
-- summary afterwards. The host asks a question on the board and frame in
-- hand ("Where should 6 stand when we lose the ball?"); each participant
-- answers with one marker on the pitch, and may move it while the question
-- is open. Answers reach the host alone until the host shows them to
-- everyone, then as points without names. One question is open at a time.
-- When the lesson is over, its host reads who was there, the chat and the
-- answers; the host's earlier lessons are listed per project.

create table core.tactics_live_questions (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references core.tactics_live_sessions(id) on delete cascade,
  board_id text not null check (length(board_id) between 1 and 80),
  frame_index integer not null check (frame_index between 0 and 500),
  prompt text not null check (length(prompt) between 1 and 200),
  status text not null default 'open' check (status in ('open', 'closed')),
  revealed boolean not null default false,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create index tactics_live_questions_session on core.tactics_live_questions (session_id, created_at);

create table core.tactics_live_answers (
  question_id uuid not null references core.tactics_live_questions(id) on delete cascade,
  profile_id uuid not null,
  display_name text not null,
  x numeric not null check (x between -60 and 170),
  y numeric not null check (y between -60 and 130),
  updated_at timestamptz not null default now(),
  primary key (question_id, profile_id)
);

alter table core.tactics_live_questions enable row level security;
alter table core.tactics_live_answers enable row level security;
revoke all on core.tactics_live_questions, core.tactics_live_answers from public, anon, authenticated;

-- An answer is activity (20261128090000).
create or replace function internal.tactics_live_touch_from_answer()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update core.tactics_live_sessions set last_activity_at = now()
  where id = (select session_id from core.tactics_live_questions where id = new.question_id)
    and status = 'live' and last_activity_at < now() - interval '10 seconds';
  return new;
end;
$$;
create trigger tactics_live_answers_touch after insert or update on core.tactics_live_answers
  for each row execute function internal.tactics_live_touch_from_answer();

create or replace function internal.tactics_live_points(target_question_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_array(answer.x, answer.y)), '[]'::jsonb)
  from core.tactics_live_answers answer where answer.question_id = target_question_id
$$;

-- A question as its reader may see it: the host with every answer and name,
-- a participant with their own answer, and the points once shown.
create or replace function internal.tactics_live_question_json(question core.tactics_live_questions, for_host boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', question.id, 'board_id', question.board_id, 'frame_index', question.frame_index, 'prompt', question.prompt,
    'status', question.status, 'revealed', question.revealed, 'created_at', question.created_at,
    'answer_count', (select count(*) from core.tactics_live_answers where question_id = question.id),
    'answers', case when for_host then coalesce((
      select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', a.display_name, 'x', a.x, 'y', a.y) order by a.updated_at)
      from core.tactics_live_answers a where a.question_id = question.id), '[]'::jsonb) else null end,
    'mine', case when for_host then null else (
      select jsonb_build_object('x', a.x, 'y', a.y) from core.tactics_live_answers a
      where a.question_id = question.id and a.profile_id = auth.uid()) end,
    'points', case when question.revealed or for_host then internal.tactics_live_points(question.id) else null end
  )
$$;

create or replace function internal.ask_tactics_live_question_for_actor(target_session_id uuid, target_board_id text, target_frame_index integer, question_prompt text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  asked core.tactics_live_questions;
  prompt text := btrim(coalesce(question_prompt, ''));
begin
  session := internal.tactics_live_require_host(target_session_id);
  if not internal.tactics_live_is_open(session) then raise insufficient_privilege using message = 'not_found'; end if;
  if length(prompt) not between 1 and 200 or length(coalesce(target_board_id, '')) not between 1 and 80
    or coalesce(target_frame_index, -1) not between 0 and 500 then
    raise invalid_parameter_value using message = 'invalid_question';
  end if;
  update core.tactics_live_questions set status = 'closed', closed_at = now() where session_id = session.id and status = 'open';
  insert into core.tactics_live_questions (session_id, board_id, frame_index, prompt)
  values (session.id, target_board_id, target_frame_index, prompt) returning * into asked;
  perform realtime.send(internal.tactics_live_question_json(asked, false), 'question', 'tactics-live:' || session.id::text, true);
  return internal.tactics_live_question_json(asked, true);
end;
$$;

-- A participant's marker, moved as often as they like while the question is open.
create or replace function internal.answer_tactics_live_question_for_actor(target_question_id uuid, answer_x numeric, answer_y numeric)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  question core.tactics_live_questions;
  session core.tactics_live_sessions;
  name text;
begin
  select * into question from core.tactics_live_questions where id = target_question_id;
  if question.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  session := internal.tactics_live_member_session(question.session_id);
  if session.host_id = auth.uid() then raise insufficient_privilege using message = 'host_does_not_answer'; end if;
  if question.status <> 'open' then raise insufficient_privilege using message = 'question_closed'; end if;
  if answer_x is null or answer_y is null or answer_x not between -60 and 170 or answer_y not between -60 and 130 then
    raise invalid_parameter_value using message = 'invalid_answer';
  end if;
  select display_name into name from core.tactics_live_participants where session_id = session.id and profile_id = auth.uid();
  insert into core.tactics_live_answers (question_id, profile_id, display_name, x, y)
  values (question.id, auth.uid(), name, round(answer_x, 2), round(answer_y, 2))
  on conflict (question_id, profile_id) do update set x = excluded.x, y = excluded.y, updated_at = now();
  perform realtime.send(jsonb_build_object('questionId', question.id, 'profileId', auth.uid(), 'name', name, 'x', round(answer_x, 2), 'y', round(answer_y, 2)),
    'answer', 'tactics-live-host:' || session.id::text, true);
  return jsonb_build_object('x', round(answer_x, 2), 'y', round(answer_y, 2));
end;
$$;

-- No more answers; shown to everyone or not (shown can come later too).
create or replace function internal.close_tactics_live_question_for_actor(target_question_id uuid, show_answers boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare question core.tactics_live_questions;
begin
  select * into question from core.tactics_live_questions where id = target_question_id;
  if question.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  perform internal.tactics_live_require_host(question.session_id);
  update core.tactics_live_questions
  set status = 'closed', closed_at = coalesce(closed_at, now()), revealed = revealed or coalesce(show_answers, false)
  where id = question.id returning * into question;
  perform realtime.send(internal.tactics_live_question_json(question, false), 'question', 'tactics-live:' || question.session_id::text, true);
  return internal.tactics_live_question_json(question, true);
end;
$$;

-- The session's questions as the one asking may see them, the latest last.
create or replace function internal.list_tactics_live_questions_for_actor(target_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  session := internal.tactics_live_member_session(target_session_id);
  return coalesce((select jsonb_agg(internal.tactics_live_question_json(question, session.host_id = auth.uid()) order by question.created_at)
    from core.tactics_live_questions question where question.session_id = session.id), '[]'::jsonb);
end;
$$;

-- After the lesson: who was there, the chat and the questions with their answers. The host's alone.
create or replace function internal.get_tactics_live_summary_for_actor(target_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare session core.tactics_live_sessions;
begin
  select * into session from core.tactics_live_sessions where id = target_session_id;
  if session.id is null or session.host_id is distinct from auth.uid() then raise insufficient_privilege using message = 'not_found'; end if;
  return jsonb_build_object(
    'id', session.id, 'code', session.code, 'created_at', session.created_at,
    'ended_at', coalesce(session.ended_at, case when internal.tactics_live_is_open(session) then null else session.last_activity_at end),
    'participants', coalesce((select jsonb_agg(jsonb_build_object('name', p.display_name, 'guest', p.is_guest, 'joined_at', p.joined_at) order by p.joined_at)
      from core.tactics_live_participants p where p.session_id = session.id), '[]'::jsonb),
    'messages', coalesce((select jsonb_agg(internal.tactics_live_message_json(m) order by m.created_at)
      from core.tactics_live_messages m where m.session_id = session.id and m.deleted_at is null), '[]'::jsonb),
    'questions', coalesce((select jsonb_agg(internal.tactics_live_question_json(q, true) order by q.created_at)
      from core.tactics_live_questions q where q.session_id = session.id), '[]'::jsonb)
  );
end;
$$;

-- The host's lessons on a project, the latest first.
create or replace function internal.list_tactics_live_sessions_for_actor(target_project_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', session.id, 'code', session.code, 'created_at', session.created_at, 'live', internal.tactics_live_is_open(session),
    'participant_count', (select count(*) from core.tactics_live_participants p where p.session_id = session.id),
    'question_count', (select count(*) from core.tactics_live_questions q where q.session_id = session.id)
  ) order by session.created_at desc), '[]'::jsonb)
  from core.tactics_live_sessions session
  where session.project_id = target_project_id and session.host_id = auth.uid()
$$;

create or replace function api.ask_tactics_live_question(target_session_id uuid, target_board_id text, target_frame_index integer, question_prompt text) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.ask_tactics_live_question_for_actor(target_session_id, target_board_id, target_frame_index, question_prompt) $$;
create or replace function api.answer_tactics_live_question(target_question_id uuid, answer_x numeric, answer_y numeric) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.answer_tactics_live_question_for_actor(target_question_id, answer_x, answer_y) $$;
create or replace function api.close_tactics_live_question(target_question_id uuid, show_answers boolean) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.close_tactics_live_question_for_actor(target_question_id, show_answers) $$;
create or replace function api.list_tactics_live_questions(target_session_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_tactics_live_questions_for_actor(target_session_id) $$;
create or replace function api.get_tactics_live_summary(target_session_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_tactics_live_summary_for_actor(target_session_id) $$;
create or replace function api.list_tactics_live_sessions(target_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_tactics_live_sessions_for_actor(target_project_id) $$;

revoke all on function
  internal.tactics_live_touch_from_answer(), internal.tactics_live_points(uuid),
  internal.tactics_live_question_json(core.tactics_live_questions, boolean),
  internal.ask_tactics_live_question_for_actor(uuid, text, integer, text), internal.answer_tactics_live_question_for_actor(uuid, numeric, numeric),
  internal.close_tactics_live_question_for_actor(uuid, boolean), internal.list_tactics_live_questions_for_actor(uuid),
  internal.get_tactics_live_summary_for_actor(uuid), internal.list_tactics_live_sessions_for_actor(uuid),
  api.ask_tactics_live_question(uuid, text, integer, text), api.answer_tactics_live_question(uuid, numeric, numeric),
  api.close_tactics_live_question(uuid, boolean), api.list_tactics_live_questions(uuid),
  api.get_tactics_live_summary(uuid), api.list_tactics_live_sessions(uuid)
from public, anon, authenticated;
grant execute on function
  internal.tactics_live_points(uuid), internal.tactics_live_question_json(core.tactics_live_questions, boolean),
  internal.ask_tactics_live_question_for_actor(uuid, text, integer, text), internal.answer_tactics_live_question_for_actor(uuid, numeric, numeric),
  internal.close_tactics_live_question_for_actor(uuid, boolean), internal.list_tactics_live_questions_for_actor(uuid),
  internal.get_tactics_live_summary_for_actor(uuid), internal.list_tactics_live_sessions_for_actor(uuid),
  api.ask_tactics_live_question(uuid, text, integer, text), api.answer_tactics_live_question(uuid, numeric, numeric),
  api.close_tactics_live_question(uuid, boolean), api.list_tactics_live_questions(uuid),
  api.get_tactics_live_summary(uuid), api.list_tactics_live_sessions(uuid)
to authenticated;
