-- Titles (UI: "Titel", stored as `functions`) and playing positions per team
-- person, now:
--  * tied to the role they describe: titles need a leader/functionary role,
--    positions need a player role (enforced here, not only in the UI);
--  * cleared automatically when that role ends, whichever flow ends it;
--  * positions come from a per-sport catalog with two levels (general and
--    detailed), so football and handball can differ;
--  * extendable with the team's own labels (custom titles/positions).
-- Still descriptive only: nothing here grants or removes capabilities.

alter table core.teams add column sport text not null default 'football'
 check(sport in('football','handball','other'));

create table core.sport_positions(
 sport text not null check(sport in('football','handball','other')),
 key text not null check(key ~ '^[a-z_]{2,40}$'),
 level text not null check(level in('general','detailed')),
 parent_key text,
 sort integer not null,
 primary key(sport,key),
 foreign key(sport,parent_key) references core.sport_positions(sport,key),
 check((level='general' and parent_key is null) or (level='detailed' and parent_key is not null))
);
alter table core.sport_positions enable row level security;
revoke all on core.sport_positions from public,anon,authenticated;

insert into core.sport_positions(sport,key,level,parent_key,sort) values
 ('football','goalkeeper','general',null,10),
 ('football','defender','general',null,20),
 ('football','midfielder','general',null,30),
 ('football','forward','general',null,40),
 ('football','centre_back','detailed','defender',21),
 ('football','left_back','detailed','defender',22),
 ('football','right_back','detailed','defender',23),
 ('football','wing_back','detailed','defender',24),
 ('football','defensive_midfielder','detailed','midfielder',31),
 ('football','central_midfielder','detailed','midfielder',32),
 ('football','attacking_midfielder','detailed','midfielder',33),
 ('football','left_winger','detailed','forward',41),
 ('football','right_winger','detailed','forward',42),
 ('football','striker','detailed','forward',43),
 ('handball','goalkeeper','general',null,10),
 ('handball','hb_backcourt','general',null,20),
 ('handball','hb_wing','general',null,30),
 ('handball','hb_pivot','general',null,40),
 ('handball','hb_left_back','detailed','hb_backcourt',21),
 ('handball','hb_centre_back','detailed','hb_backcourt',22),
 ('handball','hb_right_back','detailed','hb_backcourt',23),
 ('handball','hb_left_wing','detailed','hb_wing',31),
 ('handball','hb_right_wing','detailed','hb_wing',32);

create function internal.valid_custom_labels(labels text[])
returns boolean language sql immutable set search_path='' as $$
 select cardinality(labels)<=5 and array_position(labels,null) is null
  and not exists(select 1 from unnest(labels) label where length(btrim(label)) not between 1 and 40 or label<>btrim(label))
$$;

alter table core.team_person_details
 add column custom_titles text[] not null default '{}' check(internal.valid_custom_labels(custom_titles)),
 add column custom_positions text[] not null default '{}' check(internal.valid_custom_labels(custom_positions));

-- Positions are validated against the team's sport catalog instead of a
-- fixed football-only list.
do $$ declare constraint_name text;
begin
 for constraint_name in select con.conname from pg_constraint con
  where con.conrelid='core.team_person_details'::regclass and con.contype='c'
   and pg_get_constraintdef(con.oid) like '%striker%' loop
  execute format('alter table core.team_person_details drop constraint %I',constraint_name);
 end loop;
end$$;

create function internal.validate_team_person_details()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if cardinality(new.positions)>20 or array_position(new.positions,null) is not null
  or exists(select 1 from unnest(new.positions) position where not exists(
   select 1 from core.teams team join core.sport_positions catalog on catalog.sport=team.sport
   where team.id=new.team_id and catalog.key=position)) then
  raise check_violation using message='invalid_position';
 end if;
 return new;
end$$;
create trigger team_person_details_validate before insert or update on core.team_person_details
for each row execute function internal.validate_team_person_details();

create function internal.normalize_labels(labels text[])
returns text[] language sql immutable set search_path='' as $$
 select coalesce(array(select distinct btrim(label) from unnest(labels) label
  where label is not null and btrim(label)<>'' order by 1),'{}')
$$;

