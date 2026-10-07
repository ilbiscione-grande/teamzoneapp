-- Demoklubben IF: a demo and troubleshooting club.
--
-- Run once in the Supabase SQL editor (as postgres). It is not a migration.
-- Creates six teams with 10–20 people each (players with positions, leaders
-- with titles), guardians linked to youth players (one with children in two
-- teams, one who is also a leader), and a board and office without team
-- links. Only the administrator below gets account access; every other
-- person is a roster person without an account, like people a club adds
-- itself.
--
-- Everything created here has club_people.provenance = 'demo_seed'.
-- The script stops if the club already exists.
--
-- Everything runs in one DO block, which is atomic on its own: the SQL editor
-- may run statements in separate sessions, so no temporary objects are used.

do $demo$
declare
 -- Club administrator: an existing, confirmed TeamZone account.
 admin_email text := 'coach.emilson@gmail.com';
 admin_profile uuid;
 club uuid;
 since timestamptz := now() - interval '30 days';
 board_until timestamptz := date_trunc('year', now()) + interval '1 year 3 months';
 admin_person uuid;
 admin_assignment uuid;
 team_row record;
 team_uuid uuid;
 person uuid;
 assignment uuid;
 i integer;
 born integer;
 first_name text;
 last_name text;
 relation uuid;
 guardian uuid;
 sibling_guardian uuid;
 sibling_surname text;
 leader_parent uuid;
 player_ids uuid[];
 positions text[];
 player_position text;
 title text;
 template text;
 billing uuid;
 male text[] := array['Adam','Albin','Alexander','Alfred','Anton','Arvid','Axel','Benjamin','Carl','Casper',
  'Daniel','David','Edvin','Elias','Emil','Erik','Filip','Gabriel','Gustav','Hampus','Hugo','Isak','Jacob',
  'Jonathan','Kevin','Leo','Liam','Linus','Love','Lucas','Ludvig','Malte','Melvin','Milo','Noah','Oliver',
  'Oscar','Otto','Rasmus','Sam','Sebastian','Theo','Viktor','Vincent','William','Wilmer'];
 female text[] := array['Agnes','Alice','Alma','Astrid','Bella','Ebba','Ellen','Elsa','Elvira','Emilia',
  'Emma','Engla','Freja','Hanna','Ida','Ines','Iris','Julia','Klara','Lea','Leah','Lilly','Linnea','Lova',
  'Maja','Matilda','Meja','Moa','Molly','Nellie','Nora','Olivia','Saga','Sara','Selma','Signe','Sofia',
  'Stella','Thea','Tilde','Vera','Wilma','Alva','Edith','Ester','Juni'];
 surnames text[] := array['Andersson','Johansson','Karlsson','Nilsson','Eriksson','Larsson','Olsson',
  'Persson','Svensson','Gustafsson','Pettersson','Jonsson','Jansson','Hansson','Bengtsson','Jönsson',
  'Lindberg','Jakobsson','Magnusson','Lindström','Olofsson','Lindqvist','Lindgren','Berg','Axelsson',
  'Bergström','Lundberg','Lind','Lundgren','Lundqvist','Mattsson','Berglund','Fredriksson','Sandberg',
  'Henriksson','Forsberg','Sjöberg','Wallin','Engström','Eklund','Danielsson','Lundin','Håkansson',
  'Björk','Bergman','Gunnarsson','Holm','Wikström','Samuelsson','Isaksson','Fransson','Bergqvist'];
 football_positions text[] := array['goalkeeper','defender','defender','defender','defender',
  'midfielder','midfielder','midfielder','midfielder','forward','forward'];
 handball_positions text[] := array['goalkeeper','hb_backcourt','hb_backcourt','hb_backcourt',
  'hb_wing','hb_wing','hb_pivot'];
 leader_titles text[] := array['head_coach','assistant_coach','team_manager'];
 leader_templates text[] := array['head_coach','assistant_coach','team_manager'];
 club_capabilities text[] := array['club.memberships.manage','event.manage','event.attendance.correct_late',
  'development.manage','board.read'];
 team_number integer := 0;
