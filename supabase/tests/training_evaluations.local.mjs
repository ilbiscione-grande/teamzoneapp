// Training module, step 3 (2026-10-25): the leaders' evaluation after the
// session, with the attendance against the callups, and the module's list.
// node supabase/tests/training_evaluations.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), club = id(10), team = id(20), past = id(30), coming = id(31);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna Tränare'),('${player}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, event_type text, title text,
  state text default 'scheduled', starts_at timestamptz, ends_at timestamptz, archived_at timestamptz,
  training_theme text, training_focus text, training_plan text);
insert into core.events values
  ('${past}','${club}','${team}','training','Träning','scheduled', now() - interval '2 hours', now() - interval '30 minutes', null, null, null, null),
  ('${coming}','${club}','${team}','training','Träning 2','scheduled', now() + interval '2 days', now() + interval '2 days 90 minutes', null, null, null, null);
create table core.callups(id uuid primary key default gen_random_uuid(), event_id uuid, state text);
insert into core.callups (event_id, state) values ('${past}','accepted'),('${past}','accepted'),('${past}','accepted'),('${past}','declined'),('${past}','cancelled');
create table core.attendance_facts(id uuid primary key default gen_random_uuid(), event_id uuid, status text);
insert into core.attendance_facts (event_id, status) values ('${past}','present'),('${past}','late'),('${past}','absent');
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$ select true $$;
create function internal.actor_can_read_event(target uuid) returns boolean language sql stable as $$ select true $$;
create function internal.actor_has_event_capability(target uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid and cap = 'training.plan' $$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid and cap = 'training.plan' $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261212090000_training_sessions', '20261217090000_training_evaluations']) {
  await db.exec(read(`supabase/migrations/${name}.sql`));
}
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
const blocks = JSON.stringify([{ title: 'Rondo', rating: 'good', note: '' }, { title: 'Press 4 mot 4', rating: 'poor', note: 'För stor yta' }]);
const save = (revision, rating = 4) => call(coach, "select api.save_training_evaluation($1,$2,$3,'partly','Hög intensitet','Mindre yta i pressen','Följ upp pressen',$4::jsonb)",
  [past, revision, rating, blocks]);

// Before it is written: the attendance against the callups.
const empty = await call(coach, 'select api.get_training_evaluation($1)', [past]);
assert.deepEqual([empty.revision, empty.started, empty.rating], [0, true, null]);
assert.deepEqual(empty.attendance, { called: 4, accepted: 3, attended: 2, recorded: 3 });
await fails(player, 'select api.get_training_evaluation($1)', [past], /not_found/);

// Saved on the revision read; only after the training has started.
let evaluation = await save(0);
assert.deepEqual([evaluation.revision, evaluation.rating, evaluation.goal_reached, evaluation.updated_by], [1, 4, 'partly', 'Anna Tränare']);
assert.deepEqual(evaluation.blocks.map(b => [b.title, b.rating]), [['Rondo', 'good'], ['Press 4 mot 4', 'poor']]);
await fails(coach, "select api.save_training_evaluation($1,0,3,null,'','','','[]'::jsonb)", [past], /stale_revision/);
await fails(coach, "select api.save_training_evaluation($1,0,3,null,'','','','[]'::jsonb)", [coming], /not_started/);
await fails(coach, "select api.save_training_evaluation($1,1,6,null,'','','','[]'::jsonb)", [past], /invalid_input/);
await fails(coach, "select api.save_training_evaluation($1,1,3,null,'','','',$2::jsonb)", [past, JSON.stringify([{ title: 'X', rating: 'great' }])], /invalid_input/);
await fails(player, "select api.save_training_evaluation($1,1,3,null,'','','','[]'::jsonb)", [past], /not_allowed/);
evaluation = await save(1, 5);
assert.deepEqual([evaluation.revision, evaluation.rating], [2, 5]);

// The module's list tells which trainings are evaluated.
const list = await call(coach, "select api.list_module_trainings($1, now() - interval '1 day', now() + interval '10 days')", [team]);
assert.deepEqual(list.map(t => [t.title, t.evaluated, t.rating]), [['Träning', true, 5], ['Träning 2', false, null]]);

console.log('training_evaluations: ok');
