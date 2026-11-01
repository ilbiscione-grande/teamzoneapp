// Team Development Plan, new design step 1 (2026-11-01): blocks in the
// periods, goals of a block, the blocks' sharing, check-ins when a block,
// period or season ends, and the day's block in the suggestion.
// node supabase/tests/team_development_blocks.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), player = id(2), club = id(10), team = id(20), training = id(30);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${coach}','Anna Tränare'),('${player}','');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.person_account_links(profile_id uuid, club_id uuid, state text);
insert into core.person_account_links values ('${coach}','${club}','active');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, starts_at timestamptz);
insert into core.events values ('${training}','${club}','${team}', now() + interval '2 days');
create table core.development_plans (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references core.clubs(id), team_id uuid not null,
  subject_club_person_id uuid, plan_type text not null check (plan_type in ('team', 'player')),
  title text not null check (length(btrim(title)) between 2 and 120),
  focus text not null default '' check (length(focus) <= 4000),
  state text not null default 'draft' check (state in ('draft', 'active', 'completed', 'archived')),
  created_at timestamptz not null default now(), created_by uuid not null references core.profiles(id),
  updated_at timestamptz not null default now(), updated_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check (revision > 0), unique (id, club_id));
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$ select true $$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$
  select (auth.uid() = '${coach}'::uuid and cap in ('development.manage', 'team.roster.view'))
      or (auth.uid() = '${player}'::uuid and cap = 'team.roster.view') $$;
create function internal.actor_has_event_capability(e uuid, cap text) returns boolean language sql stable as $$
  select auth.uid() = '${coach}'::uuid and cap = 'training.plan' $$;
-- As the match module made it (20261203090000).
create table core.module_attachments (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references core.clubs(id),
  owner_kind text not null check (owner_kind in ('match_plan')), owner_id uuid not null,
  kind text not null check (kind in ('link')), title text not null, url text,
  visible_to_players boolean not null default false, position integer not null default 0,
  created_by uuid, created_at timestamptz not null default now());
