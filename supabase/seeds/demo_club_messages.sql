-- Messages for Demoklubben IF: team and leader chats, direct messages, a
-- group conversation and announcements between the demo logins.
--
-- Run after demo_club.sql, demo_club_events.sql and demo_club_logins.sql
-- (and migration 20261011090000, which lets players and guardians answer),
-- once, in the Supabase SQL editor. Everything runs in one atomic DO block
-- and stops if the demo club already has messages.
--
-- Only people with an account can take part in a conversation, so the
-- conversations are between the linked demo logins:
--   coach    Hugo Olofsson   – huvudtränare P2012 (tre60grader+tranare)
--   manager  Alva Lundberg   – lagledare P2012 (tre60grader+lagledare)
--   guardian Milo Lindqvist  – vårdnadshavare F2013/P2015 (tre60grader+vardnadshavare)
--   chair    Benjamin Jonsson – ordförande (tre60grader+styrelse)
--   player   Hugo Lindgren   – målvakt A-lag Herr (tre60grader+spelare)
--   admin    Thomas Emilson  – klubbadministratör (coach.emilson)
--
-- Players and guardians may only start conversations with leaders but can
-- answer anyone who writes to them, so their direct conversations are started
-- by the chair. The chair and the administrator get the club-wide messaging
-- capability (club.messaging.manage) so they can write to everyone.
--
-- Each message is sent through the app's own messaging functions as its
-- sender (same permission rules as in the app) and then dated back over the
-- last two weeks. Messages from the last day are left unread for the
-- recipients. No notifications are sent: the queued ones are suppressed.

do $messages$
declare
 club uuid := (select id from core.clubs where slug='demoklubben-if');
 people jsonb := '{}'::jsonb;
 threads jsonb := '{}'::jsonb;
 who record;
 def record;
 msg record;
 actor uuid;
 ctx uuid;
 thread uuid;
 recipients uuid[];
 result jsonb;
 sent_at timestamptz;
 sent_messages uuid[] := '{}';
 sent_count integer := 0;
