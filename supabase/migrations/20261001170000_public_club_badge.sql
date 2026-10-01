-- PUB-11: the club badge on the public club and team pages. A published
-- club shows its active badge through an unguessable address on the public
-- site; the site's server resolves it with the service key. Replacing or
-- removing the badge, or unpublishing the club, stops the old address.

alter table core.club_badges
 add column if not exists public_token text not null default md5(random()::text||clock_timestamp()::text||gen_random_uuid()::text);
create unique index if not exists club_badges_public_token on core.club_badges(public_token);

create or replace function internal.public_club_badge_path(target_club_id uuid)
returns text language sql stable security definer set search_path='' as $$
 select '/media/public/'||badge.public_token from core.clubs club
 join core.club_badges badge on badge.id=club.badge_asset_id and badge.state='active'
 where club.id=target_club_id
$$;

-- Projection carries the path; a badge change updates a published page at once.
do $patch$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.apply_publication_projection_job(uuid)'::regprocedure);
 patched:=replace(definition,
  'accent_color=club_row.brand_accent_color where public_id=club_setting.public_id;',
  'accent_color=club_row.brand_accent_color,
    profile_media_path=internal.public_club_badge_path(club_row.id) where public_id=club_setting.public_id;');
 if patched=definition then raise exception 'apply_publication_projection_job: patch point not found'; end if;
 execute patched;
end$patch$;

create or replace function internal.sync_public_club_badge()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public_api.club_projections projection set profile_media_path=internal.public_club_badge_path(new.id)
 from core.club_publication_settings setting
 where setting.club_id=new.id and projection.public_id=setting.public_id;
 return new;
end$$;
drop trigger if exists clubs_sync_public_badge on core.clubs;
create trigger clubs_sync_public_badge after update of badge_asset_id on core.clubs
for each row execute function internal.sync_public_club_badge();

create or replace function internal.resolve_public_club_badge(public_token text)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('bucket_id',badge.bucket_id,'object_key',badge.object_key,'mime_type',badge.mime_type)
  from core.club_badges badge
  join core.clubs club on club.badge_asset_id=badge.id and club.status='active'
  join core.club_publication_settings setting on setting.club_id=club.id
  join public_api.club_projections projection on projection.public_id=setting.public_id and projection.visibility='published'
  where badge.public_token=resolve_public_club_badge.public_token and badge.state='active'),
  jsonb_build_object('not_found',true))
$$;
create or replace function api.resolve_public_club_badge(public_token text)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.resolve_public_club_badge(public_token)$$;

revoke all on function internal.public_club_badge_path(uuid),internal.sync_public_club_badge(),
 internal.resolve_public_club_badge(text),api.resolve_public_club_badge(text) from public,anon,authenticated;
grant execute on function internal.resolve_public_club_badge(text),api.resolve_public_club_badge(text) to service_role;

-- Clubs already published get their badge now.
update public_api.club_projections projection set profile_media_path=internal.public_club_badge_path(setting.club_id)
from core.club_publication_settings setting where projection.public_id=setting.public_id;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261001170000_public_club_badge','greenfield','PUB-11 club badge on the public pages'
where not exists(select 1 from internal.migration_provenance where migration_name='20261001170000_public_club_badge');
notify pgrst,'reload schema';
