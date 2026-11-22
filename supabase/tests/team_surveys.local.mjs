// Enkäter (2026-11-22): a team's leaders with Säsongsplanering write a
// survey, share personal links and an open link, and read the answers.
// node supabase/tests/team_surveys.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const coach = id(1), adaLogin = id(2), viewer = id(3), club = id(10), team = id(20), other = id(21);
const [ada, bo, leaderPerson, otherPlayer] = [id(50), id(51), id(52), id(53)];
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema internal; create schema api; create schema core; create schema auth; create schema audit;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table core.clubs(id uuid primary key, name text);
insert into core.clubs values ('${club}','IF Test');
create table core.teams(id uuid primary key, club_id uuid, name text, status text default 'active');
insert into core.teams values ('${team}','${club}','P2012'),('${other}','${club}','F2013');
create table core.club_people(id uuid primary key, club_id uuid, display_name text, status text default 'active');
insert into core.club_people values ('${ada}','${club}','Ada'),('${bo}','${club}','Bo'),
 ('${leaderPerson}','${club}','Coach'),('${otherPlayer}','${club}','Cia');
create table core.assignments(id uuid primary key default gen_random_uuid(), club_id uuid, team_id uuid, club_person_id uuid,
  role_package text, state text, starts_at timestamptz default now() - interval '1 day', ends_at timestamptz);
insert into core.assignments(club_id, team_id, club_person_id, role_package, state) values
  ('${club}','${team}','${ada}','player','active'),('${club}','${team}','${bo}','player','active'),
  ('${club}','${team}','${leaderPerson}','leader','active'),('${club}','${other}','${otherPlayer}','player','active');
create table core.person_account_links(club_person_id uuid, profile_id uuid, state text);
insert into core.person_account_links values ('${ada}','${adaLogin}','active');
create table audit.command_events(club_id uuid, actor_profile_id uuid, command_type text, aggregate_type text,
  aggregate_id uuid, aggregate_revision int, metadata jsonb);
create table internal.notification_outbox(id uuid primary key default gen_random_uuid(), club_id uuid, domain_event_id uuid,
  event_type text, aggregate_type text, aggregate_id uuid, recipient_profile_id uuid, recipient_person_id uuid, payload_ref jsonb);
-- The coach leads the team with Säsongsplanering; the viewer only reads it.
create function internal.tdp_team_club(t uuid) returns uuid language plpgsql stable as $$
begin
  if auth.uid() is null or auth.uid() not in ('${coach}','${viewer}') or t <> '${team}' then
    raise insufficient_privilege using message = 'not_found'; end if;
  return '${club}';
