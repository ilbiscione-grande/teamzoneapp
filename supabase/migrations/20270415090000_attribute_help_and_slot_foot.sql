-- Help on each attribute, and the foot a place asks for (asked for by the
-- product owner 2026-11-22).
--
-- Each attribute explains itself (Swedish and English) and names the
-- positions it matters most for, shown where the attributes are ticked and
-- where a formation's places ask for them.
--
-- A place of a formation may ask for a foot (left or right). Templates ask
-- for it on the sides: full-backs, wing-backs and wide midfielders (wingers
-- are often on their other foot, so they do not). The suggestion scores the
-- player's preferred foot against it:
--   the same foot, or both and better with it   +3
--   both, equally good                          +3
--   both, better with the other                 +1
--   only the other foot                         -2
--   foot not set                                 0

alter table core.sport_attributes
 add column about_sv text not null default '',
 add column about_en text not null default '',
 add column positions text[] not null default '{}';

update core.sport_attributes attribute set about_sv=help.sv,about_en=help.en,
 positions=case when attribute.sport='football' then help.football when attribute.sport='handball' then help.handball else '{}' end
from (values
 ('acceleration','Hur snabbt spelaren kommer upp i fart – avgör de första metrarna i en löpning eller duell.','How quickly the player gets up to speed – decides the first metres of a run or duel.',
  array['left_back','right_back','wing_back','left_winger','right_winger','striker'],array['hb_wing']),
 ('speed','Toppfart över längre sträckor, med eller utan boll.','Top speed over longer distances, with or without the ball.',
  array['wing_back','left_back','right_back','left_winger','right_winger','striker'],array['hb_wing']),
 ('strength','Fysisk styrka i närkamper: att stå emot och skydda bollen.','Physical strength in duels: holding off opponents and shielding the ball.',
  array['centre_back','defensive_midfielder','striker'],array['hb_pivot','hb_backcourt']),
 ('endurance','Att orka springa och hålla tempot hela matchen.','Stamina to keep running and keep the tempo all match.',
  array['wing_back','central_midfielder','left_back','right_back'],array['hb_wing','hb_backcourt']),
 ('agility','Att snabbt ändra riktning och hålla balansen.','Changing direction quickly and keeping balance.',
  array['left_winger','right_winger','attacking_midfielder','goalkeeper'],array['hb_wing','goalkeeper']),
 ('jumping','Spänst: att komma högt, till exempel i luftdueller.','Leap: getting high, for example in aerial duels.',
  array['centre_back','striker','goalkeeper'],array['hb_backcourt','hb_wing']),
 ('heading','Att vinna och styra nickar, både i försvar och i anfall.','Winning and directing headers, in defence and in attack.',
  array['centre_back','striker'],'{}'::text[]),
 ('shooting','Skottkraft och precision, också från distans.','Power and accuracy when shooting, also from distance.',
  array['attacking_midfielder','striker','left_winger','right_winger'],array['hb_backcourt','hb_wing']),
 ('long_shots','Skott från distans, utanför niometerslinjen.','Shots from distance, outside the nine-metre line.',
  '{}'::text[],array['hb_backcourt']),
 ('crossing','Inlägg med rätt höjd och tajming in i straffområdet.','Crosses into the box with the right height and timing.',
  array['left_back','right_back','wing_back','left_winger','right_winger'],'{}'::text[]),
 ('passing','Korta och medellånga passningar med rätt tyngd och precision.','Short and medium passes with the right weight and accuracy.',
  array['central_midfielder','defensive_midfielder','attacking_midfielder','centre_back'],array['hb_centre_back','hb_backcourt']),
 ('long_passing','Långa passningar och diagonaler som byter sida eller hittar djupet.','Long passes and diagonals that switch play or find space in behind.',
  array['centre_back','defensive_midfielder','central_midfielder','goalkeeper'],'{}'::text[]),
 ('first_touch','Att ta emot och kontrollera bollen med första tillslaget, också under press.','Receiving and controlling the ball with the first touch, also under pressure.',
  array['central_midfielder','attacking_midfielder','striker'],'{}'::text[]),
 ('dribbling','Att ta sig förbi motståndare med bollen nära.','Getting past opponents with the ball close.',
  array['left_winger','right_winger','attacking_midfielder'],'{}'::text[]),
 ('ball_carrying','Att driva bollen framåt i ytor och vinna mark, utan att behöva dribbla förbi någon.','Carrying the ball forward into space to gain ground, without having to beat anyone.',
  array['central_midfielder','wing_back','centre_back','attacking_midfielder'],'{}'::text[]),
 ('feints','Finter för att ta sig förbi en försvarare.','Feints to get past a defender.',
  '{}'::text[],array['hb_backcourt','hb_centre_back','hb_wing']),
 ('weak_foot','Hur bra spelaren är med sin svagare fot.','How good the player is with the weaker foot.',
  array['central_midfielder','attacking_midfielder','striker'],'{}'::text[]),
 ('tackling','Att vinna bollen i en tackling, rent och vid rätt tillfälle.','Winning the ball in a tackle, cleanly and at the right moment.',
  array['centre_back','defensive_midfielder','left_back','right_back'],'{}'::text[]),
 ('back_to_goal','Att ta emot och hålla bollen med ryggen mot mål, och spela vidare eller vända.','Receiving and holding the ball with the back to goal, then laying it off or turning.',
  array['striker','attacking_midfielder'],'{}'::text[]),
 ('finishing','Att göra mål på chanserna i och runt straffområdet.','Scoring from chances in and around the box.',
  array['striker','left_winger','right_winger','attacking_midfielder'],array['hb_wing','hb_pivot']),
 ('set_pieces','Hörnor, frisparkar och straffar: att slå dem eller avsluta dem.','Corners, free kicks and penalties: taking them or finishing them.',
  array['central_midfielder','attacking_midfielder','centre_back'],'{}'::text[]),
 ('goalkeeping','Målvaktens räddningar och placering.','The goalkeeper''s saves and positioning.',
  '{}'::text[],array['goalkeeper']),
 ('goalkeeping_hands','Räddningar, grepp och att ta inlägg.','Saves, handling and claiming crosses.',
  array['goalkeeper'],'{}'::text[]),
 ('goalkeeping_feet','Målvaktens spel med fötterna: passningar, utsparkar och att vara spelbar.','The goalkeeper''s play with the feet: passing, kicking and being available.',
  array['goalkeeper'],'{}'::text[]),
 ('defending_1v1','Att stoppa en motståndare som har bollen, utan att bli passerad.','Stopping an opponent on the ball without being beaten.',
  array['left_back','right_back','centre_back','wing_back'],array['hb_backcourt','hb_centre_back']),
 ('interceptions','Att läsa passningar och bryta dem innan de når fram.','Reading passes and cutting them out before they arrive.',
  array['defensive_midfielder','centre_back'],'{}'::text[]),
 ('marking','Att hålla koll på och täcka sin motståndare, inte minst vid fasta situationer.','Keeping track of and covering an opponent, not least at set pieces.',
  array['centre_back','defensive_midfielder','left_back','right_back'],'{}'::text[]),
 ('blocking','Att komma i vägen för skott och inlägg.','Getting in the way of shots and crosses.',
  array['centre_back','left_back','right_back','defensive_midfielder'],'{}'::text[]),
 ('attacking_1v1','Att utmana och ta sig förbi sin försvarare.','Taking on and beating the defender.',
  array['left_winger','right_winger','striker'],array['hb_backcourt','hb_wing']),
 ('positioning','Att stå rätt i förhållande till boll, medspelare och motståndare.','Being in the right place relative to the ball, team-mates and opponents.',
  array['centre_back','defensive_midfielder','goalkeeper','striker'],array['hb_pivot','goalkeeper']),
 ('game_reading','Att förstå spelet och välja rätt: när man ska passa, driva eller vänta.','Understanding the game and choosing well: when to pass, carry or wait.',
  array['central_midfielder','defensive_midfielder','attacking_midfielder'],array['hb_centre_back']),
 ('pressing','Att snabbt sätta press på bollhållaren, tillsammans med laget.','Pressing the player on the ball quickly, together with the team.',
  array['striker','left_winger','right_winger','central_midfielder'],'{}'::text[]),
 ('duels','Att vinna närkamper och andrabollar.','Winning physical duels and second balls.',
  array['defensive_midfielder','centre_back','central_midfielder','striker'],array['hb_pivot']),
 ('runs_in_behind','Löpningar bakom försvarslinjen som skapar djup.','Runs in behind the back line that stretch the defence.',
  array['striker','left_winger','right_winger'],'{}'::text[]),
 ('recovery_runs','Att springa hem och hjälpa försvaret när bollen tappas.','Running back to help defend when the ball is lost.',
  array['left_winger','right_winger','wing_back','central_midfielder'],'{}'::text[]),
 ('fast_breaks','Att snabbt springa och avsluta kontringar.','Running and finishing fast breaks quickly.',
  '{}'::text[],array['hb_wing']),
 ('leadership','Att ta ansvar, styra och lyfta laget.','Taking responsibility, organising and lifting the team.',
  array['centre_back','central_midfielder','goalkeeper'],array['hb_centre_back','goalkeeper']),
 ('communication','Att prata med och coacha medspelarna under spelet.','Talking to and organising team-mates during play.',
  array['goalkeeper','centre_back'],array['goalkeeper','hb_centre_back']),
 ('work_rate','Att jobba för laget hela matchen, med och utan boll.','Working for the team all match, with and without the ball.',
  array['central_midfielder','left_winger','right_winger','wing_back'],'{}'::text[]),
 ('composure','Att hålla lugnet och välja rätt under press.','Staying calm and choosing well under pressure.',
  array['centre_back','goalkeeper','striker'],array['hb_backcourt'])
) help(key,sv,en,football,handball)
where attribute.key=help.key;

