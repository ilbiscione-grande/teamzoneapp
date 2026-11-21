-- Ready-made formations with what each place asks for (asked for by the
-- product owner 2026-11-21): every common football formation comes with a
-- position and important attributes on each place. Templates cannot be
-- changed; a team saves a copy (a team formation) and changes that. They are
-- listed with the team's formations and suggest from like them.
--
-- The places' requirements follow their role:
--   goalkeeper     saves (very), footwork, communication;
--   centre-back    heading (very), 1v1 defending, interceptions, positioning;
--   full-back      1v1 defending (very), speed, crossing, endurance
--                  (four or more at the back, the outer two);
--   wing-back      endurance (very), crossing, speed, 1v1 defending
--                  (the outer two of five, at the back or in midfield);
--   defensive mid  interceptions (very), passing, positioning, tackling
--                  (the second line of four);
--   central mid    passing (very), reading the game, endurance, work rate;
--   wide mid       crossing (very), speed, endurance (outer two of four);
--   attacking mid  passing (very), reading the game, shooting, dribbling;
--   winger         speed (very), 1v1 attacking (very), dribbling, crossing
--                  (outer two of three up front or behind the striker);
--   striker        finishing (very), back to goal, runs in behind, and
--                  heading when alone.

create table core.formation_templates(
 id uuid primary key,
 sport text not null check(sport in('football','handball','other')),
 name text not null,
 lines text not null check(lines ~ '^[1-6](-[1-6]){0,4}$'),
 match_format text not null check(match_format in('3v3','5v5','7v7','9v9','11v11')),
 slots jsonb not null,
 sort smallint not null
);
alter table core.formation_templates enable row level security;
revoke all on core.formation_templates from public,anon,authenticated;

-- The requirement list of a role.
create or replace function internal.template_role(role text)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('position',r.position,'requirements',(select jsonb_agg(jsonb_build_object(
   'attribute',split_part(x.item,':',1),'weight',split_part(x.item,':',2)::integer) order by x.n)
  from unnest(r.items) with ordinality as x(item,n)))
 from (values
  ('goalkeeper','goalkeeper',array['goalkeeping_hands:2','goalkeeping_feet:1','communication:1']),
  ('centre_back','centre_back',array['heading:2','defending_1v1:1','interceptions:1','positioning:1']),
  ('left_back','left_back',array['defending_1v1:2','speed:1','crossing:1','endurance:1']),
  ('right_back','right_back',array['defending_1v1:2','speed:1','crossing:1','endurance:1']),
  ('wing_back','wing_back',array['endurance:2','crossing:1','speed:1','defending_1v1:1']),
  ('defensive_mid','defensive_midfielder',array['interceptions:2','passing:1','positioning:1','tackling:1']),
  ('central_mid','central_midfielder',array['passing:2','game_reading:1','endurance:1','work_rate:1']),
  ('wide_mid',null,array['crossing:2','speed:1','endurance:1']),
  ('attacking_mid','attacking_midfielder',array['passing:2','game_reading:1','shooting:1','dribbling:1']),
  ('left_winger','left_winger',array['speed:2','attacking_1v1:2','dribbling:1','crossing:1']),
  ('right_winger','right_winger',array['speed:2','attacking_1v1:2','dribbling:1','crossing:1']),
  ('striker','striker',array['finishing:2','back_to_goal:1','runs_in_behind:1']),
  ('lone_striker','striker',array['finishing:2','back_to_goal:1','runs_in_behind:1','heading:1'])
 ) r(role,position,items) where r.role=template_role.role
$$;

