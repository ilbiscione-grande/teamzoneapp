-- Suggests who plays where (step 4 of docs/implementation/player-attributes.md).
-- Tacticsboard and the app's line-up call the same function, so they always
-- suggest the same thing.
--
-- Each player gets points for each place:
--   position   the place's position as the player's main position 10, as
--              another of theirs 7; else the place's general position (its
--              line) as the player's main 5 (10 when the place names no
--              position), as another of theirs 3 (6);
--   goalkeeper a place in goal without goalkeeper among the player's
--              positions -10, and a main goalkeeper outfield -10;
--   attributes per requirement of weight w (1 important, 2 very
--              important): a strength +3w, an area to develop -2w.
-- The players are then placed so that the team's total is the highest
-- (the Hungarian method). Locked places keep their player. With fewer
-- players than places, some places stay empty.
--
-- Positions come from the team's own details, for a player who represents
-- the team from another team from the home team's. Attributes are this
-- team's, so a representative has none here.

-- The general position of a position key: its parent, or itself.
create or replace function internal.position_group(team_sport text,position_key text)
returns text language sql stable security definer set search_path='' as $$
 select coalesce(catalog.parent_key,catalog.key) from core.sport_positions catalog
 where catalog.sport=team_sport and catalog.key=position_key
$$;

