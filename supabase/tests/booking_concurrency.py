"""Multi-connection regression test. Requires an EMPTY, disposable database.

BOOKING_TEST_DB_URL must point at a database named booking_safety_test.
Uses psql, Node and the same reduced schema as booking_manager.local.mjs.
Never connects to the linked Supabase project or resets an existing schema.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
URL = os.environ.get('BOOKING_TEST_DB_URL', '')
if not URL.endswith('/booking_safety_test'):
    raise SystemExit('Set BOOKING_TEST_DB_URL to a disposable booking_safety_test database')
PSQL = os.environ.get('PSQL', 'psql')
os.environ['PGCLIENTENCODING'] = 'UTF8'
ARGS = [PSQL, URL, '-X', '-A', '-t', '-q', '-v', 'ON_ERROR_STOP=1']

def sql(text, ok=True):
    p = subprocess.run(ARGS, input=text, encoding='utf-8', capture_output=True, timeout=30)
    if ok and p.returncode:
        raise AssertionError(p.stderr)
    return p

assert sql("select to_regnamespace('core') is null;").stdout.strip() == 't', 'Database must be empty'
with tempfile.TemporaryDirectory() as tmp:
    fixture = Path(tmp)/'booking.sql'
    env = dict(os.environ, BOOKING_FIXTURE_PATH=str(fixture))
    subprocess.run(['node', 'supabase/tests/booking_manager.local.mjs'], cwd=ROOT, env=env, check=True, timeout=60)
    sql('begin;\n'+fixture.read_text(encoding='utf-8')+'\ncommit;')

OWNER = '00000000-0000-4000-8000-000000000001'
FRIEND = '00000000-0000-4000-8000-000000000002'
def actor(who, statement):
    return f"set request.jwt.claim.sub = '{who}'; set role authenticated; {statement}"

org = sql(actor(OWNER, "select api.create_booking_organization('Concurrency','club',null);")).stdout.strip()
pitch = sql(actor(OWNER, f"select api.save_booking_resource('{org}',null,'Pitch','pitch',null,null,null,true,true);")).stdout.strip()
bus = sql(actor(OWNER, f"select api.save_booking_resource('{org}',null,'Bus','vehicle',null,null,null,true,true);")).stdout.strip()
sql(f"insert into core.booking_members(organization_id,profile_id,role) values('{org}','{FRIEND}','booker');")

def race(first, second, expected_error=None):
    # First writer holds its transaction open. The second writer must wait
    # rather than observing an intermediate status or slipping past a check.
    p = subprocess.Popen(ARGS, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8')
    p.stdin.write('begin;\n'+first+'\n\\echo HELD\nselect pg_sleep(1);\ncommit;\n')
    p.stdin.close()
    while True:
        line = p.stdout.readline()
        if line.strip() == 'HELD':
            break
        if not line:
            raise AssertionError(p.stderr.read())
    result = sql(second, ok=expected_error is None)
    if expected_error:
        assert result.returncode != 0 and expected_error in result.stderr, result.stderr
    p.wait(timeout=15)
    assert p.returncode == 0, p.stderr.read()
    p.stdout.close()
    p.stderr.close()
    return result.stdout.strip()

def create(resource, day):
    return f"select api.create_booking('{resource}',now()+interval '{day} days',now()+interval '{day} days 1 hour',null,null,null,null);"

race(actor(FRIEND, create(pitch,10)), actor(FRIEND, create(pitch,10)), 'resource_busy')
b = json.loads(sql(actor(FRIEND, create(bus,11))).stdout.strip())
race(actor(FRIEND,f"select api.cancel_booking('{b['id']}');"), actor(OWNER,f"select api.decide_booking('{b['id']}',true);"), 'not_pending')
assert sql(f"select status from core.booking_bookings where id='{b['id']}';").stdout.strip() == 'cancelled'
sql(actor(FRIEND,create(bus,11)))

payload = json.dumps({'target_resource_id':bus,'booking_starts_at':'2035-01-01T10:00:00Z','booking_ends_at':'2035-01-01T11:00:00Z'})
key = '00000000-0000-4000-8000-000000000300'
cmd = f"select api.execute_booking_command('{key}','create_booking','{payload}'::jsonb,null);"
race(actor(FRIEND,cmd), actor(FRIEND,cmd))
assert sql(f"select count(*) from core.booking_bookings where resource_id='{bus}' and starts_at='2035-01-01T10:00:00Z';").stdout.strip() == '1'
assert sql(f"select count(*) from internal.booking_commands where command_id='{key}';").stdout.strip() == '1'

# Separate decisions based on the same snapshot cannot both be accepted.
snapshot = json.loads(sql(actor(FRIEND,create(bus,15))).stdout.strip())
revisions = json.dumps({snapshot['id']:1})
def decision(key, approve):
    payload = json.dumps({'target_booking_id':snapshot['id'],'approve':approve})
    return f"select api.execute_booking_command('{key}','decide_booking','{payload}'::jsonb,'{revisions}'::jsonb);"
race(actor(OWNER,decision('00000000-0000-4000-8000-000000000301',True)),
     actor(OWNER,decision('00000000-0000-4000-8000-000000000302',False)),'stale_revision')
assert sql(f"select revision from core.booking_bookings where id='{snapshot['id']}';").stdout.strip() == '2'

def group(resources):
    ids = ','.join(f"'{r}'" for r in resources)
    return f"select api.create_booking_group(array[{ids}]::uuid[],now()+interval '20 days',now()+interval '20 days 1 hour',null,null,null,null,false);"
race(actor(FRIEND,group([pitch,bus])),actor(FRIEND,group([bus,pitch])),'resource_busy')
group_id = sql(f"select group_id from core.booking_bookings where group_id is not null limit 1;").stdout.strip()
member = sql(f"select id from core.booking_bookings where group_id='{group_id}' limit 1;").stdout.strip()
race(actor(FRIEND,f"select api.cancel_booking_group('{group_id}');"),actor(OWNER,f"select api.decide_booking('{member}',true);"),'not_pending')
assert sql(f"select count(*) from core.booking_bookings where group_id='{group_id}' and status='cancelled';").stdout.strip() == '2'
print('booking concurrency: conflicting creates, cancellation/approval, duplicate commands and overlapping groups passed')

rights = json.loads(sql("select jsonb_build_object('name','External hall','category','hall','ownership_kind','external','owner_name','Council','timezone','UTC','available_from',(now()+interval '25 days')::date,'available_until',(now()+interval '26 days')::date);").stdout.strip())
external = sql(actor(OWNER,f"select api.save_booking_resource_v2('{org}',null,'{json.dumps(rights)}'::jsonb,null);")).stdout.strip()
new_rights = dict(rights, available_from=rights['available_until'])
def save_rights():
    return f"select api.save_booking_resource_v2('{org}','{external}','{json.dumps(new_rights)}'::jsonb,1);"
def create_external():
    return f"select api.create_booking('{external}','{rights['available_from']} 10:00Z','{rights['available_from']} 11:00Z',null,null,null,null);"
race(actor(FRIEND,create_external()), actor(OWNER,save_rights()), 'disposition_has_bookings')
external_booking = sql(f"select id from core.booking_bookings where resource_id='{external}' limit 1;").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{external_booking}');"))
race(actor(OWNER,save_rights()), actor(FRIEND,create_external()), 'resource_outside_disposition')
print('resource disposition concurrency: booking versus shortened right, both serialization orders passed')

# Weekly-hours changes use the same resource lock in both serialization orders.
weekly = dict(rights, name='Weekly hall', ownership_kind='owned', available_from=None, available_until=None,
              availability={'mode':'always','weekly':[],'exceptions':[]})
hours = sql(actor(OWNER,f"select api.save_booking_resource_v2('{org}',null,'{json.dumps(weekly)}'::jsonb,null);")).stdout.strip()
closed = dict(weekly, availability={'mode':'weekly','weekly':[],'exceptions':[]})
save_closed = f"select api.save_booking_resource_v2('{org}','{hours}','{json.dumps(closed)}'::jsonb,1);"
create_hours = create(hours,30)
race(actor(FRIEND,create_hours),actor(OWNER,save_closed),'disposition_has_bookings')
active = sql(f"select id from core.booking_bookings where resource_id='{hours}' limit 1;").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{active}');"))
race(actor(OWNER,save_closed),actor(FRIEND,create_hours),'resource_outside_disposition')
print('resource weekly-hours concurrency: booking versus closing hours, both serialization orders passed')

hierarchy_details = {'name':'Whole','category':'pitch','ownership_kind':'owned','timezone':'UTC','requires_approval':True}
def save_hierarchy(resource=None, parent=None, name='Whole', revision=None, extra=None):
    details = dict(hierarchy_details, name=name, parent_resource_id=parent, **(extra or {}))
    return f"select api.save_booking_resource_v2('{org}',{repr(resource) if resource else 'null'},'{json.dumps(details)}'::jsonb,{revision if revision else 'null'});"
whole = sql(actor(OWNER,save_hierarchy())).stdout.strip()
half_a = sql(actor(OWNER,save_hierarchy(parent=whole,name='Half A'))).stdout.strip()
half_b = sql(actor(OWNER,save_hierarchy(parent=whole,name='Half B'))).stdout.strip()
quarter = sql(actor(OWNER,save_hierarchy(parent=half_a,name='Quarter A1'))).stdout.strip()
race(actor(FRIEND,create(whole,90)),actor(FRIEND,create(quarter,90)),'resource_busy')
race(actor(FRIEND,create(quarter,91)),actor(FRIEND,create(whole,91)),'resource_busy')
race(actor(FRIEND,create(quarter,92)),actor(FRIEND,create(half_b,92)))
independent = sql(actor(OWNER,save_hierarchy(name='Independent'))).stdout.strip()
sql(actor(FRIEND,create(independent,100)))
race(actor(FRIEND,create(whole,100)),actor(OWNER,save_hierarchy(independent,whole,revision=1)),'hierarchy_has_bookings')
parent_booking = sql(f"select id from core.booking_bookings where resource_id='{whole}' and starts_at>now()+interval '99 days' limit 1;").stdout.strip()
sql(actor(FRIEND,f"select api.cancel_booking('{parent_booking}');"))
race(actor(OWNER,save_hierarchy(independent,whole,revision=1)),actor(FRIEND,create(whole,100)),'resource_busy')
cycle_a=sql(actor(OWNER,save_hierarchy(name='Cycle A'))).stdout.strip()
cycle_b=sql(actor(OWNER,save_hierarchy(name='Cycle B'))).stdout.strip()
race(actor(OWNER,save_hierarchy(cycle_a,cycle_b,revision=1)),actor(OWNER,save_hierarchy(cycle_b,cycle_a,revision=1)),'invalid_resource_hierarchy')
hours_parent=sql(actor(OWNER,save_hierarchy(name='Hours parent'))).stdout.strip()
hours_child=sql(actor(OWNER,save_hierarchy(parent=hours_parent,name='Hours child'))).stdout.strip()
close_parent=save_hierarchy(hours_parent,revision=1,extra={'availability':{'mode':'weekly','weekly':[],'exceptions':[]}})
race(actor(FRIEND,create(hours_child,110)),actor(OWNER,close_parent),'disposition_has_bookings')
child_booking=sql(f"select id from core.booking_bookings where resource_id='{hours_child}' limit 1;").stdout.strip()
sql(actor(FRIEND,f"select api.cancel_booking('{child_booking}');"))
race(actor(OWNER,close_parent),actor(FRIEND,create(hours_child,110)),'resource_outside_disposition')
print('resource hierarchy concurrency: whole/quarter both orders, independent branches, reparenting, cycles and inherited hours passed')

COACH='00000000-0000-4000-8000-000000000003'
EVENT='00000000-0000-4000-8000-000000000030'
TEAM='00000000-0000-4000-8000-000000000020'
CLUB='00000000-0000-4000-8000-000000000010'
sql(f"update core.booking_organizations set teamzone_club_id='{CLUB}' where id='{org}';")
event_bounds=json.loads(sql("select jsonb_build_object('start',date_trunc('day',now()+interval '130 days')+interval '10 hours','end',date_trunc('day',now()+interval '130 days')+interval '11 hours');").stdout.strip())
def event_change(statement):
    return f"set request.jwt.claim.sub='{COACH}'; {statement}"
def reset_event():
    sql(event_change(f"update core.events set state='scheduled',starts_at='{event_bounds['start']}',ends_at='{event_bounds['end']}' where id='{EVENT}';"))
reset_event()
event_resource=sql(actor(OWNER,save_hierarchy(name='Activity quarter'))).stdout.strip()
def linked_booking(resource=event_resource):
    return f"select api.create_booking('{resource}','{event_bounds['start']}','{event_bounds['end']}',null,null,'{TEAM}','{EVENT}');"
cancel_event=event_change(f"update core.events set state='cancelled' where id='{EVENT}';")
race(actor(COACH,linked_booking()),cancel_event)
assert sql(f"select bool_and(status='cancelled') from core.booking_bookings where event_id='{EVENT}';").stdout.strip()=='t'
reset_event()
race(cancel_event,actor(COACH,linked_booking()),'event_not_found')
reset_event()
linked=json.loads(sql(actor(COACH,linked_booking())).stdout.strip())
move_event=event_change(f"update core.events set starts_at=starts_at+interval '2 hours',ends_at=ends_at+interval '2 hours' where id='{EVENT}';")
block_future=f"select api.create_booking('{event_resource}','{event_bounds['start']}'::timestamptz+interval '2 hours','{event_bounds['end']}'::timestamptz+interval '2 hours',null,null,null,null);"
race(actor(FRIEND,block_future),move_event,'event_booking_conflict')
block_id=sql(f"select id from core.booking_bookings where resource_id='{event_resource}' and event_id is null and status in ('pending','confirmed') limit 1;").stdout.strip()
sql(actor(FRIEND,f"select api.cancel_booking('{block_id}');"))
race(move_event,actor(FRIEND,block_future),'resource_busy')
reset_event() # also moves the linked reservation back
# A newly attached booking either participates in the move or detects its stale
# activity time; it cannot sneak in using an obsolete activity snapshot.
sql(actor(COACH,f"select api.cancel_booking('{linked['id']}');"))
anchor_payload={'target_resource_id':event_resource,'booking_starts_at':event_bounds['start'],'booking_ends_at':event_bounds['end'],
                'target_team_id':TEAM,'target_event_id':EVENT,'expected_event_starts_at':event_bounds['start'],'expected_event_ends_at':event_bounds['end']}
def anchor_command(key):
    return f"select api.execute_booking_command('{key}','create_booking','{json.dumps(anchor_payload)}'::jsonb,null);"
race(actor(COACH,anchor_command('00000000-0000-4000-8000-000000000800')),move_event)
active_id=sql(f"select id from core.booking_bookings where event_id='{EVENT}' and status in ('pending','confirmed') limit 1;").stdout.strip()
assert sql(f"select starts_at='{event_bounds['start']}'::timestamptz+interval '2 hours' from core.booking_bookings where id='{active_id}';").stdout.strip()=='t'
sql(actor(COACH,f"select api.cancel_booking('{active_id}');"))
reset_event()
race(move_event,actor(COACH,anchor_command('00000000-0000-4000-8000-000000000801')),'event_changed')
print('activity sync concurrency: cancellation/attachment, move/resource conflict and stale-activity anchors in both orders passed')

# Booking-side time changes must serialize with competing reservations and
# cancellation, and reject a preview based on an obsolete event revision.
reverse_resource=sql(actor(OWNER,save_hierarchy(name='Reverse race'))).stdout.strip()
reverse_start="date_trunc('day',now()+interval '300 days')+interval '10 hours'"
reverse_booking=json.loads(sql(actor(FRIEND,f"select api.create_booking('{reverse_resource}',{reverse_start},{reverse_start}+interval '1 hour',null,null,null,null);")).stdout.strip())
def reverse_plan(booking_id,scope='booking',offset=2):
    return json.loads(sql(actor(FRIEND,f"select api.preview_booking_time('{booking_id}','{scope}',{reverse_start}+interval '{offset} hours',{reverse_start}+interval '{offset+1} hours');")).stdout.strip())
def reverse_command(plan,key):
    payload={'target_booking_id':plan['target_booking_id'],'change_scope':plan['scope'],'new_starts_at':plan['starts_at'],'new_ends_at':plan['ends_at'],'expected_plan':plan}
    return f"select api.execute_booking_command('{key}','reschedule_booking','{json.dumps(payload)}'::jsonb,null);"
preview=reverse_plan(reverse_booking['id'])
cmd=reverse_command(preview,'00000000-0000-4000-8000-000000000850')
block_reverse=f"select api.create_booking('{reverse_resource}',{reverse_start}+interval '2 hours',{reverse_start}+interval '3 hours',null,null,null,null);"
race(actor(FRIEND,cmd),actor(OWNER,block_reverse),'resource_busy')
# Make a fresh intent, then race its two writers.
fresh=reverse_plan(reverse_booking['id'],offset=4)
race(actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000853')),
     actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000854')),'stale_revision')
assert sql(f"select revision from core.booking_bookings where id='{reverse_booking['id']}';").stdout.strip()=='3'
# Competing booking first: the previously previewed move must fail atomically.
fresh=reverse_plan(reverse_booking['id'],offset=2)
race(actor(OWNER,block_reverse),actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000855')),'resource_busy')
# Time update and cancellation use organisation gates before booking rows.
fresh=reverse_plan(reverse_booking['id'],offset=6)
race(actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000856')),
     actor(FRIEND,f"select api.cancel_booking('{reverse_booking['id']}');"))
assert sql(f"select status from core.booking_bookings where id='{reverse_booking['id']}';").stdout.strip()=='cancelled'
another=json.loads(sql(actor(FRIEND,f"select api.create_booking('{reverse_resource}',{reverse_start},{reverse_start}+interval '1 hour',null,null,null,null);")).stdout.strip())
fresh=reverse_plan(another['id'],offset=8)
race(actor(FRIEND,f"select api.cancel_booking('{another['id']}');"),
     actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000857')),'not_allowed')
reset_event()
linked=json.loads(sql(actor(COACH,linked_booking())).stdout.strip())
linked_plan=json.loads(sql(actor(COACH,f"select api.preview_booking_time('{linked['id']}','booking','{event_bounds['start']}'::timestamptz+interval '2 hours','{event_bounds['end']}'::timestamptz+interval '2 hours');")).stdout.strip())
race(move_event,actor(COACH,reverse_command(linked_plan,'00000000-0000-4000-8000-000000000858')),'stale_revision')
reset_event()
linked_plan=json.loads(sql(actor(COACH,f"select api.preview_booking_time('{linked['id']}','booking','{event_bounds['start']}'::timestamptz+interval '2 hours','{event_bounds['end']}'::timestamptz+interval '2 hours');")).stdout.strip())
race(actor(COACH,reverse_command(linked_plan,'00000000-0000-4000-8000-000000000859')),move_event)
assert sql(f"select starts_at='{event_bounds['start']}'::timestamptz+interval '4 hours' from core.booking_bookings where id='{linked['id']}';").stdout.strip()=='t'
print('reverse sync concurrency: reservation conflicts, competing previews, cancellation and activity moves in both orders passed')

# A forward time command holds every affected organisation before moving the
# first occurrence. A conflict in the middle must never leave a moved prefix.
forward_resource=sql(actor(OWNER,save_hierarchy(name='Forward series race',extra={'requires_approval':False}))).stdout.strip()
forward_base="date_trunc('week',now()+interval '350 days')+interval '6 days 10 hours'"
created=json.loads(sql(actor(FRIEND,f"select api.create_booking_series('{forward_resource}','{{7}}'::smallint[],1::smallint,({forward_base})::date,({forward_base}+interval '14 days')::date,'10:00','11:00','UTC',null,null,null,false);")).stdout.strip())
series_id=created['series_id']
anchor_id=sql(f"select id from core.booking_bookings where series_id='{series_id}' order by series_sequence limit 1;").stdout.strip()
def forward_plan(hour):
    return json.loads(sql(actor(FRIEND,f"select api.preview_booking_time('{anchor_id}','series_forward',{forward_base}+interval '{hour} hours',{forward_base}+interval '{hour+1} hours');")).stdout.strip())
plan=forward_plan(1)
middle_block=f"select api.create_booking('{forward_resource}',{forward_base}+interval '7 days 1 hour',{forward_base}+interval '7 days 2 hours',null,null,null,null);"
race(actor(OWNER,middle_block),actor(FRIEND,reverse_command(plan,'00000000-0000-4000-8000-000000000900')),'forward_conflicts')
assert sql(f"select bool_and(revision=1) from core.booking_bookings where series_id='{series_id}';").stdout.strip()=='t'
block_id=sql(f"select id from core.booking_bookings where resource_id='{forward_resource}' and series_id is null and status='confirmed' limit 1;").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{block_id}');"))
race(actor(FRIEND,reverse_command(plan,'00000000-0000-4000-8000-000000000901')),actor(OWNER,middle_block),'resource_busy')
fresh=forward_plan(2)
race(actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000902')),
     actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000903')),'stale_revision')
middle_id=sql(f"select id from core.booking_bookings where series_id='{series_id}' and series_sequence=2;").stdout.strip()
fresh=forward_plan(3)
race(actor(OWNER,f"select api.cancel_booking('{middle_id}');"),actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000904')),'stale_revision')
fresh=forward_plan(3)
race(actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000905')),actor(OWNER,f"select api.cancel_booking_series('{series_id}');"))
assert sql(f"select bool_and(status='cancelled') from core.booking_bookings where series_id='{series_id}';").stdout.strip()=='t'

# Event recurrence edits serialize with a concurrent change to a middle event.
event_resource2=sql(actor(OWNER,save_hierarchy(name='Forward event race',extra={'requires_approval':False}))).stdout.strip()
recurrence=sql('select gen_random_uuid();').stdout.strip()
event_base="date_trunc('day',now()+interval '420 days')+interval '10 hours'"
event_ids=[]
for n in range(3):
    event_id=sql(f"insert into core.events(id,club_id,title,state,starts_at,ends_at,recurrence_id,occurrence_number,timezone) values(gen_random_uuid(),'{CLUB}','Forward race','scheduled',{event_base}+interval '{7*n} days',{event_base}+interval '{7*n} days 1 hour','{recurrence}',{n+1},'UTC') returning id;").stdout.strip()
    sql(f"insert into core.event_teams values('{event_id}','{CLUB}','{TEAM}');")
    sql(actor(COACH,f"select api.create_booking('{event_resource2}',{event_base}+interval '{7*n} days',{event_base}+interval '{7*n} days 1 hour',null,null,'{TEAM}','{event_id}');"))
    event_ids.append(event_id)
event_anchor=sql(f"select id from core.booking_bookings where event_id='{event_ids[0]}';").stdout.strip()
def event_forward_plan():
    return json.loads(sql(actor(COACH,f"select api.preview_booking_time('{event_anchor}','event_forward',{event_base}+interval '1 hour',{event_base}+interval '2 hours');")).stdout.strip())
def middle_edit(hours):
    return event_change(f"update core.events set starts_at=starts_at+interval '{hours} hours',ends_at=ends_at+interval '{hours} hours',revision=revision+1 where id='{event_ids[1]}';")
fresh=event_forward_plan()
race(middle_edit(2),actor(COACH,reverse_command(fresh,'00000000-0000-4000-8000-000000000906')),'stale_revision')
sql(middle_edit(-2))
fresh=event_forward_plan()
race(actor(COACH,reverse_command(fresh,'00000000-0000-4000-8000-000000000907')),middle_edit(2))
assert sql(f"select starts_at={event_base}+interval '7 days 3 hours' from core.events where id='{event_ids[1]}';").stdout.strip()=='t'
assert sql(f"select starts_at={event_base}+interval '1 hour' from core.events where id='{event_ids[0]}';").stdout.strip()=='t'
print('forward time concurrency: middle conflicts, stale previews, cancellations and middle-activity edits in both orders passed')

# Whole-upcoming commands opened from the last occurrence must serialize with
# changes to an earlier future occurrence, including one without resources.
upcoming_resource=sql(actor(OWNER,save_hierarchy(name='Upcoming series race',extra={'requires_approval':False}))).stdout.strip()
upcoming=json.loads(sql(actor(FRIEND,f"select api.create_booking_series('{upcoming_resource}','{{7}}'::smallint[],1::smallint,({forward_base})::date,({forward_base}+interval '14 days')::date,'10:00','11:00','UTC',null,null,null,false);")).stdout.strip())
upcoming_series=upcoming['series_id']
last_id=sql(f"select id from core.booking_bookings where series_id='{upcoming_series}' and series_sequence=3;").stdout.strip()
def upcoming_plan(hour):
    return json.loads(sql(actor(FRIEND,f"select api.preview_booking_time('{last_id}','series_all',{forward_base}+interval '14 days {hour} hours',{forward_base}+interval '14 days {hour+1} hours');")).stdout.strip())
fresh=upcoming_plan(1)
earlier_block=f"select api.create_booking('{upcoming_resource}',{forward_base}+interval '1 hour',{forward_base}+interval '2 hours',null,null,null,null);"
race(actor(OWNER,earlier_block),actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000920')),'forward_conflicts')
assert sql(f"select bool_and(revision=1) from core.booking_bookings where series_id='{upcoming_series}';").stdout.strip()=='t'
blocking_id=sql(f"select id from core.booking_bookings where resource_id='{upcoming_resource}' and series_id is null and status='confirmed';").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{blocking_id}');"))
race(actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000921')),actor(OWNER,earlier_block),'resource_busy')
fresh=upcoming_plan(2)
earlier_id=sql(f"select id from core.booking_bookings where series_id='{upcoming_series}' and series_sequence=1;").stdout.strip()
race(actor(OWNER,f"select api.cancel_booking('{earlier_id}');"),actor(FRIEND,reverse_command(fresh,'00000000-0000-4000-8000-000000000922')),'stale_revision')

event_last=sql(f"select id from core.booking_bookings where event_id='{event_ids[2]}';").stdout.strip()
def upcoming_event_plan(hour):
    return json.loads(sql(actor(COACH,f"select api.preview_booking_time('{event_last}','event_all',{event_base}+interval '14 days {hour} hours',{event_base}+interval '14 days {hour+1} hours');")).stdout.strip())
def earlier_event_edit(hours):
    return event_change(f"update core.events set starts_at=starts_at+interval '{hours} hours',ends_at=ends_at+interval '{hours} hours',revision=revision+1 where id='{event_ids[0]}';")
fresh=upcoming_event_plan(2)
race(earlier_event_edit(2),actor(COACH,reverse_command(fresh,'00000000-0000-4000-8000-000000000923')),'stale_revision')
fresh=upcoming_event_plan(2)
race(actor(COACH,reverse_command(fresh,'00000000-0000-4000-8000-000000000924')),earlier_event_edit(2))
assert sql(f"select starts_at={event_base}+interval '6 hours' from core.events where id='{event_ids[0]}';").stdout.strip()=='t'
print('whole upcoming concurrency: earlier-future conflict, cancellation and event edits from last anchor in both orders passed')

# Resource replacement must reserve the destination before releasing the old
# claim and share lock order with booking cancellation and activity revisions.
swap_source=sql(actor(OWNER,save_hierarchy(name='Swap race source',extra={'requires_approval':False}))).stdout.strip()
swap_target=sql(actor(OWNER,save_hierarchy(name='Swap race target',extra={'requires_approval':False}))).stdout.strip()
swap_base="date_trunc('day',now()+interval '700 days')+interval '10 hours'"
def swap_booking(resource):
    return f"select api.create_booking('{resource}',{swap_base},{swap_base}+interval '1 hour',null,null,null,null);"
swapped=json.loads(sql(actor(FRIEND,swap_booking(swap_source))).stdout.strip())
def swap_plan(booking_id,target,who=FRIEND):
    return json.loads(sql(actor(who,f"select api.preview_booking_resource('{booking_id}','{target}');")).stdout.strip())
def swap_command(plan,key):
    payload={'target_booking_id':plan['target_booking_id'],'new_resource_id':plan['new_resource_id'],'expected_plan':plan}
    return f"select api.execute_booking_command('{key}','change_booking_resource','{json.dumps(payload)}'::jsonb,null);"
fresh=swap_plan(swapped['id'],swap_target)
race(actor(OWNER,swap_booking(swap_target)),actor(FRIEND,swap_command(fresh,'00000000-0000-4000-8000-000000000940')),'resource_change_conflicts')
assert sql(f"select resource_id='{swap_source}'::uuid and revision=1 from core.booking_bookings where id='{swapped['id']}';").stdout.strip()=='t'
block_id=sql(f"select id from core.booking_bookings where resource_id='{swap_target}' and status='confirmed';").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{block_id}');"))
race(actor(FRIEND,swap_command(fresh,'00000000-0000-4000-8000-000000000941')),actor(OWNER,swap_booking(swap_target)),'resource_busy')
assert sql(f"select resource_id='{swap_target}'::uuid and revision=2 from core.booking_bookings where id='{swapped['id']}';").stdout.strip()=='t'
race(actor(OWNER,swap_booking(swap_source)),actor(FRIEND,f"select api.cancel_booking('{swapped['id']}');"))
another=json.loads(sql(actor(FRIEND,swap_booking(swap_target))).stdout.strip())
fresh=swap_plan(another['id'],swap_source)
# Old source is now reserved; a conflict is visible without losing the target.
assert fresh['conflicts']==['resource_busy']
source_block=sql(f"select id from core.booking_bookings where resource_id='{swap_source}' and status='confirmed';").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{source_block}');"))
fresh=swap_plan(another['id'],swap_source)
race(actor(FRIEND,f"select api.cancel_booking('{another['id']}');"),actor(FRIEND,swap_command(fresh,'00000000-0000-4000-8000-000000000942')),'not_allowed')

linked_id=sql(f"select id from core.booking_bookings where event_id='{event_ids[2]}' and status in ('pending','confirmed');").stdout.strip()
fresh=swap_plan(linked_id,swap_source,COACH)
race(earlier_event_edit(1),actor(COACH,swap_command(fresh,'00000000-0000-4000-8000-000000000943')))
# Unrelated activity revisions do not invalidate a one-occurrence swap.
assert sql(f"select resource_id='{swap_source}'::uuid from core.booking_bookings where id='{linked_id}';").stdout.strip()=='t'
fresh=swap_plan(linked_id,swap_target,COACH)
edit_selected=event_change(f"update core.events set starts_at=starts_at+interval '1 hour',ends_at=ends_at+interval '1 hour',revision=revision+1 where id='{event_ids[2]}';")
race(edit_selected,actor(COACH,swap_command(fresh,'00000000-0000-4000-8000-000000000944')),'stale_revision')
fresh=swap_plan(linked_id,swap_target,COACH)
race(actor(COACH,swap_command(fresh,'00000000-0000-4000-8000-000000000945')),edit_selected)
assert sql(f"select b.resource_id='{swap_target}'::uuid and b.starts_at=e.starts_at from core.booking_bookings b join core.events e on e.id=b.event_id where b.id='{linked_id}';").stdout.strip()=='t'
print('resource swap concurrency: destination conflicts, old claim retention/release, cancellation and selected activity move in both orders passed')

# Batch resource replacement, selected from the final occurrence, holds the
# scope before its first update and detects races at earlier occurrences.
series_source=sql(actor(OWNER,save_hierarchy(name='Resource series race source',extra={'requires_approval':False}))).stdout.strip()
series_target=sql(actor(OWNER,save_hierarchy(name='Resource series race target',extra={'requires_approval':False}))).stdout.strip()
created=json.loads(sql(actor(FRIEND,f"select api.create_booking_series('{series_source}','{{7}}'::smallint[],1::smallint,({forward_base})::date,({forward_base}+interval '14 days')::date,'10:00','11:00','UTC',null,null,null,false);")).stdout.strip())
batch_series=created['series_id']
batch_last=sql(f"select id from core.booking_bookings where series_id='{batch_series}' and series_sequence=3;").stdout.strip()
batch_first=sql(f"select id from core.booking_bookings where series_id='{batch_series}' and series_sequence=1;").stdout.strip()
def batch_plan():
    return json.loads(sql(actor(FRIEND,f"select api.preview_booking_resource_series('{batch_last}','{series_target}','series_all');")).stdout.strip())
def batch_command(plan,key):
    payload={'target_booking_id':plan['target_booking_id'],'new_resource_id':plan['new_resource_id'],'change_scope':plan['scope'],'expected_plan':plan}
    return f"select api.execute_booking_command('{key}','change_booking_resource','{json.dumps(payload)}'::jsonb,null);"
fresh=batch_plan()
block_earlier=f"select api.create_booking('{series_target}',{forward_base},{forward_base}+interval '1 hour',null,null,null,null);"
race(actor(OWNER,block_earlier),actor(FRIEND,batch_command(fresh,'00000000-0000-4000-8000-000000000960')),'resource_change_conflicts')
assert sql(f"select bool_and(resource_id='{series_source}'::uuid and revision=1) from core.booking_bookings where series_id='{batch_series}';").stdout.strip()=='t'
blocking=sql(f"select id from core.booking_bookings where resource_id='{series_target}' and status='confirmed';").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{blocking}');"))
race(actor(FRIEND,batch_command(fresh,'00000000-0000-4000-8000-000000000961')),actor(OWNER,block_earlier),'resource_busy')
# Revert with two competing writers from one reviewed all-series snapshot.
back=json.loads(sql(actor(FRIEND,f"select api.preview_booking_resource_series('{batch_last}','{series_source}','series_all');")).stdout.strip())
race(actor(FRIEND,batch_command(back,'00000000-0000-4000-8000-000000000964')),actor(FRIEND,batch_command(back,'00000000-0000-4000-8000-000000000963')),'stale_revision')
fresh=batch_plan()
race(actor(FRIEND,f"select api.cancel_booking('{batch_first}');"),actor(FRIEND,batch_command(fresh,'00000000-0000-4000-8000-000000000965')),'stale_revision')

# Activity series use the same series/event/org/booking lock order as event
# revisions; an earlier activity move either invalidates the plan or follows it.
batch_event_target=sql(actor(OWNER,save_hierarchy(name='Resource activity series race target',extra={'requires_approval':False}))).stdout.strip()
event_batch_last=sql(f"select id from core.booking_bookings where event_id='{event_ids[2]}' and status='confirmed';").stdout.strip()
def event_batch_plan(target):
    return json.loads(sql(actor(COACH,f"select api.preview_booking_resource_series('{event_batch_last}','{target}','event_all');")).stdout.strip())
# The selected last occurrence currently uses swap_target, while the earlier
# occurrences use event_resource2; manual differences must remain untouched.
fresh=event_batch_plan(batch_event_target)
assert len(fresh['bookings'])==1 and len(fresh['unchanged'])==2
race(earlier_event_edit(1),actor(COACH,batch_command(fresh,'00000000-0000-4000-8000-000000000966')),'stale_revision')
fresh=event_batch_plan(batch_event_target)
race(actor(COACH,batch_command(fresh,'00000000-0000-4000-8000-000000000967')),edit_selected)
assert sql(f"select b.resource_id='{batch_event_target}'::uuid and b.starts_at=e.starts_at from core.booking_bookings b join core.events e on e.id=b.event_id where b.id='{event_batch_last}';").stdout.strip()=='t'
print('resource series concurrency: earlier conflict/cancellation, stale repeated writer, preserved exceptions and concurrent activity revisions passed')

# Add/remove sets are one atomic operation in all scopes. Reserving a new
# resource must not release an old resource before the whole scope succeeds.
set_source=sql(actor(OWNER,save_hierarchy(name='Set race source',extra={'requires_approval':False}))).stdout.strip()
set_target=sql(actor(OWNER,save_hierarchy(name='Set race target',extra={'requires_approval':False}))).stdout.strip()
set_other=sql(actor(OWNER,save_hierarchy(name='Set race other',extra={'requires_approval':False}))).stdout.strip()
created=json.loads(sql(actor(FRIEND,f"select api.create_booking_series('{set_source}','{{7}}'::smallint[],1::smallint,({forward_base})::date,({forward_base}+interval '14 days')::date,'10:00','11:00','UTC',null,null,null,false);")).stdout.strip())
set_series=created['series_id']
set_last=sql(f"select id from core.booking_bookings where series_id='{set_series}' and series_sequence=3;").stdout.strip()
def set_plan(who,booking,scope,add,remove):
    added=','.join("'"+v+"'" for v in add);removed=','.join("'"+v+"'" for v in remove)
    return json.loads(sql(actor(who,f"select api.preview_booking_resources('{booking}','{scope}',array[{added}]::uuid[],array[{removed}]::uuid[]);")).stdout.strip())
def set_command(plan,key):
    payload={'target_booking_id':plan['target_booking_id'],'change_scope':plan['scope'],'add_resource_ids':plan['add_resource_ids'],'remove_resource_ids':plan['remove_resource_ids'],'expected_plan':plan}
    return f"select api.execute_booking_command('{key}','update_booking_resources','{json.dumps(payload)}'::jsonb,null);"
fresh=set_plan(FRIEND,set_last,'series_all',[set_target],[set_source])
block_first=f"select api.create_booking('{set_target}',{forward_base},{forward_base}+interval '1 hour',null,null,null,null);"
race(actor(OWNER,block_first),actor(FRIEND,set_command(fresh,'00000000-0000-4000-8000-000000000980')),'resource_set_conflicts')
assert sql(f"select count(*)=3 and bool_and(status='confirmed' and resource_id='{set_source}'::uuid and revision=1) from core.booking_bookings where series_id='{set_series}';").stdout.strip()=='t'
blockid=sql(f"select id from core.booking_bookings where resource_id='{set_target}' and series_id is null and status='confirmed';").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{blockid}');"))
race(actor(FRIEND,set_command(fresh,'00000000-0000-4000-8000-000000000981')),actor(OWNER,block_first),'resource_busy')
assert sql(f"select count(*)=3 from core.booking_bookings where series_id='{set_series}' and resource_id='{set_source}' and status='cancelled';").stdout.strip()=='t'
new_last=sql(f"select id from core.booking_bookings where series_id='{set_series}' and series_sequence=3 and resource_id='{set_target}' and status='confirmed';").stdout.strip()
fresh=set_plan(FRIEND,new_last,'series_all',[set_other],[])
race(actor(FRIEND,set_command(fresh,'00000000-0000-4000-8000-000000000982')),actor(FRIEND,set_command(fresh,'00000000-0000-4000-8000-000000000983')),'stale_revision')
assert sql(f"select count(*)=3 from core.booking_bookings where series_id='{set_series}' and resource_id='{set_other}' and status='confirmed';").stdout.strip()=='t'
fresh=set_plan(FRIEND,new_last,'series_all',[],[set_other])
race(actor(FRIEND,f"select api.cancel_booking_series('{set_series}');"),actor(FRIEND,set_command(fresh,'00000000-0000-4000-8000-000000000984')),'not_allowed')

set_event_resource=sql(actor(OWNER,save_hierarchy(name='Set activity new resource',extra={'requires_approval':False}))).stdout.strip()
event_set_anchor=sql(f"select id from core.booking_bookings where event_id='{event_ids[2]}' and status='confirmed';").stdout.strip()
current_resource=sql(f"select resource_id from core.booking_bookings where id='{event_set_anchor}';").stdout.strip()
fresh=set_plan(COACH,event_set_anchor,'event_all',[set_event_resource],[current_resource])
race(edit_selected,actor(COACH,set_command(fresh,'00000000-0000-4000-8000-000000000985')),'stale_revision')
fresh=set_plan(COACH,event_set_anchor,'event_all',[set_event_resource],[current_resource])
race(actor(COACH,set_command(fresh,'00000000-0000-4000-8000-000000000986')),edit_selected)
assert sql(f"select b.starts_at=e.starts_at and b.ends_at=e.ends_at from core.booking_bookings b join core.events e on e.id=b.event_id where e.id='{event_ids[2]}' and b.resource_id='{set_event_resource}' and b.status='confirmed';").stdout.strip()=='t'
assert sql(f"select status='cancelled' from core.booking_bookings where id='{event_set_anchor}';").stdout.strip()=='t'
print('resource set concurrency: atomic add/remove, earlier conflict, duplicate writer, series cancellation and activity change in both orders passed')

# A combined command must reserve its FINAL time/resource set, hold the old
# claims on failure, reject stale writers, and synchronize concurrent events.
combined_source=sql(actor(OWNER,save_hierarchy(name='Combined race source',extra={'requires_approval':False}))).stdout.strip()
combined_target=sql(actor(OWNER,save_hierarchy(name='Combined race target',extra={'requires_approval':False}))).stdout.strip()
combined_other=sql(actor(OWNER,save_hierarchy(name='Combined race other',extra={'requires_approval':False}))).stdout.strip()
created=json.loads(sql(actor(FRIEND,f"select api.create_booking_series('{combined_source}','{{7}}'::smallint[],1::smallint,({forward_base})::date,({forward_base}+interval '14 days')::date,'10:00','11:00','UTC',null,null,null,false);")).stdout.strip())
combined_series=created['series_id']
combined_last=sql(f"select id from core.booking_bookings where series_id='{combined_series}' and series_sequence=3;").stdout.strip()

def combined_plan(who,booking,scope,add,remove,hours=1):
    added=','.join("'"+v+"'" for v in add);removed=','.join("'"+v+"'" for v in remove)
    reference="e" if scope.startswith('event') or sql(f"select event_id is not null from core.booking_bookings where id='{booking}';").stdout.strip()=='t' else "b"
    bounds=json.loads(sql(f"select json_build_object('s',{reference}.starts_at+interval '{hours} hour','e',{reference}.ends_at+interval '{hours} hour') from core.booking_bookings b left join core.events e on e.id=b.event_id where b.id='{booking}';").stdout.strip())
    return json.loads(sql(actor(who,f"select api.preview_booking_change('{booking}','{scope}','{bounds['s']}','{bounds['e']}',array[{added}]::uuid[],array[{removed}]::uuid[]);")).stdout.strip())

def combined_command(plan,key):
    payload={k:plan[k] for k in ['target_booking_id','add_resource_ids','remove_resource_ids','new_starts_at','new_ends_at']}
    payload.update(change_scope=plan['scope'],expected_plan=plan)
    return f"select api.execute_booking_command('{key}','update_booking','{json.dumps(payload)}'::jsonb,null);"

fresh=combined_plan(FRIEND,combined_last,'series_all',[combined_target],[combined_source])
assert not fresh['conflicts']
block_final=f"select api.create_booking('{combined_target}',{forward_base}+interval '1 hour',{forward_base}+interval '2 hours',null,null,null,null);"
race(actor(OWNER,block_final),actor(FRIEND,combined_command(fresh,'00000000-0000-4000-8000-000000000990')),'booking_change_conflicts')
assert sql(f"select count(*)=3 and bool_and(status='confirmed' and revision=1) from core.booking_bookings where series_id='{combined_series}';").stdout.strip()=='t'
blockid=sql(f"select id from core.booking_bookings where resource_id='{combined_target}' and series_id is null and status='confirmed';").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{blockid}');"))
race(actor(FRIEND,combined_command(fresh,'00000000-0000-4000-8000-000000000991')),actor(OWNER,block_final),'resource_busy')
new_last=sql(f"select id from core.booking_bookings where series_id='{combined_series}' and series_sequence=3 and resource_id='{combined_target}' and status='confirmed';").stdout.strip()
fresh=combined_plan(FRIEND,new_last,'series_all',[combined_other],[])
race(actor(FRIEND,combined_command(fresh,'00000000-0000-4000-8000-000000000992')),actor(FRIEND,combined_command(fresh,'00000000-0000-4000-8000-000000000993')),'stale_revision')
fresh=combined_plan(FRIEND,new_last,'series_all',[],[combined_other])
race(actor(FRIEND,f"select api.cancel_booking_series('{combined_series}');"),actor(FRIEND,combined_command(fresh,'00000000-0000-4000-8000-000000000994')),'not_allowed')
combined_event_source=sql(f"select id from core.booking_bookings where event_id='{event_ids[2]}' and resource_id='{set_event_resource}' and status='confirmed';").stdout.strip()
fresh=combined_plan(COACH,combined_event_source,'event_all',[combined_target],[set_event_resource])
race(edit_selected,actor(COACH,combined_command(fresh,'00000000-0000-4000-8000-000000000995')),'stale_revision')
fresh=combined_plan(COACH,combined_event_source,'event_all',[combined_target],[set_event_resource])
race(actor(COACH,combined_command(fresh,'00000000-0000-4000-8000-000000000996')),edit_selected)
assert sql(f"select b.starts_at=e.starts_at and b.ends_at=e.ends_at from core.booking_bookings b join core.events e on e.id=b.event_id where e.id='{event_ids[2]}' and b.resource_id='{combined_target}' and b.status='confirmed';").stdout.strip()=='t'
print('combined concurrency: final-time conflict and claim retention, competing writer, cancellation, concurrent activity revisions and subsequent sync passed')

# Future plans share the same series/org gate with generators, cancellation,
# competing resource claims and revision-bound edits.
future_source=sql(actor(OWNER,save_hierarchy(name='Future race source',extra={'requires_approval':False}))).stdout.strip()
future_target=sql(actor(OWNER,save_hierarchy(name='Future race target',extra={'requires_approval':False}))).stdout.strip()
future_created=json.loads(sql(actor(FRIEND,f"select api.create_booking_series('{future_source}','{{7}}'::smallint[],1::smallint,({forward_base})::date,({forward_base}+interval '14 days')::date,'10:00','11:00','UTC',null,null,null,false);")).stdout.strip())
future_series=future_created['series_id'];future_anchor=sql(f"select id from core.booking_bookings where series_id='{future_series}' and series_sequence=1;").stdout.strip()
future_defaults=json.loads(sql(actor(FRIEND,f"select api.get_booking_series_plan('{future_anchor}');")).stdout.strip())['defaults']
future_cfg=dict(future_defaults,first_day=sql(f"select ({forward_base}+interval '21 days')::date;").stdout.strip(),ends_on=sql(f"select ({forward_base}+interval '42 days')::date;").stdout.strip(),resource_ids=[future_source,future_target],automatic=True)

def future_preview(cfg):
    return json.loads(sql(actor(FRIEND,f"select api.preview_booking_series_plan('{future_anchor}','{json.dumps(cfg)}'::jsonb);")).stdout.strip())

def future_save(cfg,p,key):
    payload={'target_booking_id':future_anchor,'configuration':cfg,'expected_plan':p}
    return actor(FRIEND,f"select api.execute_booking_command('{key}','save_booking_series_plan','{json.dumps(payload)}'::jsonb,null);")

fp=future_preview(future_cfg)
future_plan=json.loads(sql(future_save(future_cfg,fp,'00000000-0000-4000-8000-000000001100')).stdout.strip())['plan_id']
as_of=sql(f"select ({forward_base}+interval '21 days')::date;").stdout.strip()
generator=f"set request.jwt.claim.sub='{FRIEND}'; select internal.generate_booking_series_plan_for_actor('{future_plan}','{as_of}');"
future_block=f"select api.create_booking('{future_target}',{forward_base}+interval '21 days',{forward_base}+interval '21 days 1 hour',null,null,null,null);"
race(actor(OWNER,future_block),generator)
assert sql(f"select state='blocked' and group_id is null from internal.booking_series_slots where plan_id='{future_plan}' and position=1;").stdout.strip()=='t'
assert sql(f"select count(*)=0 from core.booking_bookings where resource_id='{future_source}' and starts_at={forward_base}+interval '21 days';").stdout.strip()=='t'
blockid=sql(f"select id from core.booking_bookings where resource_id='{future_target}' and series_id is null and status='confirmed';").stdout.strip()
sql(actor(OWNER,f"select api.cancel_booking('{blockid}');"))
rev=sql(f"select revision from internal.booking_series_plans where id='{future_plan}';").stdout.strip()
sql(actor(FRIEND,f"select api.execute_booking_command('00000000-0000-4000-8000-000000001101','control_booking_series_plan','{{\"plan_id\":\"{future_plan}\",\"expected_revision\":{rev},\"action\":\"retry\"}}'::jsonb,null);"))
race(generator,actor(OWNER,future_block),'resource_busy')
before=sql(f"select count(*) from core.booking_bookings where series_id='{future_series}';").stdout.strip()
race(generator,generator)
assert sql(f"select count(*) from core.booking_bookings where series_id='{future_series}';").stdout.strip()==before
# A reviewed plan cannot overwrite slots materialized while its editor was open.
future_cfg.update(first_day=sql(f"select ({forward_base}+interval '49 days')::date;").stdout.strip(),ends_on=sql(f"select ({forward_base}+interval '63 days')::date;").stdout.strip())
fp=future_preview(future_cfg);sql(future_save(future_cfg,fp,'00000000-0000-4000-8000-000000001102'))
future_cfg.update(first_day=sql(f"select ({forward_base}+interval '70 days')::date;").stdout.strip(),ends_on=sql(f"select ({forward_base}+interval '84 days')::date;").stdout.strip())
fp=future_preview(future_cfg)
race(generator,future_save(future_cfg,fp,'00000000-0000-4000-8000-000000001103'),'stale_revision')
# Cancel first: queued slots are not recreated. Generate first: whole-series
# cancellation includes those new rows and pauses future generation.
future_cfg.update(first_day=sql(f"select ({forward_base}+interval '91 days')::date;").stdout.strip(),ends_on=sql(f"select ({forward_base}+interval '105 days')::date;").stdout.strip())
fp=future_preview(future_cfg);sql(future_save(future_cfg,fp,'00000000-0000-4000-8000-000000001104'))
before=sql(f"select count(*) from core.booking_bookings where series_id='{future_series}';").stdout.strip()
race(actor(FRIEND,f"select api.cancel_booking_series('{future_series}');"),generator)
assert sql(f"select state='paused' from internal.booking_series_plans where id='{future_plan}';").stdout.strip()=='t'
assert sql(f"select count(*) from core.booking_bookings where series_id='{future_series}';").stdout.strip()==before
fp=future_preview(future_cfg);sql(future_save(future_cfg,fp,'00000000-0000-4000-8000-000000001105'))
race(generator,actor(FRIEND,f"select api.cancel_booking_series('{future_series}');"))
assert sql(f"select count(*)=0 from core.booking_bookings where series_id='{future_series}' and status in('pending','confirmed');").stdout.strip()=='t'
assert sql(f"select state='paused' from internal.booking_series_plans where id='{future_plan}';").stdout.strip()=='t'
print('future plan concurrency: external claim in both orders, atomic blocked occurrence, duplicate generators, stale configuration and whole-series cancellation in both orders passed')
subprocess.run([sys.executable,str(ROOT/'supabase/tests/booking_series_plans_concurrency.py')],cwd=ROOT,check=True,timeout=180)
