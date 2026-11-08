"""Activity-plan races in the disposable database initialized by booking_concurrency.py."""
import json,os,subprocess
URL=os.environ.get('BOOKING_TEST_DB_URL','')
if not URL.endswith('/booking_safety_test'):raise SystemExit('Disposable booking_safety_test only')
ARGS=[os.environ.get('PSQL','psql'),URL,'-X','-A','-t','-q','-v','ON_ERROR_STOP=1']
def sql(s,ok=True):
 p=subprocess.run(ARGS,input=s,encoding='utf-8',capture_output=True,timeout=30)
 if ok and p.returncode:raise AssertionError(p.stderr)
 return p
OWNER='00000000-0000-4000-8000-000000000001';COACH='00000000-0000-4000-8000-000000000003';CLUB='00000000-0000-4000-8000-000000000010';TEAM='00000000-0000-4000-8000-000000000020'
def actor(who,s):return f"set request.jwt.claim.sub='{who}';set role authenticated;{s}"
def race(first,second,error=None):
 p=subprocess.Popen(ARGS,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,encoding='utf-8');p.stdin.write('begin;\n'+first+'\n\\echo HELD\nselect pg_sleep(1);commit;\n');p.stdin.close()
 while True:
  line=p.stdout.readline()
  if line.strip()=='HELD':break
  if not line:raise AssertionError(p.stderr.read())
 r=sql(second,ok=error is None)
 if error:assert r.returncode!=0 and error in r.stderr,r.stderr
 p.wait(timeout=15);assert p.returncode==0,p.stderr.read();p.stdout.close();p.stderr.close()
def call(s,who=COACH):
 value=sql(actor(who,s)).stdout.strip()
 try:return json.loads(value)
 except json.JSONDecodeError:return value
def key():return sql('select gen_random_uuid();').stdout.strip()
org=sql(f"select id from core.booking_organizations where name='Concurrency' and teamzone_club_id='{CLUB}';").stdout.strip()
assert len(org)==36,'Requires the disposable Concurrency fixture organization'
sql(f"insert into core.booking_members(organization_id,profile_id,role) values('{org}','{COACH}','booker') on conflict do nothing;")
def resource(name):return call(f"select api.save_booking_resource_v2('{org}',null,'{{\"name\":\"{name}\",\"category\":\"equipment\",\"ownership_kind\":\"owned\",\"timezone\":\"UTC\"}}'::jsonb,null);",OWNER)
source=resource('Future event race source');camera=resource('Future event race camera');locker=resource('Future event race locker')
sql(f"create or replace function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql stable as $$select auth.uid()='{COACH}'::uuid and cap='event.manage'$$;")
# Reduced event API stub; full event history/outbox is verified against audit.
sql("""create or replace function internal.create_booking_plan_event(p internal.booking_series_plans,slot internal.booking_series_slots,ns timestamptz,ne timestamptz) returns uuid language plpgsql security definer set search_path='' as $$declare eid uuid:=gen_random_uuid();e core.events;n int;begin e:=jsonb_populate_record(null::core.events,p.event_template->'event');select coalesce(max(occurrence_number),0)+1 into n from core.events where recurrence_id=p.recurrence_id;insert into core.events(id,club_id,owning_team_id,title,event_type,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values(eid,e.club_id,e.owning_team_id,e.title,e.event_type,'scheduled',ns,ne,p.recurrence_id,n,p.configuration->>'timezone');insert into core.event_teams(event_id,club_id,team_id,relation,capabilities) values(eid,e.club_id,e.owning_team_id,'primary','{view,co_manage}');return eid;end;$$;""")
rid=key();base="date_trunc('day',now()+interval '45 days')+interval '10 hours'"
sql(f"insert into core.recurrence_rules(id,club_id,timezone,frequency,interval_value,local_start,occurrence_count) values('{rid}','{CLUB}','UTC','weekly',1,({base})::timestamp,3);")
events=[];anchor=None
for i in range(3):
 eid=key();events.append(eid)
 sql(f"insert into core.events(id,club_id,owning_team_id,title,event_type,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values('{eid}','{CLUB}','{TEAM}','Future activity race','training','scheduled',{base}+interval '{i*7} days',{base}+interval '{i*7} days 1 hour','{rid}',{i+1},'UTC');insert into core.event_teams(event_id,club_id,team_id) values('{eid}','{CLUB}','{TEAM}');insert into core.event_audiences(club_id,event_id,audience_type,team_id,created_by) values('{CLUB}','{eid}','players','{TEAM}','{COACH}');")
 b=call(f"select api.create_booking('{source}',{base}+interval '{i*7} days'-interval '30 minutes',{base}+interval '{i*7} days 1 hour 15 minutes',null,null,'{TEAM}','{eid}');")
 call(f"select api.create_booking('{camera}',{base}+interval '{i*7} days'-interval '1 hour',{base}+interval '{i*7} days 3 hours',null,null,'{TEAM}','{eid}');")
 if i==0:anchor=b['id']
