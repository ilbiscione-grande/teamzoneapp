// Isolated check of 20261001170000_public_club_badge.sql.
// Run: node supabase/tests/public_club_badge.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const pub = '00000000-0000-0000-0000-000000000b1b';
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
await db.exec(`
create schema core; create schema internal; create schema api; create schema public_api;
create role authenticated; create role anon; create role service_role;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table core.clubs(id uuid primary key,status text default 'active',badge_asset_id uuid,brand_primary_color text,brand_accent_color text);
create table core.club_badges(id uuid primary key,club_id uuid,bucket_id text default 'club-badges',object_key text,
  mime_type text,state text);
create table core.club_publication_settings(club_id uuid,public_id uuid);
create table public_api.club_projections(public_id uuid primary key,visibility text,profile_media_path text
  check(profile_media_path is null or profile_media_path ~ '^/media/public/[A-Za-z0-9_-]+$'),primary_color text,accent_color text);
create function internal.apply_publication_projection_job(target_job_id uuid) returns jsonb language plpgsql as $f$
declare club_row core.clubs%rowtype; club_setting core.club_publication_settings%rowtype;
begin
 select * into club_row from core.clubs limit 1; select * into club_setting from core.club_publication_settings limit 1;
 update public_api.club_projections set profile_media_path=null where public_id=club_setting.public_id;
   update public_api.club_projections set primary_color=club_row.brand_primary_color,
    accent_color=club_row.brand_accent_color where public_id=club_setting.public_id;
 return '{}'::jsonb;
end$f$;
insert into core.clubs(id) values('${club}');
insert into core.club_badges(id,club_id,object_key,mime_type,state) values
  ('${id(1)}','${club}','${club}/a.upload','image/png','active'),
  ('${id(2)}','${club}','${club}/b.upload','image/webp','staged');
update core.clubs set badge_asset_id='${id(1)}';
insert into core.club_publication_settings values('${club}','${pub}');
insert into public_api.club_projections(public_id,visibility) values('${pub}','published');
`);
await db.exec(fs.readFileSync('supabase/migrations/20261001170000_public_club_badge.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const path = async () => (await db.query(`select profile_media_path p from public_api.club_projections`)).rows[0].p;
const token = async (n) => (await db.query(`select public_token t from core.club_badges where id=$1`, [id(n)])).rows[0].t;
const resolve = async (t) => (await db.query(`select api.resolve_public_club_badge($1) r`, [t])).rows[0].r;

const first = await token(1);
assert(/^[a-f0-9]{32}$/.test(first) && first !== await token(2), 'each badge gets its own unguessable token');
assert((await path()) === `/media/public/${first}`, 'published club gets its badge on migration');
assert((await resolve(first)).mime_type === 'image/png', 'active badge of a published club resolves');
assert((await resolve(await token(2))).not_found === true, 'a staged badge does not resolve');
await db.exec(`update core.club_badges set state='replaced' where id='${id(1)}';
  update core.club_badges set state='active' where id='${id(2)}';
  update core.clubs set badge_asset_id='${id(2)}'`);
assert((await path()) === `/media/public/${await token(2)}`, 'a new badge updates the page at once');
assert((await resolve(first)).not_found === true, 'the replaced badge address stops working');
await db.query(`select internal.apply_publication_projection_job(gen_random_uuid())`);
assert((await path()) === `/media/public/${await token(2)}`, 'reprojection keeps the badge');
await db.exec(`update public_api.club_projections set visibility='listed'`);
assert((await resolve(await token(2))).not_found === true, 'an unpublished club does not serve its badge');
await db.exec(`update core.clubs set badge_asset_id=null`);
assert((await path()) === null, 'removing the badge clears the page');
const grants = (await db.query(`select has_function_privilege('authenticated','api.resolve_public_club_badge(text)','execute') a`)).rows[0];
assert(!grants.a, 'only the service role resolves badges');
console.log('PASS');
