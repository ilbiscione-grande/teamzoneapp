// Avgiftsomgångar och familjer (2026-11-10): membership rounds with an
// amount per category and the family rule (sibling discount, cap), team
// rounds per player, families from shared guardians that the club can merge,
// split and reset, and issuing that freezes the fees.
// node supabase/tests/club_fee_rounds.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const club = id(10), team = id(20);
const [admin, treasurer, coach] = [id(1), id(2), id(3)];
const [adminP, treasurerP, coachP, alva, bertil, cissi, parent, parent2] =
  [id(41), id(42), id(43), id(44), id(45), id(46), id(47), id(48)];
const year = new Date().getFullYear();
await db.exec(`create role anon; create role authenticated;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key);
insert into core.clubs values ('${club}');
create table core.profiles(id uuid primary key);
insert into core.profiles values ('${admin}'),('${treasurer}'),('${coach}');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active', birth_year smallint,
  unique (id, club_id));
insert into core.club_people values
  ('${adminP}','${club}','Admin','active',null),
  ('${treasurerP}','${club}','Kassören','active',${year - 50}),
  ('${coachP}','${club}','Tränaren','active',${year - 40}),
  ('${alva}','${club}','Alva','active',${year - 12}),
  ('${bertil}','${club}','Bertil','active',${year - 10}),
  ('${cissi}','${club}','Cissi','active',${year - 12}),
  ('${parent}','${club}','Föräldern','active',${year - 42}),
  ('${parent2}','${club}','Annan förälder','active',${year - 44});
create table core.teams(id uuid primary key, club_id uuid, name text, unique (id, club_id));
insert into core.teams values ('${team}','${club}','P2014');
create table core.person_account_links(club_id uuid, club_person_id uuid, profile_id uuid, state text);
insert into core.person_account_links values ('${club}','${adminP}','${admin}','active'),
  ('${club}','${treasurerP}','${treasurer}','active'),('${club}','${coachP}','${coach}','active');
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, club_person_id uuid, team_id uuid,
  role_package text, state text, starts_at timestamptz, ends_at timestamptz);
insert into core.assignments(id, club_id, club_person_id, team_id, role_package, state, starts_at) values
  ('${id(51)}','${club}','${adminP}',null,'club_functionary','active', now() - interval '1 day'),
  ('${id(52)}','${club}','${treasurerP}',null,'club_functionary','active', now() - interval '1 day'),
  ('${id(53)}','${club}','${coachP}','${team}','leader','active', now() - interval '1 day');
create table core.team_assignments(club_id uuid, team_id uuid, club_person_id uuid, state text);
insert into core.team_assignments values ('${club}','${team}','${alva}','active'),('${club}','${team}','${bertil}','active'),
  ('${club}','${team}','${cissi}','active');
create table core.guardian_relations(club_id uuid, guardian_person_id uuid, child_person_id uuid, state text, ends_at timestamptz);
insert into core.guardian_relations values ('${club}','${parent}','${alva}','active',null),('${club}','${parent}','${bertil}','active',null),
  ('${club}','${parent2}','${cissi}','active',null);
create table core.capability_grants(club_id uuid, assignment_id uuid, capability text, scope_type text, scope_id uuid,
  starts_at timestamptz, ends_at timestamptz);
insert into core.capability_grants values ('${club}','${id(51)}','club.memberships.manage','club','${club}', now() - interval '1 day', null),
  ('${club}','${id(52)}','economy.manage','club','${club}', now() - interval '1 day', null);
create table internal.command_deduplication(actor_profile_id uuid, idempotency_key uuid, command_type text, result jsonb);
create table audit.command_events(club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text, aggregate_id uuid,
  aggregate_revision bigint, metadata jsonb);
grant usage on schema api, internal, core, auth, audit to authenticated;`);
await db.exec(`create function internal.actor_has_capability(target_club_id uuid, target_team_id uuid, required_capability text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from core.person_account_links link
    join core.assignments assignment on assignment.club_person_id = link.club_person_id and assignment.club_id = link.club_id
    join core.capability_grants grant_row on grant_row.assignment_id = assignment.id and grant_row.club_id = assignment.club_id
    where link.profile_id = auth.uid() and link.state = 'active' and assignment.state = 'active'
      and assignment.club_id = target_club_id and grant_row.capability = required_capability
      and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id) $$;`);
await db.exec(read('supabase/migrations/20270215090000_club_member_register.sql'));
await db.exec(read('supabase/migrations/20270216090000_club_fee_rounds.sql'));
await db.exec(read('supabase/migrations/20270217090000_club_fee_payments.sql'));
const call = async (who, sql, params = []) => {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
  await db.exec('set role authenticated');
  try { return Object.values((await db.query(sql, params)).rows[0] ?? {})[0]; } finally { await db.exec('reset role'); }
};
const save = (who, round, payload, revision) => call(who,
  'select api.save_club_fee_round($1, $2, $3, $4, gen_random_uuid())', [club, round, JSON.stringify(payload), revision]);