-- As in 20270414090000, with the foot on the sides.
create or replace function internal.template_slots(lines text,match_format text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare counts integer[]:=string_to_array(lines,'-')::integer[]; total integer:=cardinality(counts);
 result jsonb:='[]'; line integer; place integer; count integer; edge boolean; left_side boolean; role text; foot text;
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
   foot:=case when role in('left_back','right_back','wing_back','wide_mid')
    then case when left_side then 'left' else 'right' end end;
   result:=result||jsonb_build_array(jsonb_build_object('code',line||chr(65+place))||internal.template_role(role)
    ||case when foot is null then '{}'::jsonb else jsonb_build_object('foot',foot) end);
  end loop;
 end loop;
 return result;
end$$;

update core.formation_templates set slots=internal.template_slots(lines,match_format);

-- As internal.lineup_fit, with the place's foot against the player's.
create or replace function internal.lineup_fit_v2(team_sport text,slot jsonb,main_position text,positions text[],
 strengths text[],development text[],player_foot text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare fit jsonb:=internal.lineup_fit(team_sport,slot,main_position,positions,strengths,development);
 wanted text:=slot->>'foot'; delta integer; how text;
begin
 if wanted is null or player_foot is null then return fit; end if;
 if player_foot=wanted or player_foot='both_'||wanted then delta:=3; how:='good';
 elsif player_foot='both_equal' then delta:=3; how:='both';
 elsif player_foot like 'both_%' then delta:=1; how:='weaker';
 else delta:=-2; how:='wrong';
 end if;
 return fit||jsonb_build_object('score',(fit->>'score')::integer+delta,'foot',wanted,'foot_fit',how);
end$$;

-- As in 20270413090000, the list with each attribute's help.
create or replace function internal.get_team_player_attributes_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare team_sport text;
begin
 perform internal.require_player_attributes_access(target_club_id,target_team_id);
 select sport into team_sport from core.teams where id=target_team_id;
 return jsonb_build_object(
  'sport',team_sport,
  'catalog',coalesce((select jsonb_agg(jsonb_build_object('key',catalog.key,'area',catalog.area,
    'about_sv',catalog.about_sv,'about_en',catalog.about_en,'positions',to_jsonb(catalog.positions)) order by catalog.sort)
   from core.sport_attributes catalog where catalog.sport=team_sport),'[]'::jsonb),
  'custom',coalesce((select jsonb_agg(jsonb_build_object('id',own.id,'label',own.label) order by lower(own.label),own.id)
   from core.team_attributes own where own.team_id=target_team_id),'[]'::jsonb),
  'players',coalesce((select jsonb_agg(jsonb_build_object(
    'person_id',person.id,'name',person.display_name,
    'foot',(select feet.foot from core.player_feet feet where feet.team_id=target_team_id and feet.club_person_id=person.id),
    'strengths',coalesce((select jsonb_agg(value.attribute_key order by value.attribute_key) from core.player_attributes value
     where value.team_id=target_team_id and value.club_person_id=person.id and value.assessment='strength'
      and value.attribute_key in(select internal.team_attribute_keys(target_team_id))),'[]'::jsonb),
    'development',coalesce((select jsonb_agg(value.attribute_key order by value.attribute_key) from core.player_attributes value
     where value.team_id=target_team_id and value.club_person_id=person.id and value.assessment='development'
      and value.attribute_key in(select internal.team_attribute_keys(target_team_id))),'[]'::jsonb))
   order by person.display_name,person.id)
   from core.club_people person
   where person.club_id=target_club_id and person.status='active'
    and exists(select 1 from core.assignments assignment where assignment.club_id=target_club_id
     and assignment.team_id=target_team_id and assignment.club_person_id=person.id
     and assignment.role_package='player' and assignment.state='active'
     and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now()))),'[]'::jsonb));
end$$;

-- As in 20270408090000, with the foot a place asks for.
create or replace function internal.team_formation_json(formation core.team_formations)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',formation.id,'name',formation.name,'lines',formation.lines,
  'match_format',formation.match_format,'revision',formation.revision,'updated_at',formation.updated_at,
  'slots',coalesce((select jsonb_agg(jsonb_build_object('code',slot.code,'group',slot.position_group,
    'position',saved.value->>'position','foot',saved.value->>'foot',
    'requirements',coalesce((select jsonb_agg(requirement.value order by requirement.ordinality)
     from jsonb_array_elements(saved.value->'requirements') with ordinality requirement
     where requirement.value->>'attribute' in(select internal.team_attribute_keys(formation.team_id))),'[]'::jsonb))
    order by slot.sort)
   from internal.formation_slots(formation.lines,formation.match_format) slot
   left join lateral (select value from jsonb_array_elements(formation.slots) value
    where value->>'code'=slot.code limit 1) saved on true),'[]'::jsonb))