begin
 if club is null then raise exception 'Run demo_club.sql first: Demoklubben IF does not exist'; end if;
 if exists(select 1 from core.messages m where m.club_id=club) then
  raise exception 'Demoklubben IF already has messages';
 end if;

 -- Demo logins → profile ids.
 for who in select * from (values
  ('coach','tre60grader+tranare@gmail.com'),
  ('manager','tre60grader+lagledare@gmail.com'),
  ('guardian','tre60grader+vardnadshavare@gmail.com'),
  ('chair','tre60grader+styrelse@gmail.com'),
  ('player','tre60grader+spelare@gmail.com'),
  ('admin','coach.emilson@gmail.com')
 ) as w(role,email)
 loop
  select l.profile_id into actor from core.person_account_links l join auth.users u on u.id=l.profile_id
  where l.club_id=club and l.state='active' and lower(u.email)=who.email;
  if actor is null then raise exception 'Demo login % is not linked; run demo_club_logins.sql', who.email; end if;
  people := people || jsonb_build_object(who.role, actor);
 end loop;

 -- The chair and the club administrator may write to everyone in the club
 -- (club.messaging.manage on their club functionary assignments).
 insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by)
 select club,a.id,'club.messaging.manage','club',club,now()-interval '1 minute',l.profile_id
 from core.person_account_links l
 join core.assignments a on a.club_person_id=l.club_person_id and a.club_id=l.club_id
  and a.role_package='club_functionary' and a.state='active'
 where l.profile_id in((people->>'chair')::uuid,(people->>'admin')::uuid) and l.club_id=club and l.state='active'
  and not exists(select 1 from core.capability_grants g where g.assignment_id=a.id
   and g.capability='club.messaging.manage' and (g.ends_at is null or g.ends_at>now()));

 -- Conversations: key, type, creator, context team (null = club), subject,
 -- recipients (roles; '*team' = everyone with an account in the team).
 for def in select * from (values
  ('p2012_team','team',null,'P2012','P2012 – Lagchatt',null),
  ('p2012_leaders','leader',null,'P2012','P2012 – Ledarchatt',null),
  ('f2013_team','team',null,'F2013','F2013 – Lagchatt',null),
  ('p2015_team','team',null,'P2015','P2015 – Lagchatt',null),
  ('alag_team','team',null,'A-lag Herr','A-lag Herr – Lagchatt',null),
  ('dm_chair_coach','direct','chair',null,null,'coach'),
  ('dm_chair_admin','direct','chair',null,null,'admin'),
  ('dm_chair_guardian','direct','chair',null,null,'guardian'),
  ('dm_chair_player','direct','chair',null,null,'player'),
  ('dm_coach_manager','direct','coach','P2012',null,'manager'),
  ('group_autumn','group','chair',null,'Höstavslutning 2026','coach,manager,admin'),
  ('ann_club','announcement','chair',null,'Årsmöte 20 november','coach,manager,guardian,player,admin'),
  ('ann_p2012','announcement','coach','P2012','Nya träningstider från vecka 44','*team')
 ) as d(key,kind,creator,team,subject,recipients)
 loop
  thread := null;
  if def.kind in('team','leader') then
   select t.id into thread from core.message_threads t
   where t.club_id=club and t.thread_type=def.kind and t.subject=def.subject and t.state='active';
   if thread is null then raise notice 'Skipped %: no % chat', def.key, def.subject; continue; end if;
  else
   actor := (people->>def.creator)::uuid;
   perform set_config('request.jwt.claim.sub', actor::text, true);
   perform set_config('request.jwt.claims', jsonb_build_object('sub',actor,'role','authenticated')::text, true);
   select c.context_id into ctx from internal.get_my_contexts_for_actor() c
   where c.club_id=club and (case when def.team is null then c.team_id is null else c.team_name=def.team end)
   order by c.role_package limit 1;
   if ctx is null then
    -- A leader without a club-level context writes from one of their teams.
    select c.context_id into ctx from internal.get_my_contexts_for_actor() c where c.club_id=club
    order by c.team_id nulls first limit 1;
   end if;
   if def.recipients='*team' then
    select array_agg(distinct l.profile_id) into recipients
    from core.person_account_links l
    join core.assignments a on a.club_person_id=l.club_person_id and a.club_id=l.club_id and a.state='active'
    join core.teams t on t.id=a.team_id and t.name=def.team
    where l.club_id=club and l.state='active' and l.profile_id<>actor;
   else
    select array_agg((people->>r)::uuid) into recipients from unnest(string_to_array(def.recipients,',')) r;
   end if;
   if recipients is null then raise notice 'Skipped %: no recipients', def.key; continue; end if;
   begin
    if def.kind='announcement' then
     thread := internal.create_announcement_for_actor(ctx,def.subject,recipients,gen_random_uuid());
    else
     thread := internal.create_thread_for_actor(ctx,def.kind,def.subject,recipients,gen_random_uuid());
    end if;
   exception when insufficient_privilege or invalid_parameter_value then
    raise notice 'Skipped %: % (%)', def.key, sqlerrm, def.recipients;
    continue;
   end;
  end if;
  threads := threads || jsonb_build_object(def.key, thread);
 end loop;

 -- Messages: conversation, sender, minutes ago, text. Oldest first.
 for msg in select * from (values
  ('p2012_team','coach',20100,'Hej alla! Nu är höstens schema inlagt i kalendern. Träning tisdagar och torsdagar 17.30 på Demovallen.'),
  ('p2012_team','manager',20040,'Tack Hugo! Jag har lagt in matcherna också. Säg till om något krockar med skolan.'),
  ('p2012_team','admin',19980,'Snyggt jobbat, ser bra ut i klubbens kalender också.'),
  ('p2012_team','manager',11500,'Påminnelse: svara på kallelsen till lördagens match senast torsdag kväll så vi vet om vi behöver låna spelare.'),
  ('p2012_team','coach',7300,'Bra träning idag! Fint jobb med passningsspelet. På torsdag kör vi avslut och skott.'),
  ('p2012_team','manager',2900,'Samling 09.15 vid klubbstugan på lördag. Vi åker gemensamt, jag har bokat minibussen.'),
  ('p2012_team','coach',300,'Planen är lite blöt efter regnet, vi kör ändå. Ta med extra strumpor!'),

  ('p2012_leaders','coach',18000,'Alva, kan du ta hand om domarbokningen för hemmamatcherna i höst?'),
  ('p2012_leaders','manager',17900,'Absolut, jag mejlar distriktet i morgon.'),
  ('p2012_leaders','coach',9000,'Jag tänker att vi roterar målvakterna mer, alla ska få spela minst en halvlek per match.'),
  ('p2012_leaders','manager',8950,'Låter bra. Ska jag lägga in det som mål i förberedelserna inför matcherna?'),
  ('p2012_leaders','coach',8900,'Ja gärna, "Alla spelade en halvlek" finns i listan.'),
  ('p2012_leaders','manager',1500,'Två har anmält sjukdom till torsdag. Vi är 11 kvar, räcker gott.'),
  ('p2012_leaders','coach',600,'Perfekt. Jag tar med västar och koner, kan du fixa vattnet?'),

  ('f2013_team','admin',16000,'Välkomna till lagchatten för F2013! Här kommer information från ledarna.'),
  ('f2013_team','guardian',15800,'Tack! Vet ni redan nu om laget ska åka på cupen i Jönköping i december?'),
  ('f2013_team','admin',15700,'Ledarna återkommer om det efter föräldramötet, men det ser ut så.'),
  ('f2013_team','guardian',800,'Min dotter har glömt sin vattenflaska i omklädningsrummet, är det någon som har sett en blå?'),

  ('p2015_team','admin',14000,'Hej föräldrar! Nu finns P2015 i appen. Svara gärna på kallelserna här så blir det enklare för ledarna.'),
  ('p2015_team','guardian',13900,'Toppen, mycket smidigare än sms-gruppen!'),
  ('p2015_team','guardian',400,'Vi kommer 10 minuter sent på torsdag, simskolan drar ut på tiden.'),

  ('alag_team','admin',12000,'Laguttagningen till helgens match finns i kalendern. Lycka till grabbar!'),
  ('alag_team','player',11900,'Tack! Är det samling vid klubbstugan eller direkt på plan?'),
  ('alag_team','admin',11850,'Klubbstugan 13.00, vi går över tillsammans.'),
  ('alag_team','player',100,'Har ont i handleden sedan träningen, kollar med sjukgymnasten i morgon och hör av mig.'),

  ('dm_chair_coach','chair',10000,'Hej Hugo! Styrelsen har budget för nytt bollmaterial i höst. Vad behöver P2012?'),
  ('dm_chair_coach','coach',9800,'Hej Benjamin! 15 bollar storlek 4 och ett nytt set koner skulle göra stor skillnad.'),
  ('dm_chair_coach','chair',9700,'Noterat, jag tar det på styrelsemötet nästa vecka.'),
  ('dm_chair_coach','chair',700,'Beställningen är godkänd, materialet levereras till klubbstugan inom två veckor.'),

  ('dm_chair_admin','chair',8000,'Thomas, kan du lägga upp årsmötet som aktivitet för hela klubben?'),
  ('dm_chair_admin','admin',7900,'Klart! Det ligger i kalendern och jag skickar ett anslag till alla.'),
  ('dm_chair_admin','chair',200,'Tack! Glöm inte att verksamhetsberättelsen ska ut två veckor innan.'),

  ('dm_chair_guardian','chair',6100,'Hej Milo! Välkommen som förälder i Demoklubben. Hör av dig om något krånglar i appen.'),
  ('dm_chair_guardian','guardian',6000,'Tack! Jag har två barn i klubben men ser bara det ena i appen. Hur gör jag?'),
  ('dm_chair_guardian','chair',5900,'Jag har bett Thomas koppla dig till båda. Logga ut och in igen så syns båda lagen.'),
  ('dm_chair_guardian','guardian',5850,'Nu syns båda, tack för hjälpen!'),

  ('dm_chair_player','chair',4100,'Hej Hugo! En påminnelse om att medlemsavgiften för hösten ska vara betald 31 oktober.'),
  ('dm_chair_player','player',4000,'Betalade i går! Går det att få kvitto till jobbets friskvårdsbidrag?'),
  ('dm_chair_player','chair',3900,'Absolut, jag mejlar det till dig i kväll.'),
  ('dm_chair_player','player',30,'Kvittot har kommit, tack!'),

  ('dm_coach_manager','coach',3000,'Kan du skicka kallelserna till nästa match? Jag sitter i möten hela dagen.'),
  ('dm_coach_manager','manager',2950,'Klart, de är skickade. Påminnelse går ut automatiskt om några inte svarat.'),
  ('dm_coach_manager','coach',50,'Tack! Vi ses på träningen.'),

  ('group_autumn','chair',9500,'Hej! Vi vill ha en gemensam höstavslutning för alla lag. Förslag på datum?'),
  ('group_autumn','coach',9400,'Lördag 29 november passar P2012, ingen match den helgen.'),
  ('group_autumn','manager',9350,'Jag kan fixa korv och fika om klubben står för det.'),
  ('group_autumn','admin',9300,'Jag bokar klubbstugan och lägger in det i kalendern.'),
  ('group_autumn','chair',1000,'Toppen! Vi kör 29 november kl 14. Jag skickar ut ett anslag när allt är klart.'),

  ('ann_club','chair',4500,'Välkomna till årsmöte i Demoklubben IF torsdag 20 november kl 19.00 i klubbstugan. Handlingar skickas ut två veckor innan. Motioner till styrelsen senast 1 november.'),
  ('ann_p2012','coach',2500,'Från vecka 44 tränar vi tisdagar 17.00–18.30 och torsdagar 17.30–19.00 i Demohallen. Kalendern är uppdaterad.')
 ) as m(thread_key,sender,minutes_ago,body)
 loop
  thread := (threads->>msg.thread_key)::uuid;
  if thread is null then continue; end if;
  actor := (people->>msg.sender)::uuid;
  perform set_config('request.jwt.claim.sub', actor::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub',actor,'role','authenticated')::text, true);
  begin
   result := internal.send_message_for_actor(thread,msg.body,gen_random_uuid());
  exception when insufficient_privilege then
   raise notice 'Skipped message in % from %: %', msg.thread_key, msg.sender, sqlerrm;
   continue;
  end;
  sent_at := now()-make_interval(mins=>msg.minutes_ago);
  update core.messages set created_at=sent_at,expires_at=sent_at+interval '365 days'
  where id=(result->>'message_id')::uuid;
  update audit.message_versions set created_at=sent_at where message_id=(result->>'message_id')::uuid;
  sent_messages := sent_messages || (result->>'message_id')::uuid;
  sent_count := sent_count+1;
 end loop;

 perform set_config('request.jwt.claim.sub', '', true);
 perform set_config('request.jwt.claims', '', true);

 -- Conversations start with their first message.
 update core.message_threads t set created_at=first.created_at
 from (select m.thread_id,min(m.created_at) created_at from core.messages m
  where m.id=any(sent_messages) group by m.thread_id) first
 where t.id=first.thread_id and t.created_at>first.created_at;

 -- Read up to the last day (and everything you sent yourself).
 insert into core.message_reads(thread_id,profile_id,through_revision,read_at)
 select p.thread_id,p.profile_id,max(m.revision),now()
 from core.thread_participants p
 join core.messages m on m.thread_id=p.thread_id and m.id=any(sent_messages)
  and (m.created_at<now()-interval '1 day' or m.sender_profile_id=p.profile_id)
 where p.state='active'
 group by p.thread_id,p.profile_id
 on conflict(thread_id,profile_id) do update set through_revision=excluded.through_revision,read_at=excluded.read_at;

 -- Demo data must not notify anyone.
 update internal.notification_outbox set state='suppressed'
 where event_type='message.message.sent.v1' and aggregate_id=any(sent_messages) and state='pending';

 raise notice 'Created % messages in % conversations', sent_count, (select count(*) from jsonb_object_keys(threads));
end;
$messages$;

-- What each demo login sees.
select u.email, t.thread_type, coalesce(t.subject,'(direkt)') as subject,
 count(m.id) as messages,
 count(m.id) filter (where m.revision>coalesce(r.through_revision,0)) as unread
from core.thread_participants p
join core.message_threads t on t.id=p.thread_id
join core.clubs c on c.id=t.club_id and c.slug='demoklubben-if'
join auth.users u on u.id=p.profile_id
left join core.messages m on m.thread_id=t.id and m.state='sent'
left join core.message_reads r on r.thread_id=t.id and r.profile_id=p.profile_id
where p.state='active'
group by u.email,t.thread_type,t.subject
having count(m.id)>0
order by u.email,t.thread_type,t.subject;
