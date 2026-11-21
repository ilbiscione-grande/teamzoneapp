// Suggests who plays where (step 4 of docs/implementation/player-attributes.md).
// node supabase/tests/lineup_suggestion.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), outsider = id(2), club = id(10), team = id(20), home = id(21);
const p = {
  keeper: id(50), stopper: id(51), back: id(52), passer: id(53), mid: id(54), wide: id(55),
  finisher: id(56), forward: id(57), anyone: id(58), guest: id(59), stranger: id(60),
};
const people = Object.entries(p).map(([name, person]) => `('${person}','${club}','${name}')`).join(',');
const details = [
  // team, person, main, positions, number
  [team, p.keeper, 'goalkeeper', ['goalkeeper'], 1],
  [team, p.stopper, 'centre_back', ['centre_back'], 4],
  [team, p.back, 'defender', ['defender'], 2],
  [team, p.passer, 'central_midfielder', ['central_midfielder'], 8],
  [team, p.mid, 'midfielder', ['midfielder'], 6],
  [team, p.wide, 'forward', ['forward', 'midfielder'], 7],
  [team, p.finisher, 'striker', ['striker'], 9],
  [team, p.forward, 'forward', ['forward'], 11],
  [home, p.guest, 'defender', ['defender'], 3],
].map(([t, person, main, positions, number]) =>
  `('${club}','${t}','${person}','${main}','{${positions.join(',')}}',${number})`).join(',');
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.teams(id uuid primary key, club_id uuid, sport text not null default 'football');
insert into core.teams values ('${team}','${club}','football'),('${home}','${club}','football');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active');
insert into core.club_people values ${people};
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text, starts_at timestamptz default now() - interval '1 day', ends_at timestamptz);
insert into core.assignments(club_id, team_id, club_person_id, role_package, state)
  select '${club}','${team}',id,'player','active' from core.club_people where display_name not in ('guest','stranger');
create table core.team_assignments(club_id uuid, team_id uuid, club_person_id uuid, state text);
insert into core.team_assignments values ('${club}','${home}','${p.guest}','active');
create table core.play_eligibilities(club_id uuid, team_id uuid, club_person_id uuid, state text, starts_at timestamptz, ends_at timestamptz);
insert into core.play_eligibilities values ('${club}','${team}','${p.guest}','active', now() - interval '1 day', now() + interval '30 days');
create table core.team_person_details(club_id uuid, team_id uuid, club_person_id uuid, main_position text, positions text[], jersey_number smallint);
insert into core.team_person_details values ${details};
create table core.sport_positions(sport text, key text, level text, parent_key text, sort integer);
insert into core.sport_positions values ('football','goalkeeper','general',null,10),('football','defender','general',null,20),
  ('football','midfielder','general',null,30),('football','forward','general',null,40),
  ('football','centre_back','detailed','defender',21),('football','central_midfielder','detailed','midfielder',32),
  ('football','striker','detailed','forward',43);
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$
  select auth.uid() = '${coach}'::uuid and cap = 'team.roster.manage' and t = '${team}'::uuid $$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const file of ['20270407090000_player_attributes', '20270408090000_team_formations', '20270409090000_lineup_suggestion']) {
  await db.exec(read(`supabase/migrations/${file}.sql`));
}
await db.exec('begin');

const one = async (sql, args = []) => (await db.query(sql, args)).rows[0];
const rejects = async (fn, message) => {
  await db.exec('savepoint r');
  try { await assert.rejects(fn, e => e.message === message, message); } finally { await db.exec('rollback to r'); }
};

// The best total, not the best first place: 10 + 0 loses to 9 + 9.
const best = (scores, rows, columns) => one('select internal.best_assignment($1::integer[],$2,$3) v', [scores, rows, columns]).then(r => r.v);
assert.deepEqual(await best([10, 9, 9, 0], 2, 2), [2, 1]);
assert.deepEqual(await best([1, 5, 2, 7, 0, 3, 4, 9, 1], 3, 3), [3, 1, 2], '2 + 7 + 9 = 18 is the most');
assert.deepEqual(await best([5, 1, 9, 2, 8, 1], 2, 3), [3, 2], 'more players than places');

await db.exec('set role authenticated');
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [coach]);
const tick = (person, strengths, development = []) => one(
  'select api.set_player_attributes($1,$2,$3,$4::text[],$5::text[]) v', [club, team, person, strengths, development]);
await tick(p.stopper, ['heading']);
await tick(p.passer, ['passing']);
await tick(p.finisher, ['finishing', 'speed']);
await tick(p.forward, ['speed'], ['finishing']);
const formation = (await one('select api.save_team_formation($1,$2,null,$3,$4,$5,$6::jsonb,null) v', [club, team,
  '2-3-1', '2-3-1', '7v7', JSON.stringify([
    { code: '1A', position: 'centre_back', requirements: [{ attribute: 'heading', weight: 2 }] },
    { code: '2B', position: 'central_midfielder', requirements: [{ attribute: 'passing', weight: 2 }] },
    { code: '3A', position: 'striker', requirements: [{ attribute: 'finishing', weight: 2 }, { attribute: 'speed', weight: 1 }] },
  ])])).v;
