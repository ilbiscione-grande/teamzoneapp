-- More player attributes after a search of common attribute lists (asked for
-- by the product owner 2026-11-22): the goalkeeper's own (aerial play,
-- reflexes, one against one, sweeping, throwing and kicking), long shots,
-- long throws and balance, scanning, getting free and creativity, and the
-- mental ones: concentration, will to win, courage and coachability. The
-- general ones are in every sport. The goalkeeper's footwork is the short
-- passing game now; claiming crosses moved from saves to aerial play.
-- Long passing already covers the goalkeeper's long passes.

insert into core.sport_attributes(sport,key,area,sort,about_sv,about_en,positions)
select attribute.sport,attribute.key,attribute.area,attribute.sort,attribute.sv,attribute.en,
 case when attribute.sport='football' then attribute.football when attribute.sport='handball' then attribute.handball else '{}' end
from (values
 ('football','goalkeeping_reflexes','technical',212,'Snabba räddningar på nära håll och på skott som ändrar riktning.','Quick saves at close range and on deflected shots.',array['goalkeeper'],'{}'::text[]),
 ('football','goalkeeping_aerial','technical',214,'Luftrum: att ta inlägg, hörnor och höga bollar och styra sitt område.','Aerial play: claiming crosses, corners and high balls, and commanding the area.',array['goalkeeper'],'{}'::text[]),
 ('football','goalkeeping_1v1','technical',216,'Att stänga vinklar och rädda när en anfallare kommer fri mot mål.','Closing angles and saving when an attacker is through on goal.',array['goalkeeper'],'{}'::text[]),
 ('football','goalkeeping_sweeping','technical',218,'Utrusningar: att läsa djupledsbollar och rusa ut som en extra back bakom försvaret.','Sweeping: reading balls in behind and rushing out as an extra defender.',array['goalkeeper'],'{}'::text[]),
 ('football','goalkeeping_kicking','technical',222,'Utsparkar med precision och längd, från marken och ur handen.','Goal kicks and kicks from the hands with accuracy and length.',array['goalkeeper'],'{}'::text[]),
 ('football','goalkeeping_throwing','technical',224,'Utkast med handen som snabbt sätter igång anfall.','Throws with the hand that start attacks quickly.',array['goalkeeper'],'{}'::text[]),
 ('football','long_shots','technical',125,'Skott från distans, utanför straffområdet.','Shots from distance, outside the box.',array['attacking_midfielder','central_midfielder','striker'],'{}'::text[]),
 ('football','long_throws','technical',205,'Långa inkast som blir som ett inlägg in i straffområdet.','Long throw-ins that work like a cross into the box.',array['left_back','right_back','wing_back'],'{}'::text[]),
 ('football','balance','physical',55,'Att stå kvar och behålla kontrollen i närkamp och i fart.','Staying on the feet and in control in duels and at speed.',array['left_winger','right_winger','attacking_midfielder','striker'],'{}'::text[]),
 ('handball','balance','physical',55,'Att stå kvar och behålla kontrollen i närkamp och i fart.','Staying on the feet and in control in duels and at speed.','{}'::text[],array['hb_pivot','hb_wing']),
 ('other','balance','physical',55,'Att stå kvar och behålla kontrollen i närkamp och i fart.','Staying on the feet and in control in duels and at speed.','{}'::text[],'{}'::text[])
) attribute(sport,key,area,sort,sv,en,football,handball)
on conflict (sport,key) do nothing;

-- The general ones, in every sport.
insert into core.sport_attributes(sport,key,area,sort,about_sv,about_en,positions)
select sport.name,attribute.key,attribute.area,attribute.sort,attribute.sv,attribute.en,
 case when sport.name='football' then attribute.football when sport.name='handball' then attribute.handball else '{}' end
from (values ('football'),('handball'),('other')) sport(name)
cross join (values
 ('scanning','tactical',345,'Att hela tiden hålla koll på vad som händer runt omkring sig på planen, med och utan boll.','Keeping track of what happens around oneself on the pitch all the time, with and without the ball.',
  array['central_midfielder','defensive_midfielder','centre_back','attacking_midfielder'],array['hb_centre_back','hb_backcourt']),
 ('creativity','tactical',348,'Att våga det oväntade och hitta egna lösningar.','Daring the unexpected and finding solutions of one''s own.',
  array['attacking_midfielder','left_winger','right_winger','striker'],array['hb_centre_back','hb_backcourt']),
 ('off_the_ball','tactical',372,'Spelbarhet: att röra sig utan boll för att göra sig spelbar och hitta ytor.','Getting free: moving without the ball to be available and find space.',
  array['striker','attacking_midfielder','central_midfielder','left_winger','right_winger'],array['hb_pivot','hb_wing']),
 ('concentration','mental',445,'Att hålla fokus hela matchen och inte tappa i detaljer.','Staying focused all match without losing the details.',
  array['goalkeeper','centre_back','defensive_midfielder'],array['goalkeeper']),
 ('determination','mental',450,'Vinnarskalle: viljan att vinna och att aldrig ge upp.','Will to win: wanting to win and never giving up.','{}'::text[],'{}'::text[]),
 ('bravery','mental',455,'Mod: att våga gå in i dueller, ta bollen och ta risker.','Courage: daring to go into duels, ask for the ball and take risks.',
  array['centre_back','goalkeeper','striker'],array['hb_pivot','goalkeeper']),
 ('coachability','mental',460,'Att ta till sig instruktioner och feedback och utvecklas av dem.','Taking in instructions and feedback and growing from them.','{}'::text[],'{}'::text[])
) attribute(key,area,sort,sv,en,football,handball)
on conflict (sport,key) do nothing;

-- The goalkeeper's footwork is the short passing game; crosses are aerial play.
update core.sport_attributes set
 about_sv='Målvaktens korta passningsspel med fötterna: att vara spelbar och spela ut under press.',
 about_en='The goalkeeper''s short passing game with the feet: being available and playing out under pressure.'
where key='goalkeeping_feet';
update core.sport_attributes set about_sv='Räddningar och grepp på skott.',about_en='Saves and handling of shots.'
where key='goalkeeping_hands';

-- As in 20270414090000, the goalkeeper of a template also asks for aerial play.
create or replace function internal.template_role(role text)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('position',r.position,'requirements',(select jsonb_agg(jsonb_build_object(
   'attribute',split_part(x.item,':',1),'weight',split_part(x.item,':',2)::integer) order by x.n)
  from unnest(r.items) with ordinality as x(item,n)))
 from (values
  ('goalkeeper','goalkeeper',array['goalkeeping_hands:2','goalkeeping_aerial:1','goalkeeping_feet:1','communication:1']),
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

update core.formation_templates set slots=internal.template_slots(lines,match_format);
notify pgrst,'reload schema';
