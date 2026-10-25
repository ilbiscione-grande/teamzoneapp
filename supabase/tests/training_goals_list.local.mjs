// Training: the session's goals as a list (2026-10-25). The old free-text
// goal becomes own yes/no goals on the event, one per line, and a new session
// no longer starts its goal from the event's free-text focus.
// node supabase/tests/training_goals_list.local.mjs
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

// A saved session with a goal over two lines, and a goal already on the event.
await db.exec(`create table core.event_kpi_targets(id uuid primary key default gen_random_uuid(), club_id uuid not null,
  event_id uuid not null, kpi_key text not null, label text not null check(length(btrim(label)) between 1 and 80),
  value_type text not null, direction text not null, source text not null, comparator text not null, target numeric not null,
  visible_to_players boolean not null default false, position integer not null default 0, created_by uuid not null);
insert into core.event_kpi_targets (club_id, event_id, kpi_key, label, value_type, direction, source, comparator, target, position, created_by)
  values ('${club}', '${training}', 'attendance_rate', 'Närvaro', 'percent', 'higher', 'auto', 'gte', 80, 0, '${coach}');`);
await call(coach, "select api.save_training_session($1,0,'Press',$2,false,'[]'::jsonb)",
  [training, `• Vinna bollen inom fem sekunder\n\n- ${'x'.repeat(100)}`]);

await db.exec(read('supabase/migrations/20261218090000_training_goals_list.sql'));
const goals = (await db.query("select kpi_key, label, value_type, source, comparator, target::int, position, created_by from core.event_kpi_targets where event_id = $1 order by position", [training])).rows;
assert.deepEqual(goals.map(g => [g.kpi_key, g.label, g.value_type, g.source, g.comparator, g.target, g.position]), [
  ['attendance_rate', 'Närvaro', 'percent', 'auto', 'gte', 80, 0],
  ['custom', 'Vinna bollen inom fem sekunder', 'boolean', 'manual', 'eq', 1, 1],
  ['custom', 'x'.repeat(80), 'boolean', 'manual', 'eq', 1, 2],
]);
assert.equal(goals[1].created_by, coach);
const session = await call(coach, 'select api.get_training_session($1)', [training]);
assert.deepEqual([session.theme, session.goal], ['Press', '']);

// Without a session, the goal is empty; the event's focus is no goal.
const fresh = await call(coach, 'select api.get_training_session($1)', [plain]);
await db.exec(`update core.events set training_focus = 'Vinna bollen högt' where id = '${plain}'`);
assert.equal((await call(coach, 'select api.get_training_session($1)', [plain])).goal, '');
assert.equal(fresh.revision, 0);

console.log('training_goals_list: ok');
