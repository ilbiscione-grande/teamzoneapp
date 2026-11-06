-- A live lesson takes 12 participants: a line or a starting eleven with room
-- to spare. More is a paid extra to come, not part of the subscription.
-- Whoever has joined keeps their seat in that lesson, also after a reload.
create or replace function internal.join_tactics_live_for_actor(target_code text, participant_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  session core.tactics_live_sessions;
  project core.tactics_projects;
  joined core.tactics_live_participants;
  guest boolean := internal.tactics_live_actor_is_guest();
  name text := btrim(coalesce(participant_name, ''));
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into session from core.tactics_live_sessions
  where code = upper(btrim(coalesce(target_code, ''))) and status = 'live' order by created_at desc limit 1;
  if session.id is null or not internal.tactics_live_is_open(session) then raise invalid_parameter_value using message = 'not_found'; end if;
  if guest and not session.allow_guests then raise insufficient_privilege using message = 'login_required'; end if;
  if name = '' and not guest then
    name := coalesce(nullif(btrim((select display_name from core.profiles where id = auth.uid())), ''), 'Deltagare');
  end if;
  if length(name) not between 1 and 40 then raise invalid_parameter_value using message = 'invalid_name'; end if;
  -- One at a time, so that two joining at once cannot both take the last seat.
  perform 1 from core.tactics_live_sessions where id = session.id for update;
  if not exists (select 1 from core.tactics_live_participants where session_id = session.id and profile_id = auth.uid())
    and (select count(*) from core.tactics_live_participants where session_id = session.id) >= 12 then
    raise check_violation using message = 'session_full';
  end if;
  insert into core.tactics_live_participants (session_id, profile_id, display_name, is_guest)
  values (session.id, auth.uid(), name, guest)
  on conflict (session_id, profile_id) do update set display_name = excluded.display_name, is_guest = excluded.is_guest
  returning * into joined;
  select * into project from core.tactics_projects where id = session.project_id;
  return internal.tactics_live_summary(session) || jsonb_build_object(
    'name', project.name, 'kind', project.kind, 'document', project.document, 'participant_name', name, 'muted', joined.muted,
    'host_name', coalesce(nullif(btrim((select display_name from core.profiles where id = session.host_id)), ''), 'Läraren')
  );
end;
$$;
