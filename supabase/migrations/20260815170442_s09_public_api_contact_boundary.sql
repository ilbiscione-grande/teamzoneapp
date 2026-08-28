-- S09 server-side public read/contact boundary. All entry points are
-- service_role-only and return unavailable while the immutable runtime gate is off.

create table public_api.event_projections (
  public_id uuid primary key,
  team_public_id uuid not null references public_api.team_projections(public_id) on delete cascade,
  starts_at timestamptz not null,
  event_type text not null check(event_type in ('training','match','meeting','activity')),
  title text not null check(length(btrim(title)) between 1 and 160),
  location_name text,
  source_revision bigint not null check(source_revision>0),
  projected_at timestamptz not null,
  check(location_name is null or length(btrim(location_name)) between 1 and 160)
);
create index event_projections_team_cursor_idx
  on public_api.event_projections(team_public_id,starts_at desc,public_id desc);

create table public_api.content_projections (
  public_id uuid primary key,
  club_public_id uuid not null references public_api.club_projections(public_id) on delete cascade,
  team_public_id uuid references public_api.team_projections(public_id) on delete cascade,
  content_type text not null check(content_type in ('news','media')),
  title text not null check(length(btrim(title)) between 1 and 160),
  summary text check(summary is null or length(summary)<=1000),
  media_path text check(media_path is null or media_path ~ '^/media/public/[A-Za-z0-9_-]+$'),
  published_at timestamptz not null,
  source_revision bigint not null check(source_revision>0),
  projected_at timestamptz not null
);
create index content_projections_club_cursor_idx
  on public_api.content_projections(club_public_id,published_at desc,public_id desc);
create index content_projections_team_cursor_idx
  on public_api.content_projections(team_public_id,published_at desc,public_id desc)
  where team_public_id is not null;

create table internal.public_rate_limit_buckets (
  ip_hash bytea not null check(octet_length(ip_hash)=32),
  route_class text not null check(route_class in ('read','search','contact')),
  scope_public_id uuid not null,
  bucket_started_at timestamptz not null,
  request_count integer not null default 1 check(request_count between 1 and 10000),
  expires_at timestamptz not null,
  primary key(ip_hash,route_class,scope_public_id,bucket_started_at),
  check(expires_at>bucket_started_at and expires_at<=bucket_started_at+interval '90 days 1 hour')
);
create index public_rate_limit_buckets_expiry_idx
  on internal.public_rate_limit_buckets(expires_at);

create table internal.public_contact_submissions (
  id uuid primary key default gen_random_uuid(),
  public_id uuid not null default gen_random_uuid() unique,
  club_id uuid not null references core.clubs(id),
  sender_name text not null,
  sender_email text not null,
  subject text not null,
  message_body text not null,
  captcha_assertion_hash bytea not null check(octet_length(captcha_assertion_hash)=32),
  state text not null default 'pending' check(state in ('pending','delivered','failed','rejected','erased')),
  delivery_attempts integer not null default 0 check(delivery_attempts between 0 and 10),
  last_error_code text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '30 days'),
  delivered_at timestamptz,
  erased_at timestamptz,
  revision bigint not null default 1 check(revision>0),
  check(expires_at<=created_at+interval '30 days 1 minute'),
  check((state='delivered' and delivered_at is not null) or state<>'delivered'),
  check(
    (state='erased' and erased_at is not null and sender_name='' and sender_email=''
      and subject='' and message_body='')
    or
    (state<>'erased' and erased_at is null
      and length(btrim(sender_name)) between 2 and 120
      and length(sender_email) between 3 and 254
      and length(btrim(subject)) between 2 and 160
      and length(btrim(message_body)) between 2 and 2000)
  )
);
create index public_contact_submissions_delivery_idx
  on internal.public_contact_submissions(state,created_at,id)
  where state in ('pending','failed');
create index public_contact_submissions_expiry_idx
  on internal.public_contact_submissions(expires_at,id)
  where state<>'erased';
create index public_contact_submissions_club_idx
  on internal.public_contact_submissions(club_id,created_at desc,id desc);

alter table public_api.event_projections enable row level security;
alter table public_api.content_projections enable row level security;
alter table internal.public_rate_limit_buckets enable row level security;
alter table internal.public_contact_submissions enable row level security;
create policy event_projections_no_client_access on public_api.event_projections
  for all to authenticated using(false) with check(false);
