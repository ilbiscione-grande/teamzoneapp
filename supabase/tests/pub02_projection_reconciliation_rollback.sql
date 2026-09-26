-- Run only in the approved test project, after separate approval.
-- psql -v ON_ERROR_STOP=1 -f this-file.sql
begin;
\ir ../migrations/20260925175025_pub02_projection_reconciliation.sql
\ir ../migrations/20260925175933_pub02_publication_worker_delivery.sql

do $$
declare
  pilot_club_id uuid;
  pilot_team_id uuid;
  club_job uuid;
  team_job uuid;
  result jsonb;
  saved_club core.club_publication_settings%rowtype;
  current_revision bigint;
begin
  if internal.public_runtime_enabled() then
    raise exception 'Expected disabled runtime for rollback rehearsal';
  end if;
  select s.club_id into strict pilot_club_id from core.club_publication_settings s
    where s.slug='thomas-klubb-6379829a' and s.mode='published';
  select s.team_id into strict pilot_team_id from core.team_publication_settings s
    where s.club_id=pilot_club_id and s.slug='thomas-lag' and s.mode='published';
  select j.id into strict club_job from internal.publication_projection_jobs j
    where j.aggregate_id=pilot_club_id and j.action='remove' order by j.created_at desc limit 1;
  select j.id into strict team_job from internal.publication_projection_jobs j
    where j.aggregate_id=pilot_team_id and j.action='remove' order by j.created_at desc limit 1;

  -- Late remove jobs must converge to the current published state.
  update internal.publication_projection_jobs set state='processing' where id=club_job;
  result:=internal.apply_publication_projection_job(club_job);
  if result->>'state'<>'awaiting_invalidation' then raise exception 'Club rebuild failed: %',result;end if;
  update internal.publication_projection_jobs set state='processing' where id=team_job;
  result:=internal.apply_publication_projection_job(team_job);
  if result->>'state'<>'awaiting_invalidation' then raise exception 'Team rebuild failed: %',result;end if;
  if not exists(select 1 from public_api.team_projections where slug='thomas-lag') then
    raise exception 'Late remove erased current team';
  end if;

  update core.club_publication_settings set mode='private' where core.club_publication_settings.club_id=pilot_club_id;
  update internal.publication_projection_jobs set state='processing' where id=club_job;
  perform internal.apply_publication_projection_job(club_job);
  if exists(select 1 from public_api.club_projections where slug='thomas-klubb-6379829a')
    or exists(select 1 from public_api.team_projections where slug='thomas-lag') then
    raise exception 'Private club left public club/team projection';
  end if;

  update core.club_publication_settings set mode='published' where core.club_publication_settings.club_id=pilot_club_id;
  update internal.publication_projection_jobs set state='processing' where id=club_job;
  perform internal.apply_publication_projection_job(club_job);
  update internal.publication_projection_jobs set state='processing' where id=team_job;
  perform internal.apply_publication_projection_job(team_job);
  if not exists(select 1 from public_api.team_projections where slug='thomas-lag') then
    raise exception 'Team did not return after club republished';
  end if;

  -- Exercise the actual command and collision with already completed team jobs.
  select * into strict saved_club from core.club_publication_settings s where s.club_id=pilot_club_id;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',saved_club.changed_by,'role','authenticated')::text,true);
  update internal.publication_projection_jobs set state='completed',completed_at=now(),attempts=2
    where aggregate_id=pilot_team_id and requested_revision=(select revision from core.team_publication_settings where core.team_publication_settings.team_id=pilot_team_id);
  result:=internal.configure_publication_v2_for_actor(
    pilot_club_id,'club',pilot_club_id,'private',saved_club.slug,array[]::text[],
    saved_club.locality,saved_club.published_description,null,'pub02-self-service-v1',
    now()+interval '365 days',saved_club.revision,gen_random_uuid());
  current_revision:=(result->>'revision')::bigint;
  if not exists(select 1 from internal.publication_projection_jobs
    where id=team_job and state='pending' and completed_at is null and attempts=0) then
    raise exception 'Club unpublish did not requeue completed team remove';
  end if;
  result:=internal.configure_publication_v2_for_actor(
    pilot_club_id,'club',pilot_club_id,'published',saved_club.slug,saved_club.published_fields,
    saved_club.locality,saved_club.published_description,null,'pub02-self-service-v1',
    now()+interval '365 days',current_revision,gen_random_uuid());
  if not exists(select 1 from internal.publication_projection_jobs j
    where j.aggregate_id=pilot_team_id and j.action='rebuild' and j.state='pending'
      and j.completed_at is null and j.attempts=0
      and j.requested_revision=(select revision from core.team_publication_settings where core.team_publication_settings.team_id=pilot_team_id)) then
    raise exception 'Club republish did not requeue completed team rebuild';
  end if;
  if internal.public_runtime_enabled() then raise exception 'Runtime changed';end if;
  if has_function_privilege('anon','api.apply_publication_projection_job(uuid)','execute') then
    raise exception 'Anonymous worker execution allowed';
  end if;
end;
$$;

do $$
declare results jsonb; deliveries jsonb; next_claim jsonb; item jsonb; receipt jsonb;
begin
 results:=internal.process_publication_projection_batch(50);
 if exists(select 1 from jsonb_array_elements(results) r where r->>'state'<>'awaiting_invalidation') then
  raise exception 'Projection batch did not succeed: %',results;
 end if;
 if exists(select 1 from internal.publication_projection_jobs where state='processing') then
  raise exception 'Atomic worker left a processing job';
 end if;
 deliveries:=internal.claim_publication_delivery(50);
 if jsonb_array_length(deliveries)=0 then raise exception 'No deliveries claimed';end if;
 if internal.claim_publication_delivery(50)<>'[]'::jsonb then raise exception 'Active claim was duplicated';end if;
 item:=deliveries->0;
 receipt:=internal.finish_publication_delivery((item->>'id')::uuid,gen_random_uuid(),true);
 if receipt->>'state'<>'stale_claim' then raise exception 'Wrong lease accepted';end if;
 update internal.publication_projection_jobs set invalidation_claimed_at=now()-interval '11 minutes'
  where id=(item->>'id')::uuid;
 next_claim:=internal.claim_publication_delivery(50)->0;
 receipt:=internal.finish_publication_delivery((item->>'id')::uuid,(item->>'invalidation_token')::uuid,true);
 if receipt->>'state'<>'stale_claim' then raise exception 'Expired lease accepted';end if;
 receipt:=internal.finish_publication_delivery((next_claim->>'id')::uuid,(next_claim->>'invalidation_token')::uuid,false);
 if receipt->>'state'<>'failed' then raise exception 'Cache failure did not fail job';end if;
 for item in select value from jsonb_array_elements(deliveries) loop
  if item->>'id'<>next_claim->>'id' then
   receipt:=internal.finish_publication_delivery((item->>'id')::uuid,(item->>'invalidation_token')::uuid,true);
   if receipt->>'state'<>'completed' then raise exception 'Valid acknowledgement failed';end if;
  end if;
 end loop;
 if internal.public_runtime_enabled() then raise exception 'Runtime enabled unexpectedly';end if;
 if has_function_privilege('anon','api.process_publication_projection_batch(integer)','execute')
  or has_function_privilege('authenticated','api.claim_publication_delivery(integer)','execute')
  or has_function_privilege('authenticated','api.finish_publication_delivery(uuid,uuid,boolean)','execute') then
  raise exception 'Client worker access allowed';
 end if;
end;
$$;
rollback;

