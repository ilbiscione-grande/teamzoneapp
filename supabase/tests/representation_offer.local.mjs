import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';

// The home team offers a player; the receiving team decides. A request
// from the receiving team is still decided by the home team.
const db = new PGlite();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const club = id(1), aLeader = id(2), jLeader = id(3);
const teamA = id(10), teamJ = id(11);
const player = id(21), other = id(22);
const as = (actor) => db.query("select set_config('test.actor',$1,false)", [actor]);
const offer = (person, key) => db.query(
  `select api.offer_play_eligibility($1,$2,$3,'development','fixed',now(),now()+interval '30 days',null,null,
    'Beslut av lagansvarig',$4) value`, [club, teamJ, person, key]);
const list = async (team) => (await db.query(
  'select person_name, can_decide, decider_team_id from api.list_play_eligibilities($1,$2)', [club, team])).rows;
const decide = (eligibility, revision, key) => db.query(
  'select api.decide_play_eligibility($1,true,$2,$3) value', [eligibility, revision, key]);
try {
  await db.exec(`create schema core; create schema internal; create schema api; create schema auth; create schema audit;
  create role anon; create role authenticated;
  create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.actor',true),'')::uuid $$;
  create table core.teams(id uuid, club_id uuid, status text, name text, primary key(id, club_id));
  create table core.club_people(id uuid primary key, club_id uuid, status text, display_name text,
    representation_available boolean not null default false, revision bigint not null default 1);
  create table core.team_assignments(club_id uuid, team_id uuid, club_person_id uuid, state text,
    starts_at timestamptz, ends_at timestamptz);
  create table core.play_eligibilities(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid,
    home_team_id uuid, club_person_id uuid, kind text, source_club_id uuid, source text, state text,
    starts_at timestamptz, ends_at timestamptz, validity_kind text, season_ends_on date, review_due_at timestamptz,
    created_by uuid, revision bigint not null default 1);
  create table internal.command_deduplication(actor_profile_id uuid, idempotency_key uuid, command_type text, result jsonb);
  create table audit.command_events(club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text,
    aggregate_id uuid, aggregate_revision bigint, metadata jsonb);
  -- The A coach manages team A only; the J coach team J only.
  create function internal.actor_has_capability(c uuid, t uuid, cap text) returns boolean language sql as
    $$ select (auth.uid()='${aLeader}' and t='${teamA}') or (auth.uid()='${jLeader}' and t='${teamJ}') $$;
  insert into core.teams values ('${teamA}','${club}','active','A'),('${teamJ}','${club}','active','J');
  insert into core.club_people(id,club_id,status,display_name) values
    ('${player}','${club}','active','Ada'),('${other}','${club}','active','Bo');
  insert into core.team_assignments values
    ('${club}','${teamA}','${player}','active',now()-interval '1 year',null),
    ('${club}','${teamA}','${other}','active',now()-interval '1 year',null);
  -- A request made before this migration, waiting for the home team.
  insert into core.play_eligibilities(club_id,team_id,home_team_id,club_person_id,state,ends_at)
    values ('${club}','${teamJ}','${teamA}','${other}','pending',now()+interval '30 days');`);
  await db.exec(fs.readFileSync('supabase/migrations/20270420090000_representation_offer_by_home_team.sql', 'utf8'));

  const old = (await db.query(`select decider_team_id from core.play_eligibilities where club_person_id='${other}'`)).rows[0];
  assert.equal(old.decider_team_id, teamA, 'an old request is still decided by the home team');

  // The J coach cannot offer team A's player.
  await as(jLeader);
  await assert.rejects(offer(player, id(900)), /not_found/);

  await as(aLeader);
  const offered = (await offer(player, id(901))).rows[0].value;
  assert.equal((await offer(player, id(901))).rows[0].value, offered, 'idempotent');
  const row = (await db.query(`select state, decider_team_id, home_team_id from core.play_eligibilities where id=$1`,
    [offered])).rows[0];
  assert.deepEqual(row, { state: 'pending', decider_team_id: teamJ, home_team_id: teamA });
  assert.equal((await db.query(`select representation_available v from core.club_people where id='${player}'`))
    .rows[0].v, true, 'the offer makes the player available');
  await assert.rejects(offer(player, id(902)), /overlapping_play_eligibility/);

  // The API wrapper comes from an earlier migration.
  await db.exec(`create function api.decide_play_eligibility(e uuid, approve boolean, r bigint, k uuid)
    returns bigint language sql as $$ select internal.decide_play_eligibility_for_actor(e,approve,r,k) $$;`);

  // Team A sees the offer but does not decide it; team J does.
  assert.equal((await list(teamA)).find((r) => r.person_name === 'Ada').can_decide, false);
  await assert.rejects(decide(offered, 1, id(903)), /not_found/, 'the offering team cannot approve its own offer');
  await as(jLeader);
  assert.equal((await list(teamJ)).find((r) => r.person_name === 'Ada').can_decide, true);
  await assert.rejects(decide(offered, 7, id(904)), (error) => error.code === 'PT409');
  await decide(offered, 1, id(905));
  assert.equal((await db.query('select state from core.play_eligibilities where id=$1', [offered])).rows[0].state, 'active');

  // The old request: team A decides, team J does not.
  assert.equal((await list(teamJ)).find((r) => r.person_name === 'Bo').can_decide, false);
  await as(aLeader);
  assert.equal((await list(teamA)).find((r) => r.person_name === 'Bo').can_decide, true);
  console.log('representation offer: ok');
} finally {
  await db.close();
}