begin
 select u.id into admin_profile from auth.users u
 where lower(u.email)=lower(admin_email) and u.email_confirmed_at is not null;
 if admin_profile is null or not exists(select 1 from core.profiles where id=admin_profile) then
  raise exception 'No confirmed account with that e-mail address: %', admin_email;
 end if;
 if exists(select 1 from core.clubs where slug='demoklubben-if') then
  raise exception 'Demoklubben IF already exists (slug demoklubben-if)';
 end if;

 insert into core.clubs(name,slug,status,created_by,brand_primary_color,brand_accent_color)
 values('Demoklubben IF','demoklubben-if','active',admin_profile,'#0b3d91','#ffc61a')
 returning id into club;

 -- The administrator, linked to the existing account.
 insert into core.club_people(club_id,display_name,birth_year,safeguarding_required,provenance,created_by)
 values(club,coalesce(nullif(btrim((select display_name from core.profiles where id=admin_profile)),''),'Klubbadministratör'),
  null,false,'demo_seed',admin_profile) returning id into admin_person;
 insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at,created_by)
 values(club,admin_person,admin_profile,'active',now(),admin_profile);

 -- Board and office: club functionaries without a team.
 for i in 1..6 loop
  first_name := case when i % 2 = 0 then female[(i*5) % array_length(female,1) + 1] else male[(i*7) % array_length(male,1) + 1] end;
  last_name := surnames[(i*11) % array_length(surnames,1) + 1];
  insert into core.club_people(club_id,display_name,birth_year,safeguarding_required,provenance,created_by)
  values(club,first_name||' '||last_name,1960 + i*3,false,'demo_seed',admin_profile) returning id into person;
  insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
  values(club,null,person,'club_functionary','active',since,admin_profile) returning id into assignment;
  if i <= 5 then
   insert into core.board_mandates(club_id,assignment_id,office,starts_at,ends_at,state)
   values(club,assignment,(array['chair','treasurer','secretary','member','auditor'])[i],since,board_until,'active');
  end if;
 end loop;

 -- Teams: name, sport, sex, born from, born to, players, youth, leaders.
 for team_row in
  select * from (values
   ('A-lag Herr','football','m',1990,2004,16,false,3),
   ('Dam A','football','f',1992,2005,15,false,2),
   ('P2012','football','m',2012,2012,14,true,3),
   ('F2013','football','f',2013,2013,13,true,2),
   ('P2015','football','m',2015,2015,11,true,2),
   ('Handboll F14','handball','f',2011,2012,12,true,2)
  ) as t(name,sport,sex,born_from,born_to,players,youth,leaders)
 loop
  team_number := team_number + 1;
  insert into core.teams(club_id,name,status,sport,created_by)
  values(club,team_row.name,'active',team_row.sport,admin_profile) returning id into team_uuid;

  -- The administrator gets a context per team, with club-wide rights.
  insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
  values(club,team_uuid,admin_person,'club_functionary','active',since,admin_profile)
  returning id into admin_assignment;
  insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by)
  select club,admin_assignment,capability,'club',club,since,admin_profile from unnest(club_capabilities) capability
  on conflict do nothing;

  -- Players with a home team, positions and a main position.
  player_ids := array[]::uuid[];
  for i in 1..team_row.players loop
   first_name := case when team_row.sex='m'
    then male[(team_number*13 + i*7) % array_length(male,1) + 1]
    else female[(team_number*13 + i*7) % array_length(female,1) + 1] end;
   last_name := surnames[(team_number*17 + i*5) % array_length(surnames,1) + 1];
   born := team_row.born_from + (i % (team_row.born_to - team_row.born_from + 1));
   insert into core.club_people(club_id,display_name,birth_year,safeguarding_required,provenance,created_by)
   values(club,first_name||' '||last_name,born,team_row.youth,'demo_seed',admin_profile) returning id into person;
   player_ids := player_ids || person;
   insert into core.team_assignments(club_id,team_id,club_person_id,kind,state,starts_at,created_by)
   values(club,team_uuid,person,'home','active',since,admin_profile);
   positions := case when team_row.sport='handball' then handball_positions else football_positions end;
   player_position := case when i = 1 then 'goalkeeper' else positions[(i % array_length(positions,1)) + 1] end;
   insert into core.team_person_details(club_id,team_id,club_person_id,positions,main_position,updated_by)
   values(club,team_uuid,person,array[player_position],player_position,admin_profile);
  end loop;

  -- Leaders with titles; the head coach may also add leaders.
  for i in 1..team_row.leaders loop
   first_name := case when (team_number + i) % 3 = 0
    then female[(team_number*3 + i*11) % array_length(female,1) + 1]
    else male[(team_number*3 + i*11) % array_length(male,1) + 1] end;
   last_name := surnames[(team_number*23 + i*3) % array_length(surnames,1) + 1];
   -- In P2012 the second leader is also a player's parent.
   if team_row.name = 'P2012' and i = 2 then
    last_name := (select split_part(display_name,' ',2) from core.club_people where id=player_ids[3]);
   end if;
   insert into core.club_people(club_id,display_name,birth_year,safeguarding_required,provenance,created_by)
   values(club,first_name||' '||last_name,1972 + team_number + i,false,'demo_seed',admin_profile) returning id into person;
   insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
   values(club,team_uuid,person,'leader','active',since,admin_profile) returning id into assignment;
   title := leader_titles[i];
   template := leader_templates[i];
   insert into core.team_person_details(club_id,team_id,club_person_id,functions,permission_template,main_title,updated_by)
   values(club,team_uuid,person,array[title],template,title,admin_profile);
   if i = 1 then
    insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by)
    values(club,assignment,'team.leaders.manage','team',team_uuid,since,admin_profile) on conflict do nothing;
   end if;
   if team_row.name = 'P2012' and i = 2 then leader_parent := person; end if;
  end loop;

  -- Guardians for youth players: one per child for the first eight players.
  if team_row.youth then
   for i in 1..least(8, array_length(player_ids,1)) loop
    last_name := (select split_part(display_name,' ',2) from core.club_people where id=player_ids[i]);
    if team_row.name = 'P2012' and i = 3 and leader_parent is not null then
     guardian := leader_parent;
    elsif team_row.name = 'P2015' and i = 1 and sibling_guardian is not null then
     -- Sibling of an F2013 player: same parent, same surname.
     guardian := sibling_guardian;
     update core.club_people set display_name=split_part(display_name,' ',1)||' '||sibling_surname
     where id=player_ids[i];
    else
     first_name := case when i % 2 = 0
      then female[(team_number*7 + i*5) % array_length(female,1) + 1]
      else male[(team_number*7 + i*5) % array_length(male,1) + 1] end;
     insert into core.club_people(club_id,display_name,birth_year,safeguarding_required,provenance,created_by)
     values(club,first_name||' '||last_name,1975 + (i % 10),false,'demo_seed',admin_profile) returning id into guardian;
     if team_row.name = 'F2013' and i = 1 then
      sibling_guardian := guardian;
      sibling_surname := last_name;
     end if;
    end if;
    insert into core.guardian_relations(club_id,guardian_person_id,child_person_id,kind,state,starts_at,created_by)
    values(club,guardian,player_ids[i],'custodian','active',since,admin_profile) returning id into relation;
    perform internal.ensure_guardian_context_for_relation(relation);
   end loop;
  end if;
 end loop;

 -- Board pages in the app need the economy module for this club.
 insert into core.billing_accounts(club_id,environment,state) values(club,'test','active') returning id into billing;
 insert into core.club_entitlements(club_id,billing_account_id,entitlement_key,access_mode,source_subscription_revision,effective_at)
 values(club,billing,'module.economy','write',1,since);

 raise notice 'Demoklubben IF created: club %, % people', club,
  (select count(*) from core.club_people where club_id=club);
end;
$demo$;

-- A quick overview of what was created.
select t.name as team, t.sport,
 count(distinct ta.club_person_id) filter (where ta.state='active') as players,
 count(distinct a.club_person_id) filter (where a.role_package='leader') as leaders,
 count(distinct a.club_person_id) filter (where a.role_package='guardian') as guardians
from core.teams t
join core.clubs c on c.id=t.club_id and c.slug='demoklubben-if'
left join core.team_assignments ta on ta.team_id=t.id
left join core.assignments a on a.team_id=t.id and a.state='active'
group by t.name,t.sport order by t.name;