-- Points for [player] in [slot] (as internal.team_formation_json gives a
-- place), with the reasons.
create or replace function internal.lineup_fit(team_sport text,slot jsonb,main_position text,positions text[],
 strengths text[],development text[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare score integer:=0; fit text:='none'; wanted text:=slot->>'position'; grp text:=slot->>'group';
 main_group text:=internal.position_group(team_sport,main_position);
 groups text[]:=coalesce(array(select internal.position_group(team_sport,p) from unnest(positions) p),'{}');
 matched_strengths text[]:='{}'; matched_development text[]:='{}'; requirement jsonb;
begin
 if wanted is not null and main_position=wanted then score:=10; fit:='main';
 elsif wanted is not null and wanted=any(positions) then score:=7; fit:='other';
 elsif main_group=grp then score:=case when wanted is null then 10 else 5 end; fit:=case when wanted is null then 'main' else 'group' end;
 elsif grp=any(groups) then score:=case when wanted is null then 6 else 3 end; fit:=case when wanted is null then 'other' else 'group' end;
 end if;
 if grp='goalkeeper' and not ('goalkeeper'=any(groups) or main_group='goalkeeper') then score:=score-10; end if;
 if grp<>'goalkeeper' and main_group='goalkeeper' then score:=score-10; end if;
 for requirement in select value from jsonb_array_elements(coalesce(slot->'requirements','[]')) loop
  if requirement->>'attribute'=any(strengths) then
   score:=score+3*(requirement->>'weight')::integer;
   matched_strengths:=matched_strengths||(requirement->>'attribute');
  elsif requirement->>'attribute'=any(development) then
   score:=score-2*(requirement->>'weight')::integer;
   matched_development:=matched_development||(requirement->>'attribute');
  end if;
 end loop;
 return jsonb_build_object('score',score,'position_fit',fit,
  'strengths',to_jsonb(matched_strengths),'development',to_jsonb(matched_development));
end$$;

-- The assignment of rows to columns with the highest total of [scores]
-- (row-major, rows <= columns): for each row its column. The Hungarian
-- method on costs (the highest score minus each score).
create or replace function internal.best_assignment(scores integer[],row_count integer,column_count integer)
returns integer[] language plpgsql immutable set search_path='' as $$
declare top integer; u bigint[]; v bigint[]; p integer[]; way integer[]; minv bigint[]; used boolean[];
 i integer; j integer; j0 integer; j1 integer; i0 integer; delta bigint; cur bigint; result integer[];
begin
 if row_count=0 then return '{}'; end if;
 select max(s) into top from unnest(scores) s;
 u:=array_fill(0::bigint,array[row_count+1]); v:=array_fill(0::bigint,array[column_count+1]);
 p:=array_fill(0,array[column_count+1]); way:=array_fill(0,array[column_count+1]);
 -- Arrays here are 1-based; index k+1 stands for the method's k.
 for i in 1..row_count loop
  p[1]:=i; j0:=0;
  minv:=array_fill(9223372036854775807::bigint,array[column_count+1]);
  used:=array_fill(false,array[column_count+1]);
  loop
   used[j0+1]:=true; i0:=p[j0+1]; delta:=9223372036854775807; j1:=0;
   for j in 1..column_count loop
    if not used[j+1] then
     cur:=(top-scores[(i0-1)*column_count+j])-u[i0+1]-v[j+1];
     if cur<minv[j+1] then minv[j+1]:=cur; way[j+1]:=j0; end if;
     if minv[j+1]<delta then delta:=minv[j+1]; j1:=j; end if;
    end if;
   end loop;
   for j in 0..column_count loop
    if used[j+1] then u[p[j+1]+1]:=u[p[j+1]+1]+delta; v[j+1]:=v[j+1]-delta;
    else minv[j+1]:=minv[j+1]-delta; end if;
   end loop;
   j0:=j1;
   exit when p[j0+1]=0;
  end loop;
  loop
   j1:=way[j0+1]; p[j0+1]:=p[j1+1]; j0:=j1;
   exit when j0=0;
  end loop;
 end loop;
 result:=array_fill(0,array[row_count]);
 for j in 1..column_count loop
  if p[j+1]>0 then result[p[j+1]]:=j; end if;
 end loop;
 return result;
end$$;

-- The suggestion: [formation_id] (a team formation) or [new_lines] and
-- [new_match_format] (places without requirements); [candidate_ids] the
-- players to choose from (default the team's players; others must be able
-- to represent the team); [locked] {code: person_id} places already set.
create or replace function internal.suggest_lineup_for_actor(target_club_id uuid,target_team_id uuid,
 formation_id uuid,new_lines text,new_match_format text,candidate_ids uuid[],locked jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_sport text; formation core.team_formations; slots jsonb; open_slots jsonb[]; players jsonb[];
 scores integer[]; fits jsonb[]; row_count integer; column_count integer; chosen integer[];
 slot jsonb; player jsonb; fit jsonb; result jsonb:='[]'; i integer; j integer; taken uuid[];
begin
 perform internal.require_team_formations_access(target_club_id,target_team_id);
 select sport into team_sport from core.teams where id=target_team_id;
 if formation_id is not null then
  select * into formation from core.team_formations f where f.id=formation_id and f.team_id=target_team_id;
  if formation.id is null then raise no_data_found using message='formation_not_found'; end if;
 else
  new_lines:=regexp_replace(coalesce(new_lines,''),'\s','','g');
  if new_match_format is null or new_match_format not in('3v3','5v5','7v7','9v9','11v11')
   or new_lines !~ '^[1-6](-[1-6]){0,4}$'
   or (select count(*) from internal.formation_slots(new_lines,new_match_format))<>internal.format_players(new_match_format) then
   raise invalid_parameter_value using message='invalid_formation';
  end if;
  formation.team_id:=target_team_id; formation.lines:=new_lines; formation.match_format:=new_match_format;
  formation.slots:='[]';
 end if;
 slots:=internal.team_formation_json(formation)->'slots';
 if jsonb_typeof(coalesce(locked,'{}'))<>'object'
  or exists(select 1 from jsonb_each_text(coalesce(locked,'{}')) l
   where not exists(select 1 from jsonb_array_elements(slots) s where s->>'code'=l.key))
  or (select count(distinct l.value)<>count(*) from jsonb_each_text(coalesce(locked,'{}')) l) then
  raise invalid_parameter_value using message='invalid_locked';
 end if;
 -- The players to choose from, with positions and this team's ticks.
 if candidate_ids is not null and exists(select 1 from unnest(candidate_ids) c
  where c is null or not (
   exists(select 1 from core.assignments a where a.club_id=target_club_id and a.team_id=target_team_id
    and a.club_person_id=c and a.role_package='player' and a.state='active')
   or exists(select 1 from core.play_eligibilities e where e.club_id=target_club_id and e.team_id=target_team_id
    and e.club_person_id=c and e.state='active' and e.starts_at<=now() and e.ends_at>now()))) then
  raise invalid_parameter_value using message='invalid_candidate';
 end if;
 taken:=coalesce(array(select l.value::uuid from jsonb_each_text(coalesce(locked,'{}')) l),'{}');
 select coalesce(array_agg(jsonb_build_object('person_id',person.id,'name',person.display_name,
   'number',details.jersey_number,'main_position',details.main_position,
   'positions',to_jsonb(coalesce(details.positions,'{}')),
   'strengths',to_jsonb(coalesce(array(select a.attribute_key from core.player_attributes a
     where a.team_id=target_team_id and a.club_person_id=person.id and a.assessment='strength'),'{}')),
   'development',to_jsonb(coalesce(array(select a.attribute_key from core.player_attributes a
     where a.team_id=target_team_id and a.club_person_id=person.id and a.assessment='development'),'{}')))
  order by details.jersey_number nulls last,person.display_name,person.id),'{}')
 into players
 from core.club_people person
 left join lateral (select d.* from core.team_person_details d
  where d.club_person_id=person.id and (d.team_id=target_team_id or d.team_id in(select h.team_id
   from core.team_assignments h where h.club_person_id=person.id and h.club_id=target_club_id and h.state='active'))
  order by d.team_id=target_team_id desc limit 1) details on true
 where person.club_id=target_club_id and person.status='active' and not person.id=any(taken)
  and case when candidate_ids is null then exists(select 1 from core.assignments a where a.club_id=target_club_id
    and a.team_id=target_team_id and a.club_person_id=person.id and a.role_package='player' and a.state='active'
    and a.starts_at<=now() and (a.ends_at is null or a.ends_at>now()))
   else person.id=any(candidate_ids) end;
 open_slots:=coalesce(array(select s from jsonb_array_elements(slots) s
  where not coalesce(locked,'{}') ? (s->>'code')),'{}');
 row_count:=cardinality(open_slots);
 -- Empty stand-ins when there are fewer players than places.
 column_count:=greatest(cardinality(players),row_count);
 scores:='{}'; fits:='{}';
 for i in 1..row_count loop
  for j in 1..column_count loop
   if j<=cardinality(players) then
    player:=players[j];
    fit:=internal.lineup_fit(team_sport,open_slots[i],player->>'main_position',
     array(select jsonb_array_elements_text(player->'positions')),
     array(select jsonb_array_elements_text(player->'strengths')),
     array(select jsonb_array_elements_text(player->'development')));
    scores:=scores||(fit->>'score')::integer+1000;
   else
    fit:=null; scores:=scores||0;
   end if;
   fits:=fits||fit;
  end loop;
 end loop;
 chosen:=internal.best_assignment(scores,row_count,column_count);
 -- Every place in order: locked, suggested, or empty, with the next best.
 for slot in select s from jsonb_array_elements(slots) s loop
  if coalesce(locked,'{}') ? (slot->>'code') then
   result:=result||jsonb_build_array(jsonb_build_object('code',slot->>'code','group',slot->>'group',
    'person_id',locked->>(slot->>'code'),'locked',true));
   continue;
  end if;
  i:=array_position(open_slots,slot);
  j:=chosen[i];
  result:=result||jsonb_build_array(jsonb_build_object('code',slot->>'code','group',slot->>'group',
   'locked',false,
   'person_id',case when j<=cardinality(players) then players[j]->>'person_id' end,
   'name',case when j<=cardinality(players) then players[j]->>'name' end,
   'number',case when j<=cardinality(players) then players[j]->'number' end)
   ||coalesce(case when j<=cardinality(players) then fits[(i-1)*column_count+j] end,'{}')
   -- The three best others for the place, wherever they are suggested.
   ||jsonb_build_object('alternatives',coalesce((select jsonb_agg(alt.item order by alt.score desc,alt.k)
    from (select k,(fits[(i-1)*column_count+k]->>'score')::integer score,
      jsonb_build_object('person_id',players[k]->>'person_id','name',players[k]->>'name',
       'score',(fits[(i-1)*column_count+k]->>'score')::integer) item
     from generate_series(1,cardinality(players)) k where k<>j
     order by 2 desc,k limit 3) alt),'[]'::jsonb)));
 end loop;
 return jsonb_build_object('slots',result,
  'bench',coalesce((select jsonb_agg(jsonb_build_object('person_id',players[k]->>'person_id','name',players[k]->>'name',
    'number',players[k]->'number') order by k)
   from generate_series(1,cardinality(players)) k where not k=any(chosen)),'[]'::jsonb));
end$$;

create function api.suggest_lineup(target_club_id uuid,target_team_id uuid,formation_id uuid,
 new_lines text,new_match_format text,candidate_ids uuid[],locked jsonb)
returns jsonb language sql stable security invoker set search_path='' as
$$ select internal.suggest_lineup_for_actor(target_club_id,target_team_id,formation_id,
 new_lines,new_match_format,candidate_ids,locked) $$;

revoke all on function
 internal.position_group(text,text),internal.lineup_fit(text,jsonb,text,text[],text[],text[]),
 internal.best_assignment(integer[],integer,integer),
 internal.suggest_lineup_for_actor(uuid,uuid,uuid,text,text,uuid[],jsonb),
 api.suggest_lineup(uuid,uuid,uuid,text,text,uuid[],jsonb)
from public,anon,authenticated;
grant execute on function
 internal.suggest_lineup_for_actor(uuid,uuid,uuid,text,text,uuid[],jsonb),
 api.suggest_lineup(uuid,uuid,uuid,text,text,uuid[],jsonb)
to authenticated;
notify pgrst,'reload schema';