const suggest = (formationId, lines, format, candidates = null, locked = {}) => one(
  'select api.suggest_lineup($1,$2,$3,$4,$5,$6::uuid[],$7::jsonb) v',
  [club, team, formationId, lines, format, candidates, JSON.stringify(locked)]).then(r => r.v);
const at = (result, code) => result.slots.find(s => s.code === code);

let result = await suggest(formation.id, null, null);
assert.deepEqual(result.slots.map(s => s.code), ['GK', '1A', '1B', '2A', '2B', '2C', '3A']);
assert.equal(at(result, 'GK').person_id, p.keeper);
assert.equal(at(result, '1A').person_id, p.stopper);
assert.deepEqual(at(result, '1A').strengths, ['heading']);
assert.equal(at(result, '1A').position_fit, 'main');
assert.equal(at(result, '1A').score, 16, 'main position 10 + very important strength 6');
assert.equal(at(result, '1B').person_id, p.back);
assert.equal(at(result, '2B').person_id, p.passer);
assert.equal(at(result, '3A').person_id, p.finisher, 'finishing and speed beat speed with finishing to develop');
assert.equal(at(result, '3A').score, 19);
assert.ok(new Set(result.slots.map(s => s.person_id)).size === 7, 'each player once');
assert.deepEqual(result.bench.map(b => b.person_id).sort(), [p.forward, p.anyone].sort());
assert.deepEqual(at(result, '3A').alternatives.slice(0, 2).map(a => [a.person_id, a.score]), [[p.wide, 5], [p.forward, 4]],
  'finishing to develop costs the forward the second place');
assert.equal(at(result, '3A').alternatives.length, 3);

// A formation by its lines, the guest among those to choose from.
result = await suggest(null, '2-3-1', '7v7', [p.keeper, p.guest, p.back, p.passer, p.mid, p.wide, p.forward, p.anyone]);
assert.ok(['1A', '1B'].includes(result.slots.find(s => s.person_id === p.guest)?.code), 'the guest defends, by the home team position');
assert.equal(at(result, '3A').person_id, p.forward);
assert.deepEqual(result.bench.map(b => b.person_id), [p.anyone]);

// A locked place keeps its player; the keeper is then on the bench.
result = await suggest(formation.id, null, null, null, { GK: p.anyone });
assert.equal(at(result, 'GK').person_id, p.anyone);
assert.equal(at(result, 'GK').locked, true);
assert.ok(result.bench.some(b => b.person_id === p.keeper));
assert.ok(!result.slots.some(s => !s.locked && s.person_id === p.anyone));

// Fewer players than places: the rest stay empty.
result = await suggest(formation.id, null, null, [p.keeper, p.finisher, p.stopper]);
assert.equal(result.slots.filter(s => s.person_id).length, 3);
assert.equal(at(result, '3A').person_id, p.finisher);
assert.equal(at(result, '2A').person_id, null);
assert.deepEqual(result.bench, []);

// What is checked.
await rejects(() => suggest(null, '4-3-3', '7v7'), 'invalid_formation');
await rejects(() => suggest(id(99), null, null), 'formation_not_found');
await rejects(() => suggest(formation.id, null, null, [p.stranger]), 'invalid_candidate');
await rejects(() => suggest(formation.id, null, null, null, { '9Z': p.keeper }), 'invalid_locked');
await rejects(() => suggest(formation.id, null, null, null, { GK: p.keeper, '1A': p.keeper }), 'invalid_locked');
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [outsider]);
await rejects(() => suggest(formation.id, null, null), 'not_found');
console.log('lineup suggestion: ok');

// Tacticsboard knows only the team: the club is found from it.
await db.exec('rollback');
await db.exec(read('supabase/migrations/20270410090000_formations_by_team.sql'));
await db.exec('set role authenticated');
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [coach]);
const byTeam = (await one('select api.suggest_lineup(null,$1,null,$2,$3,null,$4::jsonb) v', [team, '2-3-1', '7v7', '{}'])).v;
assert.equal(byTeam.slots.length, 7);
assert.deepEqual((await one('select api.list_team_formations(null,$1) v', [team])).v.formations, []);
assert.equal((await one('select api.get_team_player_attributes(null,$1) v', [team])).v.sport, 'football');
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [outsider]);
await assert.rejects(() => one('select api.list_team_formations(null,$1) v', [team]), e => e.message === 'not_found');
console.log('lineup suggestion by team: ok');

// The app's line-up asks by its match; called players no longer in the team are left out.
await db.exec('reset role');
await db.exec(`create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid)`);
const match = id(70);
await db.query('insert into core.events values ($1,$2,$3)', [match, club, team]);
await db.exec(read('supabase/migrations/20270411090000_event_lineup_suggestion.sql'));
await db.exec('set role authenticated');
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [coach]);
const byEvent = (await one('select api.suggest_event_lineup($1,null,$2,$3,$4::uuid[],$5::jsonb) v',
  [match, '2-3-1', '7v7', [p.keeper, p.stopper, p.stranger, p.guest], '{}'])).v;
