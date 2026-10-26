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

await db.exec(`create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text);
create table core.assignments(club_id uuid, team_id uuid, club_person_id uuid, state text, role_package text, starts_at timestamptz, ends_at timestamptz);
create table core.event_teams(event_id uuid, club_id uuid, team_id uuid);
insert into core.club_people values ('${player}','${club}','Alex Spelare','active'), ('${outsider}','${club}','Annan trupp','active');
insert into core.assignments values ('${club}','${team}','${player}','active','player',now()-interval '1 day',null);
insert into core.event_teams values ('${training}','${club}','${team}');`);
for (const name of ['20261202090000_module_foundation','20261212090000_training_sessions','20261219090000_training_block_participants']) {
  await db.exec(read('supabase/migrations/' + name + '.sql'));
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
const save = (who, revision, published, blocks) => call(who,
  "select api.save_training_session($1,$2,'Press','Vinna bollen inom fem sekunder',$3,$4::jsonb)",
  [training, revision, published, JSON.stringify(blocks)]);

const anonymous = {person_id:null,name:'',team:'blue'};
const named = {person_id:player,name:'Client supplied name',team:'red'};
const first = {part:'warmup',title:'Rondo',minutes:15,players:[anonymous,named]};
const second = {part:'main',title:'Spel',minutes:30,players:[{...named,team:'green'}]};
let session = await save(coach,0,false,[first,second]);
assert.equal(session.blocks[0].players[1].name,'Alex Spelare');
const storedPlayers = (await db.query('select players from core.training_blocks')).rows.flatMap(row => row.players);
assert.ok(storedPlayers.every(player => player.name === ''));
await db.exec(`update core.club_people set display_name='Alex Nytt' where id='${player}'`);
assert.equal((await call(coach,'select api.get_training_session($1)',[training])).blocks[0].players[1].name,'Alex Nytt');
await db.exec(`update core.club_people set display_name='Alex Spelare' where id='${player}'`);
assert.deepEqual(session.blocks.map(b=>b.players.map(p=>p.team)),[['blue','red'],['green']]);
assert.equal(await call(player,'select api.get_training_session($1)',[training]),null);
await fails(player,"select api.save_training_session($1,1,'','',false,$2::jsonb)",[training,JSON.stringify([first])],/not_allowed/);
await fails(coach,"select api.save_training_session($1,1,'','',false,$2::jsonb)",[training,JSON.stringify([{...first,players:[{...named,person_id:outsider}]}])],/invalid_player_reference/);
for (const players of [[{...anonymous,team:'pink'}],[named,named],[{...named,person_id:123}],[{...anonymous,extra:true}],Array(81).fill(anonymous),null]) {
  await fails(coach,"select api.save_training_session($1,1,'','',false,$2::jsonb)",[training,JSON.stringify([{...first,players}])],/invalid_players/);
}
session = await save(coach,1,true,[second,{...first,players:[anonymous]}]);
assert.deepEqual(session.blocks.map(b=>b.players.map(p=>p.team)),[['green'],['blue']]);
const visible = await call(player,'select api.get_training_session($1)',[training]);
assert.equal(visible.blocks[0].players[0].person_id,player);
assert.equal(visible.blocks[0].players[0].name,'Alex Spelare');
await fails(coach,"select api.save_training_session($1,1,'','',false,'[]'::jsonb)",[training],/stale_revision/);
// Older clients without this field still save a valid empty assignment.
session = await save(coach,2,false,[{part:'main',title:'Legacy',minutes:5}]);
assert.deepEqual(session.blocks[0].players,[]);
// Table RLS and existing RPC permissions remain in force.
await fails(player,'select players from core.training_blocks',[],/permission denied/);

// Before the new migration, existing block assignments must survive.
const legacy = await save(coach,3,false,[first]);
await db.exec(`create table core.callups(event_id uuid, club_person_id uuid, state text);
insert into core.callups values ('${training}','${player}','accepted'), ('${plain}','${player}','accepted');
insert into core.event_teams values ('${plain}','${club}','${team}');`);
await db.exec(read('supabase/migrations/20261220090000_training_session_roster.sql'));
let current = await call(coach,'select api.get_training_session($1)',[training]);
assert.equal(current.roster.length,2);
assert.ok(current.blocks[0].players.every(p=>p.roster_id));
assert.equal(current.roster.find(p=>p.person_id===player).name,'Alex Spelare');
const automatic = await call(coach,'select api.get_training_session($1)',[plain]);
assert.equal(automatic.revision,0);
assert.deepEqual(automatic.roster.map(p=>p.person_id),[player]);
assert.equal((await db.query('select count(*)::int as n from core.training_sessions where event_id=$1',[plain])).rows[0].n,0);
const saveRoster = (revision,roster,blocks) => call(coach,
  "select api.save_training_session($1,$2,'Press','',false,$3::jsonb,$4::jsonb)",[training,revision,JSON.stringify(blocks),JSON.stringify(roster)]);
// Empty is an intentional saved choice; acceptance must not re-add someone.
current = await saveRoster(4,[],[{part:'main',title:'Spel',minutes:15,players:[]}]);
assert.deepEqual(current.roster,[]);
assert.deepEqual((await call(coach,'select api.get_training_session($1)',[training])).roster,[]);
await assert.rejects(saveRoster(5,[],[{...first,players:[named]}]),/player_not_in_session_roster/);
const unnamed={roster_id:'anonymous-test-1',person_id:null,name:'',team:'blue'};
const roster=[{...named,roster_id:player},unnamed];
const assigned={...first,players:[{...named,roster_id:player},{...unnamed,team:'green'}]};
current=await saveRoster(5,roster,[assigned,assigned]);
assert.equal(current.roster.length,2);
assert.equal(current.blocks[1].players[1].team,'green');
await assert.rejects(saveRoster(6,[unnamed],[assigned]),/player_not_in_session_roster/);
await assert.rejects(saveRoster(6,[unnamed,unnamed],[]),/duplicate_roster_player/);
await assert.rejects(saveRoster(6,roster,[{...first,players:[{...unnamed,roster_id:'anonymous-other'}]}]),/player_not_in_session_roster/);
await fails(player,"select api.save_training_session($1,6,'','',false,'[]'::jsonb,'[]'::jsonb)",[training],/not_allowed/);
assert.equal((await call(coach,'select api.get_training_session($1)',[training])).revision,6);
console.log('training_session_roster: ok');
await db.close();