end$$;
create function internal.tdp_can_edit(c uuid) returns boolean language sql stable as $$ select auth.uid() = '${coach}'::uuid $$;
grant usage on schema api, internal, core, auth, audit to authenticated, service_role;`);
await db.exec(read('supabase/migrations/20270417090000_team_surveys.sql'));
await db.exec('begin');

const as = who => db.query("select set_config('request.jwt.claim.sub',$1,false)", [who]);
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]?.v;
const asOwner = async sql => { await db.exec('reset role'); try { return (await db.query(sql)).rows; } finally { await db.exec('set role authenticated'); } };
const rejects = async (fn, message) => {
  await db.exec('savepoint r');
  try { await assert.rejects(fn, e => e.message === message, message); } finally { await db.exec('rollback to r'); }
};
const questions = [
  { id: 'q1abc', kind: 'scale', label: '  Hur trivs du   i laget? ', required: true, low: 'Inte alls', high: 'Mycket' },
  { id: 'q2abc', kind: 'single', label: 'Position', options: ['Back', 'Mitt', 'Anfall'] },
  { id: 'q3abc', kind: 'multi', label: 'Vad vill du utveckla?', options: ['Passningar', 'Skott', 'Löpning'] },
  { id: 'q4abc', kind: 'long_text', label: 'Något mer?' },
];
const save = (surveyId, title, qs = questions) => one('select api.save_team_survey($1,$2,$3,$4,$5::jsonb) v',
  [team, surveyId, title, 'Inför spelarsamtalen', JSON.stringify(qs)]);

await db.exec('set role authenticated');
await as(coach);
let survey = await save(null, '  Inför   spelarsamtal ');
assert.equal(survey.title, 'Inför spelarsamtal');
assert.equal(survey.state, 'draft');
assert.equal(survey.questions[0].label, 'Hur trivs du i laget?');
assert.equal(survey.questions[1].required, false);
assert.deepEqual(survey.players.map(p => p.name), ['Ada', 'Bo'], 'the team\'s players, not leaders or other teams');
assert.equal(survey.players[0].has_account, true);
await rejects(() => save(null, ' '), 'invalid_title');
await rejects(() => save(null, 'X', [{ id: 'q1abc', kind: 'single', label: 'A', options: ['Ja'] }]), 'invalid_options');
await rejects(() => save(null, 'X', [{ id: 'q1abc', kind: 'single', label: 'A', options: ['Ja', 'ja'] }]), 'invalid_options');
await rejects(() => save(null, 'X', [{ id: 'q1abc', kind: 'text', label: 'A' }, { id: 'q1abc', kind: 'text', label: 'B' }]), 'invalid_questions');
await rejects(() => save(null, 'X', [{ id: 'q1abc', kind: 'rating', label: 'A' }]), 'invalid_questions');
await rejects(() => one('select api.save_team_survey($1,null,$2,$3,$4::jsonb) v', [other, 'X', '', '[]']), 'not_found');

// Others: a reader sees but cannot change; outsiders see nothing.
await as(viewer);
assert.equal((await one('select api.list_team_surveys($1) v', [team])).can_edit, false);
await rejects(() => save(survey.id, 'Ändrad'), 'read_only');
await as(adaLogin);
await rejects(() => one('select api.get_team_survey($1) v', [survey.id]), 'not_found');
await rejects(() => one('select api.list_team_surveys($1) v', [team]), 'not_found');
await as(coach);

// Links: personal links for players only; the open link on and off.
await rejects(() => one('select api.invite_team_survey_players($1,$2::uuid[]) v', [survey.id, [leaderPerson]]), 'invite_needs_player_role');
await rejects(() => one('select api.invite_team_survey_players($1,$2::uuid[]) v', [survey.id, [otherPlayer]]), 'invite_needs_player_role');
survey = await one('select api.invite_team_survey_players($1,$2::uuid[]) v', [survey.id, [ada, bo]]);
assert.equal(survey.invites.length, 2);
const adaLink = survey.invites.find(i => i.person_id === ada).token, boLink = survey.invites.find(i => i.person_id === bo).token;
assert.match(adaLink, /^[a-f0-9]{32}$/);
assert.equal((await asOwner('select count(*)::int n from internal.notification_outbox'))[0].n, 0, 'no notification while a draft');
survey = await one('select api.set_team_survey_open_link($1,true) v', [survey.id]);
const openLink = survey.open_token;
assert.match(openLink, /^[a-f0-9]{32}$/);

// A draft cannot be answered.
await db.exec('reset role; set role service_role');
assert.deepEqual(await one('select api.public_get_team_survey($1) v', [adaLink]), { not_found: true });
await db.exec('reset role; set role authenticated');
survey = await one('select api.set_team_survey_state($1,$2) v', [survey.id, 'open']);
assert.equal(survey.state, 'open');
const outbox = await asOwner('select * from internal.notification_outbox');
assert.equal(outbox.length, 1, 'Ada has an account, Bo has none');
assert.equal(outbox[0].recipient_profile_id, adaLogin);
assert.equal(outbox[0].event_type, 'team.survey.invited.v1');
await one('select api.invite_team_survey_players($1,$2::uuid[]) v', [survey.id, [ada]]);
assert.equal((await asOwner('select count(*)::int n from internal.notification_outbox'))[0].n, 1, 'told once');
assert.equal(survey.invites.find(i => i.person_id === ada).token, adaLink, 'a link stays the same');

// Answering on Webtools (service role only).
await rejects(() => one('select api.public_get_team_survey($1) v', [adaLink]), 'permission denied for function public_get_team_survey');
await db.exec('reset role; set role service_role');
let page = await one('select api.public_get_team_survey($1) v', [adaLink]);
assert.equal(page.kind, 'personal');
assert.equal(page.person_name, 'Ada');
assert.equal(page.team_name, 'P2012');
assert.equal(page.answers, null);
const submit = (token, answers, name = null, ip = 'iphash-0123456789abcdef') => one(
  'select api.public_submit_team_survey($1,$2,$3::jsonb,$4) v', [token, name, JSON.stringify(answers), ip]);
await rejects(() => submit(adaLink, { q2abc: 'Mitt' }), 'answer_required');
await rejects(() => submit(adaLink, { q1abc: 6 }), 'invalid_answers');
await rejects(() => submit(adaLink, { q1abc: 4, q2abc: 'Mål' }), 'invalid_answers');
assert.deepEqual(await submit(adaLink, { q1abc: 4, q2abc: 'Mitt', q3abc: ['Löpning', 'Passningar', 'Löpning'], q4abc: '  ', zz: 1 }), { accepted: true });
page = await one('select api.public_get_team_survey($1) v', [adaLink]);
assert.deepEqual(page.answers, { q1abc: 4, q2abc: 'Mitt', q3abc: ['Passningar', 'Löpning'] }, 'cleaned, in the options\' order');
await submit(adaLink, { q1abc: 5, q4abc: 'Vill spela mer' });
page = await one('select api.public_get_team_survey($1) v', [adaLink]);
assert.deepEqual(page.answers, { q1abc: 5, q4abc: 'Vill spela mer' }, 'a personal link changes its answer');
assert.equal((await one('select api.public_get_team_survey($1) v', [openLink])).kind, 'open');
assert.equal((await one('select api.public_get_team_survey($1) v', [openLink])).person_name, null);
await rejects(() => submit(openLink, { q1abc: 3 }), 'name_required');
await submit(openLink, { q1abc: 3 }, '  Bo   B ');
await submit(openLink, { q1abc: 2 }, 'Okänd');
for (let n = 0; n < 8; n++) await submit(openLink, { q1abc: 1 }, 'Spam ' + n);
await rejects(() => submit(openLink, { q1abc: 1 }, 'Spam'), 'rate_limited');
assert.deepEqual(await one('select api.public_get_team_survey($1) v', ['f'.repeat(32)]), { not_found: true });
await db.exec('reset role; set role authenticated');

// The leaders' view.
survey = await one('select api.get_team_survey($1) v', [survey.id]);
assert.equal(survey.responses.length, 11);
assert.ok(survey.invites.find(i => i.person_id === ada).answered_at, 'Ada has answered');
assert.equal(survey.invites.find(i => i.person_id === bo).answered_at, null);
await rejects(() => save(survey.id, 'Ny titel', questions.slice(0, 2)), 'survey_has_answers');
survey = await save(survey.id, 'Ny titel');
assert.equal(survey.title, 'Ny titel', 'the title can change');
const boOpen = survey.responses.find(r => r.respondent_name === 'Bo B');
await rejects(() => one('select api.link_team_survey_response($1,$2) v', [boOpen.id, otherPlayer]), 'link_needs_player_role');
survey = await one('select api.link_team_survey_response($1,$2) v', [boOpen.id, bo]);
assert.equal(survey.responses.find(r => r.id === boOpen.id).person_name, 'Bo');
const adaResponse = survey.responses.find(r => r.person_id === ada);
await rejects(() => one('select api.link_team_survey_response($1,$2) v', [adaResponse.id, bo]), 'personal_answer');
const adaInvite = survey.invites.find(i => i.person_id === ada);
await rejects(() => one('select api.remove_team_survey_invite($1) v', [adaInvite.id]), 'invite_answered');
survey = await one('select api.remove_team_survey_invite($1) v', [survey.invites.find(i => i.person_id === bo).id]);
assert.equal(survey.invites.length, 1);

// The player's page.
let answers = await one('select api.get_player_survey_answers($1,$2) v', [team, bo]);
assert.equal(answers.length, 1);
assert.deepEqual(answers[0].answers, { q1abc: 3 });
answers = await one('select api.get_player_survey_answers($1,$2) v', [team, ada]);
assert.equal(answers[0].title, 'Ny titel');
assert.equal(answers[0].questions.length, 4);

// Closing: links stop taking answers, but show it.
await one('select api.set_team_survey_state($1,$2) v', [survey.id, 'closed']);
await db.exec('reset role; set role service_role');
assert.equal((await one('select api.public_get_team_survey($1) v', [adaLink])).state, 'closed');
assert.deepEqual(await submit(adaLink, { q1abc: 1 }), { closed: true });
await db.exec('reset role; set role authenticated');

// Deleting an answer, then the survey.
survey = await one('select api.delete_team_survey_response($1) v', [adaResponse.id]);
assert.equal(survey.responses.length, 10);
await one('select api.delete_team_survey($1) v', [survey.id]);
assert.equal((await one('select api.list_team_surveys($1) v', [team])).surveys.length, 0);
assert.equal((await asOwner('select count(*)::int n from core.team_survey_responses'))[0].n, 0, 'answers go with it');
const commands = (await asOwner('select command_type from audit.command_events order by command_type')).map(r => r.command_type);
assert.ok(commands.includes('team.survey.created.v1') && commands.includes('team.survey.deleted.v1'));
console.log('team_surveys: ok');
