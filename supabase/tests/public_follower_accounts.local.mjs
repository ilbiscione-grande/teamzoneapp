// Isolated check of 20261001120000_public_follower_accounts.sql.
// Run: node supabase/tests/public_follower_accounts.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
await db.exec(`
create schema core; create schema internal; create schema api; create schema audit;
create role authenticated; create role anon; create role service_role;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,
  aggregate_revision int,metadata jsonb);
create table core.profiles(id uuid primary key,created_at timestamptz default now(),updated_at timestamptz,revision int default 1);
create table core.person_account_links(profile_id uuid,club_person_id uuid,state text);
create table internal.legal_document_versions(document_type text,version text,active boolean);
create table core.legal_acceptances(profile_id uuid,document_type text,document_version text,source text,
  primary key(profile_id,document_type,document_version));
create table core.communication_preferences(profile_id uuid primary key,marketing_opt_in boolean);
insert into internal.legal_document_versions values('terms','2026-09-11',true),('privacy','2026-09-11',true),('terms','2026-08-24',false);
insert into core.profiles(id) values('${id(1)}'),('${id(2)}');
insert into core.profiles(id,created_at) values('${id(3)}',now()-interval '1 day');
insert into core.person_account_links values('${id(2)}','${id(22)}','active');
`);
await db.exec(fs.readFileSync('supabase/migrations/20261001120000_public_follower_accounts.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const mark = async (n, legal = true) => (await db.query(`select api.mark_public_follower_account($1,$2) r`, [id(n), legal])).rows[0].r;
const type = async (n) => (await db.query(`select account_type from core.profiles where id=$1`, [id(n)])).rows[0].account_type;

assert((await type(1)) === 'member', 'accounts are members by default');
let refused = false;
try { await mark(1, false); } catch (e) { refused = /legal_required/.test(e.message); }
assert(refused, 'terms and privacy must be accepted');
assert((await mark(1)).marked === true && (await type(1)) === 'follower', 'new public account becomes a follower');
const accepted = (await db.query(`select document_type,document_version,source from core.legal_acceptances where profile_id=$1 order by 1`, [id(1)])).rows;
assert(accepted.length === 2 && accepted.every(row => row.document_version === '2026-09-11' && row.source === 'web'),
  'current terms and privacy recorded as accepted on the web');
assert((await mark(2)).marked === false && (await type(2)) === 'member', 'an account in a club is never changed');
assert((await mark(3)).marked === false && (await type(3)) === 'member', 'an older account is never changed');
await db.exec(`insert into core.person_account_links values('${id(1)}','${id(21)}','pending')`);
assert((await type(1)) === 'follower', 'a pending link keeps the follower');
await db.exec(`update core.person_account_links set state='active' where profile_id='${id(1)}'`);
assert((await type(1)) === 'member', 'joining a club makes the follower a member');
const grants = (await db.query(`select has_function_privilege('authenticated','api.mark_public_follower_account(uuid,boolean)','execute') a,
  has_function_privilege('service_role','api.mark_public_follower_account(uuid,boolean)','execute') s`)).rows[0];
assert(!grants.a && grants.s, 'only the service role can mark follower accounts');
console.log('PASS');
