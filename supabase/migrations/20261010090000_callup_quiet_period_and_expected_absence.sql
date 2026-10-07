-- 1. A freshly sent callup is not "unanswered" in Min assistent for its
--    first 6 hours, unless the event starts within 18 hours (late callups
--    still need attention right away).
-- 2. Absence only counts when the person was expected: they had a callup,
--    or the event used no callups at all. Someone who was never called
--    (away, injured …) is not "frånvarande" in statistics.

do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('internal.get_leader_home_for_actor(uuid)'::regprocedure);
  patched := replace(definition,
    'and(callup.last_reminded_at is null or callup.last_reminded_at<=observed_at-interval ''6 hours'')',
    'and(callup.last_reminded_at is null or callup.last_reminded_at<=observed_at-interval ''6 hours'')
    and(coalesce(callup.sent_at,callup.created_at)<=observed_at-interval ''6 hours''
     or event_row.starts_at<=observed_at+interval ''18 hours'')');
  if patched = definition then raise exception 'pending callups task contract changed'; end if;
  execute patched;
end;
$migration$;

create or replace function internal.attendance_is_expected(target_event_id uuid,target_person_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from core.callups c where c.event_id=target_event_id
   and c.club_person_id=target_person_id and c.state<>'cancelled')
  or not exists(select 1 from core.callups c where c.event_id=target_event_id and c.state<>'cancelled')
$$;
revoke all on function internal.attendance_is_expected(uuid,uuid) from public,anon,authenticated;
grant execute on function internal.attendance_is_expected(uuid,uuid) to authenticated;

-- Profile statistics: an absence without a callup is not a missed event.
do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('internal.get_person_statistics_for_actor(uuid,uuid,uuid)'::regprocedure);
  patched := replace(definition,
    'fact.status<>''unknown''',
    '(fact.status in(''present'',''late'',''partial'')
   or (fact.status=''absent'' and internal.attendance_is_expected(fact.event_id,fact.club_person_id)))');
  if patched = definition then raise exception 'person statistics participation contract changed'; end if;
  execute patched;
end;
$migration$;

-- Main surface statistics: same rule for the absent count.
do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('internal.get_main_surfaces_for_actor(uuid[])'::regprocedure);
  patched := replace(definition,'select fact.status, fact.revision',
    'select fact.status, fact.revision, fact.event_id, fact.club_person_id');
  patched := replace(patched,
    '''absent'', (select count(*) from attendance where status = ''absent'')',
    '''absent'', (select count(*) from attendance where status = ''absent''
        and internal.attendance_is_expected(event_id, club_person_id))');
  if patched = definition or patched not like '%attendance_is_expected%' then
    raise exception 'main surface statistics contract changed'; end if;
  execute patched;
end;
$migration$;

-- Follow-up summary: absences of people who were not called are not counted.
create or replace function internal.event_attendance_summary(target_event_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 with called as(
  select c.club_person_id,c.state from core.callups c where c.event_id=target_event_id and c.state<>'cancelled'
 ),facts as(
  select a.club_person_id,a.status,a.minutes from core.attendance_facts a where a.event_id=target_event_id
   and (a.status<>'absent' or not exists(select 1 from called)
    or exists(select 1 from called c where c.club_person_id=a.club_person_id))
 ),counts as(
  select
   (select count(*) from called) called,
   (select count(*) from called where state='accepted') accepted,
   (select count(*) from called where state='declined') declined,
   (select count(*) from called where state='pending') pending,
   (select count(*) from facts where status='present') present,
   (select count(*) from facts where status='late') late,
   (select count(*) from facts where status='partial') partial,
   (select count(*) from facts where status='absent') absent,
   (select count(*) from facts where status<>'unknown') registered,
   (select round(avg(minutes)) from facts where status='late') late_minutes,
   (select count(*) from called c where not exists(select 1 from facts f where f.club_person_id=c.club_person_id and f.status<>'unknown')) unregistered
 )
 select jsonb_build_object('called',called,'accepted',accepted,'declined',declined,'pending',pending,
  'present',present,'late',late,'partial',partial,'absent',absent,'registered',registered,
  'unregistered',unregistered,'late_minutes_avg',late_minutes,
  'attendance_rate',case
   when registered=0 then null
   when called>0 then round(100.0*(present+late+partial)/called,1)
   else round(100.0*(present+late+partial)/registered,1) end,
  'response_rate',case when called=0 then null else round(100.0*(accepted+declined)/called,1) end)
 from counts
$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261010090000_callup_quiet_period_and_expected_absence','greenfield',
  'Unanswered callups wait 6 h (unless the event is within 18 h); absence counts only when expected');
notify pgrst,'reload schema';
