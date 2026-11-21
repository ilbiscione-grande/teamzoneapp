// A team's formations with what each place asks for (step 3 of
// docs/implementation/player-attributes.md).
// node supabase/tests/team_formations.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), outsider = id(2), club = id(10), team = id(20), other = id(21);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.teams(id uuid primary key, club_id uuid, sport text not null default 'football');
insert into core.teams values ('${team}','${club}','football'),('${other}','${club}','football');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active');
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text, starts_at timestamptz default now(), ends_at timestamptz);
create table core.sport_positions(sport text, key text, level text, parent_key text, sort integer);
insert into core.sport_positions values ('football','defender','general',null,1),('football','centre_back','detailed','defender',2),
  ('football','striker','detailed','forward',3),('handball','hb_pivot','detailed',null,4);
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$
  select auth.uid() = '${coach}'::uuid and cap = 'team.roster.manage' and t = '${team}'::uuid $$;
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20270407090000_player_attributes.sql'));
await db.exec(read('supabase/migrations/20270408090000_team_formations.sql'));
await db.exec('begin');

const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0];
const save = (formationId, name, lines, format, slots, revision = null) => one(
  'select api.save_team_formation($1,$2,$3,$4,$5,$6,$7::jsonb,$8) v',
  [club, team, formationId, name, lines, format, JSON.stringify(slots), revision]).then(r => r.v);
const list = () => one('select api.list_team_formations($1,$2) v', [club, team]).then(r => r.v.formations);
const rejects = async (fn, message, code) => {
  await db.exec('savepoint r');
  try { await assert.rejects(fn, e => e.message === message && (!code || e.code === code), message); }
  finally { await db.exec('rollback to r'); }
};

// The places, as the app numbers them.
const codes = async (lines, format) => (await db.query(
  'select code, position_group from internal.formation_slots($1,$2)', [lines, format])).rows;
assert.deepEqual((await codes('4-3-3', '11v11')).map(r => r.code),
  ['GK', '1A', '1B', '1C', '1D', '2A', '2B', '2C', '3A', '3B', '3C']);
assert.deepEqual((await codes('4-3-3', '11v11')).map(r => r.position_group).slice(0, 7),
  ['goalkeeper', 'defender', 'defender', 'defender', 'defender', 'midfielder', 'midfielder']);
assert.deepEqual((await codes('1-1-1', '3v3')).map(r => r.code), ['1A', '2A', '3A'], 'no goalkeeper in 3v3');

await db.exec('set role authenticated');
await as(coach);
const custom = (await one('select api.save_team_attribute($1,$2,null,$3) v', [club, team, 'Långa inkast'])).v.custom[0].id;
let formation = await save(null, '  4-3-3   press ', '4-3-3', '11v11', [
  { code: '1A', position: 'centre_back', requirements: [{ attribute: 'heading', weight: 2 }, { attribute: 'speed', weight: 1 }] },
  { code: '3B', position: 'striker', requirements: [{ attribute: 'finishing', weight: 2 }] },
  { code: '1D', requirements: [{ attribute: custom, weight: 1 }] },
  { code: '2A', requirements: [] },
]);
assert.equal(formation.name, '4-3-3 press');
assert.equal(formation.revision, 1);
assert.equal(formation.slots.length, 11, 'every place');
const slot = code => formation.slots.find(s => s.code === code);
assert.deepEqual(slot('1A'), { code: '1A', group: 'defender', position: 'centre_back',
  requirements: [{ attribute: 'heading', weight: 2 }, { attribute: 'speed', weight: 1 }] });
assert.deepEqual(slot('GK'), { code: 'GK', group: 'goalkeeper', position: null, requirements: [] });
assert.deepEqual(slot('1D').requirements, [{ attribute: custom, weight: 1 }]);
await db.exec('reset role');
assert.equal((await one('select jsonb_array_length(slots) n from core.team_formations')).n, 3, 'empty places not stored');
await db.exec('set role authenticated');

// Replacing, with the revision.
formation = await save(formation.id, '4-3-3 press', '4-3-3', '11v11', [{ code: 'GK', requirements: [{ attribute: 'goalkeeping_feet', weight: 2 }] }], 1);
assert.equal(formation.revision, 2);
assert.deepEqual(slot('1A').requirements, []);
await rejects(() => save(formation.id, '4-3-3 press', '4-3-3', '11v11', [], 1), 'stale_revision', 'PT409');
await rejects(() => save(id(99), 'X', '4-3-3', '11v11', [], null), 'formation_not_found');

// What is checked.
await rejects(() => save(null, '4-3-3 PRESS', '4-4-2', '11v11', []), 'formation_name_taken');
await rejects(() => save(null, 'Fel', '4-3-2', '11v11', []), 'invalid_formation');
await rejects(() => save(null, 'Fel', '4-3-3', '7v7', []), 'invalid_formation');
await rejects(() => save(null, 'Fel', '4-3-3', '11v11', [{ code: '4A' }]), 'invalid_slots');
await rejects(() => save(null, 'Fel', '4-3-3', '11v11', [{ code: '1A' }, { code: '1A' }]), 'invalid_slots');
await rejects(() => save(null, 'Fel', '4-3-3', '11v11', [{ code: '1A', position: 'hb_pivot' }]), 'invalid_slots');
await rejects(() => save(null, 'Fel', '4-3-3', '11v11', [{ code: '1A', requirements: [{ attribute: 'flying', weight: 1 }] }]), 'invalid_slots');
await rejects(() => save(null, 'Fel', '4-3-3', '11v11', [{ code: '1A', requirements: [{ attribute: 'speed', weight: 3 }] }]), 'invalid_slots');
await rejects(() => save(null, 'Fel', '4-3-3', '11v11',
  [{ code: '1A', requirements: [{ attribute: 'speed', weight: 1 }, { attribute: 'speed', weight: 2 }] }]), 'invalid_slots');
