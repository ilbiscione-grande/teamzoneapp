// Isolated check of 20261002090000_intake_forms.sql.
// Run: node supabase/tests/intake_forms.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const t1 = '00000000-0000-0000-0000-0000000000a1';
const t2 = '00000000-0000-0000-0000-0000000000a2';
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
// Profile 11 administers the club, 12 manages the roster of team 1 only, 13 has no rights.
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api; create schema audit;
create role authenticated; create role anon; create role service_role;
create table auth.actor(id uuid);
create function auth.uid() returns uuid language sql as $$ select id from auth.actor limit 1 $$;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb);
create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,
  aggregate_revision bigint,metadata jsonb);
create table core.profiles(id uuid primary key);
create table core.clubs(id uuid primary key,name text,status text default 'active');
create table core.teams(id uuid primary key,club_id uuid,name text,status text default 'active');
create table core.club_people(id uuid primary key default gen_random_uuid(),club_id uuid,team_id uuid,display_name text,
  birth_year int,birth_date date,contact_email text,phone text,street text,postal text,city text,role text default 'player');
insert into core.profiles values('${id(11)}'),('${id(12)}'),('${id(13)}');
insert into core.clubs(id,name) values('${club}','Klubben');
insert into core.teams(id,club_id,name) values('${t1}','${club}','P14'),('${t2}','${club}','F12');
create function internal.actor_manages_club(c uuid) returns boolean language sql as $f$ select auth.uid()='${id(11)}'::uuid $f$;
create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql as $f$
 select auth.uid()='${id(11)}'::uuid or (auth.uid()='${id(12)}'::uuid and t='${t1}'::uuid and cap='team.roster.manage') $f$;
create function internal.create_roster_person_v3_for_actor(c uuid,t uuid,n text,y int,d date,s timestamptz,k uuid)
returns uuid language plpgsql as $f$ declare p uuid; begin
 insert into core.club_people(club_id,team_id,display_name,birth_year,birth_date) values(c,t,n,y,d) returning id into p; return p; end $f$;
create function internal.set_person_contact_for_actor(c uuid,t uuid,p uuid,e text,ph text) returns void language sql as $f$
 update core.club_people set contact_email=e,phone=ph where id=p $f$;
create function internal.set_person_address_for_actor(c uuid,t uuid,p uuid,s text,pc text,ci text) returns void language sql as $f$
 update core.club_people set street=s,postal=pc,city=ci where id=p $f$;
create function internal.team_role_command(c uuid,t uuid,p uuid,f text,r text,k uuid) returns jsonb language plpgsql as $f$
begin
 if auth.uid()<>'${id(11)}'::uuid then raise insufficient_privilege using message='not_allowed'; end if;
 update core.club_people set role=r where id=p; return '{}'::jsonb; end $f$;
create function internal.normalized_contact(new_email text,new_phone text) returns jsonb language plpgsql immutable as $f$
declare email text:=nullif(lower(btrim(coalesce(new_email,''))),''); phone text:=nullif(btrim(coalesce(new_phone,'')),'');
begin
 if email is not null and email !~* '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$' then raise invalid_parameter_value using message='invalid_email'; end if;
 if phone is not null and phone !~ '^\\+?[0-9 ()-]{5,30}$' then raise invalid_parameter_value using message='invalid_phone'; end if;
 return jsonb_build_object('email',email,'phone',phone);
