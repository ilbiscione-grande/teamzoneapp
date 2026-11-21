-- The app's line-up knows its match, not the team (step 6 of
-- docs/implementation/player-attributes.md): the team's formations and the
-- suggestion by the event. The players to choose from are the app's called
-- players; those who may no longer play for the team (an ended role or
-- representation) are left out instead of failing the suggestion.

create or replace function internal.require_event_team(target_event_id uuid,out club_id uuid,out team_id uuid)
language plpgsql stable security definer set search_path='' as $$
begin
 select event_row.club_id,event_row.owning_team_id into club_id,team_id
 from core.events event_row where event_row.id=target_event_id;
 if team_id is null then raise insufficient_privilege using message='not_found'; end if;
end$$;

-- The team's formations and its own attributes' names, for the team's leaders.
create or replace function internal.list_event_team_formations_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_team record;
begin
 select * into event_team from internal.require_event_team(target_event_id);
 return internal.list_team_formations_for_actor(event_team.club_id,event_team.team_id)
  ||jsonb_build_object('custom',coalesce((select jsonb_agg(jsonb_build_object('id',own.id,'label',own.label)
   order by lower(own.label)) from core.team_attributes own where own.team_id=event_team.team_id),'[]'::jsonb));
end$$;

create or replace function internal.suggest_event_lineup_for_actor(target_event_id uuid,formation_id uuid,
 new_lines text,new_match_format text,candidate_ids uuid[],locked jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_team record; allowed uuid[];
begin
 select * into event_team from internal.require_event_team(target_event_id);
 if candidate_ids is not null then
  allowed:=coalesce(array(select c from unnest(candidate_ids) c where c is not null and (
   exists(select 1 from core.assignments a where a.club_id=event_team.club_id and a.team_id=event_team.team_id
    and a.club_person_id=c and a.role_package='player' and a.state='active')
   or exists(select 1 from core.play_eligibilities e where e.club_id=event_team.club_id and e.team_id=event_team.team_id
    and e.club_person_id=c and e.state='active' and e.starts_at<=now() and e.ends_at>now()))),'{}');
 end if;
 return internal.suggest_lineup_for_actor(event_team.club_id,event_team.team_id,formation_id,
  new_lines,new_match_format,allowed,locked);
end$$;

create function api.list_event_team_formations(target_event_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$ select internal.list_event_team_formations_for_actor(target_event_id) $$;
create function api.suggest_event_lineup(target_event_id uuid,formation_id uuid,
 new_lines text,new_match_format text,candidate_ids uuid[],locked jsonb)
returns jsonb language sql stable security invoker set search_path='' as
$$ select internal.suggest_event_lineup_for_actor(target_event_id,formation_id,new_lines,new_match_format,candidate_ids,locked) $$;

revoke all on function
 internal.require_event_team(uuid),
 internal.list_event_team_formations_for_actor(uuid),
 internal.suggest_event_lineup_for_actor(uuid,uuid,text,text,uuid[],jsonb),
 api.list_event_team_formations(uuid),
 api.suggest_event_lineup(uuid,uuid,text,text,uuid[],jsonb)
from public,anon,authenticated;
grant execute on function
 internal.list_event_team_formations_for_actor(uuid),
 internal.suggest_event_lineup_for_actor(uuid,uuid,text,text,uuid[],jsonb),
 api.list_event_team_formations(uuid),
 api.suggest_event_lineup(uuid,uuid,text,text,uuid[],jsonb)
to authenticated;
notify pgrst,'reload schema';
