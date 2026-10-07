-- Activities for Demoklubben IF: trainings, matches, meetings and club
-- activities from four weeks back to eight weeks ahead, for every team.
--
-- Run after demo_club.sql, once, in the Supabase SQL editor. Everything runs
-- in one atomic DO block. It stops if the demo club already has activities.
--
-- Events are created like the app does: an owning team (primary, view and
-- co-manage), audiences, a saved place, typed fields, and a 'created'
-- revision. Past activities are completed.
--
-- Trainings and matches from four weeks back to ten days ahead get a sent
-- squad and callups with responses (accepted, declined with a reason, or
-- unanswered, some reminded). Past ones have attendance: present, late (5–20
-- minutes), partial and absent. Deliberate gaps for demos: the last three
-- days have no attendance yet, and A-lag Herr's next match has no callups.

do $events$
declare
 club uuid := (select id from core.clubs where slug='demoklubben-if');
 admin_profile uuid;
 team_row record;
 team_uuid uuid;
 club_team uuid;
 week_start date := date_trunc('week', now())::date;
 week integer;
 slot record;
 day date;
 starts timestamptz;
 ends timestamptz;
 event_id uuid;
 field_main uuid;
 field_grass uuid;
 hall uuid;
 clubhouse uuid;
 place uuid;
 match_number integer;
 home boolean;
 opponent text;
 theme text;
 opponents text[] := array['Eksjö BK','Nässjö FF','Vetlanda IF','Tranås AIF','Aneby SK','Sävsjö FF',
  'Gislaved IS','Värnamo Södra','Jönköping BK','Huskvarna IF','Mullsjö IF','Habo IF'];
 handball_opponents text[] := array['Eksjö HK','HK Nässjö','Vetlanda HF','Tranås HK','IK Cyrus','HK Jönköping'];
 themes text[] := array['Passningsspel och mottagning','Försvarsspel i zon','Avslut och skott',
  'Omställning','Fasta situationer','Spelbredd och djup','Press och återerövring','Uppbyggnadsspel'];
 handball_themes text[] := array['Kontringar','6-0-försvar','Skott från distans','Kantspel',
  'Snabba omställningar','Målvaktsträning'];
 created integer := 0;
 team_number integer := 0;
 ev record;
 player record;
 is_past boolean;
 sent timestamptz;
 squad uuid;
 callup uuid;
 callup_state text;
 roll integer;
 roll2 integer;
 callups_created integer := 0;
 attendance_created integer := 0;