d=call(f"select api.get_booking_series_plan('{anchor}');");cfg=dict(d['defaults'],first_day=sql(f"select ({base}+interval '21 days')::date;").stdout.strip(),ends_on=sql(f"select ({base}+interval '91 days')::date;").stdout.strip(),resource_ids=[source,camera],automatic=True)
def preview_cfg():return call(f"select api.preview_booking_series_plan('{anchor}','{json.dumps(cfg)}'::jsonb);")
p=preview_cfg();payload={'target_booking_id':anchor,'configuration':cfg,'expected_plan':p}
plan=call(f"select api.execute_booking_command('{key()}','save_booking_series_plan','{json.dumps(payload)}'::jsonb,null);")['plan_id']
def combined_preview():
 bounds=json.loads(sql(f"select json_build_object('s',starts_at+interval '1 hour','e',ends_at+interval '1 hour') from core.events where id='{events[0]}';").stdout.strip())
 return call(f"select api.preview_booking_change('{anchor}','event_all','{bounds['s']}','{bounds['e']}',array['{locker}'::uuid],array['{source}'::uuid]);")
def combined_save(p):
 payload={k:p[k] for k in ['target_booking_id','new_starts_at','new_ends_at','add_resource_ids','remove_resource_ids']};payload.update(change_scope=p['scope'],expected_plan=p)
 return actor(COACH,f"select api.execute_booking_command('{key()}','update_booking','{json.dumps(payload)}'::jsonb,null);")
def generator(days):return f"set request.jwt.claim.sub='{COACH}';select internal.generate_booking_series_plan_for_actor('{plan}',(now()+interval '{days} days')::date);"
p=combined_preview();assert not p['conflicts'];race(generator(30),combined_save(p),'stale_revision')
p=combined_preview();assert not p['conflicts'];race(combined_save(p),generator(50))
assert sql(f"select bool_and(b.starts_at=e.starts_at-interval '30 minutes' and b.ends_at=e.ends_at+interval '15 minutes') from core.booking_bookings b join core.events e on e.id=b.event_id where e.recurrence_id='{rid}' and b.resource_id='{locker}' and b.status='confirmed';").stdout.strip()=='t'
assert sql(f"select bool_and(b.starts_at=e.starts_at-interval '1 hour' and b.ends_at=e.ends_at+interval '2 hours') from core.booking_bookings b join core.events e on e.id=b.event_id where e.recurrence_id='{rid}' and b.resource_id='{camera}' and b.status='confirmed';").stdout.strip()=='t'
before=sql(f"select count(*) from core.events where recurrence_id='{rid}';").stdout.strip();race(generator(60),generator(60));assert sql(f"select count(*) from core.events where recurrence_id='{rid}';").stdout.strip()==before
eid=sql(f"select event_id from internal.booking_series_slots where plan_id='{plan}' and state='created' order by position limit 1;").stdout.strip()
race(f"set request.jwt.claim.sub='{COACH}';update core.events set state='cancelled',revision=revision+1 where id='{eid}';",generator(60))
assert sql(f"select state='cancelled' from core.events where id='{eid}';").stdout.strip()=='t'
assert sql(f"select count(*)=0 from core.booking_bookings where event_id='{eid}' and status in('pending','confirmed');").stdout.strip()=='t'
print('activity future-plan concurrency: generation versus combined time/resource change in both orders, duplicate generators, stable recurrence identity, independent margins and cancellation preservation passed')
