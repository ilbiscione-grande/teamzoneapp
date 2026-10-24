// Decision package 12, step 1 (2026-10-24): the match live on the team's
// public page — the settings, the projection after every change, names only
// with consent, removal when not published, and the public read.
// node supabase/tests/public_live_match.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), parent = id(2), club = id(10), team = id(20), teamPublic = id(21), clubPublic = id(11);
const match = id(30), [mia, ali] = [id(41), id(42)];
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth; create schema audit; create schema public_api;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key); insert into core.clubs values ('${club}');
create table core.teams(id uuid primary key, club_id uuid); insert into core.teams values ('${team}','${club}');
create table core.events(id uuid primary key, club_id uuid, owning_team_id uuid, event_type text, title text, state text, starts_at timestamptz, opponent_name text, home_away text);
insert into core.events values ('${match}','${club}','${team}','match','P2012 – Aneby SK','scheduled', now(), 'Aneby SK', 'home');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, person_id uuid);
insert into core.club_people values ('${mia}','${club}','Mia Lind',null),('${ali}','${club}','Ali Berg',null);
create table core.publication_consents(id uuid primary key default gen_random_uuid(), club_id uuid, subject_club_person_id uuid,
  field_class text, purpose_code text default 'public_team_profile_v1', state text, withdrawn_at timestamptz, expires_at timestamptz);
create table core.match_workspaces(event_id uuid primary key, state text, match_started_at timestamptz, match_paused_at timestamptz,
  paused_seconds integer default 0, completed_at timestamptz, period_minutes integer[] default '{30,30}', current_period integer default 1);
create table core.match_projections(event_id uuid primary key, score_us integer, score_opponent integer);
create table core.match_facts(id uuid primary key default gen_random_uuid(), event_id uuid, minute integer, fact_type text, side text,
  club_person_id uuid, secondary_club_person_id uuid, detail jsonb default '{}', state text default 'active', created_at timestamptz default clock_timestamp());
create table core.event_publication_settings(event_id uuid primary key, club_id uuid, team_id uuid, state text, revision bigint default 1);
create table core.team_publication_settings(team_id uuid primary key, club_id uuid, mode text, public_id uuid, revision bigint default 1);
create table public_api.club_projections(public_id uuid primary key, visibility text);
create table public_api.team_projections(public_id uuid primary key, club_public_id uuid, visibility text);
create table public_api.event_projections(public_id uuid primary key, team_public_id uuid, starts_at timestamptz, title text);
insert into public_api.club_projections values ('${clubPublic}','published');
insert into public_api.team_projections values ('${teamPublic}','${clubPublic}','published');
create table audit.command_events(club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text, aggregate_id uuid,
  aggregate_revision bigint, metadata jsonb);
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid and cap = 'publication.manage' $$;
create function internal.actor_can_read_event(e uuid) returns boolean language sql stable as $$ select auth.uid() is not null $$;
create function internal.assert_match_manager(e uuid) returns core.events language plpgsql as $$
declare row_value core.events; begin
  if auth.uid() <> '${coach}'::uuid then raise insufficient_privilege using message = 'not_found'; end if;
  select * into row_value from core.events where id = e; return row_value; end $$;