const decide = (round, decision, revision) => call(admin,
  'select api.decide_club_fee_round($1, $2, $3, $4, gen_random_uuid())', [club, round, decision, revision]);
const round = (who, roundId) => call(who, 'select api.get_club_fee_round($1, $2)', [club, roundId]);
const family = (change, people) => call(admin,
  'select api.change_club_family($1, $2, $3, gen_random_uuid())', [club, change, people]);
const amounts = r => Object.fromEntries(r.fees.map(f => [f.name, [f.base_amount, f.discount_amount, f.amount, f.state]]));

// Families: Alva and Bertil share a guardian; Cissi has her own.
const members = (await call(admin, 'select api.get_club_families($1)', [club])).members;
const keyOf = name => members.find(m => m.name === name).family_key;
assert.equal(keyOf('Alva'), keyOf('Bertil'));
assert.notEqual(keyOf('Alva'), keyOf('Cissi'));
assert.deepEqual(members.find(m => m.name === 'Alva').guardians, ['Föräldern']);
assert.equal(members.some(m => m.name === 'Föräldern'), false);

// A membership round: 300 kr youth, 500 kr adult, 50 % from the second
// sibling and at most 400 kr per family.
const membership = { kind: 'membership', title: 'Medlemsavgift 2027', due_on: `${year + 1}-03-31`,
  amount_youth: 30000, amount_adult: 50000, sibling_discount_percent: 50, family_cap: 40000 };
const created = await save(treasurer, null, membership, 0);
assert.equal(created.revision, 1);
let draft = await round(admin, created.round_id);
assert.deepEqual(amounts(draft), {
  Alva: [30000, 0, 30000, 'open'], Bertil: [30000, 20000, 10000, 'open'], Cissi: [30000, 0, 30000, 'open'],
  Kassören: [50000, 0, 50000, 'open'], Tränaren: [50000, 0, 50000, 'open'] });
assert.deepEqual(draft.missing, ['Admin']);

// Cissi joins the family: the cap leaves nothing for her.
await family('merge', [alva, cissi]);
draft = await round(admin, created.round_id);
assert.deepEqual([amounts(draft).Alva, amounts(draft).Bertil, amounts(draft).Cissi],
  [[30000, 0, 30000, 'open'], [30000, 20000, 10000, 'open'], [30000, 30000, 0, 'waived']]);
// Bertil moves out to a family of his own.
await family('split', [bertil]);
draft = await round(admin, created.round_id);
assert.deepEqual([amounts(draft).Alva[2], amounts(draft).Bertil[2], amounts(draft).Cissi[2]], [30000, 30000, 10000]);
// Reset: back to the guardians.
await family('reset', [alva]);
await family('reset', [bertil]);
draft = await round(admin, created.round_id);
assert.deepEqual([amounts(draft).Alva[2], amounts(draft).Bertil[2], amounts(draft).Cissi[2]], [30000, 10000, 30000]);
await assert.rejects(family('merge', [alva]), /invalid_family_change/);
await assert.rejects(family('split', [parent]), /not_found/);

// Editing a draft; a stale one gets PT409, never 40001.
const edited = await save(admin, created.round_id, { ...membership, amount_adult: 60000 }, 1);
assert.equal(edited.revision, 2);
await assert.rejects(save(admin, created.round_id, membership, 1), e => e.code === 'PT409');
await assert.rejects(save(admin, null, { ...membership, kind: 'team' }, 0), /invalid_fee_round/);
await assert.rejects(save(admin, null, { ...membership, sibling_discount_percent: 150 }, 0), /invalid_fee_round/);
await assert.rejects(save(admin, null, { ...membership, due_on: 'snart' }, 0), /invalid_fee_round/);

// Issuing freezes the fees; then the round cannot change.
const issued = await decide(created.round_id, 'issue', 2);
assert.deepEqual([issued.state, issued.fee_count], ['issued', 5]);
await db.exec(`update core.club_fee_rounds set amount_youth = 1 where id = '${created.round_id}'`);
const frozen = await round(admin, created.round_id);
assert.equal(frozen.state, 'issued');
assert.deepEqual(amounts(frozen).Tränaren, [60000, 0, 60000, 'open']);
assert.deepEqual(amounts(frozen).Bertil, [30000, 20000, 10000, 'open']);
assert.deepEqual(frozen.missing, []);
await assert.rejects(save(admin, created.round_id, membership, 3), /fee_round_issued/);
await assert.rejects(decide(created.round_id, 'cancel', 3), /fee_round_issued/);