create policy content_projections_no_client_access on public_api.content_projections
  for all to authenticated using(false) with check(false);
create policy public_rate_limit_buckets_no_client_access on internal.public_rate_limit_buckets
  for all to authenticated using(false) with check(false);
create policy public_contact_submissions_no_client_access on internal.public_contact_submissions
  for all to authenticated using(false) with check(false);
revoke all on table public_api.event_projections,public_api.content_projections,
  internal.public_rate_limit_buckets,internal.public_contact_submissions
from public,anon,authenticated;

create function internal.public_runtime_enabled()
returns boolean language sql stable security definer set search_path='' as $$
  select coalesce((select enabled from internal.publication_runtime_state where singleton),false)
$$;

create function internal.consume_public_rate_limit(
  ip_sha256_hex text,new_route_class text,new_scope_public_id uuid
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare max_requests integer; bucket_span interval; bucket_start timestamptz;
  new_count integer; scope_id uuid:=coalesce(new_scope_public_id,'00000000-0000-0000-0000-000000000000');
begin
  if ip_sha256_hex !~ '^[0-9a-fA-F]{64}$' then raise invalid_parameter_value using message='invalid_request'; end if;
  if new_route_class='read' then max_requests:=60; bucket_span:=interval '1 minute';
  elsif new_route_class='search' then max_requests:=20; bucket_span:=interval '1 minute';
  elsif new_route_class='contact' then max_requests:=5; bucket_span:=interval '1 hour';
  else raise invalid_parameter_value using message='invalid_request'; end if;
  bucket_start:=date_bin(bucket_span,now(),'2000-01-01 00:00:00+00'::timestamptz);
  insert into internal.public_rate_limit_buckets(
    ip_hash,route_class,scope_public_id,bucket_started_at,request_count,expires_at
  ) values(
    decode(lower(ip_sha256_hex),'hex'),new_route_class,scope_id,bucket_start,1,
    case when new_route_class='contact' then bucket_start+interval '90 days'
      else bucket_start+interval '1 day' end
  ) on conflict(ip_hash,route_class,scope_public_id,bucket_started_at) do update
    set request_count=internal.public_rate_limit_buckets.request_count+1
  returning request_count into new_count;
  return jsonb_build_object('allowed',new_count<=max_requests,'remaining',greatest(0,max_requests-new_count));
end;
$$;

create function internal.public_search_clubs(
  search_text text,ip_sha256_hex text,page_limit integer default 10
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb; result jsonb;
begin
  if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'items','[]'::jsonb); end if;
  if length(btrim(coalesce(search_text,'')))<3 or length(search_text)>80 or page_limit not between 1 and 10
  then raise invalid_parameter_value using message='invalid_request'; end if;
  rate:=internal.consume_public_rate_limit(ip_sha256_hex,'search',null);
  if not (rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',public_id,'slug',slug,'name',name,'locality',locality,'profile_media_path',profile_media_path
  ) order by lower(name),public_id),'[]'::jsonb) into result
  from (select public_id,slug,name,locality,profile_media_path
    from public_api.club_projections
    where lower(name)>=lower(btrim(search_text)) and lower(name)<lower(btrim(search_text))||chr(1114111)
    order by lower(name),public_id limit page_limit) matches;
  return jsonb_build_object('available',true,'items',result,'cache_control','no-store');
end;
$$;