create function internal.save_team_person_details(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 expected_revision bigint,idempotency_key uuid,command_type text)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); current_revision bigint; saved_revision bigint; cached jsonb;
 has_leader boolean; has_player boolean;
 titles text[]:=internal.normalize_labels(new_titles); positions text[]:=internal.normalize_labels(new_positions);
 custom_titles text[]:=internal.normalize_labels(new_custom_titles);
 custom_positions text[]:=internal.normalize_labels(new_custom_positions);
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 if idempotency_key is null or new_titles is null or new_positions is null or new_custom_titles is null
  or new_custom_positions is null or expected_revision is null or expected_revision<0
  or command_type not in('team.person_details.updated.v1','team.person_details.updated.v2') then
  raise invalid_parameter_value using message='invalid_input'; end if;
 perform pg_advisory_xact_lock(hashtextextended('team-person-details:'||target_team_id::text||':'||target_person_id::text,0));
 select d.result into cached from internal.command_deduplication d
 where d.actor_profile_id=actor_id and d.command_type=save_team_person_details.command_type
  and d.idempotency_key=save_team_person_details.idempotency_key;
 if cached is not null then return (cached->>'revision')::bigint; end if;
 select bool_or(a.role_package in('leader','club_functionary')),bool_or(a.role_package='player')
 into has_leader,has_player
 from core.assignments a join core.club_people p on p.id=a.club_person_id and p.club_id=a.club_id
 where a.club_id=target_club_id and a.team_id=target_team_id and a.club_person_id=target_person_id
  and a.role_package in('player','leader','club_functionary') and a.state='active'
  and a.starts_at<=now() and (a.ends_at is null or a.ends_at>now()) and p.status='active';
 if has_leader is null then raise insufficient_privilege using message='not_found'; end if;
 if not has_leader and (cardinality(titles)>0 or cardinality(custom_titles)>0) then
  raise check_violation using message='titles_need_leader_role'; end if;
 if not has_player and (cardinality(positions)>0 or cardinality(custom_positions)>0) then
  raise check_violation using message='positions_need_player_role'; end if;
 select d.revision into current_revision from core.team_person_details d
 where d.team_id=target_team_id and d.club_person_id=target_person_id for update;
 if coalesce(current_revision,0)<>expected_revision then
  raise serialization_failure using message='stale_revision'; end if;
 saved_revision:=coalesce(current_revision,0)+1;
 insert into core.team_person_details(club_id,team_id,club_person_id,functions,positions,custom_titles,custom_positions,revision,updated_by)
 values(target_club_id,target_team_id,target_person_id,titles,positions,custom_titles,custom_positions,saved_revision,actor_id)
 on conflict(team_id,club_person_id) do update
 set functions=excluded.functions,positions=excluded.positions,custom_titles=excluded.custom_titles,
  custom_positions=excluded.custom_positions,revision=excluded.revision,updated_by=actor_id,updated_at=now();
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,command_type,jsonb_build_object('revision',saved_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,command_type,'team_person',target_person_id,saved_revision,
  jsonb_build_object('team_id',target_team_id,'titles',titles,'positions',positions,
   'custom_titles',custom_titles,'custom_positions',custom_positions));
 return saved_revision;
end$$;