await rejects(() => save(null, 'Fel', '4-3-3', '11v11', [{ code: '1A', requirements:
  ['speed', 'heading', 'passing', 'crossing', 'shooting', 'dribbling', 'agility'].map(attribute => ({ attribute, weight: 1 })) }]), 'invalid_slots');
const small = await save(null, '2-3-1', '2-3-1', '7v7', [{ code: '3A', requirements: [{ attribute: custom, weight: 2 }] }]);
assert.equal(small.slots.length, 7);

// A removed team attribute drops out of the requirements.
await one('select api.delete_team_attribute($1,$2,$3) v', [club, team, custom]);
assert.deepEqual((await list()).find(f => f.name === '2-3-1').slots.find(s => s.code === '3A').requirements, []);
assert.deepEqual((await list()).map(f => f.name), ['2-3-1', '4-3-3 press']);

// Only the team's leaders.
await as(outsider);
await rejects(() => list(), 'not_found');
await rejects(() => save(null, 'X', '4-3-3', '11v11', []), 'not_found');
await as(coach);
await rejects(() => one('select api.list_team_formations($1,$2) v', [club, other]), 'not_found');
await rejects(() => db.query('select * from core.team_formations'), 'permission denied for table team_formations');
assert.deepEqual((await one('select api.delete_team_formation($1,$2,$3) v', [club, team, small.id])).v.formations.map(f => f.name), ['4-3-3 press']);

// Ready-made formations: each place asks for something; a copy can be changed.
await db.exec('reset role');
await db.exec(`insert into core.sport_positions values ('football','goalkeeper','general',null,0),
  ('football','midfielder','general',null,5),('football','forward','general',null,6),
  ('football','left_back','detailed','defender',7),('football','right_back','detailed','defender',8),
  ('football','wing_back','detailed','defender',9),('football','defensive_midfielder','detailed','midfielder',10),
  ('football','central_midfielder','detailed','midfielder',11),('football','attacking_midfielder','detailed','midfielder',12),
  ('football','left_winger','detailed','forward',13),('football','right_winger','detailed','forward',14)`);
await db.exec(read('supabase/migrations/20270412100000_more_football_attributes.sql'));
await db.exec(read('supabase/migrations/20270414090000_formation_templates.sql'));
assert.equal((await one('select count(*)::int n from core.formation_templates')).n, 21);
await db.exec('set role authenticated');
const listed = (await one('select api.list_team_formations($1,$2) v', [club, team])).v;
assert.deepEqual(listed.formations.map(f => f.name), ['4-3-3 press'], 'the team\'s own stay apart');
const templates = listed.templates;
assert.equal(templates.length, 21);
assert.ok(templates.every(t => t.template === true && t.revision === 0));
const t433 = templates.find(t => t.lines === '4-3-3' && t.match_format === '11v11');
const place = (formation, code) => formation.slots.find(s => s.code === code);
const roles = code => [place(t433, code).position, place(t433, code).requirements.map(r => `${r.attribute}:${r.weight}`).join(',')];
assert.deepEqual(roles('GK'), ['goalkeeper', 'goalkeeping_hands:2,goalkeeping_feet:1,communication:1']);
assert.deepEqual(roles('1A'), ['left_back', 'defending_1v1:2,speed:1,crossing:1,endurance:1']);
assert.deepEqual(roles('1B'), ['centre_back', 'heading:2,defending_1v1:1,interceptions:1,positioning:1']);
assert.deepEqual(roles('1D'), ['right_back', 'defending_1v1:2,speed:1,crossing:1,endurance:1']);
assert.deepEqual(roles('2B'), ['central_midfielder', 'passing:2,game_reading:1,endurance:1,work_rate:1']);
assert.deepEqual(roles('3A'), ['left_winger', 'speed:2,attacking_1v1:2,dribbling:1,crossing:1']);
assert.deepEqual(roles('3B'), ['striker', 'finishing:2,back_to_goal:1,runs_in_behind:1']);
const t4231 = templates.find(t => t.lines === '4-2-3-1');
assert.equal(place(t4231, '2A').position, 'defensive_midfielder');
assert.equal(place(t4231, '3B').position, 'attacking_midfielder');
assert.equal(place(t4231, '3A').position, 'left_winger');
assert.deepEqual(place(t4231, '4A').requirements.map(r => r.attribute), ['finishing', 'back_to_goal', 'runs_in_behind', 'heading'], 'alone up front: heading too');
const t352 = templates.find(t => t.lines === '3-5-2');
assert.equal(place(t352, '2A').position, 'wing_back');
assert.equal(place(t352, '1A').position, 'centre_back', 'three at the back are centre-backs');
assert.equal(place(templates.find(t => t.lines === '4-4-2'), '2A').position, null, 'a wide midfielder asks for its line');
assert.ok(templates.filter(t => t.match_format === '7v7').every(t => t.slots.length === 7));
// A copy of a template is the team's own and can be changed.
const copy = await save(null, '4-3-3 (kopia)', t433.lines, t433.match_format, t433.slots.map(s => ({ code: s.code, position: s.position, requirements: s.requirements })));
assert.equal(place(copy, '3B').requirements[0].attribute, 'finishing');
assert.equal((await list()).length, 2);
await db.exec('set role authenticated');
await rejects(() => db.query("update core.formation_templates set name='x' where false"), 'permission denied for table formation_templates');
console.log('team formations: ok');