create function internal.public_get_club(
  club_slug text,ip_sha256_hex text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb; result jsonb;
begin
  if not internal.public_runtime_enabled() then return jsonb_build_object('available',false); end if;
  rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
  if not (rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited'; end if;
  select jsonb_build_object('id',public_id,'slug',slug,'name',name,'locality',locality,
    'description',description,'profile_media_path',profile_media_path) into result
  from public_api.club_projections where slug=lower(btrim(club_slug));
  return coalesce(result,jsonb_build_object('not_found',true));
end;
$$;

create function internal.public_get_team(
  target_club_slug text,target_team_slug text,ip_sha256_hex text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb; result jsonb;
begin
  if not internal.public_runtime_enabled() then return jsonb_build_object('available',false); end if;
  rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
  if not (rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited'; end if;
  select jsonb_build_object('id',public_id,'club_slug',team.club_slug,'slug',slug,'name',name,'age_class',age_class)
    into result from public_api.team_projections team
   where team.club_slug=lower(btrim(target_club_slug)) and team.slug=lower(btrim(target_team_slug));
  return coalesce(result,jsonb_build_object('not_found',true));
end;
$$;

create function internal.public_list_team_events(
  target_team_id uuid,before_starts_at timestamptz,before_id uuid,ip_sha256_hex text,page_limit integer default 20
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb; result jsonb;
begin
  if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'items','[]'::jsonb); end if;
  if page_limit not between 1 and 20 then raise invalid_parameter_value using message='invalid_request'; end if;
  rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
  if not (rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',public_id,'starts_at',starts_at,
    'event_type',event_type,'title',title,'location_name',location_name)
    order by starts_at desc,public_id desc),'[]'::jsonb) into result
  from (select * from public_api.event_projections event
    where event.team_public_id=target_team_id and (before_starts_at is null
      or (event.starts_at,event.public_id)<(before_starts_at,coalesce(before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff')))
    order by starts_at desc,public_id desc limit page_limit) page;
  return jsonb_build_object('available',true,'items',result,'cache_control','no-store');
end;
$$;

create function internal.public_list_publications(
  target_club_id uuid,target_team_id uuid,before_published_at timestamptz,before_id uuid,
  ip_sha256_hex text,page_limit integer default 20
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb; result jsonb;
begin
  if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'items','[]'::jsonb); end if;
  if page_limit not between 1 and 20 then raise invalid_parameter_value using message='invalid_request'; end if;
  rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
  if not (rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',public_id,'content_type',content_type,
    'title',title,'summary',summary,'media_path',media_path,'published_at',published_at)
    order by published_at desc,public_id desc),'[]'::jsonb) into result
  from (select * from public_api.content_projections content
    where content.club_public_id=target_club_id and (target_team_id is null or content.team_public_id=target_team_id)
      and (before_published_at is null or (content.published_at,content.public_id)<
        (before_published_at,coalesce(before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff')))
    order by published_at desc,public_id desc limit page_limit) page;
  return jsonb_build_object('available',true,'items',result,'cache_control','no-store');
end;
$$;

create function internal.public_submit_contact(
  target_club_public_id uuid,new_sender_name text,new_sender_email text,new_subject text,
  new_message_body text,ip_sha256_hex text,captcha_verified boolean,
  captcha_assertion_sha256_hex text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb; target_club_id uuid; submission_id uuid;
begin
  if not internal.public_runtime_enabled() then return jsonb_build_object('accepted',false,'code','unavailable'); end if;
  if captcha_verified is not true or captcha_assertion_sha256_hex !~ '^[0-9a-fA-F]{64}$'
     or length(btrim(coalesce(new_sender_name,''))) not between 2 and 120
     or length(coalesce(new_sender_email,'')) not between 3 and 254
     or new_sender_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or length(btrim(coalesce(new_subject,''))) not between 2 and 160
     or length(btrim(coalesce(new_message_body,''))) not between 2 and 2000 then
    raise invalid_parameter_value using message='invalid_request';
  end if;
  select setting.club_id into target_club_id
   from core.club_publication_settings setting
   join public_api.club_projections projection on projection.public_id=setting.public_id
   where setting.public_id=target_club_public_id and setting.mode='draft';
  if target_club_id is null then return jsonb_build_object('accepted',true); end if;
  rate:=internal.consume_public_rate_limit(ip_sha256_hex,'contact',target_club_public_id);
  if not (rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited'; end if;
  insert into internal.public_contact_submissions(
    club_id,sender_name,sender_email,subject,message_body,captcha_assertion_hash
  ) values(
    target_club_id,btrim(new_sender_name),lower(btrim(new_sender_email)),btrim(new_subject),
    btrim(new_message_body),decode(lower(captcha_assertion_sha256_hex),'hex')
  ) returning public_id into submission_id;
  return jsonb_build_object('accepted',true,'reference',submission_id);
end;
$$;

create function internal.apply_public_contact_retention(batch_size integer default 100)
returns integer language plpgsql security definer set search_path='' as $$
declare changed integer;
begin
  if batch_size not between 1 and 500 then raise invalid_parameter_value using message='invalid_batch'; end if;
  with targets as (select id from internal.public_contact_submissions
    where state<>'erased' and expires_at<=now() order by expires_at,id for update skip locked limit batch_size)
  update internal.public_contact_submissions submission set
    sender_name='',sender_email='',subject='',message_body='',state='erased',erased_at=now(),
    captcha_assertion_hash=extensions.digest(gen_random_uuid()::text,'sha256'),revision=revision+1
  from targets where submission.id=targets.id;
  get diagnostics changed=row_count;
  delete from internal.public_rate_limit_buckets where expires_at<=now();
  return changed;
end;
$$;

revoke all on function internal.public_runtime_enabled(),
  internal.consume_public_rate_limit(text,text,uuid),internal.public_search_clubs(text,text,integer),
  internal.public_get_club(text,text),internal.public_get_team(text,text,text),
  internal.public_list_team_events(uuid,timestamptz,uuid,text,integer),
  internal.public_list_publications(uuid,uuid,timestamptz,uuid,text,integer),
  internal.public_submit_contact(uuid,text,text,text,text,text,boolean,text),
  internal.apply_public_contact_retention(integer)
from public,anon,authenticated;
grant execute on function internal.public_search_clubs(text,text,integer),
  internal.public_get_club(text,text),internal.public_get_team(text,text,text),
  internal.public_list_team_events(uuid,timestamptz,uuid,text,integer),
  internal.public_list_publications(uuid,uuid,timestamptz,uuid,text,integer),
  internal.public_submit_contact(uuid,text,text,text,text,text,boolean,text),
  internal.apply_public_contact_retention(integer)
to service_role;

create function api.public_search_clubs(query text,ip_hash text,page_limit integer default 10)
returns jsonb language sql security invoker set search_path='' as
$$select internal.public_search_clubs(query,ip_hash,page_limit)$$;
create function api.public_get_club(slug text,ip_hash text) returns jsonb language sql security invoker set search_path='' as
$$select internal.public_get_club(slug,ip_hash)$$;
create function api.public_get_team(club_slug text,team_slug text,ip_hash text) returns jsonb language sql security invoker set search_path='' as
$$select internal.public_get_team(club_slug,team_slug,ip_hash)$$;
create function api.public_list_team_events(team_id uuid,before_starts_at timestamptz,before_id uuid,ip_hash text,page_limit integer default 20)
returns jsonb language sql security invoker set search_path='' as
$$select internal.public_list_team_events(team_id,before_starts_at,before_id,ip_hash,page_limit)$$;
create function api.public_list_publications(club_id uuid,team_id uuid,before_published_at timestamptz,before_id uuid,ip_hash text,page_limit integer default 20)
returns jsonb language sql security invoker set search_path='' as
$$select internal.public_list_publications(club_id,team_id,before_published_at,before_id,ip_hash,page_limit)$$;
create function api.public_submit_contact(club_id uuid,sender_name text,sender_email text,subject text,message_body text,ip_hash text,captcha_verified boolean,captcha_assertion_hash text)
returns jsonb language sql security invoker set search_path='' as
$$select internal.public_submit_contact(club_id,sender_name,sender_email,subject,message_body,ip_hash,captcha_verified,captcha_assertion_hash)$$;
create function api.apply_public_contact_retention(batch_size integer default 100)
returns integer language sql security invoker set search_path='' as
$$select internal.apply_public_contact_retention(batch_size)$$;

revoke all on function api.public_search_clubs(text,text,integer),api.public_get_club(text,text),
  api.public_get_team(text,text,text),api.public_list_team_events(uuid,timestamptz,uuid,text,integer),
  api.public_list_publications(uuid,uuid,timestamptz,uuid,text,integer),
  api.public_submit_contact(uuid,text,text,text,text,text,boolean,text),
  api.apply_public_contact_retention(integer)
from public,anon,authenticated;
grant execute on function api.public_search_clubs(text,text,integer),api.public_get_club(text,text),
  api.public_get_team(text,text,text),api.public_list_team_events(uuid,timestamptz,uuid,text,integer),
  api.public_list_publications(uuid,uuid,timestamptz,uuid,text,integer),
  api.public_submit_contact(uuid,text,text,text,text,text,boolean,text),
  api.apply_public_contact_retention(integer)
to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815170442_s09_public_api_contact_boundary','greenfield',
  'Service-only allowlist; 60/20/5 limits; CAPTCHA assertion; 30-day contact and 90-day abuse retention; runtime disabled');