-- The v1 command keeps working for older clients; it leaves custom labels
-- unchanged and follows the same role rules.
create or replace function internal.set_team_person_details_for_actor(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_functions text[],new_positions text[],expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare existing core.team_person_details%rowtype;
begin
 select * into existing from core.team_person_details d where d.team_id=target_team_id and d.club_person_id=target_person_id;
 return internal.save_team_person_details(target_club_id,target_team_id,target_person_id,
  new_functions,new_positions,coalesce(existing.custom_titles,'{}'),coalesce(existing.custom_positions,'{}'),
  expected_revision,idempotency_key,'team.person_details.updated.v1');
end$$;

create function api.set_team_person_details_v2(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$
 select internal.save_team_person_details(target_club_id,target_team_id,target_person_id,
  new_titles,new_positions,new_custom_titles,new_custom_positions,expected_revision,idempotency_key,
  'team.person_details.updated.v2')
$$;

-- When the role a label describes ends (role change, removal, archiving,
-- erasure), its titles or positions go with it.
create function internal.clear_team_person_details_on_role_end()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.state='active' and new.state<>'active' and old.team_id is not null then
  if old.role_package='player' and not exists(select 1 from core.assignments a where a.id<>old.id
   and a.club_id=old.club_id and a.team_id=old.team_id and a.club_person_id=old.club_person_id
   and a.role_package='player' and a.state='active') then
   update core.team_person_details set positions='{}',custom_positions='{}',revision=revision+1,updated_at=now()
   where team_id=old.team_id and club_person_id=old.club_person_id
    and (cardinality(positions)>0 or cardinality(custom_positions)>0);
  elsif old.role_package in('leader','club_functionary') and not exists(select 1 from core.assignments a where a.id<>old.id
   and a.club_id=old.club_id and a.team_id=old.team_id and a.club_person_id=old.club_person_id
   and a.role_package in('leader','club_functionary') and a.state='active') then
   update core.team_person_details set functions='{}',custom_titles='{}',revision=revision+1,updated_at=now()
   where team_id=old.team_id and club_person_id=old.club_person_id
    and (cardinality(functions)>0 or cardinality(custom_titles)>0);
  end if;
 end if;
 return new;
end$$;
create trigger assignments_clear_team_person_details after update of state on core.assignments
for each row execute function internal.clear_team_person_details_on_role_end();

-- Existing rows: drop labels whose role is already gone.
update core.team_person_details d set positions='{}',revision=revision+1,updated_at=now()
where cardinality(d.positions)>0 and not exists(select 1 from core.assignments a where a.team_id=d.team_id
 and a.club_person_id=d.club_person_id and a.role_package='player' and a.state='active');
update core.team_person_details d set functions='{}',revision=revision+1,updated_at=now()
where cardinality(d.functions)>0 and not exists(select 1 from core.assignments a where a.team_id=d.team_id
 and a.club_person_id=d.club_person_id and a.role_package in('leader','club_functionary') and a.state='active');

create function internal.set_team_sport_for_actor(target_club_id uuid,target_team_id uuid,new_sport text,idempotency_key uuid)
returns text language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); cached jsonb; previous text;
begin
 perform internal.assert_team_role_manager(target_club_id,target_team_id);
 if idempotency_key is null or new_sport not in('football','handball','other') then
  raise invalid_parameter_value using message='invalid_sport'; end if;
 select d.result into cached from internal.command_deduplication d
 where d.actor_profile_id=actor_id and d.command_type='team.sport.updated.v1'
  and d.idempotency_key=set_team_sport_for_actor.idempotency_key;
 if cached is not null then return cached->>'sport'; end if;
 select sport into previous from core.teams where id=target_team_id for update;
 if previous<>new_sport then
  update core.teams set sport=new_sport,revision=revision+1 where id=target_team_id;
  -- Positions from the previous sport's catalog no longer apply; the
  -- team's own custom position labels are kept.
  update core.team_person_details d set positions=coalesce(array(select position from unnest(d.positions) position
    where exists(select 1 from core.sport_positions catalog where catalog.sport=new_sport and catalog.key=position)
    order by 1),'{}'),revision=revision+1,updated_at=now(),updated_by=actor_id
  where d.team_id=target_team_id and cardinality(d.positions)>0;
 end if;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'team.sport.updated.v1',jsonb_build_object('sport',new_sport));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'team.sport.updated.v1','team',target_team_id,1,
  jsonb_build_object('from',previous,'to',new_sport));
 return new_sport;
end$$;

create function api.set_team_sport(target_club_id uuid,target_team_id uuid,new_sport text,idempotency_key uuid)
returns text language sql security invoker set search_path='' as
$$select internal.set_team_sport_for_actor(target_club_id,target_team_id,new_sport,idempotency_key)$$;

create or replace function internal.list_team_roles_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_sport text;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
  and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage') then
  raise insufficient_privilege using message='not_found';
 end if;
 select sport into team_sport from core.teams where id=target_team_id and club_id=target_club_id;
 return jsonb_build_object(
  'can_manage',internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage'),
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
    'details_revision',coalesce(details.revision,0))
   order by case assignment.role_package when 'leader' then 0 when 'club_functionary' then 1 else 2 end,person.display_name,person.id)
   from core.assignments assignment
   join core.club_people person on person.id=assignment.club_person_id and person.club_id=assignment.club_id
   left join core.team_person_details details on details.club_id=assignment.club_id
    and details.team_id=assignment.team_id and details.club_person_id=assignment.club_person_id
   where assignment.club_id=target_club_id and assignment.team_id=target_team_id
    and assignment.role_package in('player','leader','club_functionary')
    and assignment.state='active' and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and person.status='active'),'[]'::jsonb));
end$$;

revoke all on function internal.valid_custom_labels(text[]),internal.normalize_labels(text[]),
 internal.validate_team_person_details(),
 internal.save_team_person_details(uuid,uuid,uuid,text[],text[],text[],text[],bigint,uuid,text),
 internal.clear_team_person_details_on_role_end(),
 internal.set_team_sport_for_actor(uuid,uuid,text,uuid),
 api.set_team_person_details_v2(uuid,uuid,uuid,text[],text[],text[],text[],bigint,uuid),
 api.set_team_sport(uuid,uuid,text,uuid) from public,anon,authenticated;
-- The table check calls this as whoever writes the row.
grant execute on function internal.valid_custom_labels(text[]) to authenticated;
grant execute on function internal.save_team_person_details(uuid,uuid,uuid,text[],text[],text[],text[],bigint,uuid,text),
 internal.set_team_sport_for_actor(uuid,uuid,text,uuid),
 api.set_team_person_details_v2(uuid,uuid,uuid,text[],text[],text[],text[],bigint,uuid),
 api.set_team_sport(uuid,uuid,text,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260929140000_team_titles_positions_by_sport','greenfield',
 'Role-bound titles/positions, two-level positions per sport, custom labels, team sport');
notify pgrst,'reload schema';
