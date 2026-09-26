-- A listed team is not a public channel; a direct URL must not bypass the club decision.
create or replace function internal.public_get_team(
  target_club_slug text,target_team_slug text,ip_sha256_hex text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rate jsonb;result jsonb;
begin
 if not internal.public_runtime_enabled() then return jsonb_build_object('available',false);end if;
 rate:=internal.consume_public_rate_limit(ip_sha256_hex,'read',null);
 if not(rate->>'allowed')::boolean then raise program_limit_exceeded using message='rate_limited';end if;
 select jsonb_build_object('id',team.public_id,'club_slug',team.club_slug,
  'slug',team.slug,'name',team.name,'age_class',team.age_class)
 into result from public_api.team_projections team
 join public_api.club_projections club on club.public_id=team.club_public_id
 where team.club_slug=lower(btrim(target_club_slug))
  and team.slug=lower(btrim(target_team_slug))
  and team.visibility='published' and club.visibility='published';
 return coalesce(result,jsonb_build_object('not_found',true));
end;$$;
