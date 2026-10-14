// Inbox and conversation profile pictures: the real migrations in isolated
// Postgres (inbox rows, and senders in a thread), with
// thread access and club sharing stubbed (their rules are tested with the
// messaging and profile migrations).
// node supabase/tests/inbox_thread_avatars.local.mjs
// (also covers 20261027090000_thread_sender_avatars)
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const me = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const people = ['b', 'c', 'd', 'e', 'f'].map(x => `${x.repeat(8)}-${x.repeat(4)}-4${x.repeat(3)}-8${x.repeat(3)}-${x.repeat(12)}`);
const [bo, cia, dan, eva, far] = people;
const club = '10000000-0000-4000-8000-000000000001';
const direct = '40000000-0000-4000-8000-000000000001', group = '40000000-0000-4000-8000-000000000002';
const hidden = '40000000-0000-4000-8000-000000000003';
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
try {
  await db.exec(`create role anon;create role authenticated;create role service_role;
  create schema internal;create schema api;create schema core;create schema auth;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.profiles(id uuid primary key,display_name text,avatar_asset_id uuid);
  create table core.profile_avatars(id uuid primary key,profile_id uuid,object_key text,state text);
  create table core.club_people(id uuid primary key,club_id uuid,display_name text);
  create table core.thread_participants(thread_id uuid,profile_id uuid,club_id uuid,club_person_id uuid,
   state text default 'active',joined_at timestamptz default now());
  create table core.messages(thread_id uuid,sender_profile_id uuid,created_at timestamptz);
  -- Stubs: access to every thread but 'hidden'; a shared club with everyone but Far.
  create function internal.actor_can_access_thread(target uuid,require_send boolean default false) returns boolean
   language sql stable as $$select target<>'${hidden}'$$;
  create function internal.actor_shares_club_with_profile(target uuid) returns boolean
   language sql stable as $$select target<>'${far}'$$;
  grant usage on schema api, internal, core to authenticated;`);
  const names = { [me]: 'Jag', [bo]: 'Bo Berg', [cia]: 'Cia Ek', [dan]: 'Dan Ås', [eva]: '', [far]: 'Far Fot' };
  let n = 0;
  for (const [id, name] of Object.entries(names)) {
    n++;
    const avatar = `90000000-0000-4000-8000-00000000000${n}`;
    await db.query('insert into core.profile_avatars values($1,$2,$3,$4)', [avatar, id, `${id}/pic.jpg`, id === dan ? 'deleted' : 'active']);
    await db.query('insert into core.profiles values($1,$2,$3)', [id, name, avatar]);
    await db.query('insert into core.club_people values($1,$2,$3)', [`5000000${n}-0000-4000-8000-000000000001`, club, id === eva ? 'Eva Lind' : name]);
  }
  const person = id => `5000000${Object.keys(names).indexOf(id) + 1}-0000-4000-8000-000000000001`;
  const join = (thread, id, minutes, state = 'active') => db.query(
    "insert into core.thread_participants values($1,$2,$3,$4,$5,now()-make_interval(mins=>$6))", [thread, id, club, person(id), state, minutes]);
  for (const id of [me, bo]) await join(direct, id, 60);
  for (const [id, minutes] of [[me, 90], [bo, 80], [cia, 70], [dan, 60], [eva, 50], [far, 40]]) await join(group, id, minutes);
  await join(group, '99999999-9999-4999-8999-999999999999', 30, 'left');
  // Eva wrote last, then Cia; the others never wrote.
  await db.query("insert into core.messages values($1,$2,now()-interval '5 minutes'),($1,$3,now()-interval '1 minute')", [group, cia, eva]);
  for (const name of ['20261026090000_inbox_thread_avatars', '20261027090000_thread_sender_avatars']) {
    await db.exec(read(`supabase/migrations/${name}.sql`).replace(/notify pgrst[^;]*;/, ''));
  }
  await db.exec('begin');

  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [me]);
  await db.exec('set role authenticated');
  const rows = await one('select api.list_thread_avatars($1)', [[direct, group, hidden, direct]]);
  await db.exec('reset role');
  const byThread = Object.fromEntries(rows.map(row => [row.thread_id, row]));

  // A direct thread: the other person, with their picture.
  assert.equal(byThread[direct].participant_count, 1);
  assert.deepEqual(byThread[direct].people, [{ profile_id: bo, name: 'Bo Berg', object_key: `${bo}/pic.jpg` }]);

  // A group: the three most recently active others, and how many take part.
  assert.equal(byThread[group].participant_count, 5, 'active others only');
  assert.deepEqual(byThread[group].people.map(p => p.profile_id), [eva, cia, bo]);
  assert.equal(byThread[group].people[0].name, 'Eva Lind', 'a blank profile name falls back to the club name');

  // Threads one cannot access are left out (and duplicates only once).
  assert.equal(rows.length, 2);
  assert.equal(byThread[hidden], undefined);

  // No key without a shared club, nor for a removed picture.
  await db.query("update core.messages set created_at=now() where sender_profile_id=$1", [eva]);
  await db.query("insert into core.messages values($1,$2,now()+interval '1 minute'),($1,$3,now()+interval '2 minutes')", [group, far, dan]);
  await db.exec('set role authenticated');
  const again = (await one('select api.list_thread_avatars($1)', [[group]]))[0].people;
  await db.exec('reset role');
  assert.deepEqual(again.map(p => [p.name, p.object_key]), [['Dan Ås', null], ['Far Fot', null], ['Eva Lind', `${eva}/pic.jpg`]]);

  // Senders in a conversation: everyone with a picture one may see, also
  // people who have left; no key for Far (no shared club) or Dan (removed).
  await db.query("update core.thread_participants set state='left' where profile_id=$1 and thread_id=$2", [cia, group]);
  await db.exec('set role authenticated');
  const senders = await one('select api.list_thread_sender_avatars($1)', [group]);
  await db.exec('reset role');
  assert.deepEqual(senders.map(row => row.profile_id).sort(), [me, bo, cia, eva].sort());
  assert.equal(senders.find(row => row.profile_id === cia).object_key, `${cia}/pic.jpg`);
  await db.exec('set role authenticated');
  await reject(() => db.query('select api.list_thread_sender_avatars($1)', [hidden]), /not_found/);
  await db.exec('reset role');

  // Signed-in users only; at most 200 threads per call.
  await reject(() => db.query('select api.list_thread_avatars($1)', [Array(201).fill(direct)]), /invalid_input/);
  await db.query("select set_config('request.jwt.claim.sub','',false)");
  await reject(() => db.query('select api.list_thread_avatars($1)', [[direct]]), /unauthenticated/);
  assert.equal(await one("select has_function_privilege('anon','api.list_thread_avatars(uuid[])','execute')"), false);
  assert.equal(await one("select has_function_privilege('authenticated','api.list_thread_avatars(uuid[])','execute')"), true);
  assert.equal(await one("select has_function_privilege('anon','api.list_thread_sender_avatars(uuid)','execute')"), false);
  await db.exec('rollback');
  console.log('inbox and sender avatars: ok');
} finally {
  await db.close();
}
