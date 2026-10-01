// Isolated check of 20261001090000_club_brand_colors.sql.
// Run: node supabase/tests/club_brand_colors.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const pub = '00000000-0000-0000-0000-000000000b1b';
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
// Profile 11 administers the club; profile 12 does not.
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api; create schema public_api; create schema audit;
create role authenticated; create role anon;
create table auth.actor(id uuid);
create function auth.uid() returns uuid language sql as $$ select id from auth.actor limit 1 $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,
  aggregate_revision int,metadata jsonb);
create table core.clubs(id uuid primary key,name text,revision int default 1);
create table core.club_publication_settings(club_id uuid,public_id uuid);
create table public_api.club_projections(public_id uuid primary key,name text,official boolean);
create function internal.actor_is_club_admin(c uuid) returns boolean language sql as $$ select auth.uid()='${id(11)}'::uuid $$;
create function internal.apply_publication_projection_job(target_job_id uuid) returns jsonb language plpgsql as $f$
declare club_row core.clubs%rowtype; club_setting core.club_publication_settings%rowtype;
begin
 select * into club_row from core.clubs limit 1; select * into club_setting from core.club_publication_settings limit 1;
 insert into public_api.club_projections(public_id,name,official) values(club_setting.public_id,club_row.name,false)
 on conflict(public_id) do update set name=excluded.name,
  official=excluded.official,visibility=excluded.visibility;
 return '{}'::jsonb;
end$f$;
create function internal.public_get_club(slug text,ip_hash text) returns jsonb language sql as $f$
 select jsonb_build_object('name',club.name,'official',club.official,'teams','[]'::jsonb)
 from public_api.club_projections club limit 1 $f$;
insert into core.clubs(id,name) values('${club}','Klubben');
insert into core.club_publication_settings values('${club}','${pub}');
insert into public_api.club_projections values('${pub}','Klubben',false);
`);
// The stub's "visibility" column is only referenced by the patched text.
await db.exec(`alter table public_api.club_projections add column visibility text`);
await db.exec(fs.readFileSync('supabase/migrations/20261001090000_club_brand_colors.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const as = (n) => db.exec(`delete from auth.actor; insert into auth.actor values('${id(n)}')`);
const fails = async (sql, params, pattern) => { try { await db.query(sql, params); return false; } catch (e) { return pattern.test(e.message); } };

await as(11);
const set = await db.query(`select api.set_club_colors($1,$2,$3) r`, [club, '#0A3D2A', ' #FFD100 ']);
assert(set.rows[0].r.primary === '#0a3d2a' && set.rows[0].r.accent === '#ffd100', 'admin sets colours, normalised');
const projected = (await db.query(`select primary_color,accent_color from public_api.club_projections`)).rows[0];
assert(projected.primary_color === '#0a3d2a' && projected.accent_color === '#ffd100', 'published page gets them straight away');
const page = (await db.query(`select internal.public_get_club('x','y') r`)).rows[0].r;
assert(page.primary_color === '#0a3d2a' && page.accent_color === '#ffd100', 'public read returns them');
assert((await db.query(`select api.get_club_colors($1) r`, [club])).rows[0].r.accent === '#ffd100', 'admin reads them');
assert(await fails(`select api.set_club_colors($1,$2,$3)`, [club, 'red', null], /invalid_color/), 'non-hex refused');
assert(await fails(`select api.set_club_colors($1,$2,$3)`, [club, '#000000;}body{', null], /invalid_color/), 'css injection refused');
await db.query(`select api.set_club_colors($1,$2,$3)`, [club, null, '']);
assert((await db.query(`select primary_color from public_api.club_projections`)).rows[0].primary_color === null, 'colours can be cleared');
await db.query(`select api.set_club_colors($1,$2,$3)`, [club, '#112233', '#445566']);
await db.exec(`update public_api.club_projections set primary_color=null,accent_color=null`);
await db.query(`select internal.apply_publication_projection_job(gen_random_uuid())`);
assert((await db.query(`select primary_color from public_api.club_projections`)).rows[0].primary_color === '#112233', 'reprojection copies colours');
await as(12);
assert(await fails(`select api.set_club_colors($1,$2,$3)`, [club, '#000000', null], /club_admin_required/), 'non-admin refused');
assert(await fails(`select api.get_club_colors($1)`, [club], /club_admin_required/), 'non-admin cannot read');
console.log('PASS');