$$;

create or replace function internal.save_team_formation_for_actor(target_club_id uuid,target_team_id uuid,
 formation_id uuid,new_name text,new_lines text,new_match_format text,new_slots jsonb,expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare clean_name text:=regexp_replace(btrim(coalesce(new_name,'')),'\s+',' ','g');
 clean_lines text:=regexp_replace(coalesce(new_lines,''),'\s','','g');
 team_sport text; clean_slots jsonb; saved core.team_formations;
begin
 perform internal.require_team_formations_access(target_club_id,target_team_id);
 if length(clean_name) not between 1 and 60 then raise invalid_parameter_value using message='invalid_name'; end if;
 if new_match_format is null or new_match_format not in('3v3','5v5','7v7','9v9','11v11')
  or clean_lines !~ '^[1-6](-[1-6]){0,4}$'
  or (select count(*) from internal.formation_slots(clean_lines,new_match_format))<>internal.format_players(new_match_format) then
  raise invalid_parameter_value using message='invalid_formation';
 end if;
 if jsonb_typeof(coalesce(new_slots,'[]'))<>'array' then raise invalid_parameter_value using message='invalid_slots'; end if;
 select sport into team_sport from core.teams where id=target_team_id for update;
 -- Each place once, a known code, a position of the sport, valid requirements.
 if exists(select 1 from jsonb_array_elements(coalesce(new_slots,'[]')) value
  where jsonb_typeof(value)<>'object'
   or value->>'code' is null
   or value->>'code' not in(select code from internal.formation_slots(clean_lines,new_match_format))
   or (value->>'position' is not null and not exists(select 1 from core.sport_positions catalog
    where catalog.sport=team_sport and catalog.key=value->>'position'))
   or (value->>'foot' is not null and value->>'foot' not in('left','right'))
   or jsonb_typeof(coalesce(value->'requirements','[]'))<>'array'
   or jsonb_array_length(coalesce(value->'requirements','[]'))>6
   or exists(select 1 from jsonb_array_elements(coalesce(value->'requirements','[]')) requirement
    where jsonb_typeof(requirement)<>'object'
     or requirement->>'attribute' is null
     or requirement->>'attribute' not in(select internal.team_attribute_keys(target_team_id))
     or coalesce(requirement->>'weight','') not in('1','2'))
   or (select count(distinct requirement->>'attribute')<>count(*)
    from jsonb_array_elements(coalesce(value->'requirements','[]')) requirement))
  or (select count(distinct value->>'code')<>count(*) from jsonb_array_elements(coalesce(new_slots,'[]')) value) then
  raise invalid_parameter_value using message='invalid_slots';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('code',value->>'code','position',value->>'position','foot',value->>'foot',
   'requirements',coalesce((select jsonb_agg(jsonb_build_object('attribute',requirement.value->>'attribute',
     'weight',(requirement.value->>'weight')::integer) order by requirement.ordinality)
    from jsonb_array_elements(value->'requirements') with ordinality requirement),'[]'::jsonb))),'[]'::jsonb)
 into clean_slots
 from jsonb_array_elements(coalesce(new_slots,'[]')) value
 where value->>'position' is not null or value->>'foot' is not null or jsonb_array_length(coalesce(value->'requirements','[]'))>0;
 if exists(select 1 from core.team_formations formation where formation.team_id=target_team_id
  and lower(formation.name)=lower(clean_name) and formation.id is distinct from formation_id) then
  raise unique_violation using message='formation_name_taken';
 end if;
 if formation_id is null then
  if (select count(*) from core.team_formations formation where formation.team_id=target_team_id)>=30 then
   raise check_violation using message='too_many_formations'; end if;
  insert into core.team_formations(club_id,team_id,name,lines,match_format,slots,updated_by)
  values(target_club_id,target_team_id,clean_name,clean_lines,new_match_format,clean_slots,auth.uid())
  returning * into saved;
 else
  update core.team_formations formation set name=clean_name,lines=clean_lines,match_format=new_match_format,
   slots=clean_slots,revision=formation.revision+1,updated_at=now(),updated_by=auth.uid()
  where formation.id=formation_id and formation.team_id=target_team_id
   and (expected_revision is null or formation.revision=expected_revision)
  returning * into saved;
  if saved.id is null then
   if exists(select 1 from core.team_formations formation where formation.id=formation_id and formation.team_id=target_team_id) then
    raise sqlstate 'PT409' using message='stale_revision'; end if;
   raise no_data_found using message='formation_not_found';
  end if;
 end if;
 return internal.team_formation_json(saved);
end$$;

-- As in 20270414090000, scoring the foot too.
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
   'number',details.jersey_number,
   'foot',(select feet.foot from core.player_feet feet where feet.team_id=target_team_id and feet.club_person_id=person.id),'main_position',details.main_position,
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
    fit:=internal.lineup_fit_v2(team_sport,open_slots[i],player->>'main_position',
     array(select jsonb_array_elements_text(player->'positions')),
     array(select jsonb_array_elements_text(player->'strengths')),
     array(select jsonb_array_elements_text(player->'development')),player->>'foot');
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


revoke all on function internal.lineup_fit_v2(text,jsonb,text,text[],text[],text[],text) from public,anon,authenticated;
notify pgrst,'reload schema';
