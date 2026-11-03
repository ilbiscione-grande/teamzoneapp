// Tacticsboard's lock without a trial or subscription (20270206090000).
// 1. Every gated API function's latest definition, across all migrations,
//    still calls internal.require_tacticsboard (a later create or replace
//    must not drop the lock without anyone noticing).
// 2. In PGlite: locked before the trial, open during it, locked after; a
//    shared link and a running live lesson keep working.
// node supabase/tests/tacticsboard_write_gate.local.mjs
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { host, liveDb, member } from './tactics-live-db.mjs';

const dir = new URL('../migrations/', import.meta.url);
const gate = readFileSync(new URL('20270206090000_tacticsboard_write_gate.sql', dir), 'utf8');
const gated = [...gate.matchAll(/create or replace function api\.([a-z_]+)\(/g)].map(m => m[1]);
assert.ok(gated.length >= 44, `gated ${gated.length}`);
for (const name of ['create_tactics_project', 'save_tactics_project', 'get_tactics_project', 'list_my_tactics_projects',
  'publish_tactics_item', 'start_tactics_live', 'create_tactics_share_link', 'search_tactics_shared_items']) {
  assert.ok(gated.includes(name), `${name} is gated`);
}
for (const name of ['get_shared_tactics', 'get_shared_tactics_folder', 'join_tactics_live', 'revoke_tactics_share_link',
  'unshare_tactics_item', 'end_tactics_live']) {
  assert.ok(!gated.includes(name), `${name} stays open`);
}
const latest = new Map();
for (const file of readdirSync(dir).filter(f => f.endsWith('.sql')).sort()) {
  const sql = readFileSync(new URL(file, dir), 'utf8');
  for (const m of sql.matchAll(/create (?:or replace )?function api\.([a-z_]+)\([\s\S]*?\$\$([\s\S]*?)\$\$/g)) latest.set(m[1], { file, body: m[2] });
}
for (const name of gated) {
  assert.match(latest.get(name).body, /internal\.require_tacticsboard\(\)/, `${name} lost its lock in ${latest.get(name).file}`);
}
// A new Tacticsboard API function must be placed on one side or the other.
const known = new Set([...gated, 'get_shared_tactics', 'get_shared_tactics_folder', 'get_shared_tactics_folder_project',
  'decide_tactics_shared_reports', 'list_tactics_shared_reports', 'get_tactics_shared_report_item', 'revoke_tactics_share_link', 'revoke_tactics_folder_share_link',
  'unshare_tactics_item']);
for (const name of latest.keys()) {
  if (!/tactics/.test(name) || /tacticsboard/.test(name) || (/live/.test(name) && name !== 'start_tactics_live')) continue;
  assert.ok(known.has(name), `api.${name} is new: gate it in a migration or add it to the open list here`);
}

const { db, as, asRole, call, fails } = await liveDb(['20261124090000_tactics_share_links', '20261126090000_tactics_live']);
await db.exec(`rollback; create schema audit; create table audit.command_events(id bigserial, club_id uuid, actor_profile_id uuid,
  command_type text, aggregate_type text, aggregate_id uuid, metadata jsonb); create schema extensions;`);
for (const name of ['20270204090000_tacticsboard_personal_billing', '20270205090000_tacticsboard_personal_checkout',
  '20270206090000_tacticsboard_write_gate']) await db.exec(readFileSync(new URL(`${name}.sql`, dir), 'utf8'));
await db.exec('begin');
const document = JSON.stringify({ schemaVersion: 1, boards: [{ id: 'b1' }] });

// Before the trial: locked, also for reading one's own list.
await fails(host, "select api.create_tactics_project('Försvar','education',null,$1)", [document], /tacticsboard_locked/);
await fails(host, 'select api.list_my_tactics_projects()', [], /tacticsboard_locked/);

// During the trial: everything.
await call(host, 'select api.start_tacticsboard_trial()');
const project = await call(host, "select api.create_tactics_project('Försvar','education',null,$1)", [document]);
const link = await call(host, "select api.create_tactics_share_link($1,'b1')", [project.id]);
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);

// After it: the owner is locked out, but the link and the running lesson still work for others.
await db.exec(`update core.personal_billing_accounts set trial_started_at = now() - interval '8 days', trial_ends_at = now() - interval '1 day'`);
await fails(host, 'select api.get_tactics_project($1)', [project.id], /tacticsboard_locked/);
await fails(host, 'select api.save_tactics_project($1,1,$2,$3,null,$4)', [project.id, 'Nytt', 'education', document], /tacticsboard_locked/);
await fails(host, 'select api.start_tactics_live($1,true)', [project.id], /tacticsboard_locked/);
// Webtools reads a shared link on the server, as service_role.
await as(null);
assert.ok((await asRole('service_role', () => db.query('select api.get_shared_tactics($1) r', [link.token ?? link]))).rows[0].r);
assert.ok(await call(member, "select api.join_tactics_live($1,'')", [session.code]));
await call(host, 'select api.end_tactics_live($1)', [session.id]);

// The signed-out keep getting the inner function's own answer.
await fails(null, "select api.create_tactics_project('x','education',null,$1)", [document], /not_signed_in/);
assert.deepEqual(await call(null, 'select api.list_my_tactics_projects()'), []);
await db.exec('rollback');
console.log('tacticsboard write gate: ok');
