-- Service-only worker delivery. Does not change the public runtime gate.
alter table internal.publication_projection_jobs add column invalidation_token uuid;

create function internal.reset_publication_delivery_claim()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.state<>'awaiting_invalidation' or old.state<>'awaiting_invalidation' then
  new.invalidation_token:=null;
  new.invalidation_claimed_at:=null;
 end if;
 return new;
end;$$;
create trigger publication_delivery_claim_reset before update of state
 on internal.publication_projection_jobs for each row
 execute function internal.reset_publication_delivery_claim();
revoke all on function internal.reset_publication_delivery_claim() from public,anon,authenticated;

create function internal.process_publication_projection_batch(batch_size integer default 20)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job record;results jsonb:='[]'::jsonb;
begin
 if batch_size not between 1 and 50 then raise invalid_parameter_value using message='invalid_batch';end if;
 -- One transaction owns both claiming and projection. A crash rolls both back.
 if not pg_try_advisory_xact_lock(hashtextextended('publication-projection-worker',0)) then return results;end if;
 for job in select id from internal.publication_projection_jobs
  where action in('rebuild','remove') and aggregate_type in('club','team')
   and state in('pending','failed') and available_at<=now() and attempts<20
  order by case aggregate_type when 'club' then 0 else 1 end,created_at,id
  for update skip locked limit batch_size
 loop
  update internal.publication_projection_jobs set state='processing',attempts=attempts+1,
    completed_at=null,last_error_code=null where id=job.id;
  results:=results||jsonb_build_array(internal.apply_publication_projection_job(job.id));
 end loop;
 return results;
end;$$;

create function internal.claim_publication_delivery(batch_size integer default 20)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if batch_size not between 1 and 50 then raise invalid_parameter_value using message='invalid_batch';end if;
 -- Includes projected rebuild/remove jobs, not just standalone invalidate jobs.
 with claimed as (
  select id from internal.publication_projection_jobs
  where (state='awaiting_invalidation' and
     (invalidation_claimed_at is null or invalidation_claimed_at<now()-interval '10 minutes'))
   or (action='invalidate' and state in('pending','failed') and available_at<=now() and attempts<20)
  order by created_at,id for update skip locked limit batch_size
 ), prepared as (
  update internal.publication_projection_jobs j set state='awaiting_invalidation',
   completed_at=null,attempts=case when j.state='awaiting_invalidation' then j.attempts else j.attempts+1 end
  from claimed where j.id=claimed.id returning j.id
 ) select coalesce(jsonb_agg(id),'[]'::jsonb) into result from prepared;
 -- Separate update so the state transition trigger cannot erase the new lease.
 with leased as (
  update internal.publication_projection_jobs j set invalidation_claimed_at=now(),
   invalidation_token=gen_random_uuid()
  where j.id in(select value::uuid from jsonb_array_elements_text(result))
  returning j.id,j.affected_paths,j.invalidation_token
 ) select coalesce(jsonb_agg(to_jsonb(leased)),'[]'::jsonb) into result from leased;
 return result;
end;$$;

create function internal.finish_publication_delivery(target_job_id uuid,claim_token uuid,
 invalidation_succeeded boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job internal.publication_projection_jobs%rowtype;
begin
 select * into job from internal.publication_projection_jobs where id=target_job_id for update;
 if job.id is null or job.state<>'awaiting_invalidation' or claim_token is null
  or job.invalidation_token is distinct from claim_token then
  return jsonb_build_object('state','stale_claim');
 end if;
 return internal.finish_publication_invalidation(target_job_id,invalidation_succeeded,
  case when invalidation_succeeded then null else 'invalidation_failed' end);
end;$$;

create function api.process_publication_projection_batch(batch_size integer default 20)
returns jsonb language sql security invoker set search_path='' as
$$select internal.process_publication_projection_batch(batch_size)$$;
create function api.claim_publication_delivery(batch_size integer default 20)
returns jsonb language sql security invoker set search_path='' as
$$select internal.claim_publication_delivery(batch_size)$$;
create function api.finish_publication_delivery(job_id uuid,claim_token uuid,succeeded boolean)
returns jsonb language sql security invoker set search_path='' as
$$select internal.finish_publication_delivery(job_id,claim_token,succeeded)$$;
revoke all on function internal.process_publication_projection_batch(integer),
 internal.claim_publication_delivery(integer),internal.finish_publication_delivery(uuid,uuid,boolean),
 api.process_publication_projection_batch(integer),api.claim_publication_delivery(integer),
 api.finish_publication_delivery(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function internal.process_publication_projection_batch(integer),
 internal.claim_publication_delivery(integer),internal.finish_publication_delivery(uuid,uuid,boolean),
 api.process_publication_projection_batch(integer),api.claim_publication_delivery(integer),
 api.finish_publication_delivery(uuid,uuid,boolean) to service_role;
notify pgrst,'reload schema';
