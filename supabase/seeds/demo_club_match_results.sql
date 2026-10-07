-- Results and match reports for Demoklubben IF's played matches.
--
-- Run after demo_club_events.sql, once, in the Supabase SQL editor.
-- Everything runs in one atomic DO block. Matches that already have a
-- match workspace (registered in the app) are left alone.
--
-- Most played matches get a completed result built from real match facts:
-- a frozen squad (the players registered as present), goals with scorer,
-- assist and minute, opponent goals and full time, so scores, player
-- statistics and KPI follow-up all work. Deliberate gaps for demos: three
-- teams' latest match has no result yet (the assistant asks for it) and
-- some results have no written report. About half of the reports are
-- published, the rest are internal drafts.

do $results$
declare
 club uuid := (select id from core.clubs where slug='demoklubben-if');
 admin_profile uuid;
 m record;
 command uuid;
 roster uuid;
 players uuid[];
 periods integer[];
 total integer;
 score_us integer;
 score_them integer;
 n integer;
 scorer uuid;
 assist uuid;
 minute integer;
 scorers text;
 opponent text;
 report text;
 results_created integer := 0;
 reports_created integer := 0;
begin
 if club is null then raise exception 'Run demo_club.sql first: Demoklubben IF does not exist'; end if;
 select created_by into admin_profile from core.clubs where id=club;

 for m in
  select e.id, e.club_id, e.owning_team_id, e.starts_at, e.ends_at, e.opponent_name, e.home_away,
   t.name team_name, t.sport,
   row_number() over (partition by e.owning_team_id order by e.starts_at desc) latest,
   dense_rank() over (order by t.name) team_number
  from core.events e join core.teams t on t.id=e.owning_team_id
  where e.club_id=club and e.event_type='match' and e.ends_at<now() and e.state<>'cancelled'
   and e.archived_at is null
   and not exists(select 1 from core.match_workspaces w where w.event_id=e.id)
  order by e.starts_at
 loop
  -- Gaps: the latest match of every other team, and roughly one in eight.
  continue when m.latest=1 and m.team_number % 2=1;
  continue when abs(hashtext(m.id::text||'skip')) % 8=0;

  periods := case
   when m.sport='handball' then array[20,20]
   when m.team_name in('A-lag Herr','Dam A') then array[45,45]
   when m.team_name like '%2015%' then array[20,20]
   else array[30,30] end;
  total := periods[1]+periods[2];
  opponent := coalesce(nullif(btrim(m.opponent_name),''),'motståndarna');

  insert into core.match_workspaces(event_id,club_id,team_id,state,revision,roster_revision,match_started_at,
   completed_at,updated_at,updated_by,period_minutes,current_period)
  values(m.id,m.club_id,m.owning_team_id,'completed',2,1,m.starts_at,m.ends_at,m.ends_at,admin_profile,periods,2);

  -- The squad: players registered as present, late or partly present.
  roster := gen_random_uuid();
  insert into core.match_roster_revisions(id,event_id,revision,state,reason_code,created_at,created_by)
  values(roster,m.id,1,'frozen','initial',m.starts_at,admin_profile);
  insert into core.match_roster_members(roster_revision_id,club_person_id,club_id,source_callup_id,source_state,created_at)
  select distinct on (f.club_person_id) roster,f.club_person_id,m.club_id,c.id,
   case when c.id is null then 'leader_added' else 'accepted' end,m.starts_at
  from core.attendance_facts f
  join core.assignments a on a.club_person_id=f.club_person_id and a.club_id=m.club_id
   and a.team_id=m.owning_team_id and a.role_package='player' and a.state='active'
  left join core.callups c on c.event_id=m.id and c.club_person_id=f.club_person_id and c.state='accepted'
  where f.event_id=m.id and f.status in('present','late','partial')
  order by f.club_person_id;
  select array_agg(r.club_person_id order by r.club_person_id) into players
  from core.match_roster_members r where r.roster_revision_id=roster;
  if players is null then
   select array_agg(a.club_person_id order by a.club_person_id) into players from core.assignments a
   where a.club_id=m.club_id and a.team_id=m.owning_team_id and a.role_package='player' and a.state='active';
  end if;

  -- Score: more goals in handball, a mix of wins, draws and losses.
  score_us := case when m.sport='handball' then 14+abs(hashtext(m.id::text||'us')) % 12
   else (array[0,1,1,2,2,2,3,3,4,5])[abs(hashtext(m.id::text||'us')) % 10 + 1] end;
  score_them := case when m.sport='handball' then 13+abs(hashtext(m.id::text||'them')) % 12
   else (array[0,0,1,1,1,2,2,3,4])[abs(hashtext(m.id::text||'them')) % 9 + 1] end;

  for n in 1..score_us loop
   minute := 1+abs(hashtext(m.id::text||'us'||n)) % (total-1);
   scorer := players[1+abs(hashtext(m.id::text||'scorer'||n)) % cardinality(players)];
   assist := case when cardinality(players)>1 and abs(hashtext(m.id::text||'assist'||n)) % 10<6
    then players[1+abs(hashtext(m.id::text||'assister'||n)) % cardinality(players)] end;
   if assist=scorer then assist := null; end if;
   command := gen_random_uuid();
   insert into audit.match_commands(command_id,event_id,expected_revision,command_type,payload,result,actor_profile_id,created_at)
   values(command,m.id,null,'record_event','{"source":"demo_seed"}','{}',admin_profile,m.starts_at+make_interval(mins=>minute));
   insert into core.match_facts(event_id,minute,fact_type,side,club_person_id,secondary_club_person_id,club_id,detail,
    source_command_id,created_at,created_by,updated_at,updated_by)
   values(m.id,minute,'goal','us',scorer,assist,m.club_id,'{}',command,m.starts_at+make_interval(mins=>minute),
    admin_profile,m.ends_at,admin_profile);
  end loop;
  for n in 1..score_them loop
   minute := 1+abs(hashtext(m.id::text||'them'||n)) % (total-1);
   command := gen_random_uuid();
   insert into audit.match_commands(command_id,event_id,expected_revision,command_type,payload,result,actor_profile_id,created_at)
   values(command,m.id,null,'record_event','{"source":"demo_seed"}','{}',admin_profile,m.starts_at+make_interval(mins=>minute));
   insert into core.match_facts(event_id,minute,fact_type,side,club_id,detail,source_command_id,created_at,created_by,updated_at,updated_by)
   values(m.id,minute,'goal','opponent',m.club_id,'{}',command,m.starts_at+make_interval(mins=>minute),admin_profile,m.ends_at,admin_profile);
  end loop;
  command := gen_random_uuid();
  insert into audit.match_commands(command_id,event_id,expected_revision,command_type,payload,result,actor_profile_id,created_at)
  values(command,m.id,null,'complete','{"source":"demo_seed"}','{}',admin_profile,m.ends_at);
  insert into core.match_facts(event_id,minute,fact_type,club_id,detail,source_command_id,created_at,created_by,updated_at,updated_by)
  values(m.id,total,'full_time',m.club_id,'{"source":"registered_result"}',command,m.ends_at,admin_profile,m.ends_at,admin_profile);
  insert into audit.match_fact_versions(fact_id,event_id,fact_revision,snapshot,action,actor_profile_id,created_at)
  select f.id,f.event_id,1,to_jsonb(f),'created',admin_profile,f.created_at from core.match_facts f where f.event_id=m.id;
  perform internal.recompute_match_projection(m.id);
  results_created := results_created+1;

  -- A written report for about two results in three.
  continue when abs(hashtext(m.id::text||'report')) % 3=0;
  select string_agg(name||case when goals>1 then ' ('||goals||')' else '' end, ', ' order by goals desc,name) into scorers
  from (select p.display_name name,count(*) goals from core.match_facts f join core.club_people p on p.id=f.club_person_id
   where f.event_id=m.id and f.fact_type='goal' and f.side='us' group by p.display_name) s;
  report := case
   when score_us>score_them then (array[
    'Stark insats av hela laget mot '||opponent||'! Vi tog kommandot tidigt och höll ihop försvaret bra. Passningsspelet satt fint och vi skapade många chanser.',
    'Seger med '||score_us||'–'||score_them||' mot '||opponent||'. Ett tålmodigt uppbyggnadsspel gav utdelning och alla spelare bidrog. Nu bygger vi vidare på träningarna i veckan.',
    'Härlig match och välförtjänt seger mot '||opponent||'. Bra press högt upp i planen och snabba omställningar var nyckeln.'])[abs(hashtext(m.id::text||'text')) % 3 + 1]
   when score_us=score_them then (array[
    'Jämn match mot '||opponent||' som slutade '||score_us||'–'||score_them||'. Vi hade mer av spelet i andra halvlek men fick inte till det avgörande målet.',
    'Oavgjort mot '||opponent||'. Bra kämpaglöd hela vägen, och vi tar med oss att vi kom tillbaka efter en trög start.'])[abs(hashtext(m.id::text||'text')) % 2 + 1]
   else (array[
    'Tung förlust mot '||opponent||', men mycket att ta med oss. Vi skapade chanser men var för slarviga i avsluten. Fokus på avslut och skott på träningen.',
    opponent||' var starkare idag och vann med '||score_them||'–'||score_us||'. Vi kämpade bra men tappade för många bollar på egen planhalva.'])[abs(hashtext(m.id::text||'text')) % 2 + 1]
  end || case when scorers is null then '' else E'\n\nMålskyttar: '||scorers||'.' end;
  insert into core.match_reports(event_id,body,published,revision,updated_by,updated_at)
  values(m.id,report,abs(hashtext(m.id::text||'publish')) % 2=0,1,admin_profile,m.ends_at+interval '3 hours');
  reports_created := reports_created+1;
 end loop;

 raise notice 'Created % results and % match reports', results_created, reports_created;
end;
$results$;

-- Played matches per team: with result, with report, still without result.
select t.name as team,
 count(*) as played,
 count(w.event_id) filter (where w.state='completed') as with_result,
 count(r.event_id) as with_report,
 count(*) filter (where w.event_id is null) as without_result
from core.events e
join core.teams t on t.id=e.owning_team_id
join core.clubs c on c.id=e.club_id and c.slug='demoklubben-if'
left join core.match_workspaces w on w.event_id=e.id
left join core.match_reports r on r.event_id=e.id
where e.event_type='match' and e.ends_at<now() and e.state<>'cancelled'
group by t.name order by t.name;
