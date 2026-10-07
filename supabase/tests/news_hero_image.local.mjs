// Real editorial, public-media and hero-image migrations in isolated Postgres.
// Only identity, capability and Storage are fixtures.
// node supabase/tests/news_hero_image.local.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const segment = (s, start, end) => { const a = s.indexOf(start), b = s.indexOf(end, a); if (a < 0 || b < 0) throw Error(`Missing SQL segment ${start}`); return s.slice(a, b); };
const db = new PGlite();
const publisher = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', outsider = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const club = '10000000-0000-4000-8000-000000000001', clubPublic = '10000000-0000-4000-8000-0000000000aa';
const as = id => db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]);
const one = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const reject = async (fn, pattern) => { await db.exec('savepoint denied'); try { await assert.rejects(fn, pattern); } finally { await db.exec('rollback to denied'); } };
try {
  await db.exec(`create role anon;create role authenticated;create role service_role;
  create schema public_api;create schema internal;create schema api;create schema core;create schema auth;create schema audit;create schema storage;
  create table auth.users(id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table internal.publication_runtime_state(singleton boolean primary key,enabled boolean);
  insert into internal.publication_runtime_state values(true,true);
  create table internal.migration_provenance(migration_name text,source_kind text,source_reference text);
  create table core.profiles(id uuid primary key);
  insert into core.profiles values('${publisher}'),('${outsider}');
  create table core.clubs(id uuid primary key,name text,slug text,status text default 'active');
  insert into core.clubs values('${club}','Testklubben');
  create table core.teams(id uuid primary key,club_id uuid,name text,status text default 'active',unique(id,club_id));
  create table core.club_publication_settings(club_id uuid primary key,public_id uuid,slug text,mode text,confirmation_id uuid);
  insert into core.club_publication_settings values('${club}','${clubPublic}','testklubben','published',gen_random_uuid());
  create table core.team_publication_settings(team_id uuid primary key,public_id uuid,slug text,mode text,confirmation_id uuid);
  create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb,primary key(actor_profile_id,idempotency_key,command_type));
  create table internal.publication_projection_jobs(club_id uuid,aggregate_type text,aggregate_id uuid,requested_revision bigint,action text,affected_paths text[],created_by uuid,
   unique(club_id,aggregate_type,aggregate_id,requested_revision,action));
  create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb,reason text);
  create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
  create table storage.objects(bucket_id text,name text,owner_id text,metadata jsonb);
  -- Publisher has publication.manage in the club; the outsider has nothing.
  create function internal.actor_has_capability(uuid,uuid,text) returns boolean language sql stable as $$select auth.uid()='${publisher}'::uuid$$;
  grant usage on schema api,internal,auth to authenticated,anon,service_role;`);
  const projection = read('supabase/migrations/20260815164018_s09_publication_consent_projection.sql');
  await db.exec(segment(projection, 'create table public_api.club_projections', 'alter table core.person_age_assertions'));
  const boundary = read('supabase/migrations/20260815170442_s09_public_api_contact_boundary.sql');
  await db.exec(segment(boundary, 'create table public_api.event_projections', 'create table internal.public_contact_submissions'));
  await db.exec(segment(boundary, 'create function internal.public_runtime_enabled', 'create function internal.public_search_clubs'));
  const catalog = read('supabase/migrations/20260827125738_pub02_catalog_publication_model.sql');
  await db.exec(segment(catalog, 'alter table public_api.club_projections', 'create function internal.publication_fields_valid'));
  await db.exec(`insert into public_api.club_projections(public_id,slug,name,visibility,source_revision,projected_at)
   values('${clubPublic}','testklubben','Testklubben','published',1,now())`).catch(async () => {
    await db.exec(`insert into public_api.club_projections(public_id,slug,name,source_revision,projected_at) values('${clubPublic}','testklubben','Testklubben',1,now())`);
  });
  await db.exec(read('supabase/migrations/20260827131955_pub03_editorial_news_flow.sql'));
  await db.exec(read('supabase/migrations/20260828083753_pub03_editorial_list_for_actor.sql'));
  await db.exec(read('supabase/migrations/20260925070651_pub03_disambiguate_editorial_draft_save.sql'));
  const events = read('supabase/migrations/20260827134457_pub04_events_partners_contact.sql');
  await db.exec(segment(events, 'create table core.public_media_assets', 'create table core.public_partners'));
  await db.exec(read('supabase/migrations/20260828092016_pub04_public_media_delivery.sql'));
  await db.exec(read('supabase/migrations/20261007090000_editorial_hero_image.sql'));
  await db.exec('begin');

  await as(publisher);
  const saved = await one(`select api.save_editorial_article($1,null,'forsta-nyheten','Första nyheten',null,
    '[{"type":"paragraph","text":"Hej"}]'::jsonb,null,true,'{}'::uuid[],0,gen_random_uuid())`, [club]);
  const article = saved.article_id;
  const stage = async () => one("select api.stage_public_media($1,'editorial_hero','image/jpeg',1000)", [club]);
  const asset1 = (await stage()).asset_id;
  const setHero = (asset, alt, revision, key = crypto.randomUUID()) =>
    one('select api.set_editorial_article_hero($1,$2,$3,$4,$5)', [article, asset, alt, revision, key]);
  const key = crypto.randomUUID();
  const hero = await setHero(asset1, '  Laget firar  ', saved.revision, key);
  assert.equal(hero.media_status, 'pending');
  assert.deepEqual(await setHero(asset1, 'Laget firar', saved.revision, key), hero, 'idempotent retry');
  await reject(() => setHero(asset1, 'x', saved.revision), /stale_revision/);
  let snapshot = await one('select api.get_editorial_article($1)', [article]);
  assert.equal(snapshot.hero_alt, 'Laget firar');
  assert.equal(snapshot.media_status, 'pending');
  assert.equal(snapshot.hero_path, null, 'nothing public before processing');
  console.log('PASS: hero is set on a draft, revision checked, idempotent and pending until processed');

  // Another club's or another purpose's media cannot be attached; outsiders are refused.
  await db.exec(`insert into core.clubs values('20000000-0000-4000-8000-000000000002','Annan')`);
  const foreign = await one("select api.stage_public_media('20000000-0000-4000-8000-000000000002','editorial_hero','image/jpeg',1000)");
  await reject(() => setHero(foreign.asset_id, null, hero.revision), /invalid_media|violates foreign key/);
  const logo = await one("select api.stage_public_media($1,'partner_logo','image/png',1000)", [club]);
  await reject(() => setHero(logo.asset_id, null, hero.revision), /invalid_media/);
  await as(outsider);
  await reject(() => setHero(asset1, null, hero.revision), /not_found/);
  await as(publisher);
  console.log('PASS: only the club publisher can attach the club\'s own editorial images');

  // Publishing before processing projects no image; processing then fills it in.
  const published = await one("select api.transition_editorial_article($1,'published',null,$2,gen_random_uuid())", [article, hero.revision]);
  let content = (await db.query('select media_path,media_alt from public_api.content_projections where public_id=$1', [article])).rows[0];
  assert.deepEqual(content, { media_path: null, media_alt: null });
  await reject(() => setHero(null, null, published.revision), /unpublish_before_edit/);
  const token = await one('select public_token from core.public_media_assets where id=$1', [asset1]);
  const variant = `${club}/${token}.webp`;
  await db.exec(`insert into storage.objects values('public-media-variants','${variant}',null,'{"mimetype":"image/webp"}')`);
  await db.query("select internal.finish_public_media_processing($1,'clean','ready',$2,1200,800)", [asset1, variant]);
  content = (await db.query('select media_path,media_alt from public_api.content_projections where public_id=$1', [article])).rows[0];
  assert.deepEqual(content, { media_path: `/media/public/${token}`, media_alt: 'Laget firar' });
  const page = await one("select internal.public_get_article('testklubben','forsta-nyheten',repeat('a',64))");
  assert.equal(page.media_path, `/media/public/${token}`);
  assert.equal(page.media_alt, 'Laget firar');
  assert.equal(await one("select count(*)::int from internal.publication_projection_jobs where aggregate_id=$1 and 'testklubben/nyheter/forsta-nyheten'=any(array(select trim(leading '/' from unnest(affected_paths))))", [article]) >= 1, true);
  console.log('PASS: processing after publishing updates the public article, image description and cache invalidation');

  // Replacing the image removes the old one from public delivery.
  const unpublished = await one("select api.transition_editorial_article($1,'unpublished',null,$2,gen_random_uuid())", [article, published.revision]);
  const asset2 = (await stage()).asset_id;
  const replaced = await setHero(asset2, 'Ny bild', unpublished.revision);
  assert.equal(await one('select variant_state from core.public_media_assets where id=$1', [asset1]), 'removed');
  assert.deepEqual(await one('select internal.resolve_public_media($1)', [token]), { not_found: true });
  const republished = await one("select api.transition_editorial_article($1,'published',null,$2,gen_random_uuid())", [article, replaced.revision]);
  content = (await db.query('select media_path from public_api.content_projections where public_id=$1', [article])).rows[0];
  assert.equal(content.media_path, null, 'new image not public until processed');
  // A rejected upload is never published.
  await db.query("select internal.finish_public_media_processing($1,'rejected','removed',null,null,null)", [asset2]);
  snapshot = await one('select api.get_editorial_article($1)', [article]);
  assert.equal(snapshot.media_status, 'rejected');
  assert.equal(snapshot.hero_path, null);
  // Removing the hero clears it.
  const down = await one("select api.transition_editorial_article($1,'unpublished',null,$2,gen_random_uuid())", [article, republished.revision]);
  const cleared = await setHero(null, 'ignored', down.revision);
  assert.equal(cleared.media_status, 'none');
  snapshot = await one('select api.get_editorial_article($1)', [article]);
  assert.equal(snapshot.hero_alt, null);
  console.log('PASS: replacing stops the old image, rejected uploads stay private and removal clears the hero');

  await as('');
  await reject(() => setHero(null, null, cleared.revision), /not_found/);
  assert.equal(await one("select has_function_privilege('anon','api.set_editorial_article_hero(uuid,uuid,text,bigint,uuid)','execute')"), false);
  console.log('PASS: unauthenticated and anonymous callers are refused');
} catch (error) {
  console.error(error.message, error.code ?? '', error.where ?? '');
  process.exitCode = 1;
} finally { await db.close(); }
