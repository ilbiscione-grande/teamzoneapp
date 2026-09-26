// Isolated PostgreSQL tests, never a hosted database connection.
// npm install --prefix .tmp-search-test --no-audit --no-fund @electric-sql/pglite
// node supabase/tests/pub07_personal_home.local.mjs
import { PGlite } from '../../.tmp-search-test/node_modules/@electric-sql/pglite/dist/index.js';
import { readFileSync } from 'node:fs';
const read = p => readFileSync(new URL('../../'+p,import.meta.url),'utf8');
const segment = (s,start,end) => { const a=s.indexOf(start),b=s.indexOf(end,a);if(a<0||b<0)throw Error('Missing SQL segment');return s.slice(a,b); };
const db=new PGlite();
try {
 await db.exec(`create role anon;create role authenticated;create role service_role;
 create schema public_api;create schema internal;create schema api;create schema core;create schema auth;create schema audit;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table internal.publication_runtime_state(singleton boolean primary key,enabled boolean);
 insert into internal.publication_runtime_state values(true,true);
 create table core.profiles(id uuid primary key);
 create table core.teams(id uuid primary key,club_id uuid,name text);
 create table core.events(id uuid primary key,club_id uuid,owning_team_id uuid,state text,event_type text,title text,starts_at timestamptz,location_id uuid,unique(id,club_id,owning_team_id));
 create table core.event_locations(id uuid primary key,name text);
 create table core.club_publication_settings(club_id uuid primary key,public_id uuid,slug text,mode text);
 create table core.team_publication_settings(team_id uuid primary key,public_id uuid,slug text,mode text,confirmation_id uuid);
 create table core.match_workspaces(event_id uuid primary key,state text);
 create table core.match_projections(event_id uuid primary key,revision bigint,score_us integer,score_opponent integer);
 create table core.public_partners(id uuid,club_id uuid,name text,website_url text,state text,sort_order integer,revision bigint,logo_asset_id uuid);
 create table core.public_media_assets(id uuid,variant_state text);
 create table internal.command_deduplication(actor_profile_id uuid,idempotency_key uuid,command_type text,result jsonb,primary key(actor_profile_id,idempotency_key,command_type));
 create table internal.publication_projection_jobs(club_id uuid,aggregate_type text,aggregate_id uuid,requested_revision bigint,action text,affected_paths text[],created_by uuid);
 create table audit.command_events(club_id uuid,actor_profile_id uuid,command_type text,aggregate_type text,aggregate_id uuid,aggregate_revision bigint,metadata jsonb);
 -- Controlled capability fixture: account A is publisher, account B has no mandate.
 create function internal.actor_has_capability(uuid,uuid,text) returns boolean language sql stable as $$select auth.uid()='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid$$;
 grant usage on schema api,internal,auth to authenticated,anon,service_role;
 `);
 const projection=read('supabase/migrations/20260815164018_s09_publication_consent_projection.sql');
 await db.exec(segment(projection,'create table public_api.club_projections','alter table core.person_age_assertions'));
 const boundary=read('supabase/migrations/20260815170442_s09_public_api_contact_boundary.sql');
 await db.exec(segment(boundary,'create table public_api.event_projections','create table internal.public_contact_submissions'));
 await db.exec(segment(boundary,'create function internal.public_runtime_enabled','create function internal.public_search_clubs'));
 const catalog=read('supabase/migrations/20260827125738_pub02_catalog_publication_model.sql');
 await db.exec(segment(catalog,'alter table public_api.club_projections','create function internal.publication_fields_valid'));
 const articles=read('supabase/migrations/20260827131955_pub03_editorial_news_flow.sql');
 await db.exec(segment(articles,'alter table public_api.content_projections add column','alter table public_api.content_team_channels enable'));
 const events=read('supabase/migrations/20260827134457_pub04_events_partners_contact.sql');
 await db.exec(segment(events,'create table core.event_publication_settings','create table public_api.partner_projections'));
 await db.exec(segment(events,'create function internal.configure_event_publication_for_actor','create function internal.save_public_partner_for_actor'));
 await db.exec(segment(events,'create function api.configure_event_publication','create function api.save_public_partner'));
 await db.exec(read('supabase/migrations/20260925203332_pub07_account_follows_and_feed.sql'));
 await db.exec(read('supabase/migrations/20260925203446_pub07_explicit_public_match_results.sql'));
 if (process.argv.includes('--dashboard')) {
  await db.exec(`create function internal.get_my_contexts_for_actor() returns table(team_id uuid,team_name text,club_id uuid,club_name text) language sql stable as $$select id,name,club_id,'Testklubb'::text from core.teams where id='20000000-0000-4000-8000-000000000001' and auth.uid()='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$`);
  await db.exec(read('supabase/migrations/20260926062708_pub09_personal_dashboard_content.sql'));
  await db.exec(read('supabase/tests/pub07_personal_home.sql').split('do $$')[0]);
  await db.exec(read('supabase/tests/pub09_dashboard.sql'));
  console.log('PASS: own content without follow, other-team isolation, public calendar types, deduplication, runtime and anonymous gates');
 } else if (process.argv.includes('--team-visibility') || process.argv.includes('--direct-result')) {
  await db.exec("alter table internal.publication_projection_jobs add column state text default 'pending', add column available_at timestamptz default now(), add column attempts integer default 0, add column completed_at timestamptz, add column last_error_code text, add unique(club_id,aggregate_type,aggregate_id,requested_revision,action)");
  await db.exec(read('supabase/migrations/20260926012847_pub08_team_event_visibility.sql'));
  await db.exec(read('supabase/migrations/20260926060124_pub08_invalidation_queue_keys.sql'));
  const fixture=read('supabase/tests/pub07_personal_home.sql').split('do $$')[0];
  await db.exec(fixture);
  await db.exec('alter table core.events add column archived_at timestamptz');
  if (process.argv.includes('--direct-result')) {
   const { testDirectResult } = await import('./match_direct_result.local.mjs');
   await testDirectResult(db, read, segment);
  } else {
   await db.exec(read('supabase/tests/pub08_team_event_visibility.sql'));
   console.log('PASS: team-wide visibility, completed results, future events, corrections, cancellation, privacy, revisions and authorization');
  }
 } else await db.exec(read('supabase/tests/pub07_personal_home.sql'));
 if (!process.argv.includes('--team-visibility') && !process.argv.includes('--dashboard') && !process.argv.includes('--direct-result')) console.log('PASS: account isolation, follow/unfollow, no membership requirement, deduplicated feed, cursor, publication opt-in, score corrections and runtime/privacy gates');
} catch(error) {
 console.error(error.message, error.code ?? '', error.where ?? '');
 process.exitCode=1;
} finally { await db.close(); }
