// Tacticsboard's leader access (20270102090000), in isolated Postgres with a
// reduced schema. node supabase/tests/tactics_leader_access.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const owner = id(1), coach = id(2), stranger = id(3), team = id(20), otherTeam = id(21);
const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who ?? '']);
const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
const call = async (who, sql, params = []) => { await as(who); return asRole('authenticated', async () => Object.values((await db.query(sql, params)).rows[0] ?? {})[0]); };
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.profiles(id uuid primary key, display_name text not null default '');
insert into core.profiles values ('${owner}','Ägaren'),('${coach}','Anna'),('${stranger}','Någon annan');
create table core.teams(id uuid primary key, name text);
insert into core.teams values ('${team}','P2012'),('${otherTeam}','F2013');
-- Who leads which team: the owner and the coach lead P2012, the stranger F2013.
create table core.test_leaders(profile_id uuid, team_id uuid);
insert into core.test_leaders values ('${owner}','${team}'),('${coach}','${team}'),('${stranger}','${otherTeam}');
create function internal.tournament_actor_teams() returns table(team_id uuid, team_name text, club_id uuid, club_name text) language sql stable security definer set search_path = '' as
  $$select leader.team_id, null::text, null::uuid, null::text from core.test_leaders leader where leader.profile_id = auth.uid()$$;
grant usage on schema api, internal, core, auth to authenticated;`);
for (const file of ['20261123090000_tacticsboard', '20261130090000_tactics_host_notes', '20270101090000_tactics_versions', '20270102090000_tactics_leader_access']) {
  await db.exec(read(`supabase/migrations/${file}.sql`));
}
await db.exec('begin');

const doc = boards => JSON.stringify({ version: 1, boards: boards.map(name => ({ id: name, name })) });
const project = (await call(owner, 'select api.create_tactics_project($1,$2,$3,$4::jsonb)', ['Spelidé', 'match', team, doc(['A'])])).id;
const mine = (await call(owner, 'select api.create_tactics_project($1,$2,$3,$4::jsonb)', ['Utan lag', 'match', null, doc(['A'])])).id;
await call(owner, 'select api.save_tactics_host_notes($1,$2,$3)', [project, 'A', 'Bara för mig']);
const save = (who, revision, boards, name = 'Spelidé', target = project, teamId = team) =>
  call(who, 'select api.save_tactics_project($1,$2,$3,$4,$5,$6::jsonb)', [target, revision, name, 'match', teamId, doc(boards)]);
const get = (who, target = project) => call(who, 'select api.get_tactics_project($1)', [target]);

// The team's other leader sees it in the team's list and reads it, without the owner's notes.
let listed = await call(coach, 'select api.list_team_tactics_projects()');
assert.deepEqual(listed.map(item => [item.name, item.access, item.owner_name]), [['Spelidé', 'view', 'Ägaren']]);
assert.deepEqual(await call(owner, 'select api.list_team_tactics_projects()'), [], 'the owner sees it under their own');
assert.deepEqual(await call(stranger, 'select api.list_team_tactics_projects()'), []);
let seen = await get(coach);
assert.equal(seen.access, 'view');
assert.deepEqual(seen.host_notes, {});
assert.equal((await get(owner)).access, 'owner');
assert.deepEqual((await get(owner)).host_notes, { A: 'Bara för mig' });

// Others never: not a leader of the team, nor a project without a team.
await fails(stranger, 'select api.get_tactics_project($1)', [project], /not_found/);
await fails(coach, 'select api.get_tactics_project($1)', [mine], /not_found/);

// Watching, the leader cannot save, see the versions or set the access.
await fails(coach, 'select api.save_tactics_project($1,$2,$3,$4,$5,$6::jsonb)', [project, seen.revision, 'X', 'match', team, doc(['B'])], /not_found/);
await fails(coach, 'select api.list_tactics_versions($1)', [project], /not_found/);
await fails(coach, 'select api.set_tactics_leader_access($1,$2)', [project, 'edit'], /not_found/);
await fails(owner, 'select api.set_tactics_leader_access($1,$2)', [project, 'all'], /invalid_access/);

// The owner lets the team's leaders edit: the leader saves the boards, never the name, kind or team.
await call(owner, 'select api.set_tactics_leader_access($1,$2)', [project, 'edit']);
seen = await get(coach);
assert.equal(seen.access, 'edit');
let revision = Number(await save(coach, seen.revision, ['A', 'B'], 'Omdöpt', project, null));
seen = await get(owner);
assert.equal(seen.name, 'Spelidé');
assert.equal(seen.teamzone_team_id, team);
assert.deepEqual(seen.document.boards.map(board => board.name), ['A', 'B']);
assert.deepEqual(seen.host_notes, { A: 'Bara för mig' }, 'the notes stay');

// Two at once: the later save is refused, not merged.
revision = Number(await save(owner, revision, ['A', 'B', 'C']));
await fails(coach, 'select api.save_tactics_project($1,$2,$3,$4,$5,$6::jsonb)', [project, revision - 1, 'Spelidé', 'match', team, doc(['A'])], /stale_revision/);

// The leader's save kept the owner's content as a version; the leader sees them but cannot put one back.
const versions = await call(coach, 'select api.list_tactics_versions($1)', [project]);
assert.ok(versions.some(version => version.reason === 'other_editor'));
assert.ok(await call(coach, 'select api.get_tactics_version($1)', [versions[0].id]));
await fails(coach, 'select api.restore_tactics_version($1,$2)', [versions[0].id, revision], /not_found/);

// Notes, removal and sharing stay the owner's.
await fails(coach, 'select api.save_tactics_host_notes($1,$2,$3)', [project, 'A', 'Mitt'], /not_found/);
await fails(coach, 'select api.delete_tactics_project($1)', [project], /not_found/);

// Moved to another team, the old team's leaders lose it.
await save(owner, revision, ['A'], 'Spelidé', project, null);
await fails(coach, 'select api.get_tactics_project($1)', [project], /not_found/);
assert.deepEqual(await call(coach, 'select api.list_team_tactics_projects()'), []);

await db.exec('rollback');
console.log('tactics_leader_access.local: ok');