assert.deepEqual(byEvent.slots.filter(s => s.person_id).map(s => s.person_id).sort(), [p.keeper, p.stopper, p.guest].sort(), 'the stranger is left out');
assert.equal(byEvent.slots.find(s => s.code === 'GK').person_id, p.keeper);
const listed = (await one('select api.list_event_team_formations($1) v', [match])).v;
assert.deepEqual(listed.formations, []);
assert.deepEqual(listed.custom, []);
await assert.rejects(() => one('select api.list_event_team_formations($1) v', [id(71)]), e => e.message === 'not_found');
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [outsider]);
await assert.rejects(() => one('select api.suggest_event_lineup($1,null,$2,$3,null,$4::jsonb) v', [match, '2-3-1', '7v7', '{}']), e => e.message === 'not_found');
console.log('lineup suggestion by event: ok');

// Suggesting from a ready-made formation, by its id.
await db.exec('reset role');
await db.exec(read('supabase/migrations/20270412100000_more_football_attributes.sql'));
await db.exec(read('supabase/migrations/20270414090000_formation_templates.sql'));
const template = (await one("select id from core.formation_templates where lines = '2-3-1' and match_format = '7v7'")).id;
await db.exec('set role authenticated');
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [coach]);
await one('select api.set_player_attributes($1,$2,$3,$4::text[],$5::text[]) v', [club, team, p.finisher, ['finishing'], []]);
const fromTemplate = (await one('select api.suggest_lineup($1,$2,$3,null,null,null,$4::jsonb) v', [club, team, template, '{}'])).v;
assert.equal(fromTemplate.slots.find(s => s.code === 'GK').person_id, p.keeper);
assert.equal(fromTemplate.slots.find(s => s.code === '3A').person_id, p.finisher);
assert.deepEqual(fromTemplate.slots.find(s => s.code === '3A').strengths, ['finishing'], 'the template asks for finishing up front');
console.log('lineup suggestion from a template: ok');

// The foot a place asks for, against the player's.
await db.exec('reset role');
await db.exec(read('supabase/migrations/20270413090000_preferred_foot.sql'));
await db.exec(read('supabase/migrations/20270415090000_attribute_help_and_slot_foot.sql'));
const help = (await db.query("select key, about_sv, about_en, positions from core.sport_attributes where sport = 'football'")).rows;
assert.deepEqual(help.filter(h => !h.about_sv || !h.about_en).map(h => h.key), [], 'every football attribute explains itself');
assert.deepEqual(help.find(h => h.key === 'heading').positions, ['centre_back', 'striker']);
const t433 = (await one("select slots from core.formation_templates where lines = '4-3-3' and match_format = '11v11'")).slots;
assert.deepEqual(['1A', '1B', '1D', '3A'].map(code => t433.find(s => s.code === code).foot ?? null), ['left', null, 'right', null],
  'full-backs on their side, wingers free');
const t352 = (await one("select slots from core.formation_templates where lines = '3-5-2'")).slots;
assert.deepEqual(['2A', '2E'].map(code => t352.find(s => s.code === code).foot), ['left', 'right'], 'wing-backs too');
await db.exec('set role authenticated');
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [coach]);
const feetFormation = (await one('select api.save_team_formation($1,$2,null,$3,$4,$5,$6::jsonb,null) v', [club, team,
  'Fötter', '2-3-1', '7v7', JSON.stringify([{ code: '1A', foot: 'left' }, { code: '1B', foot: 'right' }])])).v;
assert.equal(feetFormation.slots.find(s => s.code === '1A').foot, 'left');
assert.equal(feetFormation.slots.find(s => s.code === 'GK').foot, null);
await assert.rejects(() => one('select api.save_team_formation($1,$2,null,$3,$4,$5,$6::jsonb,null) v', [club, team,
  'Fel fot', '2-3-1', '7v7', JSON.stringify([{ code: '1A', foot: 'middle' }])]), e => e.message === 'invalid_slots');
// Two defenders alike but for the foot: each goes to the side of their foot.
const setFoot = (person, foot) => one('select api.set_player_foot($1,$2,$3,$4) v', [club, team, person, foot]);
await setFoot(p.stopper, 'right');
await setFoot(p.back, 'both_left');
const footed = (await one('select api.suggest_lineup($1,$2,$3,null,null,$4::uuid[],$5::jsonb) v',
  [club, team, feetFormation.id, [p.keeper, p.stopper, p.back], '{}'])).v;
const footAt = code => footed.slots.find(s => s.code === code);
assert.equal(footAt('1A').person_id, p.back, 'both, better with the left: left side');
assert.equal(footAt('1A').foot_fit, 'good');
assert.equal(footAt('1B').person_id, p.stopper, 'right-footed: right side');
await setFoot(p.back, 'right');
const wrong = (await one('select api.suggest_lineup($1,$2,$3,null,null,$4::uuid[],$5::jsonb) v',
  [club, team, feetFormation.id, [p.keeper, p.back], '{}'])).v;
assert.equal(wrong.slots.find(s => s.code === '1B').person_id, p.back, 'the right side rather than the wrong foot');
console.log('lineup suggestion with feet: ok');
