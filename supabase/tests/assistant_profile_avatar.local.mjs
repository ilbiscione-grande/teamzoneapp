import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const actor = '00000000-0000-0000-0000-000000000001';
const other = '00000000-0000-0000-0000-000000000002';
const value = async (sql, params = []) => (await db.query(sql, params)).rows[0].value;
const load = () => value('select api.get_assistant_preference() value');
const saveAvatar = (key, revision, command) => value(
  'select api.set_assistant_avatar($1,$2,$3) value',
  [key, revision, command],
);

try {
  await db.exec(`
    create schema core; create schema internal; create schema api; create schema auth;
    create role anon; create role authenticated;
    create table core.profiles(id uuid primary key);
    insert into core.profiles values('${actor}'),('${other}');
    create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
    create table internal.command_deduplication(
      actor_profile_id uuid not null,
      idempotency_key uuid not null,
      command_type text not null,
      result jsonb not null,
      primary key(actor_profile_id,idempotency_key,command_type)
    );
    create function auth.uid() returns uuid language sql as $$
      select nullif(current_setting('test.actor',true),'')::uuid
    $$;
    select set_config('test.actor','${actor}',false);
  `);
  await db.exec(fs.readFileSync('supabase/migrations/20260828160052_ac04_assistant_identity_preferences.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261003070703_assistant_profile_avatar.sql','utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261003072031_expand_assistant_profile_avatars.sql','utf8'));

  assert.deepEqual(await load(), {custom_name:null, avatar_key:null, revision:0});
  const woman = await saveAvatar('woman', 0, '10000000-0000-0000-0000-000000000001');
  assert.deepEqual(woman, {custom_name:null, avatar_key:'woman', revision:1});
  assert.deepEqual(
    await saveAvatar('woman', 0, '10000000-0000-0000-0000-000000000001'),
    woman,
    'idempotent retry',
  );
  await assert.rejects(
    saveAvatar('man', 0, '10000000-0000-0000-0000-000000000002'),
    /stale_revision/,
  );
  await assert.rejects(
    saveAvatar('unknown', 1, '10000000-0000-0000-0000-000000000003'),
    /invalid_assistant_avatar/,
  );
  const named = await value(
    "select api.set_assistant_name('Nova',1,'10000000-0000-0000-0000-000000000004') value",
  );
  assert.equal(named.revision, 2);
  assert.deepEqual(await load(), {custom_name:'Nova', avatar_key:'woman', revision:2});
  assert.deepEqual(
    await saveAvatar('man_3', 2, '10000000-0000-0000-0000-000000000007'),
    {custom_name:'Nova', avatar_key:'man_3', revision:3},
    'additional avatar option',
  );
  assert.deepEqual(
    await saveAvatar(null, 3, '10000000-0000-0000-0000-000000000005'),
    {custom_name:'Nova', avatar_key:null, revision:4},
    'restore standard avatar',
  );

  await db.query("select set_config('test.actor',$1,false)", [other]);
  assert.deepEqual(await load(), {custom_name:null, avatar_key:null, revision:0});
  await db.query("select set_config('test.actor','',false)");
  assert.equal(await load(), null, 'unauthenticated read reveals no preference');
  await assert.rejects(
    saveAvatar('man', 0, '10000000-0000-0000-0000-000000000006'),
    /unauthenticated/,
  );
  const acl = await value(`select jsonb_build_object(
    'anon',has_function_privilege('anon','api.set_assistant_avatar(text,bigint,uuid)','execute'),
    'authenticated',has_function_privilege('authenticated','api.set_assistant_avatar(text,bigint,uuid)','execute'),
    'table',has_table_privilege('authenticated','core.assistant_preferences','select,insert,update,delete')
  ) value`);
  assert.deepEqual(acl, {anon:false, authenticated:true, table:false});
  console.log('PASS: assistant avatar persistence, retry, validation, revision, isolation, reset and ACL');
} finally {
  await db.close();
}