grant usage on schema api, internal, core, auth to authenticated;`);
for (const name of ['20261202090000_module_foundation', '20261209090000_team_development_plan',
  '20261210090000_team_development_principles', '20261211090000_team_development_sharing',
  '20270122090000_team_development_blocks']) {
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
const day = offset => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);

let plan = await call(coach, "select api.create_team_development_plan($1,'Säsongen',$2,$3,'')", [team, day(-60), day(200)]);
const season = plan.id;
plan = await call(coach, "select api.save_team_development_period($1,1,null,'Försäsong','preseason',$2,$3,'Grund')", [season, day(-60), day(20)]);
const pre = plan.periods[0].id;
plan = await call(coach, "select api.save_team_development_principle($1,2,null,'build_up','Spelbarhet','')", [season]);
plan = await call(coach, "select api.save_team_development_principle($1,3,null,'regaining','Fem sekunder','')", [season]);
const [playable, fiveSec] = plan.principles.map(p => p.id);

// Blocks: inside their period, never overlapping, with the plan's principles in the order chosen.
const block = (rev, blockId, name, starts, ends, principles = []) => call(coach,
  'select api.save_team_development_block($1,$2,$3,$4,$5,$6,$7,$8,$9)', [season, rev, blockId, pre, name, starts, ends, '', principles]);
plan = await block(4, null, 'Grund', day(-60), day(-5));
plan = await block(5, null, 'Speluppbyggnad', day(-4), day(10), [fiveSec, playable]);
assert.deepEqual(plan.blocks.map(b => b.name), ['Grund', 'Speluppbyggnad']);
assert.deepEqual(plan.blocks[1].principles.map(p => p.title), ['Fem sekunder', 'Spelbarhet']);
const [basic, buildUp] = plan.blocks.map(b => b.id);
const newBlock = 'select api.save_team_development_block($1,6,null,$2,$3,$4,$5,$6,$7)';
await fails(coach, newBlock, [season, pre, 'Krock', day(5), day(15), '', []], /overlapping_block/);
await fails(coach, newBlock, [season, pre, 'Utanför', day(15), day(30), '', []], /outside_period/);
await fails(coach, newBlock, [season, pre, 'Dubbel', day(11), day(12), '', [playable, playable]], /invalid_input/);
await fails(coach, newBlock, [season, pre, 'Främmande', day(11), day(12), '', [id(99)]], /not_found/);
await fails(player, newBlock, [season, pre, 'Spelarens', day(11), day(12), '', []], /not_found/);
plan = await block(6, buildUp, 'Speluppbyggnad', day(-4), day(10), [playable]);
assert.deepEqual(plan.blocks[1].principles.map(p => p.title), ['Spelbarhet'], 'principles replaced');

// The period cannot shrink past its blocks; moved with the same length, its blocks go along.
const period = "select api.save_team_development_period($1,$2,$3,'Försäsong','preseason',$4,$5,'Grund')";
await fails(coach, period, [season, 7, pre, day(-60), day(5)], /outside_period/);
plan = await call(coach, period, [season, 7, pre, day(-59), day(21)]);
assert.deepEqual(plan.blocks.map(b => [b.starts_on, b.ends_on]), [[day(-59), day(-4)], [day(-3), day(11)]]);
plan = await call(coach, period, [season, 8, pre, day(-60), day(20)]);

// Goals of a block; the earlier signature still saves season, period and dated goals.
const goal = (rev, horizon, periodId, blockId, title) => call(coach,
  "select api.save_team_development_goal($1,$2,null,$3,$4,$5,$6,'',null,'open')", [season, rev, horizon, periodId, blockId, title]);
plan = await goal(9, 'block', null, basic, 'Passningar på två tillslag');
plan = await goal(10, 'block', null, buildUp, 'Ur egen zon i sex av tio');
plan = await goal(11, 'period', pre, null, 'Gemensam bild av pressen');
plan = await call(coach, "select api.save_team_development_goal($1,12,null,'season',null,'Alla spelar två positioner','',null,'open')", [season]);
assert.deepEqual(plan.goals.map(g => [g.horizon, g.block_id !== null]),
  [['block', true], ['block', true], ['period', false], ['season', false]]);
await fails(coach, "select api.save_team_development_goal($1,13,null,'block',null,null,'Utan block','',null,'open')", [season], /invalid_input/);
await fails(coach, "select api.save_team_development_goal($1,13,null,'block',null,'Gamla vägen','',null,'open')", [season], /invalid_input/);

// Check-ins when things end: the first block ended five days ago; nothing else has.
const due = async () => (await call(coach, 'select api.list_my_team_development_checkins_due()'))[0]?.due ?? 0;
assert.equal(await due(), 1);
const basicGoal = plan.goals.find(g => g.block_id === basic).id;
await call(coach, "select api.add_team_development_checkin($1,$2,null,$3,'on_track',null,'')", [season, basicGoal, day(-1)]);
assert.equal(await due(), 0, 'checked after the end');

// Sharing the blocks; the block goals follow the goals.
plan = await call(coach, 'select api.set_team_development_sharing($1,13,false,false,false,true,true)', [season]);
assert.deepEqual(plan.sharing, { vision: false, periods: false, principles: false, goals: true, blocks: true });
const shared = await call(player, 'select api.get_shared_team_development($1)', [team]);
assert.deepEqual(shared.blocks.map(b => b.name), ['Grund', 'Speluppbyggnad']);
assert.deepEqual(shared.goals.map(g => g.horizon), ['block', 'block', 'period', 'season']);
plan = await call(coach, 'select api.set_team_development_sharing($1,14,true,false,false,true)', [season]);
assert.equal(plan.sharing.blocks, true, 'the earlier signature leaves the blocks shared');

// The suggestion for a training in the second block: its focus, principles and goals first.
const suggestion = await call(coach, 'select api.get_team_plan_suggestion($1)', [training]);
assert.equal(suggestion.block.name, 'Speluppbyggnad');
assert.deepEqual(suggestion.block.principles.map(p => p.title), ['Spelbarhet']);
assert.deepEqual(suggestion.goals.map(g => g.title), ['Ur egen zon i sex av tio', 'Gemensam bild av pressen']);

// A deleted principle leaves the block; a deleted block takes its goals; a deleted period its blocks.
plan = await call(coach, 'select api.delete_team_development_principle($1,15,$2)', [season, playable]);
assert.deepEqual(plan.blocks[1].principles, []);
plan = await call(coach, 'select api.delete_team_development_block($1,16,$2)', [season, buildUp]);
assert.deepEqual([plan.blocks.length, plan.goals.filter(g => g.horizon === 'block').length], [1, 1]);
plan = await call(coach, 'select api.delete_team_development_period($1,17,$2)', [season, pre]);
assert.deepEqual([plan.blocks.length, plan.goals.map(g => g.horizon)], [0, ['season']]);

console.log('team_development_blocks: ok');
