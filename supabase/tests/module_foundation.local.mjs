// Module foundation (2026-10-23, decision package 11): a club's access to
// the modules, beta open to all, bought or ended, and each area's level.
// node supabase/tests/module_foundation.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), outsider = id(2), club = id(10), otherClub = id(11), team = id(20);
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.club_entitlements(club_id uuid, entitlement_key text, access_mode text, expires_at timestamptz);
create function internal.actor_has_club_access(target uuid) returns boolean language sql stable as $$
  select auth.uid() = '${coach}'::uuid and target = '${club}'::uuid $$;
grant usage on schema api, internal, core, auth to authenticated;`);
await db.exec(read('supabase/migrations/20261202090000_module_foundation.sql'));
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try { return Object.values((await db.query(sql, params)).rows[0] ?? {})[0]; } finally { await db.exec('reset role'); }
};
const access = (target, key) => db.query('select internal.club_module_access($1,$2) v', [target, key]).then(r => r.rows[0].v);

// In beta every module is open to every club; the Tacticsboard link is not yet.
assert.equal(await access(otherClub, 'module.match_workspace'), 'write');
assert.equal(await access(club, 'webtool.tacticsboard_link'), 'none');
assert.equal(await access(club, 'module.unknown'), 'none');

// Out of beta: what the club bought, read-only once it has ended, nothing otherwise.
await db.exec("update core.module_catalog set beta_open = false where key = 'module.training'");
assert.equal(await access(club, 'module.training'), 'none');
await db.query("insert into core.club_entitlements values ($1,'module.training','write',null)", [club]);
assert.equal(await access(club, 'module.training'), 'write');
await db.exec("update core.club_entitlements set expires_at = now() - interval '1 day'");
assert.equal(await access(club, 'module.training'), 'read_only', 'ended: kept readable, never deleted');
await db.exec("update core.club_entitlements set access_mode = 'denied'");
assert.equal(await access(club, 'module.training'), 'none');

// A team's modules and levels, for people of the club only.
const modules = await call(coach, 'select api.get_team_modules($1)', [team]);
assert.deepEqual(modules.modules.map(m => [m.key, m.access]), [
  ['module.match_workspace', 'write'], ['module.team_development', 'write'], ['module.training', 'none'],
  ['module.player_development', 'write'], ['webtool.tacticsboard_link', 'none']]);
assert.deepEqual(modules.levels, {
  lineup: 'module', match_preparation: 'module', match_followup: 'module',
  team_development: 'module', training: 'base', player_development: 'module' });
await assert.rejects(call(outsider, 'select api.get_team_modules($1)', [team]), /not_found/);

// With the Tacticsboard link open, its areas move up; the match follow-up stays with the module.
await db.exec("update core.module_catalog set beta_open = true where key = 'webtool.tacticsboard_link'");
const linked = await call(coach, 'select api.get_team_modules($1)', [team]);
assert.deepEqual([linked.levels.lineup, linked.levels.training, linked.levels.match_followup], ['tacticsboard', 'tacticsboard', 'module']);
console.log('module foundation: ok');
