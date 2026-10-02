// Isolated check of the profile migrations (contact, name sync, member card).
// Run: node supabase/tests/profile_contact.local.mjs
import fs from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const club = '00000000-0000-0000-0000-000000000c1b';
const team = '00000000-0000-0000-0000-0000000000a1';
const otherTeam = '00000000-0000-0000-0000-0000000000a2';
const id = (n) => `00000000-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
// Profiles: 11 leader, 12 player with account, 13 teammate, 14 support, 15 outsider.
// Club people: 21 leader, 22 player (account 12), 23 teammate (account 13), 24 player without account,
// 25 player in another team.
await db.exec(`
create schema core; create schema internal; create schema auth; create schema api; create schema storage; create schema audit;
create role authenticated; create role anon;
create table auth.actor(id uuid);
create function auth.uid() returns uuid language sql as $$ select id from auth.actor limit 1 $$;
create table auth.users(id uuid primary key,email text);
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(bucket_id text,name text);
alter table storage.objects enable row level security;
create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb);
create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,
  aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
create table core.profiles(id uuid primary key,display_name text not null default '',updated_at timestamptz,
  revision bigint not null default 1);
create table core.club_people(id uuid primary key,club_id uuid,display_name text,revision bigint default 1,
  status text default 'active',birth_year smallint,created_at timestamptz default now());
create table core.clubs(id uuid primary key,name text);
create table core.teams(id uuid primary key,club_id uuid,name text);
create table core.team_person_details(club_id uuid,team_id uuid,club_person_id uuid,functions text[] default '{}',
  custom_titles text[] default '{}');
create table core.guardian_relations(club_id uuid,guardian_person_id uuid,child_person_id uuid,state text default 'active');
create table core.person_account_links(club_person_id uuid,club_id uuid,profile_id uuid,state text default 'active',
  created_at timestamptz default now());
create table core.assignments(club_id uuid,club_person_id uuid,team_id uuid,role_package text,state text default 'active',
  starts_at timestamptz default now()-interval '1 day',ends_at timestamptz);
create table core.team_assignments(club_id uuid,club_person_id uuid,team_id uuid,state text default 'active');
-- Profile 16 administers the club.
create function internal.actor_has_capability(c uuid,t uuid,cap text) returns boolean language sql as $$
  select auth.uid()='00000000-0000-0000-0000-000000000016'::uuid and cap='club.memberships.manage' $$;
create function internal.actor_has_club_access(c uuid) returns boolean language sql as $$
  select exists(select 1 from core.person_account_links where profile_id=auth.uid() and club_id=c and state='active') $$;
create function internal.actor_owns_club_person(c uuid,p uuid) returns boolean language sql as $$
  select exists(select 1 from core.person_account_links where profile_id=auth.uid() and club_person_id=p) $$;
create function internal.actor_is_support_admin() returns boolean language sql as $$ select auth.uid()='${id(14)}'::uuid $$;
insert into auth.users values('${id(11)}','leader@x.se'),('${id(12)}','ada@x.se'),('${id(13)}','bo@x.se'),
  ('${id(14)}','support@x.se'),('${id(15)}','out@x.se');
insert into core.profiles(id,display_name) values('${id(11)}','Lars'),('${id(12)}','Ada'),('${id(13)}','Bo'),
  ('${id(14)}','Sam'),('${id(15)}','Olle');
insert into core.club_people(id,club_id,display_name) values('${id(21)}','${club}','Lars'),('${id(22)}','${club}','Ada'),
  ('${id(23)}','${club}','Bo'),('${id(24)}','${club}','Cia'),('${id(25)}','${club}','Dan');
insert into core.clubs values('${club}','Alby IF');
insert into core.teams values('${team}','${club}','F2012');
insert into core.club_people(id,club_id,display_name) values('${id(26)}','${club}','Gun');
insert into core.assignments(club_id,club_person_id,team_id,role_package) values('${club}','${id(26)}','${team}','guardian');
insert into core.guardian_relations(club_id,guardian_person_id,child_person_id) values('${club}','${id(26)}','${id(22)}');
insert into core.team_person_details(club_id,team_id,club_person_id,functions) values('${club}','${team}','${id(21)}','{head_coach}');
insert into core.profiles(id,display_name) values('${id(16)}','Admin');
insert into core.person_account_links(club_person_id,club_id,profile_id) values
  ('${id(21)}','${club}','${id(11)}'),('${id(22)}','${club}','${id(12)}'),('${id(23)}','${club}','${id(13)}'),
  ('${id(26)}','${club}','${id(16)}');
