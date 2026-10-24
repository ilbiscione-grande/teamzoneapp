// Training module, step 1 (2026-10-24): the training session with its
// blocks, what players see of it, the module's list, and the module's access.
// node supabase/tests/training_sessions.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), outsider = id(3), club = id(10), team = id(20);
const training = id(30), match = id(31), plain = id(32);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna Tränare'),('${player}',''),('${outsider}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, event_type text, title text,
  state text default 'scheduled', starts_at timestamptz, ends_at timestamptz, archived_at timestamptz,
  training_theme text, training_focus text, training_plan text);
insert into core.events values
  ('${training}','${club}','${team}','training','Träning','scheduled', now() + interval '1 day', now() + interval '1 day 90 minutes', null,
    'Press', 'Vinna bollen högt', 'Rondo, press 4v4, match'),
  ('${match}','${club}','${team}','match','Match','scheduled', now() + interval '3 days', now() + interval '3 days 2 hours', null, null, null, null),
  ('${plain}','${club}','${team}','training','Träning 2','scheduled', now() + interval '5 days', now() + interval '5 days 1 hour', null, null, null, null);
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$ select auth.uid() <> '${outsider}'::uuid $$;
create function internal.actor_can_read_event(target uuid) returns boolean language sql stable as $$ select auth.uid() in ('${coach}'::uuid, '${player}'::uuid) $$;
create function internal.actor_has_event_capability(target uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid and cap = 'training.plan' $$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid and cap = 'training.plan' $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261212090000_training_sessions']) await db.exec(read(`supabase/migrations/${name}.sql`));
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try {
    const rows = (await db.query(sql, params)).rows;
    return Object.values(rows[0] ?? {})[0];
  } finally {
    await db.exec('reset role');
  }
};
const fails = async (who, sql, params, pattern) => assert.rejects(call(who, sql, params), pattern);
const save = (who, revision, published, blocks) => call(who,
  "select api.save_training_session($1,$2,'Press','Vinna bollen inom fem sekunder',$3,$4::jsonb)",
  [training, revision, published, JSON.stringify(blocks)]);
const blocks = [
  { part: 'warmup', title: 'Rondo 5v2', minutes: 12, organisation: '10x10 m', coaching_points: 'Kroppsställning', phase: null },
  { part: 'main', title: 'Press 4v4+2', minutes: 25, organisation: '', coaching_points: 'Pressa direkt', phase: 'regaining' },
  { part: 'finish', title: 'Match 7v7', minutes: 30, organisation: '', coaching_points: '', phase: 'attacking_play' },
];

// No session yet: the coach starts from the event's theme, focus and plan; a player sees nothing.
const empty = await call(coach, 'select api.get_training_session($1)', [training]);
assert.deepEqual([empty.can_edit, empty.revision, empty.theme, empty.goal, empty.event_plan, empty.blocks],
  [true, 0, 'Press', 'Vinna bollen högt', 'Rondo, press 4v4, match', []]);
assert.equal(await call(player, 'select api.get_training_session($1)', [training]), null);
await fails(outsider, 'select api.get_training_session($1)', [training], /not_found/);
await fails(coach, 'select api.get_training_session($1)', [match], /not_found/);

// Saving the whole session on the revision read; blocks keep their order.
let session = await save(coach, 0, false, blocks);
assert.deepEqual([session.revision, session.updated_by, session.event_plan], [1, 'Anna Tränare', null]);
assert.deepEqual(session.blocks.map(b => [b.part, b.title, b.minutes, b.phase]),
  [['warmup', 'Rondo 5v2', 12, null], ['main', 'Press 4v4+2', 25, 'regaining'], ['finish', 'Match 7v7', 30, 'attacking_play']]);
await fails(coach, "select api.save_training_session($1,0,'','',false,'[]'::jsonb)", [training], /stale_revision/);
await fails(player, "select api.save_training_session($1,1,'','',false,'[]'::jsonb)", [training], /not_allowed/);
await fails(coach, "select api.save_training_session($1,1,'','',false,$2::jsonb)", [training, JSON.stringify([{ part: 'cooldown', title: 'X', minutes: 5 }])], /invalid_input/);
await fails(coach, "select api.save_training_session($1,1,'','',false,$2::jsonb)", [training, JSON.stringify([{ part: 'main', title: 'X', minutes: 2.5 }])], /invalid_input/);
await fails(coach, "select api.save_training_session($1,1,'','',false,$2::jsonb)", [training, JSON.stringify([{ part: 'main', title: 'X', minutes: 5, phase: 'attack' }])], /invalid_input/);
assert.equal(await call(player, 'select api.get_training_session($1)', [training]), null, 'a draft is the leaders\'');

// Reordered and published: the players see it.
session = await save(coach, 1, true, [blocks[1], blocks[0]]);
assert.deepEqual([session.revision, session.blocks.map(b => b.title)], [2, ['Press 4v4+2', 'Rondo 5v2']]);
const seen = await call(player, 'select api.get_training_session($1)', [training]);
assert.deepEqual([seen.can_edit, seen.blocks.length, seen.goal], [false, 2, 'Vinna bollen inom fem sekunder']);

// The module's list: trainings only, with how far each session is planned.
const list = await call(coach, "select api.list_module_trainings($1, now(), now() + interval '30 days')", [team]);
assert.deepEqual(list.map(t => [t.title, t.session, Number(t.minutes), Number(t.blocks)]),
  [['Träning', 'published', 37, 2], ['Träning 2', 'none', 0, 0]]);
await fails(player, "select api.list_module_trainings($1, now(), now() + interval '30 days')", [team], /not_found/);

// A club whose module ended reads its sessions but cannot change them; without it, none.
await db.exec(`update core.module_catalog set beta_open = false where key = 'module.training';
  insert into core.club_entitlements values ('${club}', 'module.training', 'read_only', null);`);
assert.equal((await call(coach, 'select api.get_training_session($1)', [training])).can_edit, false);
await fails(coach, "select api.save_training_session($1,2,'','',false,'[]'::jsonb)", [training], /not_allowed/);
await db.exec('delete from core.club_entitlements');
await fails(coach, 'select api.get_training_session($1)', [training], /not_found/);

console.log('training_sessions: ok');
