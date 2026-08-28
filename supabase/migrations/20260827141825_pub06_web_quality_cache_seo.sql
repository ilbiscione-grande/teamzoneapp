-- PUB-06 cache invalidation claims and service-only sitemap projection.

alter table internal.publication_projection_jobs add column invalidation_claimed_at timestamptz;

create function internal.claim_publication_invalidation_jobs(batch_size integer default 20)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if batch_size not between 1 and 50 then raise invalid_parameter_value using message='invalid_batch';end if;
 update internal.publication_projection_jobs set state='failed',available_at=now(),
  last_error_code='invalidation_worker_timeout',invalidation_claimed_at=null
 where state='awaiting_invalidation' and invalidation_claimed_at<now()-interval '10 minutes';
 with claimed as(
  select id from internal.publication_projection_jobs
  where action='invalidate' and state in('pending','failed') and available_at<=now() and attempts<20
  order by available_at,created_at,id for update skip locked limit batch_size
 ),updated as(
  update internal.publication_projection_jobs job set state='awaiting_invalidation',attempts=attempts+1,
   last_error_code=null,invalidation_claimed_at=now()
  from claimed where job.id=claimed.id
  returning job.id,job.affected_paths,job.attempts
 ) select coalesce(jsonb_agg(to_jsonb(updated) order by updated.id),'[]'::jsonb) into result from updated;
 return result;
end;$$;

create or replace function internal.finish_publication_invalidation(target_job_id uuid,
 invalidation_succeeded boolean,new_error_code text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job internal.publication_projection_jobs%rowtype;
begin
 select * into job from internal.publication_projection_jobs where id=target_job_id for update;
 if job.id is null or job.state<>'awaiting_invalidation' then
  raise object_not_in_prerequisite_state using message='job_not_awaiting_invalidation';end if;
 if invalidation_succeeded then
  update internal.publication_projection_jobs set state='completed',completed_at=now(),last_error_code=null,
   invalidation_claimed_at=null where id=job.id;
  return jsonb_build_object('job_id',job.id,'state','completed');
 end if;
 update internal.publication_projection_jobs set state='failed',
  available_at=now()+least(interval '15 minutes',interval '30 seconds'*(2^least(attempts,5))),
  last_error_code=coalesce(nullif(btrim(new_error_code),''),'cache_invalidation_failed'),
  invalidation_claimed_at=null where id=job.id;
 return jsonb_build_object('job_id',job.id,'state','failed');
end;$$;

create function internal.public_sitemap_entries()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not internal.public_runtime_enabled() then return '[]'::jsonb;end if;
 select coalesce(jsonb_agg(entry order by entry->>'url_key'),'[]'::jsonb) into result from(
  select jsonb_build_object('url_key','club:'||club.slug,'kind','club','club_slug',club.slug,
   'external_path','/','path_url','/'||club.slug,'canonical_hostname',domain.hostname,
   'last_modified',club.projected_at) entry
  from public_api.club_projections club
  left join core.club_publication_settings setting on setting.public_id=club.public_id
  left join core.publication_domains domain on domain.club_id=setting.club_id and domain.canonical
   and domain.state='active' and domain.tls_state='ready' and domain.commercial_state='approved'
  where club.visibility='published'
  union all
  select jsonb_build_object('url_key','team:'||team.club_slug||':'||team.slug,'kind','team','club_slug',team.club_slug,
   'external_path','/'||team.slug,'path_url','/'||team.club_slug||'/'||team.slug,
   'canonical_hostname',domain.hostname,'last_modified',team.projected_at)
  from public_api.team_projections team
  join public_api.club_projections club on club.public_id=team.club_public_id and club.visibility='published'
  left join core.club_publication_settings setting on setting.public_id=club.public_id
  left join core.publication_domains domain on domain.club_id=setting.club_id and domain.canonical
   and domain.state='active' and domain.tls_state='ready' and domain.commercial_state='approved'
  where team.visibility='published'
  union all
  select jsonb_build_object('url_key','news:'||club.slug||':'||content.slug,'kind','news','club_slug',club.slug,
   'external_path','/nyheter/'||content.slug,'path_url','/'||club.slug||'/nyheter/'||content.slug,
   'canonical_hostname',domain.hostname,'last_modified',content.projected_at)
  from public_api.content_projections content
  join public_api.club_projections club on club.public_id=content.club_public_id and club.visibility='published'
  left join core.club_publication_settings setting on setting.public_id=club.public_id
  left join core.publication_domains domain on domain.club_id=setting.club_id and domain.canonical
   and domain.state='active' and domain.tls_state='ready' and domain.commercial_state='approved'
  where content.content_type='news' and content.slug is not null
 ) entries;
 return result;
end;$$;

create function api.claim_publication_invalidation_jobs(batch_size integer default 20)
returns jsonb language sql security invoker set search_path='' as
$$select internal.claim_publication_invalidation_jobs(batch_size)$$;
create function api.public_sitemap_entries() returns jsonb language sql stable security invoker set search_path='' as
$$select internal.public_sitemap_entries()$$;

revoke all on function internal.claim_publication_invalidation_jobs(integer),internal.public_sitemap_entries(),
 api.claim_publication_invalidation_jobs(integer),api.public_sitemap_entries() from public,anon,authenticated;
grant execute on function internal.claim_publication_invalidation_jobs(integer),internal.public_sitemap_entries(),
 api.claim_publication_invalidation_jobs(integer),api.public_sitemap_entries() to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827141825_pub06_web_quality_cache_seo','greenfield','PUB-06 service-only invalidation claim and sitemap projection; no live match scope');
notify pgrst,'reload schema';
