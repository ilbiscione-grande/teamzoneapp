// Webtools Tacticsboard (2026-10-22): the presenter's notes, one per board,
// kept beside the document so participants never get them.
// node supabase/tests/tactics-host-notes.local.mjs
import assert from 'node:assert/strict';
import { host, liveDb, member } from './tactics-live-db.mjs';
const { call, fails } = await liveDb(['20261126090000_tactics_live', '20261127090000_tactics_live_chat',
  '20261128090000_tactics_live_idle', '20261129090000_tactics_live_draw', '20261130090000_tactics_host_notes']);

const project = await call(host, "select api.create_tactics_project('Försvar','education',null,$1)", [JSON.stringify({ schemaVersion: 1, boards: [{ id: 'b1' }] })]);
await call(host, "select api.save_tactics_host_notes($1,'b1',$2)", [project.id, '- Fråga om 6:ans position\n- Visa frame 3 två gånger']);
assert.deepEqual((await call(host, 'select api.get_tactics_project($1)', [project.id])).host_notes, { b1: '- Fråga om 6:ans position\n- Visa frame 3 två gånger' });
await fails(member, "select api.save_tactics_host_notes($1,'b1','Kapat')", [project.id], /not_found/);
await fails(host, "select api.save_tactics_host_notes($1,'b1',$2)", [project.id, 'x'.repeat(5001)], /invalid_notes/);

// A participant joining reads the document, never the notes.
const session = await call(host, 'select api.start_tactics_live($1,true)', [project.id]);
const joined = await call(member, "select api.join_tactics_live($1,'')", [session.code]);
assert.equal(JSON.stringify(joined).includes('6:ans'), false);
assert.equal(joined.host_notes, undefined);

// Empty removes them.
await call(host, "select api.save_tactics_host_notes($1,'b1','  ')", [project.id]);
assert.deepEqual((await call(host, 'select api.get_tactics_project($1)', [project.id])).host_notes, {});
console.log('tactics host notes: ok');
