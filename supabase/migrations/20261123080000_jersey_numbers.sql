-- Shirt numbers in TeamZone: a player's number in a team, set with the
-- player's other team details, one number per player in a team. The team
-- roles list sends it, and again the main position and main title, which
-- 20261108090000 left out when it rewrote the list.

alter table core.team_person_details
  add column jersey_number smallint check (jersey_number is null or jersey_number between 0 and 999);
create unique index team_person_details_jersey_number on core.team_person_details (team_id, jersey_number)
  where jersey_number is not null;

-- As set_team_person_details_v4, with the shirt number; only players have one.
create or replace function internal.set_team_person_details_v5_for_actor(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_title text,new_main_position text,new_jersey_number integer,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare saved_revision bigint;
begin
 if new_jersey_number is not null and new_jersey_number not between 0 and 999 then
  raise invalid_parameter_value using message='invalid_jersey_number'; end if;
 saved_revision:=internal.set_team_person_details_v4_for_actor(target_club_id,target_team_id,target_person_id,
  new_titles,new_positions,new_custom_titles,new_custom_positions,new_main_title,new_main_position,
  expected_revision,idempotency_key);
 if new_jersey_number is not null and exists(select 1 from core.team_person_details
  where team_id=target_team_id and jersey_number=new_jersey_number and club_person_id<>target_person_id) then
  raise invalid_parameter_value using message='jersey_number_taken'; end if;
 update core.team_person_details set jersey_number=new_jersey_number::smallint
 where team_id=target_team_id and club_person_id=target_person_id and jersey_number is distinct from new_jersey_number::smallint;
 return saved_revision;
end$$;

-- As in 20261108090000, with the main position and title back and the
-- shirt number.
create or replace function internal.list_team_roles_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_sport text; manages_leaders boolean;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
  and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  and not internal.actor_has_capability(target_club_id,target_team_id,'team.leaders.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
 manages_leaders:=internal.actor_has_capability(target_club_id,target_team_id,'team.leaders.manage');
 select sport into team_sport from core.teams where id=target_team_id and club_id=target_club_id;
 return jsonb_build_object(
  'can_manage',manages_leaders,
  'can_edit_details',internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') or manages_leaders,
  'grantable',case when manages_leaders then to_jsonb(coalesce(array(select v from unnest(internal.leader_permission_catalog()) v
    where internal.actor_has_capability(target_club_id,target_team_id,v)),'{}')) else '[]'::jsonb end,
  'sport',coalesce(team_sport,'football'),
  'position_catalog',coalesce((select jsonb_agg(jsonb_build_object('key',catalog.key,'level',catalog.level,
    'parent',catalog.parent_key) order by catalog.sort) from core.sport_positions catalog
   where catalog.sport=team_sport),'[]'::jsonb),
  'roles',coalesce((select jsonb_agg(jsonb_build_object(
    'person_id',person.id,'name',person.display_name,'role',assignment.role_package,
    'starts_at',assignment.starts_at,'is_self',internal.actor_owns_club_person(target_club_id,person.id),
    'functions',coalesce(details.functions,'{}'::text[]),
    'positions',coalesce(details.positions,'{}'::text[]),
    'custom_titles',coalesce(details.custom_titles,'{}'::text[]),
    'custom_positions',coalesce(details.custom_positions,'{}'::text[]),
    'main_position',details.main_position,'main_title',details.main_title,
    'jersey_number',details.jersey_number,
    'details_revision',coalesce(details.revision,0),
    'permissions',case when manages_leaders and assignment.role_package='leader'
     then to_jsonb(internal.leader_panel_capabilities(target_club_id,target_team_id,person.id)) else null end,
    'permission_template',case when manages_leaders then details.permission_template else null end)
   order by case assignment.role_package when 'leader' then 0 when 'club_functionary' then 1 else 2 end,person.display_name,person.id)
   from core.assignments assignment
   join core.club_people person on person.id=assignment.club_person_id and person.club_id=assignment.club_id
   left join core.team_person_details details on details.club_id=assignment.club_id
    and details.team_id=assignment.team_id and details.club_person_id=assignment.club_person_id
   where assignment.club_id=target_club_id and assignment.team_id=target_team_id
    and assignment.role_package in('player','leader','club_functionary','referee','referee_assigner')
    and assignment.state='active' and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and person.status='active'),'[]'::jsonb));
end$$;

create or replace function api.set_team_person_details_v5(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_title text,new_main_position text,new_jersey_number integer,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as
$$ select internal.set_team_person_details_v5_for_actor(target_club_id,target_team_id,target_person_id,
 new_titles,new_positions,new_custom_titles,new_custom_positions,new_main_title,new_main_position,new_jersey_number,
 expected_revision,idempotency_key) $$;

revoke all on function
 internal.set_team_person_details_v5_for_actor(uuid,uuid,uuid,text[],text[],text[],text[],text,text,integer,bigint,uuid),
 api.set_team_person_details_v5(uuid,uuid,uuid,text[],text[],text[],text[],text,text,integer,bigint,uuid)
from public,anon,authenticated;
grant execute on function
 internal.set_team_person_details_v5_for_actor(uuid,uuid,uuid,text[],text[],text[],text[],text,text,integer,bigint,uuid),
 api.set_team_person_details_v5(uuid,uuid,uuid,text[],text[],text[],text[],text,text,integer,bigint,uuid)
to authenticated;
notify pgrst,'reload schema';