-- Each place of a football formation with the requirements of its role.
create or replace function internal.template_slots(lines text,match_format text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare counts integer[]:=string_to_array(lines,'-')::integer[]; total integer:=cardinality(counts);
 result jsonb:='[]'; line integer; place integer; count integer; edge boolean; left_side boolean; role text;
begin
 if match_format<>'3v3' then
  result:=result||jsonb_build_array(jsonb_build_object('code','GK')||internal.template_role('goalkeeper'));
 end if;
 for line in 1..total loop
  count:=counts[line];
  for place in 0..count-1 loop
   edge:=count>1 and (place=0 or place=count-1);
   left_side:=place=0;
   role:=case
    when line=1 and total>1 then case
     when count=5 and edge then 'wing_back'
     when count=4 and edge then case when left_side then 'left_back' else 'right_back' end
     else 'centre_back' end
    when line=total then case
     when count=3 and edge then case when left_side then 'left_winger' else 'right_winger' end
     when count=1 then 'lone_striker'
     else 'striker' end
    when total=4 and line=2 then 'defensive_mid'
    when total=4 and line=3 then case
     when count>=3 and edge then case when left_side then 'left_winger' else 'right_winger' end
     else 'attacking_mid' end
    when count=5 and edge then 'wing_back'
    when count=4 and edge then 'wide_mid'
    else 'central_mid' end;
   result:=result||jsonb_build_array(jsonb_build_object('code',line||chr(65+place))||internal.template_role(role));
  end loop;
 end loop;
 return result;
end$$;

insert into core.formation_templates(id,sport,name,lines,match_format,slots,sort)
select md5('football-'||t.match_format||'-'||t.lines)::uuid,'football',t.lines,t.lines,t.match_format,
 internal.template_slots(t.lines,t.match_format),t.sort
from (values
 ('4-3-3','11v11',10),('4-4-2','11v11',11),('4-2-3-1','11v11',12),('4-1-4-1','11v11',13),('4-3-1-2','11v11',14),
 ('4-5-1','11v11',15),('3-5-2','11v11',16),('3-4-3','11v11',17),('5-3-2','11v11',18),('5-4-1','11v11',19),
 ('3-3-2','9v9',20),('3-2-3','9v9',21),('3-4-1','9v9',22),('2-3-2-1','9v9',23),
 ('2-3-1','7v7',30),('3-2-1','7v7',31),('2-1-2-1','7v7',32),('3-1-2','7v7',33),
 ('2-2','5v5',40),('1-2-1','5v5',41),('2-1-1','5v5',42)
) t(lines,match_format,sort);

-- A team formation, or a template of the team's sport as one (revision 0).
create or replace function internal.team_formation_record(target_formation_id uuid,target_team_id uuid)
returns core.team_formations language plpgsql stable security definer set search_path='' as $$
declare result core.team_formations;
begin
 select * into result from core.team_formations f where f.id=target_formation_id and f.team_id=target_team_id;
 if result.id is null then
  select template.id,team.club_id,team.id,template.name,template.lines,template.match_format,template.slots,0,now(),null
  into result
  from core.formation_templates template join core.teams team on team.id=target_team_id and team.sport=template.sport
  where template.id=target_formation_id;
 end if;
 return result;
end$$;

-- The team's formations and the templates of its sport.
create or replace function internal.list_team_formations_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform internal.require_team_formations_access(target_club_id,target_team_id);
 return jsonb_build_object(
  'formations',coalesce((select jsonb_agg(internal.team_formation_json(formation)
    order by lower(formation.name),formation.id)
   from core.team_formations formation where formation.team_id=target_team_id),'[]'::jsonb),
  'templates',coalesce((select jsonb_agg(internal.team_formation_json(
     internal.team_formation_record(template.id,target_team_id))||jsonb_build_object('template',true)
    order by template.sort)
   from core.formation_templates template join core.teams team on team.id=target_team_id and team.sport=template.sport),'[]'::jsonb));
end$$;

revoke all on function internal.template_role(text),internal.template_slots(text,text),
 internal.team_formation_record(uuid,uuid) from public,anon,authenticated;

-- As in 20270409090000, also from a template.
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
  formation:=internal.team_formation_record(formation_id,target_team_id);
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

notify pgrst,'reload schema';
