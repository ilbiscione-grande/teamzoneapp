-- PROF-01: own profile with contact details and picture, contact details on
-- club records for people without an account, and login-email changes that
-- support must approve.
--
-- Visibility: contact details are shown to the person and to leaders of a
-- team the person belongs to. The profile picture is shown to members of the
-- clubs the person belongs to.

-- ------------------------------------------------------------------ fields
alter table core.profiles
  add column if not exists contact_email text,
  add column if not exists phone text,
  add column if not exists avatar_asset_id uuid;
alter table core.profiles
  add constraint profiles_contact_email_check check (contact_email is null or
    (length(contact_email)<=254 and contact_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  add constraint profiles_phone_check check (phone is null or phone ~ '^\+?[0-9 ()-]{5,30}$');

alter table core.club_people
  add column if not exists contact_email text,
  add column if not exists phone text;
alter table core.club_people
  add constraint club_people_contact_email_check check (contact_email is null or
    (length(contact_email)<=254 and contact_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  add constraint club_people_phone_check check (phone is null or phone ~ '^\+?[0-9 ()-]{5,30}$');

create or replace function internal.normalized_contact(new_email text,new_phone text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare email text:=nullif(lower(btrim(coalesce(new_email,''))),'');
 phone text:=nullif(regexp_replace(btrim(coalesce(new_phone,'')),'\s+',' ','g'),'');
begin
 if email is not null and (length(email)>254 or email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then
  raise invalid_parameter_value using message='invalid_email';
 end if;
 if phone is not null and phone !~ '^\+?[0-9 ()-]{5,30}$' then
  raise invalid_parameter_value using message='invalid_phone';
 end if;
 return jsonb_build_object('email',email,'phone',phone);
end$$;

-- ------------------------------------------------------------------ avatars
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-avatars','profile-avatars',false,2097152,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

create table if not exists core.profile_avatars (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references core.profiles(id) on delete cascade,
  bucket_id text not null default 'profile-avatars' check(bucket_id='profile-avatars'),
  object_key text not null unique,
  mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp')),
  size_bytes bigint not null check(size_bytes between 1 and 2097152),
  state text not null default 'staged' check(state in ('staged','active','replaced','removed')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '30 minutes',
  activated_at timestamptz,
  retired_at timestamptz
);
alter table core.profile_avatars enable row level security;
revoke all on table core.profile_avatars from public,anon,authenticated;
alter table core.profiles
  add constraint profiles_avatar_asset_fk foreign key(avatar_asset_id) references core.profile_avatars(id);

create or replace function internal.actor_can_upload_profile_avatar(target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from core.profile_avatars avatar
    where avatar.bucket_id=target_bucket and avatar.object_key=target_key and avatar.state='staged'
      and avatar.expires_at>now() and avatar.profile_id=auth.uid())
$$;

drop policy if exists profile_avatars_insert on storage.objects;
create policy profile_avatars_insert on storage.objects for insert to authenticated
with check(bucket_id='profile-avatars' and internal.actor_can_upload_profile_avatar(bucket_id,name));

-- Whether the actor shares a club with the profile (sees its picture).
create or replace function internal.actor_shares_club_with_profile(target_profile_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select target_profile_id=auth.uid() or exists(
    select 1 from core.person_account_links link
    where link.profile_id=target_profile_id and link.state='active'
      and internal.actor_has_club_access(link.club_id))
$$;

create or replace function internal.actor_can_read_profile_avatar(target_key text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from core.profile_avatars avatar
    where avatar.object_key=target_key and avatar.state='active'
      and internal.actor_shares_club_with_profile(avatar.profile_id))
$$;

drop policy if exists profile_avatars_select on storage.objects;
create policy profile_avatars_select on storage.objects for select to authenticated
using(bucket_id='profile-avatars' and internal.actor_can_read_profile_avatar(name));

create or replace function internal.stage_profile_avatar_for_actor(target_mime_type text,
 target_size_bytes bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); avatar_id uuid; object_key text; existing_result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select dedupe.result into existing_result from internal.command_deduplication dedupe
 where dedupe.actor_profile_id=actor_id and dedupe.command_type='profile.avatar.stage.v1'
  and dedupe.idempotency_key=stage_profile_avatar_for_actor.idempotency_key;
 if existing_result is not null then return existing_result; end if;
 if target_mime_type not in ('image/jpeg','image/png','image/webp') or target_size_bytes not between 1 and 2097152
 then raise invalid_parameter_value using message='invalid_avatar'; end if;
 avatar_id:=gen_random_uuid();
 object_key:=actor_id::text||'/'||avatar_id::text||'.upload';
 insert into core.profile_avatars(id,profile_id,object_key,mime_type,size_bytes)
 values(avatar_id,actor_id,object_key,target_mime_type,target_size_bytes);
 existing_result:=jsonb_build_object('avatar_id',avatar_id,'bucket_id','profile-avatars','object_key',object_key);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'profile.avatar.stage.v1',existing_result);
 return existing_result;
end$$;

create or replace function internal.authorize_profile_avatar_for_actor(target_profile_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare avatar_row core.profile_avatars%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select avatar.* into avatar_row from core.profiles profile
 join core.profile_avatars avatar on avatar.id=profile.avatar_asset_id and avatar.state='active'
 where profile.id=target_profile_id;
 if avatar_row.id is null or not internal.actor_shares_club_with_profile(target_profile_id) then
  return null;
 end if;
 return jsonb_build_object('bucket_id',avatar_row.bucket_id,'object_key',avatar_row.object_key,
  'expires_in_seconds',3600);
end$$;

-- ------------------------------------------------------------------ own profile
create or replace function internal.get_my_profile_details_for_actor()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select jsonb_build_object(
  'profile_id',profile.id,'display_name',profile.display_name,
  'contact_email',profile.contact_email,'phone',profile.phone,
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

create or replace function internal.update_my_profile_details_for_actor(new_display_name text,
 new_contact_email text,new_phone text,avatar_action text,staged_avatar_id uuid,
 expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); profile_row core.profiles%rowtype; avatar_row core.profile_avatars%rowtype;
 contact jsonb; name text:=btrim(coalesce(new_display_name,'')); next_avatar uuid; existing_result jsonb;
 new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select dedupe.result into existing_result from internal.command_deduplication dedupe
 where dedupe.actor_profile_id=actor_id and dedupe.command_type='profile.details.update.v1'
  and dedupe.idempotency_key=update_my_profile_details_for_actor.idempotency_key;
 if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
 if length(name) not between 1 and 120 or avatar_action not in ('keep','replace','remove')
  or (avatar_action='replace')<>(staged_avatar_id is not null)
 then raise invalid_parameter_value using message='invalid_profile'; end if;
 contact:=internal.normalized_contact(new_contact_email,new_phone);
 select * into profile_row from core.profiles where id=actor_id for update;
 if profile_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
 next_avatar:=profile_row.avatar_asset_id;
 if avatar_action='replace' then
  select * into avatar_row from core.profile_avatars avatar
  where avatar.id=staged_avatar_id and avatar.profile_id=actor_id and avatar.state='staged'
   and avatar.expires_at>now() for update;
  if avatar_row.id is null or not exists(select 1 from storage.objects object
    where object.bucket_id=avatar_row.bucket_id and object.name=avatar_row.object_key)
  then raise invalid_parameter_value using message='avatar_not_uploaded'; end if;
  update core.profile_avatars set state='replaced',retired_at=now()
  where id=profile_row.avatar_asset_id and state='active';
  update core.profile_avatars set state='active',activated_at=now() where id=avatar_row.id;
  next_avatar:=avatar_row.id;
 elsif avatar_action='remove' then
  update core.profile_avatars set state='removed',retired_at=now()
  where id=profile_row.avatar_asset_id and state='active';
  next_avatar:=null;
 end if;
 update core.profiles set display_name=name,contact_email=contact->>'email',phone=contact->>'phone',
  avatar_asset_id=next_avatar,updated_at=now(),revision=revision+1
 where id=actor_id returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'profile.details.update.v1',jsonb_build_object('revision',new_revision));
 return new_revision;
end$$;

-- ------------------------------------------------------------------ club records and access
-- Leaders of the team (leader or functionary there), or club membership admins.
create or replace function internal.actor_leads_team(target_club_id uuid,target_team_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select internal.actor_has_capability(target_club_id,null,'club.memberships.manage') or exists(
    select 1 from core.person_account_links link
    join core.assignments assignment on assignment.club_person_id=link.club_person_id
     and assignment.club_id=link.club_id and assignment.team_id=target_team_id
     and assignment.role_package in ('leader','club_functionary') and assignment.state='active'
     and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())
    where link.profile_id=auth.uid() and link.club_id=target_club_id and link.state='active')
$$;

create or replace function internal.person_in_team(target_club_id uuid,target_team_id uuid,target_person_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from core.team_assignments item where item.club_id=target_club_id
     and item.team_id=target_team_id and item.club_person_id=target_person_id and item.state='active')
   or exists(select 1 from core.assignments assignment where assignment.club_id=target_club_id
     and assignment.team_id=target_team_id and assignment.club_person_id=target_person_id
     and assignment.state='active' and assignment.starts_at<=now()
     and (assignment.ends_at is null or assignment.ends_at>now()))
$$;

-- Contact details and picture of a team member. The account's own details
-- win; the club record fills in for people without an account.
create or replace function internal.get_person_contact_for_actor(target_club_id uuid,target_team_id uuid,
 target_person_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare person_row core.club_people%rowtype; account core.profiles%rowtype; self boolean; leads boolean;
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
 return jsonb_strip_nulls(jsonb_build_object(
  'avatar_profile_id',case when account.avatar_asset_id is not null then account.id end,
  'can_see_contact',self or leads,
  'can_edit_club_contact',leads and account.id is null,
  'contact_email',case when self or leads then coalesce(account.contact_email,person_row.contact_email) end,
  'phone',case when self or leads then coalesce(account.phone,person_row.phone) end,
  'contact_source',case when not (self or leads) then null
    when account.contact_email is not null or account.phone is not null then 'account'
    when person_row.contact_email is not null or person_row.phone is not null then 'club' end,
  'has_account',account.id is not null));
end$$;

create or replace function internal.set_person_contact_for_actor(target_club_id uuid,target_team_id uuid,
 target_person_id uuid,new_contact_email text,new_phone text)
returns void language plpgsql security definer set search_path='' as $$
declare contact jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.person_in_team(target_club_id,target_team_id,target_person_id)
  or not internal.actor_leads_team(target_club_id,target_team_id)
 then raise insufficient_privilege using message='not_found'; end if;
 contact:=internal.normalized_contact(new_contact_email,new_phone);
 update core.club_people set contact_email=contact->>'email',phone=contact->>'phone',revision=revision+1
 where id=target_person_id and club_id=target_club_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata)
 values(target_club_id,auth.uid(),'club.person.contact.update.v1','club_person',target_person_id,0,
  jsonb_build_object('has_email',contact->>'email' is not null,'has_phone',contact->>'phone' is not null));
end$$;

-- ------------------------------------------------------------------ login email change
create table if not exists core.login_email_change_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references core.profiles(id) on delete cascade,
  current_email text,
  requested_email text not null check(length(requested_email)<=254),
  reason text not null check(length(btrim(reason)) between 5 and 500),
  state text not null default 'pending' check(state in ('pending','approved','rejected','completed','cancelled')),
  decision_note text,
  decided_by uuid references core.profiles(id),
  decided_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists login_email_change_one_open_idx
  on core.login_email_change_requests(profile_id) where state in ('pending','approved');
alter table core.login_email_change_requests enable row level security;
revoke all on table core.login_email_change_requests from public,anon,authenticated;

create or replace function internal.request_login_email_change_for_actor(new_email text,new_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); contact jsonb; current text; request_id uuid;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 contact:=internal.normalized_contact(new_email,null);
 if contact->>'email' is null or length(btrim(coalesce(new_reason,''))) not between 5 and 500
 then raise invalid_parameter_value using message='invalid_request'; end if;
 select email into current from auth.users where id=actor_id;
 if lower(current)=contact->>'email' then raise invalid_parameter_value using message='same_email'; end if;
 if exists(select 1 from core.login_email_change_requests where profile_id=actor_id and state in ('pending','approved'))
 then raise unique_violation using message='request_open'; end if;
 insert into core.login_email_change_requests(profile_id,current_email,requested_email,reason)
 values(actor_id,current,contact->>'email',btrim(new_reason)) returning id into request_id;
 return request_id;
end$$;

create or replace function internal.cancel_login_email_change_for_actor(target_request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 update core.login_email_change_requests set state='cancelled'
 where id=target_request_id and profile_id=auth.uid() and state in ('pending','approved');
end$$;

-- After approval the person confirms the change through the account's own
-- email confirmation; once the login email matches, the request is done.
create or replace function internal.complete_login_email_change_for_actor()
returns text language plpgsql security definer set search_path='' as $$
declare current text; request core.login_email_change_requests%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into request from core.login_email_change_requests
 where profile_id=auth.uid() and state='approved' order by created_at desc limit 1;
 if request.id is null then return null; end if;
 select email into current from auth.users where id=auth.uid();
 if lower(current)=request.requested_email then
  update core.login_email_change_requests set state='completed' where id=request.id;
  return 'completed';
 end if;
 return 'approved';
end$$;

create or replace function internal.list_login_email_change_requests_for_actor(target_state text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not internal.actor_is_support_admin() then raise insufficient_privilege using message='not_found'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',request.id,'display_name',profile.display_name,
   'current_email',request.current_email,'requested_email',request.requested_email,'reason',request.reason,
   'state',request.state,'decision_note',request.decision_note,'created_at',request.created_at,
   'decided_at',request.decided_at) order by request.created_at desc)
  from core.login_email_change_requests request join core.profiles profile on profile.id=request.profile_id
  where target_state is null or request.state=target_state),'[]'::jsonb);
end$$;

create or replace function internal.decide_login_email_change_for_actor(target_request_id uuid,
 approve boolean,note text)
returns text language plpgsql security definer set search_path='' as $$
declare next_state text:=case when approve then 'approved' else 'rejected' end;
begin
 if not internal.actor_is_support_admin() then raise insufficient_privilege using message='not_found'; end if;
 if length(btrim(coalesce(note,''))) not between 2 and 500 then
  raise invalid_parameter_value using message='invalid_note'; end if;
 update core.login_email_change_requests set state=next_state,decision_note=btrim(note),
  decided_by=auth.uid(),decided_at=now()
 where id=target_request_id and state='pending';
 if not found then raise serialization_failure using message='stale_request'; end if;
 return next_state;
end$$;

-- ------------------------------------------------------------------ api
create or replace function api.get_my_profile_details() returns jsonb language sql stable security invoker
 set search_path='' as $$ select internal.get_my_profile_details_for_actor() $$;
create or replace function api.update_my_profile_details(new_display_name text,new_contact_email text,
 new_phone text,avatar_action text,staged_avatar_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$
 select internal.update_my_profile_details_for_actor(new_display_name,new_contact_email,new_phone,
  avatar_action,staged_avatar_id,expected_revision,idempotency_key) $$;
create or replace function api.stage_profile_avatar(target_mime_type text,target_size_bytes bigint,
 idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as $$
 select internal.stage_profile_avatar_for_actor(target_mime_type,target_size_bytes,idempotency_key) $$;
create or replace function api.authorize_profile_avatar(target_profile_id uuid) returns jsonb language sql
 stable security invoker set search_path='' as $$ select internal.authorize_profile_avatar_for_actor(target_profile_id) $$;
create or replace function api.get_person_contact(target_club_id uuid,target_team_id uuid,target_person_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select internal.get_person_contact_for_actor(target_club_id,target_team_id,target_person_id) $$;
create or replace function api.set_person_contact(target_club_id uuid,target_team_id uuid,target_person_id uuid,
 new_contact_email text,new_phone text) returns void language sql security invoker set search_path='' as $$
 select internal.set_person_contact_for_actor(target_club_id,target_team_id,target_person_id,new_contact_email,new_phone) $$;
create or replace function api.request_login_email_change(new_email text,new_reason text) returns uuid
 language sql security invoker set search_path='' as $$
 select internal.request_login_email_change_for_actor(new_email,new_reason) $$;
create or replace function api.cancel_login_email_change(target_request_id uuid) returns void
 language sql security invoker set search_path='' as $$
 select internal.cancel_login_email_change_for_actor(target_request_id) $$;
create or replace function api.complete_login_email_change() returns text
 language sql security invoker set search_path='' as $$ select internal.complete_login_email_change_for_actor() $$;
create or replace function api.list_login_email_change_requests(target_state text default null) returns jsonb
 language sql stable security invoker set search_path='' as $$
 select internal.list_login_email_change_requests_for_actor(target_state) $$;
create or replace function api.decide_login_email_change(target_request_id uuid,approve boolean,note text)
returns text language sql security invoker set search_path='' as $$
 select internal.decide_login_email_change_for_actor(target_request_id,approve,note) $$;

revoke all on function
 internal.normalized_contact(text,text),internal.actor_can_upload_profile_avatar(text,text),
 internal.actor_shares_club_with_profile(uuid),internal.actor_can_read_profile_avatar(text),internal.stage_profile_avatar_for_actor(text,bigint,uuid),
 internal.authorize_profile_avatar_for_actor(uuid),internal.get_my_profile_details_for_actor(),
 internal.update_my_profile_details_for_actor(text,text,text,text,uuid,bigint,uuid),
 internal.actor_leads_team(uuid,uuid),internal.person_in_team(uuid,uuid,uuid),
 internal.get_person_contact_for_actor(uuid,uuid,uuid),
 internal.set_person_contact_for_actor(uuid,uuid,uuid,text,text),
 internal.request_login_email_change_for_actor(text,text),internal.cancel_login_email_change_for_actor(uuid),
 internal.complete_login_email_change_for_actor(),internal.list_login_email_change_requests_for_actor(text),
 internal.decide_login_email_change_for_actor(uuid,boolean,text),
 api.get_my_profile_details(),api.update_my_profile_details(text,text,text,text,uuid,bigint,uuid),
 api.stage_profile_avatar(text,bigint,uuid),api.authorize_profile_avatar(uuid),
 api.get_person_contact(uuid,uuid,uuid),api.set_person_contact(uuid,uuid,uuid,text,text),
 api.request_login_email_change(text,text),api.cancel_login_email_change(uuid),
 api.complete_login_email_change(),api.list_login_email_change_requests(text),
 api.decide_login_email_change(uuid,boolean,text)
from public,anon,authenticated;
grant execute on function
 internal.actor_can_upload_profile_avatar(text,text),internal.actor_shares_club_with_profile(uuid),
 internal.actor_can_read_profile_avatar(text),
 internal.stage_profile_avatar_for_actor(text,bigint,uuid),internal.authorize_profile_avatar_for_actor(uuid),
 internal.get_my_profile_details_for_actor(),
 internal.update_my_profile_details_for_actor(text,text,text,text,uuid,bigint,uuid),
 internal.get_person_contact_for_actor(uuid,uuid,uuid),
 internal.set_person_contact_for_actor(uuid,uuid,uuid,text,text),
 internal.request_login_email_change_for_actor(text,text),internal.cancel_login_email_change_for_actor(uuid),
 internal.complete_login_email_change_for_actor(),internal.list_login_email_change_requests_for_actor(text),
 internal.decide_login_email_change_for_actor(uuid,boolean,text),
 api.get_my_profile_details(),api.update_my_profile_details(text,text,text,text,uuid,bigint,uuid),
 api.stage_profile_avatar(text,bigint,uuid),api.authorize_profile_avatar(uuid),
 api.get_person_contact(uuid,uuid,uuid),api.set_person_contact(uuid,uuid,uuid,text,text),
 api.request_login_email_change(text,text),api.cancel_login_email_change(uuid),
 api.complete_login_email_change(),api.list_login_email_change_requests(text),
 api.decide_login_email_change(uuid,boolean,text)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260930120000_profile_contact_avatar','greenfield',
 'PROF-01 own profile contact details and picture, club contact records, support-approved login email change');
notify pgrst,'reload schema';
