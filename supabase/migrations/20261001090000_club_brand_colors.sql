-- PUB-08: club colours. Club administrators choose a primary colour (header,
-- hero and dark surfaces) and an accent colour (highlights) for the public
-- club and team pages. Colours are branding, not personal data: they are
-- copied to the club projection whenever the club is projected, and straight
-- away when changed.

alter table core.clubs
 add column if not exists brand_primary_color text
  check (brand_primary_color ~ '^#[0-9a-f]{6}$'),
 add column if not exists brand_accent_color text
  check (brand_accent_color ~ '^#[0-9a-f]{6}$');
alter table public_api.club_projections
 add column if not exists primary_color text check (primary_color ~ '^#[0-9a-f]{6}$'),
 add column if not exists accent_color text check (accent_color ~ '^#[0-9a-f]{6}$');

create or replace function internal.get_club_colors_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare club_row core.clubs%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_is_club_admin(target_club_id) then
  raise insufficient_privilege using message='club_admin_required'; end if;
 select * into club_row from core.clubs where id=target_club_id;
 return jsonb_strip_nulls(jsonb_build_object('primary',club_row.brand_primary_color,
  'accent',club_row.brand_accent_color));
end$$;

create or replace function internal.set_club_colors_for_actor(target_club_id uuid,new_primary text,new_accent text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); primary_value text:=lower(nullif(btrim(new_primary),''));
 accent_value text:=lower(nullif(btrim(new_accent),''));
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_is_club_admin(target_club_id) then
  raise insufficient_privilege using message='club_admin_required'; end if;
 if (primary_value is not null and primary_value!~'^#[0-9a-f]{6}$')
  or (accent_value is not null and accent_value!~'^#[0-9a-f]{6}$') then
  raise invalid_parameter_value using message='invalid_color'; end if;
 update core.clubs set brand_primary_color=primary_value,brand_accent_color=accent_value,
  revision=revision+1 where id=target_club_id;
 update public_api.club_projections projection set primary_color=primary_value,accent_color=accent_value
 from core.club_publication_settings setting
 where setting.club_id=target_club_id and projection.public_id=setting.public_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'club.colors.updated.v1','club',target_club_id,1,
  jsonb_build_object('primary',primary_value,'accent',accent_value));
 return jsonb_strip_nulls(jsonb_build_object('primary',primary_value,'accent',accent_value));
end$$;

create or replace function api.get_club_colors(target_club_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_club_colors_for_actor(target_club_id)$$;
create or replace function api.set_club_colors(target_club_id uuid,new_primary text,new_accent text)
returns jsonb language sql security invoker set search_path='' as
$$select internal.set_club_colors_for_actor(target_club_id,new_primary,new_accent)$$;

revoke all on function internal.get_club_colors_for_actor(uuid),internal.set_club_colors_for_actor(uuid,text,text),
 api.get_club_colors(uuid),api.set_club_colors(uuid,text,text) from public,anon,authenticated;
grant execute on function internal.get_club_colors_for_actor(uuid),internal.set_club_colors_for_actor(uuid,text,text),
 api.get_club_colors(uuid),api.set_club_colors(uuid,text,text) to authenticated;

-- Projection and public read carry the colours.
do $patch$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.apply_publication_projection_job(uuid)'::regprocedure);
 patched:=replace(definition,
  'official=excluded.official,visibility=excluded.visibility;',
  'official=excluded.official,visibility=excluded.visibility;
   update public_api.club_projections set primary_color=club_row.brand_primary_color,
    accent_color=club_row.brand_accent_color where public_id=club_setting.public_id;');
 if patched=definition then raise exception 'apply_publication_projection_job: patch point not found'; end if;
 execute patched;

 definition:=pg_get_functiondef('internal.public_get_club(text,text)'::regprocedure);
 patched:=replace(definition,
  '''official'',club.official,',
  '''official'',club.official,''primary_color'',club.primary_color,''accent_color'',club.accent_color,');
 if patched=definition then raise exception 'public_get_club: patch point not found'; end if;
 execute patched;
end$patch$;

-- Already published clubs without colours keep the default look.

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261001090000_club_brand_colors','greenfield',
 'PUB-08 club colours for the public club and team pages'
where not exists(select 1 from internal.migration_provenance
 where migration_name='20261001090000_club_brand_colors');
notify pgrst,'reload schema';
