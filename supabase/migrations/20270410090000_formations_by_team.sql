-- Tacticsboard knows a project's TeamZone team but not its club: the
-- attribute, formation and suggestion functions take no club (null) and find
-- it from the team. Access is checked as before, on the club and team.

create or replace function internal.club_of_team(target_club_id uuid,target_team_id uuid)
returns uuid language sql stable security definer set search_path='' as $$
 select coalesce(target_club_id,(select team.club_id from core.teams team where team.id=target_team_id))
$$;

create or replace function api.get_team_player_attributes(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$ select internal.get_team_player_attributes_for_actor(internal.club_of_team(target_club_id,target_team_id),target_team_id) $$;

create or replace function api.list_team_formations(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$ select internal.list_team_formations_for_actor(internal.club_of_team(target_club_id,target_team_id),target_team_id) $$;

create or replace function api.save_team_formation(target_club_id uuid,target_team_id uuid,formation_id uuid,
 new_name text,new_lines text,new_match_format text,new_slots jsonb,expected_revision bigint)
returns jsonb language sql security invoker set search_path='' as
$$ select internal.save_team_formation_for_actor(internal.club_of_team(target_club_id,target_team_id),target_team_id,
 formation_id,new_name,new_lines,new_match_format,new_slots,expected_revision) $$;

create or replace function api.delete_team_formation(target_club_id uuid,target_team_id uuid,formation_id uuid)
returns jsonb language sql security invoker set search_path='' as
$$ select internal.delete_team_formation_for_actor(internal.club_of_team(target_club_id,target_team_id),target_team_id,formation_id) $$;

create or replace function api.suggest_lineup(target_club_id uuid,target_team_id uuid,formation_id uuid,
 new_lines text,new_match_format text,candidate_ids uuid[],locked jsonb)
returns jsonb language sql stable security invoker set search_path='' as
$$ select internal.suggest_lineup_for_actor(internal.club_of_team(target_club_id,target_team_id),target_team_id,
 formation_id,new_lines,new_match_format,candidate_ids,locked) $$;

revoke all on function internal.club_of_team(uuid,uuid) from public,anon,authenticated;
grant execute on function internal.club_of_team(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