// Betalstatus: paid by hand, waived with a note, opened again; PT409 when
// someone else marked the fee meanwhile.
const mark = (who, fees, decision, day, method, note) => call(who,
  'select api.mark_club_fees($1, $2, $3, $4, $5, $6, gen_random_uuid())',
  [club, JSON.stringify(fees.map(f => ({ fee_id: f.fee_id, revision: f.revision }))), decision, day, method, note]);
const feeOf = (r, name) => r.fees.find(f => f.name === name);
const today = new Date().toISOString().slice(0, 10);
assert.equal(typeof feeOf(frozen, 'Alva').fee_id, 'string');
assert.equal(feeOf(draft, 'Alva').fee_id, undefined);
assert.deepEqual(await mark(treasurer, [feeOf(frozen, 'Alva'), feeOf(frozen, 'Cissi')], 'paid', today, 'swish', null),
  { decision: 'paid', count: 2 });
let paid = await round(admin, created.round_id);
assert.deepEqual([feeOf(paid, 'Alva').state, feeOf(paid, 'Alva').paid_on, feeOf(paid, 'Alva').payment_method, feeOf(paid, 'Alva').revision],
  ['paid', today, 'swish', 2]);
await assert.rejects(mark(admin, [feeOf(frozen, 'Alva')], 'waived', null, null, null), e => e.code === 'PT409');
await mark(admin, [feeOf(paid, 'Tränaren')], 'waived', null, null, ' Ledare ');
await mark(admin, [feeOf(paid, 'Alva')], 'open', null, null, null);
paid = await round(admin, created.round_id);
assert.deepEqual([feeOf(paid, 'Tränaren').state, feeOf(paid, 'Tränaren').note], ['waived', 'Ledare']);
assert.deepEqual([feeOf(paid, 'Alva').state, feeOf(paid, 'Alva').paid_on], ['open', undefined]);
let listed = (await call(treasurer, 'select api.get_club_fee_rounds($1)', [club])).rounds[0];
assert.deepEqual([listed.paid_count, listed.paid_total, listed.open_count, listed.open_total], [1, 30000, 3, 100000]);
await assert.rejects(mark(admin, [feeOf(paid, 'Alva')], 'paid', today, null, null), /invalid_fee_mark/);
await assert.rejects(mark(admin, [feeOf(paid, 'Alva')], 'paid', '2099-01-01', 'bank', null), /invalid_fee_mark/);
await assert.rejects(mark(admin, [{ fee_id: id(99), revision: 1 }], 'waived', null, null, null), /not_found/);
await assert.rejects(mark(coach, [feeOf(paid, 'Alva')], 'waived', null, null, null), /not_found/);
// A fee the family cap covers has nothing to pay.
await db.exec(`update core.club_fees set discount_amount = base_amount, amount = 0, state = 'waived'
  where id = '${feeOf(paid, 'Bertil').fee_id}'`);
paid = await round(admin, created.round_id);
await assert.rejects(mark(admin, [feeOf(paid, 'Bertil')], 'paid', today, 'cash', null), /nothing_to_pay/);

// A team round: 1000 kr per player, no family rule.
const teamRound = await save(admin, null, { kind: 'team', team_id: team, title: 'Lagavgift P2014', due_on: `${year + 1}-04-30`,
  amount_player: 100000 }, 0);
const teamFees = await round(admin, teamRound.round_id);
assert.deepEqual(Object.values(amounts(teamFees)).map(a => a[2]), [100000, 100000, 100000]);
assert.equal(teamFees.team_name, 'P2014');
await assert.rejects(save(admin, null, { kind: 'team', team_id: team, title: 'X', due_on: `${year}-01-01`,
  amount_player: 100, family_cap: 50 }, 0), /invalid_fee_round/);
// A cancelled draft is gone from the list.
await decide(teamRound.round_id, 'cancel', 1);
const rounds = (await call(treasurer, 'select api.get_club_fee_rounds($1)', [club])).rounds;
assert.deepEqual(rounds.map(r => [r.title, r.state, r.fee_count, r.total]), [["Medlemsavgift 2027", "issued", 4, 180000]]);
await assert.rejects(round(admin, teamRound.round_id), /not_found/);

// Without members and teams or economy: nothing to see or change.
await assert.rejects(call(coach, 'select api.get_club_fee_rounds($1)', [club]), /not_found/);
await assert.rejects(call(coach, 'select api.get_club_families($1)', [club]), /not_found/);
await assert.rejects(save(coach, null, membership, 0), /not_found/);
assert.equal((await db.query("select count(*)::int n from audit.command_events where command_type like 'club.%'")).rows[0].n, 13);
assert.doesNotMatch(read('supabase/migrations/20270217090000_club_fee_payments.sql'), /serialization_failure/);
assert.doesNotMatch(read('supabase/migrations/20270216090000_club_fee_rounds.sql'), /serialization_failure/);
console.log('club fee rounds: ok');
