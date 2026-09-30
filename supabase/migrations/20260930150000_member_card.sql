-- PROF-04: virtual member card. Front: picture, club badge, name, team,
-- roles and titles, birth year, member since, member id. Back: address and
-- contact details, only for the person and the team's leaders.
-- Adds postal addresses (account and club record) and a club badge that club
-- administrators upload; members of the club see it.

-- ------------------------------------------------------------------ addresses
alter table core.profiles
  add column if not exists street_address text,
  add column if not exists postal_code text,
  add column if not exists city text;
alter table core.club_people
  add column if not exists street_address text,
  add column if not exists postal_code text,
  add column if not exists city text;

create or replace function internal.normalized_address(new_street text,new_postal text,new_city text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare street text:=nullif(btrim(coalesce(new_street,'')),'');
 postal text:=nullif(upper(btrim(coalesce(new_postal,''))),'');
 city text:=nullif(btrim(coalesce(new_city,'')),'');
begin
 if length(street)>120 or length(city)>80 or (postal is not null and postal !~ '^[0-9A-Z -]{3,12}$') then
  raise invalid_parameter_value using message='invalid_address';
 end if;
 return jsonb_build_object('street',street,'postal',postal,'city',city);
end$$;

create or replace function internal.update_my_address_for_actor(new_street text,new_postal text,new_city text)
returns void language plpgsql security definer set search_path='' as $$
declare address jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 address:=internal.normalized_address(new_street,new_postal,new_city);
 update core.profiles set street_address=address->>'street',postal_code=address->>'postal',
  city=address->>'city',updated_at=now()
 where id=auth.uid();
end$$;

create or replace function internal.set_person_address_for_actor(target_club_id uuid,target_team_id uuid,
 target_person_id uuid,new_street text,new_postal text,new_city text)
returns void language plpgsql security definer set search_path='' as $$
declare address jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.person_in_team(target_club_id,target_team_id,target_person_id)
  or not internal.actor_leads_team(target_club_id,target_team_id)
 then raise insufficient_privilege using message='not_found'; end if;
 address:=internal.normalized_address(new_street,new_postal,new_city);
 update core.club_people set street_address=address->>'street',postal_code=address->>'postal',
  city=address->>'city',revision=revision+1
 where id=target_person_id and club_id=target_club_id;
end$$;

-- Own details now include the address.
create or replace function internal.get_my_profile_details_for_actor()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select jsonb_build_object(
  'profile_id',profile.id,'display_name',profile.display_name,
  'contact_email',profile.contact_email,'phone',profile.phone,
  'street_address',profile.street_address,'postal_code',profile.postal_code,'city',profile.city,
  'has_avatar',profile.avatar_asset_id is not null,
  'login_email',(select account.email from auth.users account where account.id=profile.id),
  'revision',profile.revision,
  'email_change',(select jsonb_build_object('id',request.id,'requested_email',request.requested_email,
     'state',request.state,'decision_note',request.decision_note,'created_at',request.created_at,
     'decided_at',request.decided_at)
   from core.login_email_change_requests request where request.profile_id=profile.id
   order by request.created_at desc limit 1)
 ) into result from core.profiles profile where profile.id=actor_id;
 return result;
end$$;

-- Contact now includes the address for the person and leaders.
create or replace function internal.get_person_contact_for_actor(target_club_id uuid,target_team_id uuid,
 target_person_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare person_row core.club_people%rowtype; account core.profiles%rowtype; self boolean; leads boolean;
 own_address boolean;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into person_row from core.club_people where id=target_person_id and club_id=target_club_id;
 if person_row.id is null or not internal.person_in_team(target_club_id,target_team_id,target_person_id)
 then raise insufficient_privilege using message='not_found'; end if;
 self:=internal.actor_owns_club_person(target_club_id,target_person_id);
 leads:=internal.actor_leads_team(target_club_id,target_team_id);
 if not self and not leads and not internal.actor_has_club_access(target_club_id)
 then raise insufficient_privilege using message='not_found'; end if;
 select profile.* into account from core.person_account_links link
 join core.profiles profile on profile.id=link.profile_id
 where link.club_person_id=target_person_id and link.club_id=target_club_id and link.state='active'
 order by link.created_at desc limit 1;
 own_address:=account.street_address is not null or account.postal_code is not null or account.city is not null;
 return jsonb_strip_nulls(jsonb_build_object(
  'avatar_profile_id',case when account.avatar_asset_id is not null then account.id end,
  'can_see_contact',self or leads,
  'can_edit_club_contact',leads and account.id is null,
  'contact_email',case when self or leads then coalesce(account.contact_email,person_row.contact_email) end,
  'phone',case when self or leads then coalesce(account.phone,person_row.phone) end,
  'street_address',case when self or leads then
    case when own_address then account.street_address else person_row.street_address end end,
  'postal_code',case when self or leads then
    case when own_address then account.postal_code else person_row.postal_code end end,
  'city',case when self or leads then case when own_address then account.city else person_row.city end end,
  'contact_source',case when not (self or leads) then null
    when account.contact_email is not null or account.phone is not null or own_address then 'account'
    when person_row.contact_email is not null or person_row.phone is not null
      or person_row.street_address is not null or person_row.city is not null then 'club' end,
  'has_account',account.id is not null));
end$$;

-- ------------------------------------------------------------------ club badge
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('club-badges','club-badges',false,1048576,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

create table if not exists core.club_badges (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id) on delete cascade,
  bucket_id text not null default 'club-badges' check(bucket_id='club-badges'),
  object_key text not null unique,
  mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp')),
  size_bytes bigint not null check(size_bytes between 1 and 1048576),
  state text not null default 'staged' check(state in ('staged','active','replaced','removed')),
  uploaded_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '30 minutes',
  activated_at timestamptz,
  retired_at timestamptz
);
alter table core.club_badges enable row level security;
revoke all on table core.club_badges from public,anon,authenticated;
alter table core.clubs add column if not exists badge_asset_id uuid references core.club_badges(id);

create or replace function internal.actor_manages_club(target_club_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select internal.actor_has_capability(target_club_id,null,'club.memberships.manage')
$$;

create or replace function internal.actor_can_upload_club_badge(target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from core.club_badges badge
    where badge.bucket_id=target_bucket and badge.object_key=target_key and badge.state='staged'
      and badge.expires_at>now() and badge.uploaded_by=auth.uid()
      and internal.actor_manages_club(badge.club_id))
$$;

create or replace function internal.actor_can_read_club_badge(target_key text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from core.club_badges badge
    where badge.object_key=target_key and badge.state='active'
      and internal.actor_has_club_access(badge.club_id))
$$;

drop policy if exists club_badges_insert on storage.objects;
create policy club_badges_insert on storage.objects for insert to authenticated
with check(bucket_id='club-badges' and internal.actor_can_upload_club_badge(bucket_id,name));
drop policy if exists club_badges_select on storage.objects;
create policy club_badges_select on storage.objects for select to authenticated
using(bucket_id='club-badges' and internal.actor_can_read_club_badge(name));

create or replace function internal.stage_club_badge_for_actor(target_club_id uuid,target_mime_type text,
 target_size_bytes bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare badge_id uuid:=gen_random_uuid(); object_key text;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_manages_club(target_club_id) then raise insufficient_privilege using message='not_found'; end if;
 if target_mime_type not in ('image/jpeg','image/png','image/webp') or target_size_bytes not between 1 and 1048576
 then raise invalid_parameter_value using message='invalid_badge'; end if;
 object_key:=target_club_id::text||'/'||badge_id::text||'.upload';
 insert into core.club_badges(id,club_id,object_key,mime_type,size_bytes,uploaded_by)
 values(badge_id,target_club_id,object_key,target_mime_type,target_size_bytes,auth.uid());
 return jsonb_build_object('badge_id',badge_id,'bucket_id','club-badges','object_key',object_key);
end$$;

create or replace function internal.set_club_badge_for_actor(target_club_id uuid,badge_action text,
 staged_badge_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare badge_row core.club_badges%rowtype; club_row core.clubs%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_manages_club(target_club_id) then raise insufficient_privilege using message='not_found'; end if;
 if badge_action not in ('replace','remove') or (badge_action='replace')<>(staged_badge_id is not null)
 then raise invalid_parameter_value using message='invalid_badge'; end if;
 select * into club_row from core.clubs where id=target_club_id for update;
 if badge_action='replace' then
  select * into badge_row from core.club_badges badge
  where badge.id=staged_badge_id and badge.club_id=target_club_id and badge.state='staged'
   and badge.expires_at>now() and badge.uploaded_by=auth.uid() for update;
  if badge_row.id is null or not exists(select 1 from storage.objects object
    where object.bucket_id=badge_row.bucket_id and object.name=badge_row.object_key)
  then raise invalid_parameter_value using message='badge_not_uploaded'; end if;
  update core.club_badges set state='replaced',retired_at=now() where id=club_row.badge_asset_id and state='active';
  update core.club_badges set state='active',activated_at=now() where id=badge_row.id;
  update core.clubs set badge_asset_id=badge_row.id where id=target_club_id;
 else
  update core.club_badges set state='removed',retired_at=now() where id=club_row.badge_asset_id and state='active';
  update core.clubs set badge_asset_id=null where id=target_club_id;
 end if;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata)
 values(target_club_id,auth.uid(),'club.badge.'||badge_action||'.v1','club',target_club_id,0,
  jsonb_build_object('badge_id',staged_badge_id));
end$$;

create or replace function internal.authorize_club_badge_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare badge_row core.club_badges%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_club_access(target_club_id) then return null; end if;
 select badge.* into badge_row from core.clubs club
 join core.club_badges badge on badge.id=club.badge_asset_id and badge.state='active'
 where club.id=target_club_id;
 if badge_row.id is null then return null; end if;
 return jsonb_build_object('bucket_id',badge_row.bucket_id,'object_key',badge_row.object_key,
  'expires_in_seconds',3600);
end$$;

-- ------------------------------------------------------------------ member card
create or replace function internal.get_member_card_for_actor(target_club_id uuid,target_team_id uuid,
 target_person_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare person_row core.club_people%rowtype; contact jsonb; roles text[]; details core.team_person_details%rowtype;
begin
 contact:=internal.get_person_contact_for_actor(target_club_id,target_team_id,target_person_id);
 select * into person_row from core.club_people where id=target_person_id and club_id=target_club_id;
 select array_agg(distinct role order by role) into roles from (
  select 'player' as role from core.team_assignments item where item.club_id=target_club_id
   and item.team_id=target_team_id and item.club_person_id=target_person_id and item.state='active'
  union
  select assignment.role_package from core.assignments assignment where assignment.club_id=target_club_id
   and assignment.team_id=target_team_id and assignment.club_person_id=target_person_id
   and assignment.state='active' and assignment.starts_at<=now()
   and (assignment.ends_at is null or assignment.ends_at>now())
 ) held;
 select * into details from core.team_person_details
 where club_id=target_club_id and team_id=target_team_id and club_person_id=target_person_id;
 return jsonb_strip_nulls(jsonb_build_object(
  'person_id',person_row.id,
  'name',person_row.display_name,
  'club_id',target_club_id,
  'club_name',(select name from core.clubs where id=target_club_id),
  'has_badge',(select badge_asset_id is not null from core.clubs where id=target_club_id),
  'team_name',(select name from core.teams where id=target_team_id),
  'roles',to_jsonb(coalesce(roles,'{}'::text[])),
  'titles',to_jsonb(coalesce(details.functions,'{}'::text[])),
  'custom_titles',to_jsonb(coalesce(details.custom_titles,'{}'::text[])),
  'guardian_of',(select jsonb_agg(child.display_name order by child.display_name)
    from core.guardian_relations relation
    join core.club_people child on child.id=relation.child_person_id and child.club_id=relation.club_id
    where relation.club_id=target_club_id and relation.guardian_person_id=target_person_id
     and relation.state='active'),
  'birth_year',person_row.birth_year,
  'member_since',coalesce(
    (select min(assignment.starts_at) from core.assignments assignment
     where assignment.club_id=target_club_id and assignment.club_person_id=target_person_id),
    person_row.created_at),
  'member_number',upper(substr(replace(person_row.id::text,'-',''),1,8)),
  'contact',contact));
end$$;

-- ------------------------------------------------------------------ api
create or replace function api.update_my_address(new_street text,new_postal text,new_city text) returns void
 language sql security invoker set search_path='' as $$ select internal.update_my_address_for_actor(new_street,new_postal,new_city) $$;
create or replace function api.set_person_address(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_street text,new_postal text,new_city text) returns void language sql security invoker set search_path='' as $$
 select internal.set_person_address_for_actor(target_club_id,target_team_id,target_person_id,new_street,new_postal,new_city) $$;
create or replace function api.stage_club_badge(target_club_id uuid,target_mime_type text,target_size_bytes bigint)
returns jsonb language sql security invoker set search_path='' as $$
 select internal.stage_club_badge_for_actor(target_club_id,target_mime_type,target_size_bytes) $$;
create or replace function api.set_club_badge(target_club_id uuid,badge_action text,staged_badge_id uuid)
returns void language sql security invoker set search_path='' as $$
 select internal.set_club_badge_for_actor(target_club_id,badge_action,staged_badge_id) $$;
create or replace function api.authorize_club_badge(target_club_id uuid) returns jsonb language sql stable
 security invoker set search_path='' as $$ select internal.authorize_club_badge_for_actor(target_club_id) $$;
create or replace function api.get_member_card(target_club_id uuid,target_team_id uuid,target_person_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select internal.get_member_card_for_actor(target_club_id,target_team_id,target_person_id) $$;

revoke all on function
 internal.normalized_address(text,text,text),internal.update_my_address_for_actor(text,text,text),
 internal.set_person_address_for_actor(uuid,uuid,uuid,text,text,text),internal.actor_manages_club(uuid),
 internal.actor_can_upload_club_badge(text,text),internal.actor_can_read_club_badge(text),
 internal.stage_club_badge_for_actor(uuid,text,bigint),internal.set_club_badge_for_actor(uuid,text,uuid),
 internal.authorize_club_badge_for_actor(uuid),internal.get_member_card_for_actor(uuid,uuid,uuid),
 api.update_my_address(text,text,text),api.set_person_address(uuid,uuid,uuid,text,text,text),
 api.stage_club_badge(uuid,text,bigint),api.set_club_badge(uuid,text,uuid),api.authorize_club_badge(uuid),
 api.get_member_card(uuid,uuid,uuid)
from public,anon,authenticated;
grant execute on function
 internal.update_my_address_for_actor(text,text,text),
 internal.set_person_address_for_actor(uuid,uuid,uuid,text,text,text),
 internal.actor_can_upload_club_badge(text,text),internal.actor_can_read_club_badge(text),
 internal.stage_club_badge_for_actor(uuid,text,bigint),internal.set_club_badge_for_actor(uuid,text,uuid),
 internal.authorize_club_badge_for_actor(uuid),internal.get_member_card_for_actor(uuid,uuid,uuid),
 api.update_my_address(text,text,text),api.set_person_address(uuid,uuid,uuid,text,text,text),
 api.stage_club_badge(uuid,text,bigint),api.set_club_badge(uuid,text,uuid),api.authorize_club_badge(uuid),
 api.get_member_card(uuid,uuid,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260930150000_member_card','greenfield',
 'PROF-04 virtual member card, postal addresses and club badge');
notify pgrst,'reload schema';