end $f$;
`);
await db.exec(fs.readFileSync('supabase/migrations/20261002090000_intake_forms.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));
await db.exec(`create function internal.person_in_team(c uuid,t uuid,p uuid) returns boolean language sql as $f$
 select exists(select 1 from core.club_people where id=p and team_id=t) $f$;`);
await db.exec(fs.readFileSync('supabase/migrations/20261002120000_intake_update_existing.sql', 'utf8')
  .replace("notify pgrst,'reload schema';", ''));

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const as = (n) => db.exec(`delete from auth.actor; insert into auth.actor values('${id(n)}')`);
const fails = async (fn, pattern) => { try { await fn(); return false; } catch (e) { return pattern.test(e.message); } };
const overview = async () => (await db.query(`select api.get_intake_overview($1) r`, [club])).rows[0].r;
const submit = (token, overrides = {}) => {
  const v = { name: 'Ada Andersson', phone: '070-123 45 67', email: 'Ada@Mail.se', birth: '2012-05-03',
    street: 'Storgatan 1', postal: '575 31', city: 'Eksjö', ip: 'a'.repeat(64), ...overrides };
  return db.query(`select api.public_submit_intake($1,$2,$3,$4,$5,$6,$7,$8,$9) r`,
    [token, v.name, v.phone, v.email, v.birth, v.street, v.postal, v.city, v.ip]);
};

// Forms.
await as(12);
assert(await fails(() => db.query(`select api.create_intake_form($1,null)`, [club]), /not_found/),
  'a team leader cannot create the club-wide form');
const teamForm = (await db.query(`select api.create_intake_form($1,$2) r`, [club, t1])).rows[0].r;
assert(/^[a-f0-9]{32}$/.test(teamForm.token), 'team form gets an unguessable token');
assert((await db.query(`select api.create_intake_form($1,$2) r`, [club, t1])).rows[0].r.id === teamForm.id,
  'one active form per team');
assert(await fails(() => db.query(`select api.create_intake_form($1,$2)`, [club, t2]), /not_found/),
  'no form for a team you do not manage');
await as(11);
const clubForm = (await db.query(`select api.create_intake_form($1,null) r`, [club])).rows[0].r;

// Public side (the site's server runs as the service role; here the owner).
const form = (await db.query(`select api.public_get_intake_form($1) r`, [teamForm.token])).rows[0].r;
assert(form.club_name === 'Klubben' && form.team_name === 'P14', 'form shows club and team');
assert((await db.query(`select api.public_get_intake_form('x') r`)).rows[0].r.not_found, 'unknown token not found');
assert((await submit(teamForm.token)).rows[0].r.accepted, 'submission accepted');
await submit(clubForm.token, { name: 'Bo Berg', ip: 'b'.repeat(64) });
assert(await fails(() => submit(teamForm.token, { email: 'inte-en-adress', ip: 'c'.repeat(64) }), /invalid_email/), 'bad email refused');
assert(await fails(() => submit(teamForm.token, { birth: '2999-01-01', ip: 'c'.repeat(64) }), /invalid_request/), 'future birth date refused');
for (let i = 0; i < 5; i++) await submit(teamForm.token, { name: `Spam ${i}`, ip: 'd'.repeat(64) });
assert(await fails(() => submit(teamForm.token, { ip: 'd'.repeat(64) }), /rate_limited/), 'five per hour and address');
const grants = (await db.query(`select has_function_privilege('authenticated','api.public_submit_intake(text,text,text,text,date,text,text,text,text)','execute') a`)).rows[0];
assert(!grants.a, 'signed-in users cannot submit directly');

// Overview and visibility.
let o = await overview();
assert(o.can_manage_club && o.teams.length === 2 && o.forms.length === 2 && o.submissions.length === 7, 'club admin sees everything');
assert(o.submissions.find((s) => s.full_name === 'Ada Andersson').email === 'ada@mail.se', 'email normalised');
await as(12);
o = await overview();
assert(!o.can_manage_club && o.teams.length === 1 && o.teams[0].name === 'P14', 'team leader adds only to own team');
assert(o.submissions.length === 7, 'team leader sees own team and club-wide submissions');
await as(13);
assert(await fails(() => overview(), /not_found/), 'no rights, no overview');

// Accept and dismiss.
await as(12);
const ada = o.submissions.find((s) => s.full_name === 'Ada Andersson').id;
const bo = o.submissions.find((s) => s.full_name === 'Bo Berg').id;
assert(await fails(() => db.query(`select api.accept_intake_submission($1,$2,'player',gen_random_uuid())`, [ada, t2]), /not_found/),
  'cannot add to a team you do not manage');
const key = '00000000-0000-0000-0000-00000000ee01';
const person = (await db.query(`select api.accept_intake_submission($1,$2,'player',$3) r`, [ada, t1, key])).rows[0].r;
const row = (await db.query(`select * from core.club_people where id=$1`, [person])).rows[0];
assert(row.team_id === t1 && row.birth_year === 2012 && row.contact_email === 'ada@mail.se' && row.city === 'Eksjö',
  'person created in the team with contact details and address');
assert((await db.query(`select api.accept_intake_submission($1,$2,'player',$3) r`, [ada, t1, key])).rows[0].r === person,
  'a retry returns the same person');
assert((await db.query(`select count(*)::int n from core.intake_submissions where id=$1`, [ada])).rows[0].n === 0,
  'handled submission is deleted');
assert(await fails(() => db.query(`select api.accept_intake_submission($1,$2,'leader',gen_random_uuid())`, [bo, t1]), /not_allowed/),
  'leader role needs the right to manage leaders');
await as(11);
const leader = (await db.query(`select api.accept_intake_submission($1,$2,'leader',gen_random_uuid()) r`, [bo, t2])).rows[0].r;
assert((await db.query(`select role from core.club_people where id=$1`, [leader])).rows[0].role === 'leader', 'added as leader');
const spam = (await overview()).submissions.find((s) => s.full_name === 'Spam 0').id;
await db.query(`select api.dismiss_intake_submission($1)`, [spam]);
assert((await overview()).submissions.length === 4, 'dismissed submission removed');
// Pages expire after 14 days; a new one can then be created.
const expiry = (await db.query(`select round(extract(epoch from expires_at-created_at)/86400)::int d from core.intake_forms where id=$1`, [clubForm.id])).rows[0].d;
assert(expiry === 14, 'pages are valid for 14 days');
await db.exec(`update core.intake_forms set expires_at=now()-interval '1 minute' where id='${clubForm.id}'`);
assert((await db.query(`select api.public_get_intake_form($1) r`, [clubForm.token])).rows[0].r.not_found, 'an expired page is closed');
assert((await submit(clubForm.token, { ip: 'e'.repeat(64) })).rows[0].r.not_found, 'an expired page takes no submissions');
assert(!(await overview()).forms.some((f) => f.id === clubForm.id), 'an expired page is not listed');
const renewed = (await db.query(`select api.create_intake_form($1,null) r`, [club])).rows[0].r;
assert(renewed.id !== clubForm.id && renewed.expires_at, 'a new page replaces the expired one');
await db.query(`select api.close_intake_form($1)`, [teamForm.id]);
assert((await db.query(`select api.public_get_intake_form($1) r`, [teamForm.token])).rows[0].r.not_found, 'closed form stops working');
// Update an existing person instead of creating one.
await as(12);
const existing = (await db.query(`insert into core.club_people(club_id,team_id,display_name,birth_year,phone)
  values($1,$2,'Ada A.',2012,'0700000000') returning id`, [club, t1])).rows[0].id;
const renewedToken = (await db.query(`select public_token t from core.intake_forms where id=$1`, [renewed.id])).rows[0].t;
await submit(renewedToken, { name: 'Ada Andersson', phone: '070-999 99 99', ip: 'f'.repeat(64) });
const pending = (await overview()).submissions.find((x) => x.phone === '070-999 99 99').id;
assert(await fails(() => db.query(`select api.update_person_from_intake($1,$2,$3)`, [pending, t1, leader]), /not_found/),
  'only a person in the chosen team can be updated');
await db.query(`select api.update_person_from_intake($1,$2,$3)`, [pending, t1, existing]);
const merged = (await db.query(`select * from core.club_people where id=$1`, [existing])).rows[0];
assert(merged.phone === '070-999 99 99' && merged.contact_email === 'ada@mail.se' && merged.city === 'Eksjö',
  'contact details and address replaced');
assert(merged.display_name === 'Ada A.' && merged.birth_date !== null, 'name kept, missing birth date filled in');
assert((await db.query(`select count(*)::int n from core.intake_submissions where id=$1`, [pending])).rows[0].n === 0,
  'merged submission is deleted');
console.log('PASS');
