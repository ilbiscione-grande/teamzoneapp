-- Search only published allowlisted projections. Existing club-only RPC is unchanged.
alter table public_api.club_projections add column search_document tsvector
 generated always as (to_tsvector('simple'::regconfig,coalesce(name,'')||' '||coalesce(locality,''))) stored;
alter table public_api.team_projections add column search_document tsvector
 generated always as (to_tsvector('simple'::regconfig,coalesce(name,'')||' '||coalesce(age_class,''))) stored;
create index club_public_search_idx on public_api.club_projections using gin(search_document)
 where visibility in('listed','published');
create index team_public_search_idx on public_api.team_projections using gin(search_document)
 where visibility='published';

create function internal.public_search_directory(search_text text,ip_sha256_hex text,page_limit integer default 10)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tokens text[];all_terms tsquery;any_terms tsquery;rate jsonb;result jsonb;normalized text:=lower(btrim(search_text));
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false,'items','[]'::jsonb);end if;
 if search_text is null or length(normalized)<3 or length(search_text)>80 or page_limit is null or page_limit not between 1 and 10 then
  raise invalid_parameter_value using message='invalid_request';
 end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'search',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 select array_agg(distinct token) into tokens from regexp_split_to_table(normalized,'[^[:alnum:]]+') token where token<>'';
 if coalesce(cardinality(tokens),0)=0 then return jsonb_build_object('available',true,'items','[]'::jsonb,'has_more',false);end if;
 select to_tsquery('simple',string_agg(quote_literal(token)||':*',' & ')),
        to_tsquery('simple',string_agg(quote_literal(token)||':*',' | '))
 into all_terms,any_terms from unnest(tokens) token;
 with matching_clubs as materialized (
  select * from public_api.club_projections where visibility in('listed','published') and search_document@@any_terms
 ), candidate_teams as (
  select public_id from public_api.team_projections where visibility='published' and search_document@@any_terms
  union
  select t.public_id from public_api.team_projections t join matching_clubs c on c.public_id=t.club_public_id
   where t.visibility='published' and c.visibility='published'
 ), hits as (
  select 'club'::text kind,c.public_id id,c.slug,c.name,c.locality,c.official,c.visibility,
   null::text club_slug,null::text club_name,null::text age_class,
   case when lower(c.name)=normalized then 0 when to_tsvector('simple',c.name)@@all_terms then 1 else 2 end priority
  from matching_clubs c where c.search_document@@all_terms
  union all
  select 'team',t.public_id,t.slug,t.name,c.locality,c.official,t.visibility,c.slug,c.name,t.age_class,
   case when lower(t.name)=normalized then 0 when to_tsvector('simple',t.name)@@all_terms then 1 else 2 end
  from candidate_teams candidate join public_api.team_projections t on t.public_id=candidate.public_id
  join public_api.club_projections c on c.public_id=t.club_public_id
  where t.visibility='published' and c.visibility='published' and (t.search_document||c.search_document)@@all_terms
 ), limited as (
  select * from hits order by priority,kind,lower(name),id limit page_limit+1
 ) select coalesce(jsonb_agg(to_jsonb(limited)-'priority' order by priority,kind,lower(name),id),'[]'::jsonb) into result from limited;
 return jsonb_build_object('available',true,'items',(select coalesce(jsonb_agg(value order by ordinality),'[]'::jsonb)
  from jsonb_array_elements(result) with ordinality where ordinality<=page_limit),
  'has_more',jsonb_array_length(result)>page_limit,'cache_control','no-store');
end;$$;
create function api.public_search_directory(query text,ip_hash text,page_limit integer default 10)
returns jsonb language sql security invoker set search_path='' as
$$select internal.public_search_directory(query,ip_hash,page_limit)$$;
revoke all on function internal.public_search_directory(text,text,integer),api.public_search_directory(text,text,integer)
 from public,anon,authenticated;
grant execute on function internal.public_search_directory(text,text,integer),api.public_search_directory(text,text,integer)
 to service_role;
notify pgrst,'reload schema';