insert into core.assignments(club_id,club_person_id,team_id,role_package) values('${club}','${id(21)}','${team}','leader');
insert into core.team_assignments(club_id,club_person_id,team_id) values('${club}','${id(22)}','${team}'),
  ('${club}','${id(23)}','${team}'),('${club}','${id(24)}','${team}'),('${club}','${id(25)}','${otherTeam}');
`);
for (const file of ['20260930120000_profile_contact_avatar.sql', '20260930140000_profile_name_to_club_records.sql',
  '20260930150000_member_card.sql']) {
  await db.exec(fs.readFileSync('supabase/migrations/' + file, 'utf8').replace("notify pgrst,'reload schema';", ''));
}

const assert = (ok, msg) => { if (!ok) throw new Error(msg); console.log('ok -', msg); };
const as = (n) => db.exec(`delete from auth.actor; insert into auth.actor values('${id(n)}')`);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const refused = async (sql, params = [], pattern = /./) => {
  try { await db.query(sql, params); return false; } catch (e) { return pattern.test(e.message); }
};
const key = () => crypto.randomUUID();

// Own profile.
await as(12);
let rev = await one(`select api.update_my_profile_details('Ada Andersson','  Ada@Mail.se ','070-123 45 67','keep',null,1,$1)`, [key()]);
let me = await one(`select api.get_my_profile_details()`);
assert(rev === 2 && me.display_name === 'Ada Andersson' && me.contact_email === 'ada@mail.se'
  && me.phone === '070-123 45 67' && me.login_email === 'ada@x.se', 'own profile saves name, email, phone');
const names = Object.fromEntries((await db.query('select id,display_name from core.club_people')).rows.map((r) => [r.id, r.display_name]));
assert(names[id(22)] === 'Ada Andersson' && names[id(23)] === 'Bo' && names[id(24)] === 'Cia',
  'the new name follows to your own member record only');
assert(await refused(`select api.update_my_profile_details('Ada','inte-en-adress','','keep',null,2,$1)`, [key()], /invalid_email/),
  'invalid email is refused');
assert(await refused(`select api.update_my_profile_details('Ada','','abc','keep',null,2,$1)`, [key()], /invalid_phone/),
  'invalid phone is refused');
assert(await refused(`select api.update_my_profile_details('Ada','','','keep',null,1,$1)`, [key()], /stale_revision/),
  'stale revision is refused');

// Avatar: staged, must be uploaded before it is used.
const staged = await one(`select api.stage_profile_avatar('image/png',1000,$1)`, [key()]);
assert(staged.object_key.startsWith(id(12) + '/'), 'avatar is staged in own folder');
assert(await refused(`select api.update_my_profile_details('Ada Andersson','ada@mail.se','','replace',$1,2,$2)`,
  [staged.avatar_id, key()], /avatar_not_uploaded/), 'avatar must be uploaded first');
await db.query(`insert into storage.objects values('profile-avatars',$1)`, [staged.object_key]);
rev = await one(`select api.update_my_profile_details('Ada Andersson','ada@mail.se','','replace',$1,2,$2)`,
  [staged.avatar_id, key()]);
assert((await one(`select api.get_my_profile_details()`)).has_avatar === true, 'avatar is active');
await as(13);
assert((await one(`select api.authorize_profile_avatar($1)`, [id(12)])).object_key === staged.object_key,
  'club member may see the picture');
await as(15);
assert(await one(`select api.authorize_profile_avatar($1)`, [id(12)]) === null, 'outsider gets no picture');

// Contact visibility.
await as(11);
let contact = await one(`select api.get_person_contact($1,$2,$3)`, [club, team, id(22)]);
assert(contact.contact_email === 'ada@mail.se' && contact.contact_source === 'account', 'leader sees account contact');
await as(13);
contact = await one(`select api.get_person_contact($1,$2,$3)`, [club, team, id(22)]);
assert(contact.contact_email === undefined && contact.can_see_contact === false && contact.avatar_profile_id === id(12),
  'teammate sees picture but no contact');
await as(12);
assert((await one(`select api.get_person_contact($1,$2,$3)`, [club, team, id(22)])).contact_email === 'ada@mail.se',
  'the person sees own contact');
await as(15);
assert(await refused(`select api.get_person_contact($1,$2,$3)`, [club, team, id(22)], /not_found/), 'outsider is refused');
await as(11);
assert(await refused(`select api.get_person_contact($1,$2,$3)`, [club, team, id(25)], /not_found/),
  'person outside the team is refused');

// Club record for a player without an account.
await one(`select api.set_person_contact($1,$2,$3,'cia.forälder@mail.se','0701234567')`, [club, team, id(24)]);
contact = await one(`select api.get_person_contact($1,$2,$3)`, [club, team, id(24)]);
assert(contact.contact_email === 'cia.forälder@mail.se' && contact.contact_source === 'club'
  && contact.can_edit_club_contact === true, 'leader keeps contact for a player without account');
await as(13);
assert(await refused(`select api.set_person_contact($1,$2,$3,'x@y.se','')`, [club, team, id(24)], /not_found/),
  'teammate cannot set contact');

// Login email change via support.
await as(12);
const request = await one(`select api.request_login_email_change('Ny@Mail.se','Bytt jobb')`);
assert(await refused(`select api.request_login_email_change('annan@mail.se','Andra försöket')`, [], /request_open/),
  'only one open request');
assert(await refused(`select api.decide_login_email_change($1,true,'ok')`, [request], /not_found/),
  'the user cannot approve own request');
await as(14);
const queue = await one(`select api.list_login_email_change_requests('pending')`);
assert(queue.length === 1 && queue[0].requested_email === 'ny@mail.se', 'support sees the request');
assert(await one(`select api.decide_login_email_change($1,true,'Verifierad per telefon')`, [request]) === 'approved',
  'support approves');
await as(12);
assert((await one(`select api.get_my_profile_details()`)).email_change.state === 'approved', 'user sees approval');
assert(await one(`select api.complete_login_email_change()`) === 'approved', 'not done until the login email changed');
await db.exec(`update auth.users set email='ny@mail.se' where id='${id(12)}'`);
assert(await one(`select api.complete_login_email_change()`) === 'completed', 'completed after confirmation');

// Member card and address.
await as(12);
await one(`select api.update_my_address('Storgatan 1','123 45','Alby')`);
assert(await refused(`select api.update_my_address('x','ABC!','y')`, [], /invalid_address/), 'invalid postal code is refused');
let card = await one(`select api.get_member_card($1,$2,$3)`, [club, team, id(22)]);
assert(card.name === 'Ada Andersson' && card.club_name === 'Alby IF' && card.team_name === 'F2012'
  && card.roles.includes('player') && card.member_number.length === 8, 'own card has name, club, team and role');
assert(card.contact.street_address === 'Storgatan 1' && card.contact.postal_code === '123 45'
  && card.contact.city === 'Alby', 'own card back shows the address');
await as(13);
card = await one(`select api.get_member_card($1,$2,$3)`, [club, team, id(22)]);
assert(card.name === 'Ada Andersson' && card.contact.street_address === undefined
  && card.contact.can_see_contact === false, 'teammate sees the front but not the address');
await as(11);
card = await one(`select api.get_member_card($1,$2,$3)`, [club, team, id(21)]);
assert(card.roles.includes('leader') && card.titles.includes('head_coach'), 'leader card shows role and title');
card = await one(`select api.get_member_card($1,$2,$3)`, [club, team, id(26)]);
assert(card.roles.includes('guardian') && card.guardian_of[0] === 'Ada Andersson', 'guardian card names the child');
await one(`select api.set_person_address($1,$2,$3,'Byvägen 2','54321','Byn')`, [club, team, id(24)]);
card = await one(`select api.get_member_card($1,$2,$3)`, [club, team, id(24)]);
assert(card.contact.city === 'Byn' && card.contact.contact_source === 'club', 'leader keeps address for no-account member');
await as(15);
assert(await refused(`select api.get_member_card($1,$2,$3)`, [club, team, id(22)], /not_found/), 'outsider gets no card');

// Club badge: only club admins upload; members see it.
await as(11);
assert(await refused(`select api.stage_club_badge($1,'image/png',100)`, [club], /not_found/), 'a team leader cannot set the badge');
await as(16);
const badge = await one(`select api.stage_club_badge($1,'image/png',100)`, [club]);
assert(await refused(`select api.set_club_badge($1,'replace',$2)`, [club, badge.badge_id], /badge_not_uploaded/),
  'badge must be uploaded first');
await db.query(`insert into storage.objects values('club-badges',$1)`, [badge.object_key]);
await one(`select api.set_club_badge($1,'replace',$2)`, [club, badge.badge_id]);
await as(13);
assert((await one(`select api.authorize_club_badge($1)`, [club])).object_key === badge.object_key, 'members see the badge');
assert((await one(`select api.get_member_card($1,$2,$3)`, [club, team, id(22)])).has_badge === true, 'card knows the badge');
await as(15);
assert(await one(`select api.authorize_club_badge($1)`, [club]) === null, 'outsiders do not see the badge');
console.log('PASS');
export { db, club, team, id, as, one };
