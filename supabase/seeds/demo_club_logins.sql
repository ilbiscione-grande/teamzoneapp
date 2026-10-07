-- Demo logins for Demoklubben IF: links existing TeamZone accounts to
-- people in the demo club so you can sign in as a coach, a team manager, a
-- guardian, a board member and a player.
--
-- 1. Run demo_club.sql first.
-- 2. Create the accounts yourself (sign up in the app, or Supabase dashboard
--    → Authentication → Add user, with "Auto confirm"). Gmail delivers
--    tre60grader+<roll>@gmail.com to tre60grader@gmail.com.
-- 3. Run this script in the SQL editor. It can be run again at any time:
--    missing accounts are skipped, linked accounts are left as they are.
--
-- No passwords are stored or set here. Everything runs in one DO block,
-- which is atomic on its own; no temporary objects are needed.


do $logins$
declare
 club uuid := (select id from core.clubs where slug='demoklubben-if');
 login record;
 account uuid;
 target uuid;
 functionary uuid;
begin
 if club is null then raise exception 'Run demo_club.sql first: Demoklubben IF does not exist'; end if;

 for login in select * from (values
  ('tre60grader+tranare@gmail.com','Huvudtränare i P2012'),
  ('tre60grader+lagledare@gmail.com','Lagledare i P2012'),
  ('tre60grader+vardnadshavare@gmail.com','Vårdnadshavare med barn i F2013 och P2015'),
  ('tre60grader+styrelse@gmail.com','Ordförande i styrelsen'),
  ('tre60grader+spelare@gmail.com','Målvakt i A-lag Herr')
 ) as l(email,role)
 loop
  select u.id into account from auth.users u
  where lower(u.email)=lower(login.email) and u.email_confirmed_at is not null;
  if account is null or not exists(select 1 from core.profiles where id=account) then
   raise notice 'Skipped %: no confirmed account yet', login.email;
   continue;
  end if;

  target := case login.role
   when 'Huvudtränare i P2012' then (
    select d.club_person_id from core.team_person_details d join core.teams t on t.id=d.team_id
    where t.club_id=club and t.name='P2012' and d.main_title='head_coach' limit 1)
   when 'Lagledare i P2012' then (
    select d.club_person_id from core.team_person_details d join core.teams t on t.id=d.team_id
    where t.club_id=club and t.name='P2012' and d.main_title='team_manager' limit 1)
   when 'Vårdnadshavare med barn i F2013 och P2015' then (
    select g.guardian_person_id from core.guardian_relations g
    join core.team_assignments ta on ta.club_person_id=g.child_person_id and ta.state='active'
    join core.teams t on t.id=ta.team_id
    where g.club_id=club and g.state='active'
    group by g.guardian_person_id
    having count(distinct t.name) filter (where t.name in('F2013','P2015'))=2 limit 1)
   when 'Ordförande i styrelsen' then (
    select a.club_person_id from core.board_mandates m join core.assignments a on a.id=m.assignment_id
    where m.club_id=club and m.office='chair' and m.state='active' limit 1)
   when 'Målvakt i A-lag Herr' then (
    select d.club_person_id from core.team_person_details d join core.teams t on t.id=d.team_id
    where t.club_id=club and t.name='A-lag Herr' and d.main_position='goalkeeper'
    order by d.club_person_id limit 1)
  end;
  if target is null then raise exception 'Demo person for % not found', login.role; end if;

  if exists(select 1 from core.person_account_links where club_person_id=target and state='active') then
   raise notice 'Already linked: % (%)', login.email, login.role;
   continue;
  end if;
  if exists(select 1 from core.person_account_links where profile_id=account and club_id=club and state='active') then
   raise notice 'Skipped %: the account is already linked to another person in the demo club', login.email;
   continue;
  end if;

  insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at,created_by)
  values(club,target,account,'active',now(),account);

  -- The chair reads and manages the board and reads the club's economy.
  if login.role='Ordförande i styrelsen' then
   select a.id into functionary from core.assignments a
   where a.club_person_id=target and a.role_package='club_functionary' and a.state='active' limit 1;
   insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by)
   select club,functionary,capability,'club',club,now()-interval '1 minute',account
   from unnest(array['board.read','board.manage','economy.read']) capability
   on conflict do nothing;
  end if;

  raise notice 'Linked % → %', login.email, login.role;
 end loop;
end;
$logins$;

-- Which demo logins are linked.
select u.email, p.display_name as person,
 string_agg(distinct coalesce(t.name,'klubb')||': '||a.role_package, ', ') as roles
from core.person_account_links l
join core.clubs c on c.id=l.club_id and c.slug='demoklubben-if'
join auth.users u on u.id=l.profile_id
join core.club_people p on p.id=l.club_person_id
left join core.assignments a on a.club_person_id=l.club_person_id and a.state='active'
left join core.teams t on t.id=a.team_id
where l.state='active'
group by u.email,p.display_name order by u.email;