begin
 if club is null then raise exception 'Run demo_club.sql first: Demoklubben IF does not exist'; end if;
 if exists(select 1 from core.events where club_id=club) then
  raise exception 'Demoklubben IF already has activities';
 end if;
 select created_by into admin_profile from core.clubs where id=club;

 insert into core.event_locations(club_id,name,pitch,surface,address,created_by)
 values(club,'Demovallen','Plan 1','Konstgräs','Idrottsvägen 1, Demostad',admin_profile) returning id into field_main;
 insert into core.event_locations(club_id,name,pitch,surface,address,created_by)
 values(club,'Demovallen','Plan 2','Naturgräs','Idrottsvägen 1, Demostad',admin_profile) returning id into field_grass;
 insert into core.event_locations(club_id,name,address,created_by)
 values(club,'Demohallen','Hallgatan 4, Demostad',admin_profile) returning id into hall;
 insert into core.event_locations(club_id,name,address,created_by)
 values(club,'Klubbstugan','Idrottsvägen 3, Demostad',admin_profile) returning id into clubhouse;

 for team_row in
  select t.id, t.name, t.sport,
   case t.name when 'A-lag Herr' then false when 'Dam A' then false else true end as youth,
   -- Training days (1 = Monday) and start time, match day and start time.
   case t.name when 'A-lag Herr' then array[2,4] when 'Dam A' then array[1,3] when 'P2012' then array[1,4]
    when 'F2013' then array[2,4] when 'P2015' then array[3] else array[2,5] end as training_days,
   case t.name when 'A-lag Herr' then time '19:00' when 'Dam A' then time '19:00' when 'P2012' then time '17:30'
    when 'F2013' then time '17:30' when 'P2015' then time '17:00' else time '18:00' end as training_time,
   case t.name when 'A-lag Herr' then 7 when 'Dam A' then 7 else 6 end as match_day,
   case t.name when 'A-lag Herr' then time '15:00' when 'Dam A' then time '13:00' when 'P2012' then time '10:00'
    when 'F2013' then time '12:00' when 'P2015' then time '09:30' else time '11:00' end as match_time
  from core.teams t where t.club_id=club order by t.name
 loop
  team_number := team_number + 1;
  team_uuid := team_row.id;
  if team_row.name = 'A-lag Herr' then club_team := team_uuid; end if;
  match_number := 0;

  for week in -4..7 loop
   -- Trainings.
   for i in 1..array_length(team_row.training_days,1) loop
    day := week_start + week*7 + team_row.training_days[i] - 1;
    starts := (day + team_row.training_time) at time zone 'Europe/Stockholm';
    ends := starts + interval '90 minutes';
    theme := case when team_row.sport='handball'
     then handball_themes[(week + 10 + i + team_number) % array_length(handball_themes,1) + 1]
     else themes[(week + 10 + i + team_number) % array_length(themes,1) + 1] end;
    place := case when team_row.sport='handball' then hall when team_row.youth then field_grass else field_main end;
    insert into core.events(club_id,owning_team_id,event_type,title,state,starts_at,ends_at,timezone,
     location_id,created_by,assembly_minutes_before,training_theme,training_focus,callups_required)
    values(club,team_uuid,'training','Träning',case when ends < now() then 'completed' else 'scheduled' end,
     starts,ends,'Europe/Stockholm',place,admin_profile,15,theme,
     'Uppvärmning, '||lower(theme)||' och avslutande spel.',false)
    returning id into event_id;
    insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
    values(club,event_id,team_uuid,'primary',array['view','co_manage'],admin_profile);
    insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
    select club,event_id,audience,team_uuid,admin_profile from unnest(array['players','leaders']) audience;
    insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id)
    select club,e.id,1,'created','one',internal.event_snapshot(e),admin_profile from core.events e where e.id=event_id;
    created := created + 1;
   end loop;

   -- A match every weekend, home and away in turn.
   match_number := match_number + 1;
   home := match_number % 2 = 1;
   opponent := case when team_row.sport='handball'
    then handball_opponents[(match_number + team_number) % array_length(handball_opponents,1) + 1]
    else opponents[(match_number*5 + team_number) % array_length(opponents,1) + 1] end;
   day := week_start + week*7 + team_row.match_day - 1;
   starts := (day + team_row.match_time) at time zone 'Europe/Stockholm';
   ends := starts + case when team_row.youth then interval '75 minutes' else interval '2 hours' end;
   insert into core.events(club_id,owning_team_id,event_type,title,state,starts_at,ends_at,timezone,
    location_id,created_by,assembly_minutes_before,opponent_name,home_away,match_notes,callups_required)
   values(club,team_uuid,'match',
    case when home then team_row.name||' – '||opponent else opponent||' – '||team_row.name end,
    case when ends < now() then 'completed' else 'scheduled' end,
    starts,ends,'Europe/Stockholm',
    case when not home then null when team_row.sport='handball' then hall else field_main end,
    admin_profile,case when team_row.youth then 45 else 60 end,opponent,case when home then 'home' else 'away' end,
    case when home then 'Hemmamatch. Kom i klubbens matchställ.' else 'Bortamatch. Samåkning från klubbstugan.' end,true)
   returning id into event_id;
   insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
   values(club,event_id,team_uuid,'primary',array['view','co_manage'],admin_profile);
   insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
   select club,event_id,audience,team_uuid,admin_profile
   from unnest(case when team_row.youth then array['players','leaders','guardians'] else array['players','leaders'] end) audience;
   insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id)
   select club,e.id,1,'created','one',internal.event_snapshot(e),admin_profile from core.events e where e.id=event_id;
   created := created + 1;
  end loop;

  -- One team meeting: a parents' meeting for youth teams, a team meeting for seniors.
  day := week_start + 7 + 2;
  starts := (day + time '19:00') at time zone 'Europe/Stockholm';
  insert into core.events(club_id,owning_team_id,event_type,title,state,starts_at,ends_at,timezone,
   location_id,created_by,assembly_minutes_before,meeting_purpose,meeting_agenda,callups_required)
  values(club,team_uuid,'meeting',case when team_row.youth then 'Föräldramöte' else 'Lagmöte' end,'scheduled',
   starts,starts + interval '1 hour','Europe/Stockholm',clubhouse,admin_profile,0,
   case when team_row.youth then 'Information inför säsongens andra halva.' else 'Genomgång av säsongen och målen framåt.' end,
   case when team_row.youth then '1. Säsongen hittills'||chr(10)||'2. Cuper och resor'||chr(10)||'3. Kiosk och ideella insatser'||chr(10)||'4. Övriga frågor'
    else '1. Säsongen hittills'||chr(10)||'2. Mål och spelidé'||chr(10)||'3. Övriga frågor' end,false)
  returning id into event_id;
  insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
  values(club,event_id,team_uuid,'primary',array['view','co_manage'],admin_profile);
  insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
  select club,event_id,audience,team_uuid,admin_profile
  from unnest(case when team_row.youth then array['guardians','leaders'] else array['players','leaders'] end) audience;
  insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id)
  select club,e.id,1,'created','one',internal.event_snapshot(e),admin_profile from core.events e where e.id=event_id;
  created := created + 1;
 end loop;

 -- Club-wide activities and a leaders' meeting, owned by A-lag Herr.
 for slot in select * from (values
  ('activity','Städdag på Demovallen',week_start - 14 + 5,time '10:00',interval '3 hours','club',field_main),
  ('meeting','Ledarmöte',week_start + 3,time '19:00',interval '90 minutes','leaders',clubhouse),
  ('activity','Cupresa till Demo Cup',week_start + 21 + 4,time '16:00',interval '2 days','club',null),
  ('activity','Säsongsavslutning',week_start + 49 + 5,time '15:00',interval '3 hours','club',clubhouse)
 ) as s(kind,title,day,at_time,length,audience,location)
 loop
  starts := (slot.day + slot.at_time) at time zone 'Europe/Stockholm';
  insert into core.events(club_id,owning_team_id,event_type,title,state,starts_at,ends_at,timezone,
   location_id,created_by,assembly_minutes_before,meeting_purpose,callups_required)
  values(club,club_team,slot.kind,slot.title,case when starts + slot.length < now() then 'completed' else 'scheduled' end,
   starts,starts + slot.length,'Europe/Stockholm',slot.location,admin_profile,0,
   case when slot.kind='meeting' then 'Samordning mellan klubbens lag.' end,false)
  returning id into event_id;
  insert into core.event_teams(club_id,event_id,team_id,relation,capabilities,created_by)
  values(club,event_id,club_team,'primary',array['view','co_manage'],admin_profile);
  insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by)
  values(club,event_id,slot.audience,case when slot.audience='club' then null else club_team end,admin_profile);
  insert into core.event_revisions(club_id,event_id,event_revision,action,scope,snapshot,actor_profile_id)
  select club,e.id,1,'created','one',internal.event_snapshot(e),admin_profile from core.events e where e.id=event_id;
  created := created + 1;
 end loop;

 -- Squads, callups, responses and attendance for trainings and matches from
 -- four weeks back to ten days ahead. Outcomes are fixed per event and
 -- person (hash based), so a re-created club looks the same.
 for ev in
  select e.id, e.owning_team_id, e.event_type, e.starts_at, e.ends_at, t.name as team_name
  from core.events e join core.teams t on t.id=e.owning_team_id
  where e.club_id=club and e.event_type in('training','match')
   and e.starts_at < now() + interval '10 days'
  order by e.starts_at
 loop
  is_past := ev.ends_at < now();
  -- Left without callups so the assistant flags it: A-lag Herr's next match.
  if not is_past and ev.event_type='match' and ev.team_name='A-lag Herr'
   and ev.starts_at < now() + interval '48 hours' then continue; end if;
  sent := least(ev.starts_at - case when ev.event_type='match' then interval '5 days' else interval '3 days' end,
   now() - interval '1 hour');
  insert into core.squad_revisions(club_id,event_id,revision,state,created_by,locked_at,sent_at)
  values(club,ev.id,1,'sent',admin_profile,sent,sent) returning id into squad;
  for player in
   select ta.club_person_id as id from core.team_assignments ta
   where ta.team_id=ev.owning_team_id and ta.state='active' order by ta.club_person_id
  loop
   roll := abs(hashtext(ev.id::text||player.id::text)) % 100;
   roll2 := abs(hashtext(player.id::text||ev.id::text||'attendance')) % 100;
   insert into core.squad_members(club_id,event_id,squad_revision_id,club_person_id,selection_state,source,eligibility_snapshot,created_by)
   values(club,ev.id,squad,player.id,'selected','all','{}'::jsonb,admin_profile);
   callup_state := case
    when is_past then case when roll < 78 then 'accepted' when roll < 90 then 'declined' else 'pending' end
    else case when roll < 55 then 'accepted' when roll < 68 then 'declined' else 'pending' end end;
   insert into core.callups(club_id,event_id,squad_revision_id,club_person_id,state,sent_at,expires_at,created_by,revision,
    last_reminded_at,reminder_count)
   values(club,ev.id,squad,player.id,callup_state,sent,greatest(ev.starts_at - interval '2 hours', sent + interval '1 hour'),
    admin_profile,case when callup_state='pending' then 1 else 2 end,
    case when callup_state='pending' and roll2 < 40 then least(sent + interval '1 day', now() - interval '7 hours') end,
    case when callup_state='pending' and roll2 < 40 then 1 else 0 end)
   returning id into callup;
   if callup_state in('accepted','declined') then
    insert into core.callup_responses(club_id,callup_id,response,decline_reason_code,decline_reason_text,
     actor_profile_id,acting_as_person_id,revision,created_at)
    values(club,callup,callup_state,
     case when callup_state='declined' then (array['illness','injury','unavailable','transport','other'])[roll % 5 + 1] end,
     case when callup_state='declined' and roll % 5 = 4 then 'Släktkalas' end,
     admin_profile,player.id,1,least(sent + (roll || ' hours')::interval, now()));
   end if;
   callups_created := callups_created + 1;
   -- Attendance for past events, except the last three days (still to register).
   if is_past and ev.ends_at < now() - interval '3 days' then
    insert into core.attendance_facts(club_id,event_id,club_person_id,status,minutes,note,recorded_at,recorded_by)
    select club,ev.id,player.id,status,minutes,note,ev.ends_at + interval '30 minutes',admin_profile
    from (select
     case
      when callup_state='declined' then 'absent'
      when callup_state='pending' then case when roll2 < 45 then 'present' else 'absent' end
      when roll2 < 7 then 'late'
      when roll2 < 10 then 'partial'
      when roll2 < 14 then 'absent'
      else 'present' end as status) chosen
    cross join lateral (select
     case chosen.status when 'late' then 5 + roll2 % 4 * 5 when 'partial' then 30 + roll2 % 3 * 15 end as minutes,
     case chosen.status when 'late' then 'Sen ankomst' when 'partial' then 'Gick tidigare'
      when 'absent' then case when callup_state='accepted' then 'Uteblev utan besked' end end as note) detail;
    attendance_created := attendance_created + 1;
   end if;
  end loop;
 end loop;

 raise notice 'Created % activities, % callups and % attendance records for Demoklubben IF',
  created, callups_created, attendance_created;
end;
$events$;

-- Overview per team and type.
select t.name as team, e.event_type, count(*) as activities,
 count(*) filter (where e.starts_at >= now()) as upcoming
from core.events e join core.teams t on t.id=e.owning_team_id
join core.clubs c on c.id=e.club_id and c.slug='demoklubben-if'
group by t.name, e.event_type order by t.name, e.event_type;

-- Callups and attendance per team.
select t.name as team,
 count(*) filter (where cu.state='accepted') as accepted,
 count(*) filter (where cu.state='declined') as declined,
 count(*) filter (where cu.state='pending') as unanswered,
 count(af.id) filter (where af.status='present') as present,
 count(af.id) filter (where af.status='late') as late,
 count(af.id) filter (where af.status='partial') as partial,
 count(af.id) filter (where af.status='absent') as absent
from core.callups cu join core.events e on e.id=cu.event_id
join core.teams t on t.id=e.owning_team_id
join core.clubs c on c.id=e.club_id and c.slug='demoklubben-if'
left join core.attendance_facts af on af.event_id=cu.event_id and af.club_person_id=cu.club_person_id
group by t.name order by t.name;