create function internal.public_runtime_enabled() returns boolean language sql as $$ select true $$;
create function internal.consume_public_rate_limit(ip text, kind text, x text) returns jsonb language sql as $$ select '{"allowed":true}'::jsonb $$;
grant usage on schema api, internal, core, auth, audit, public_api to authenticated, service_role;`);
for (const name of ['20261207090000_public_live_match', '20261207100000_public_live_match_sides']) await db.exec(read(`supabase/migrations/${name}.sql`));
await db.exec('begin');
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  const rows = (await db.query(sql, params)).rows;
  await db.exec('reset role');
  return Object.values(rows[0] ?? {})[0];
};
const fails = async (who, sql, params, pattern) => {
  await db.exec('savepoint s');
  await assert.rejects(call(who, sql, params), pattern);
  await db.exec('rollback to s');
};
const projection = async () => (await db.query('select * from public_api.match_live_projections where event_public_id = $1', [match])).rows[0];
const publicRead = async () => {
  await db.exec('set role service_role');
  const value = (await db.query("select api.public_team_live_matches($1, 'ip') v", [teamPublic])).rows[0].v;
  await db.exec('reset role');
  return value;
};

// The team and the match published, the match started — but no live reporting chosen.
await db.query("insert into core.team_publication_settings values ($1,$2,'published',$3)", [team, club, teamPublic]);
await db.query("insert into public_api.event_projections values ($1,$2,now(),'P2012 – Aneby SK')", [match, teamPublic]);
await db.query("insert into core.event_publication_settings values ($1,$2,$3,'published')", [match, club, team]);
await db.query("insert into core.match_projections values ($1,0,0)", [match]);
await db.query("insert into core.match_workspaces(event_id, state, match_started_at) values ($1,'live',now())", [match]);
assert.equal(await projection(), undefined, 'off by default (PLM-03)');

// The team chooses live reporting: the match appears, and follows every change.
await fails(parent, 'select api.set_team_live_reporting($1, true)', [team], /not_found/);
assert.deepEqual(await call(coach, 'select api.set_team_live_reporting($1, true)', [team]), { enabled: true, published: true });
assert.deepEqual([(await projection()).state, (await projection()).opponent_name, (await projection()).home_away], ['live', 'Aneby SK', 'home']);
await db.query("insert into core.match_facts(event_id, minute, fact_type, side, club_person_id, secondary_club_person_id) values ($1,12,'goal','us',$2,$3)", [match, mia, ali]);
await db.query("update core.match_projections set score_us = 1 where event_id = $1", [match]);
await db.query("insert into core.match_facts(event_id, minute, fact_type, side, detail) values ($1,14,'shot','opponent','{\"result\":\"missed\"}')", [match]);
await db.query("insert into core.match_facts(event_id, minute, fact_type, side, detail) values ($1,15,'note','us','{\"text\":\"privat\"}'),($1,16,'kpi','us','{}')", [match]);
let live = await projection();
assert.equal(live.score_us, 1);
assert.deepEqual(live.feed.map(f => [f.n, f.minute, f.type, f.side, f.result, f.player, f.second]),
  [[1, 12, 'goal', 'us', null, null, null], [2, 14, 'shot', 'opponent', 'missed', null, null]], 'no names without consent; no notes or counters (PLM-04)');

// A name consent names the player; withdrawn, the name goes again (PLM-01).
await db.query("insert into core.publication_consents(club_id, subject_club_person_id, field_class, state, expires_at) values ($1,$2,'name','active', now() + interval '30 days')", [club, mia]);
assert.equal((await projection()).feed[0].player, 'Mia Lind');
assert.equal((await projection()).feed[0].second, null, 'Ali has no consent');
await db.query("insert into core.publication_consents(club_id, subject_club_person_id, field_class, state, expires_at) values ($1,$2,'name','pending_guardian', now() + interval '30 days')", [club, ali]);
assert.equal((await projection()).feed[0].second, null, 'a consent waiting for a guardian is not one');
await db.query("update core.publication_consents set state = 'withdrawn', withdrawn_at = now() where subject_club_person_id = $1", [mia]);
assert.equal((await projection()).feed[0].player, null);

// A removed event leaves the feed; the public read has the match with the server's time.
await db.query("update core.match_facts set state = 'voided' where fact_type = 'shot'");
assert.equal((await projection()).feed.length, 1);
const read1 = await publicRead();
assert.deepEqual([read1.available, read1.items.length, read1.items[0].state, typeof read1.server_now], [true, 1, 'live', 'string']);

// The match turns its own way: off follows nothing, null follows the team again.
await fails(parent, 'select api.set_match_live_reporting($1, false)', [match], /not_found/);
assert.equal((await call(coach, 'select api.set_match_live_reporting($1, false)', [match])).live, false);
assert.equal(await projection(), undefined, 'switched off, it is gone (PLM-09)');
const status = await call(coach, 'select api.set_match_live_reporting($1, null)', [match]);
assert.deepEqual([status.team_default, status.match_choice, status.published, status.live], [true, null, true, true]);

// Full time keeps the course (PLM-05); unpublishing the event or the team removes it (PLM-09).
await db.query("update core.match_workspaces set state = 'completed', completed_at = now() where event_id = $1", [match]);
assert.equal((await projection()).state, 'completed');
await db.query("update core.event_publication_settings set state = 'private' where event_id = $1", [match]);
assert.equal(await projection(), undefined);
await db.query("update core.event_publication_settings set state = 'published' where event_id = $1", [match]);
assert.equal((await projection()).state, 'completed');
await db.query("update core.team_publication_settings set mode = 'listed' where team_id = $1", [team]);
assert.equal(await projection(), undefined);
await db.query("update core.team_publication_settings set mode = 'published' where team_id = $1", [team]);
await db.query('delete from public_api.event_projections where public_id = $1', [match]);
assert.equal(await projection(), undefined, 'the event projection gone takes the feed with it');
await fails(coach, "select api.set_match_live_reporting($1, true)", [id(99)], /not_found|event_not_published/);
console.log('public live match: ok');
