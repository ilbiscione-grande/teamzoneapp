-- TEAM-14: a leader's main title (e.g. Huvudtränare), shown in the squad list
-- and the team picker instead of the role (Ledare, Klubbfunktionär). Like
-- the main position it is one of the person's titles and is cleared when it
-- no longer is.

alter table core.team_person_details
 add column if not exists main_title text
  check (main_title is null or length(btrim(main_title)) between 1 and 40);

create or replace function internal.validate_team_person_details()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if cardinality(new.positions)>20 or array_position(new.positions,null) is not null
  or exists(select 1 from unnest(new.positions) position where not exists(
   select 1 from core.teams team join core.sport_positions catalog on catalog.sport=team.sport
   where team.id=new.team_id and catalog.key=position)) then
  raise check_violation using message='invalid_position';
 end if;
 if new.main_position is not null and not (new.main_position=any(new.positions)
  or new.main_position=any(new.custom_positions)) then
  new.main_position:=null;
 end if;
 if new.main_title is not null and not (new.main_title=any(new.functions)
  or new.main_title=any(new.custom_titles)) then
  new.main_title:=null;
 end if;
 return new;
end$$;

do $patch$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.list_team_roles_for_actor(uuid,uuid)'::regprocedure);
 patched:=replace(definition,
  '''main_position'',details.main_position,',
  '''main_position'',details.main_position,''main_title'',details.main_title,');
 if patched=definition then raise exception 'list_team_roles_for_actor: patch point not found'; end if;
 execute patched;

 definition:=pg_get_functiondef('internal.get_my_team_titles_for_actor()'::regprocedure);
 patched:=replace(definition,
  '''custom_titles'',to_jsonb(coalesce(details.custom_titles,''{}''::text[])))',
  '''custom_titles'',to_jsonb(coalesce(details.custom_titles,''{}''::text[])),''main_title'',details.main_title)');
 if patched=definition then raise exception 'get_my_team_titles_for_actor: patch point not found'; end if;
 execute patched;
end$patch$;

create or replace function internal.set_team_person_details_v4_for_actor(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_title text,new_main_position text,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare title text:=nullif(btrim(new_main_title),''); saved_revision bigint;
begin
 if title is not null and not (title=any(internal.normalize_labels(new_titles))
  or title=any(internal.normalize_labels(new_custom_titles))) then
  raise invalid_parameter_value using message='invalid_main_title'; end if;
 saved_revision:=internal.set_team_person_details_v3_for_actor(target_club_id,target_team_id,target_person_id,
  new_titles,new_positions,new_custom_titles,new_custom_positions,new_main_position,expected_revision,idempotency_key);
 update core.team_person_details set main_title=title
 where team_id=target_team_id and club_person_id=target_person_id and main_title is distinct from title;
 return saved_revision;
end$$;

create or replace function api.set_team_person_details_v4(
 target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_titles text[],new_positions text[],new_custom_titles text[],new_custom_positions text[],
 new_main_title text,new_main_position text,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$
 select internal.set_team_person_details_v4_for_actor(target_club_id,target_team_id,target_person_id,
  new_titles,new_positions,new_custom_titles,new_custom_positions,new_main_title,new_main_position,
  expected_revision,idempotency_key)
$$;

revoke all on function internal.set_team_person_details_v4_for_actor(uuid,uuid,uuid,text[],text[],text[],text[],text,text,bigint,uuid),
 api.set_team_person_details_v4(uuid,uuid,uuid,text[],text[],text[],text[],text,text,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.set_team_person_details_v4_for_actor(uuid,uuid,uuid,text[],text[],text[],text[],text,text,bigint,uuid),
 api.set_team_person_details_v4(uuid,uuid,uuid,text[],text[],text[],text[],text,text,bigint,uuid) to authenticated;

-- Leaders with exactly one title get it as their main title.
update core.team_person_details set main_title=coalesce(functions[1],custom_titles[1])
where main_title is null and cardinality(functions)+cardinality(custom_titles)=1;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261001210000_main_title','greenfield','TEAM-14 main title for leaders'
where not exists(select 1 from internal.migration_provenance where migration_name='20261001210000_main_title');
notify pgrst,'reload schema';
