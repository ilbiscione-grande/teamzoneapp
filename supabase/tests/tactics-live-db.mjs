// The database for the live lesson tests: PGlite with the tables, auth and
// Realtime parts the migrations need, the Tacticsboard and live migrations
// run, and helpers to call as an account or a guest. realtime.send is kept
// in realtime.sent, so a test can see what the database sent and where.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
export const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
export const host = id(1), member = id(2), guest = id(3), stranger = id(4);

export async function liveDb(migrations) {
  const db = new PGlite();
  // Who is calling: an account, or a guest (an anonymous sign-in).
  const as = (who, anonymous = false) => db.query(
    "select set_config('request.jwt.claim.sub',$1,false), set_config('request.jwt.claims',$2,false)",
    [who ?? '', JSON.stringify({ sub: who, is_anonymous: anonymous })]);
  // No finally: in an aborted transaction it would hide the real error.
  const asRole = async (role, fn) => { await db.exec(`set role ${role}`); const result = await fn(); await db.exec('reset role'); return result; };
  const call = async (who, sql, params = [], anonymous = false) => {
    await as(who, anonymous);
    return asRole('authenticated', async () => Object.values((await db.query(sql, params)).rows[0] ?? {})[0]);
  };
  const fails = async (who, sql, params, pattern, anonymous = false) => {
    await db.exec('savepoint s');
    await assert.rejects(call(who, sql, params, anonymous), pattern);
    await db.exec('rollback to s');
  };
  await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth; create schema realtime;
set check_function_bodies = off;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create table core.profiles(id uuid primary key, display_name text default '');
insert into core.profiles(id, display_name) values ('${host}','Tränare Tina'),('${member}','Mats'),('${guest}',''),('${stranger}','');
create table core.clubs(id uuid primary key, name text);
create table core.teams(id uuid primary key, club_id uuid, name text, status text default 'active');
create table core.club_people(id uuid primary key, display_name text);
create table core.person_account_links(profile_id uuid, club_id uuid, club_person_id uuid, state text);
create table core.assignments(club_id uuid, team_id uuid, club_person_id uuid, role_package text, state text default 'active',
  starts_at timestamptz default now()-interval '1 year', ends_at timestamptz);
create table core.team_person_details(team_id uuid, club_person_id uuid, main_position text, positions text[], jersey_number smallint);
create table core.events(id uuid primary key);
create function internal.booking_person_name(p uuid) returns text language sql stable as $$select null::text$$;
create function internal.actor_can_read_event(e uuid) returns boolean language sql stable as $$select false$$;
create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql stable as $$select true$$;
-- Realtime's own table, topic and send, as far as the migrations need them.
create table realtime.messages(topic text, extension text, payload jsonb, event text);
alter table realtime.messages enable row level security;
create function realtime.topic() returns text language sql stable as $$select current_setting('realtime.topic',true)$$;
create table realtime.sent(topic text, event text, payload jsonb);
create function realtime.send(payload jsonb, event text, topic text, private boolean default true) returns void
  language sql security definer as $$insert into realtime.sent values (topic, event, payload)$$;
grant usage on schema api, internal, core, auth, realtime to authenticated, service_role;
grant select, insert on realtime.messages to authenticated;`);
  for (const name of ['20261119090000_tournament_planner', '20261120090000_tournament_schedule', '20261121090000_tournament_teamzone',
    '20261123090000_tacticsboard', ...migrations]) await db.exec(read(`supabase/migrations/${name}.sql`));
  await db.exec('begin');
  return { db, as, asRole, call, fails };
}
