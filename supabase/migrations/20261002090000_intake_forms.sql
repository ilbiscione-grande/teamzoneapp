-- TEAM-15: contact pages. From the app a club or team creates a temporary
-- page on the public site (link and QR code, valid for 14 days) where anyone
-- can send their basic contact details (name, phone, email, birth date and
-- address). The site's server submits them
-- behind an origin check and captcha; only the service role can write.
-- Club and team leaders see the submissions in the app and add a person to
-- a team with one tap (player by default, or leader). A handled submission
-- is deleted: the details then live on the club's person record.

create table if not exists core.intake_forms (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id) on delete cascade,
  team_id uuid references core.teams(id) on delete cascade,
  public_token text not null unique default md5(random()::text||clock_timestamp()::text||gen_random_uuid()::text),
  active boolean not null default true,
  expires_at timestamptz not null default now()+interval '14 days',
  created_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now()
);
create unique index if not exists intake_forms_one_active
 on core.intake_forms(club_id,coalesce(team_id,'00000000-0000-0000-0000-000000000000'::uuid)) where active;

create table if not exists core.intake_submissions (
  id uuid primary key default gen_random_uuid(),
  form_id uuid not null references core.intake_forms(id) on delete cascade,
  club_id uuid not null references core.clubs(id) on delete cascade,
  team_id uuid references core.teams(id) on delete set null,
  full_name text not null check (length(full_name) between 2 and 120),
  phone text not null check (length(phone) between 5 and 30),
  email text not null check (length(email) between 3 and 254),
  birth_date date not null,
  street_address text not null check (length(street_address) between 2 and 120),
  postal_code text not null check (length(postal_code) between 3 and 10),
  city text not null check (length(city) between 2 and 80),
  ip_hash text not null,
  created_at timestamptz not null default now()
);
create index if not exists intake_submissions_club on core.intake_submissions(club_id,created_at);
create index if not exists intake_submissions_ip on core.intake_submissions(ip_hash,created_at);

alter table core.intake_forms enable row level security;
alter table core.intake_submissions enable row level security;
revoke all on table core.intake_forms,core.intake_submissions from public,anon,authenticated;

-- Who may handle a club's submissions: club administrators all of them; a
-- team's roster managers their team's and the club-wide ones.
create or replace function internal.actor_handles_intake(target_club_id uuid,target_team_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select internal.actor_manages_club(target_club_id) or (
  case when target_team_id is null then exists(select 1 from core.teams team
    where team.club_id=target_club_id and team.status='active'
     and internal.actor_has_capability(target_club_id,team.id,'team.roster.manage'))
  else internal.actor_has_capability(target_club_id,target_team_id,'team.roster.manage') end)
$$;

create or replace function internal.get_intake_overview_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare teams jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',team.id,'name',team.name) order by lower(team.name)),'[]'::jsonb)
 into teams from core.teams team
 where team.club_id=target_club_id and team.status='active'
  and (internal.actor_manages_club(target_club_id)
   or internal.actor_has_capability(target_club_id,team.id,'team.roster.manage'));
 if teams='[]'::jsonb then raise insufficient_privilege using message='not_found'; end if;
 return jsonb_build_object(
  'can_manage_club',internal.actor_manages_club(target_club_id),
  'teams',teams,
  'forms',coalesce((select jsonb_agg(jsonb_build_object('id',form.id,'team_id',form.team_id,'team_name',team.name,
     'token',form.public_token,'created_at',form.created_at,'expires_at',form.expires_at)
     order by form.team_id nulls first,form.created_at)
   from core.intake_forms form left join core.teams team on team.id=form.team_id
   where form.club_id=target_club_id and form.active and form.expires_at>now()
    and internal.actor_handles_intake(target_club_id,form.team_id)),'[]'::jsonb),
  'submissions',coalesce((select jsonb_agg(jsonb_build_object('id',submission.id,'team_id',submission.team_id,
     'team_name',team.name,'full_name',submission.full_name,'phone',submission.phone,'email',submission.email,
     'birth_date',submission.birth_date,'street_address',submission.street_address,
     'postal_code',submission.postal_code,'city',submission.city,'created_at',submission.created_at)
     order by submission.created_at desc)
   from core.intake_submissions submission left join core.teams team on team.id=submission.team_id
   where submission.club_id=target_club_id and internal.actor_handles_intake(target_club_id,submission.team_id)),'[]'::jsonb));
end$$;

create or replace function internal.create_intake_form_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare form core.intake_forms%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if (target_team_id is null and not internal.actor_manages_club(target_club_id))
  or (target_team_id is not null and (not exists(select 1 from core.teams team where team.id=target_team_id
    and team.club_id=target_club_id and team.status='active')
   or not internal.actor_handles_intake(target_club_id,target_team_id))) then
  raise insufficient_privilege using message='not_found'; end if;
 -- An expired page is closed so that a new one can be created.
 update core.intake_forms set active=false where club_id=target_club_id
  and team_id is not distinct from target_team_id and active and expires_at<=now();
 select * into form from core.intake_forms where club_id=target_club_id
  and team_id is not distinct from target_team_id and active;
 if form.id is null then
  insert into core.intake_forms(club_id,team_id,created_by) values(target_club_id,target_team_id,auth.uid())
  returning * into form;
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
  values(target_club_id,auth.uid(),'club.intake_form.created.v1','intake_form',form.id,1,
   jsonb_build_object('team_id',target_team_id));
 end if;
 return jsonb_build_object('id',form.id,'token',form.public_token,'expires_at',form.expires_at);
end$$;

create or replace function internal.close_intake_form_for_actor(target_form_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare form core.intake_forms%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into form from core.intake_forms where id=target_form_id for update;
 if form.id is null or not internal.actor_handles_intake(form.club_id,form.team_id)
  or (form.team_id is null and not internal.actor_manages_club(form.club_id)) then
  raise insufficient_privilege using message='not_found'; end if;
 update core.intake_forms set active=false where id=target_form_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(form.club_id,auth.uid(),'club.intake_form.closed.v1','intake_form',form.id,2,'{}'::jsonb);
end$$;

create or replace function internal.accept_intake_submission_for_actor(target_submission_id uuid,target_team_id uuid,
 new_role text,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); submission core.intake_submissions%rowtype; person_id uuid; cached jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if idempotency_key is null or new_role not in('player','leader') then
  raise invalid_parameter_value using message='invalid_input'; end if;
 select d.result into cached from internal.command_deduplication d
 where d.actor_profile_id=actor_id and d.command_type='club.intake.accepted.v1'
  and d.idempotency_key=accept_intake_submission_for_actor.idempotency_key;
 if cached is not null then return (cached->>'club_person_id')::uuid; end if;
 select * into submission from core.intake_submissions where id=target_submission_id for update;
 if submission.id is null or not internal.actor_handles_intake(submission.club_id,submission.team_id)
  or not exists(select 1 from core.teams team where team.id=target_team_id and team.club_id=submission.club_id
   and team.status='active')
  or not internal.actor_handles_intake(submission.club_id,target_team_id) then
  raise insufficient_privilege using message='not_found'; end if;
 person_id:=internal.create_roster_person_v3_for_actor(submission.club_id,target_team_id,submission.full_name,
  extract(year from submission.birth_date)::integer,submission.birth_date,now(),idempotency_key);
 perform internal.set_person_contact_for_actor(submission.club_id,target_team_id,person_id,submission.email,submission.phone);
 perform internal.set_person_address_for_actor(submission.club_id,target_team_id,person_id,
  submission.street_address,submission.postal_code,submission.city);
 if new_role='leader' then
  perform internal.team_role_command(submission.club_id,target_team_id,person_id,'player','leader',
   md5(idempotency_key::text||':role')::uuid);
 end if;
 delete from core.intake_submissions where id=submission.id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'club.intake.accepted.v1',jsonb_build_object('club_person_id',person_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(submission.club_id,actor_id,'club.intake.accepted.v1','club_person',person_id,1,
  jsonb_build_object('team_id',target_team_id,'role',new_role));
 return person_id;
end$$;

create or replace function internal.dismiss_intake_submission_for_actor(target_submission_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare submission core.intake_submissions%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into submission from core.intake_submissions where id=target_submission_id for update;
 if submission.id is null then return; end if;
 if not internal.actor_handles_intake(submission.club_id,submission.team_id) then
  raise insufficient_privilege using message='not_found'; end if;
 delete from core.intake_submissions where id=submission.id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(submission.club_id,auth.uid(),'club.intake.dismissed.v1','intake_submission',submission.id,1,'{}'::jsonb);
end$$;

-- Public side, for the public site's server only.
create or replace function internal.public_get_intake_form(public_token text)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('club_name',club.name,'team_name',team.name)
  from core.intake_forms form join core.clubs club on club.id=form.club_id and club.status='active'
  left join core.teams team on team.id=form.team_id
  where form.public_token=public_get_intake_form.public_token and form.active and form.expires_at>now()
   and (form.team_id is null or team.status='active')),jsonb_build_object('not_found',true))
$$;

create or replace function internal.public_submit_intake(public_token text,full_name text,phone text,email text,
 birth_date date,street_address text,postal_code text,city text,ip_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare form core.intake_forms%rowtype; contact jsonb;
 name text:=regexp_replace(btrim(coalesce(full_name,'')),'\s+',' ','g');
 street text:=btrim(coalesce(street_address,'')); postal text:=regexp_replace(btrim(coalesce(postal_code,'')),'\s+',' ','g');
 town text:=btrim(coalesce(city,''));
begin
 if current_user not in('service_role','postgres') then raise insufficient_privilege using message='service_role_required'; end if;
 select * into form from core.intake_forms f where f.public_token=public_submit_intake.public_token and f.active
  and f.expires_at>now();
 if form.id is null then return jsonb_build_object('not_found',true); end if;
 if ip_hash is null or length(ip_hash)<16 then raise invalid_parameter_value using message='invalid_request'; end if;
 if (select count(*) from core.intake_submissions s where s.ip_hash=public_submit_intake.ip_hash
     and s.created_at>now()-interval '1 hour')>=5
  or (select count(*) from core.intake_submissions s where s.form_id=form.id)>=500 then
  raise invalid_parameter_value using message='rate_limited'; end if;
 if length(name) not between 2 and 120 or phone is null or email is null
  or birth_date is null or birth_date<date '1900-01-01' or birth_date>current_date
  or length(street) not between 2 and 120 or length(postal) not between 3 and 10 or length(town) not between 2 and 80 then
  raise invalid_parameter_value using message='invalid_request'; end if;
 contact:=internal.normalized_contact(email,phone);
 if contact->>'email' is null or contact->>'phone' is null then
  raise invalid_parameter_value using message='invalid_request'; end if;
 insert into core.intake_submissions(form_id,club_id,team_id,full_name,phone,email,birth_date,street_address,
  postal_code,city,ip_hash)
 values(form.id,form.club_id,form.team_id,name,contact->>'phone',contact->>'email',birth_date,street,postal,town,ip_hash);
 return jsonb_build_object('accepted',true);
end$$;

create or replace function api.get_intake_overview(target_club_id uuid) returns jsonb language sql stable
 security invoker set search_path='' as $$select internal.get_intake_overview_for_actor(target_club_id)$$;
create or replace function api.create_intake_form(target_club_id uuid,target_team_id uuid) returns jsonb language sql
 security invoker set search_path='' as $$select internal.create_intake_form_for_actor(target_club_id,target_team_id)$$;
create or replace function api.close_intake_form(target_form_id uuid) returns void language sql
 security invoker set search_path='' as $$select internal.close_intake_form_for_actor(target_form_id)$$;
create or replace function api.accept_intake_submission(target_submission_id uuid,target_team_id uuid,new_role text,
 idempotency_key uuid) returns uuid language sql security invoker set search_path='' as
 $$select internal.accept_intake_submission_for_actor(target_submission_id,target_team_id,new_role,idempotency_key)$$;
create or replace function api.dismiss_intake_submission(target_submission_id uuid) returns void language sql
 security invoker set search_path='' as $$select internal.dismiss_intake_submission_for_actor(target_submission_id)$$;
create or replace function api.public_get_intake_form(public_token text) returns jsonb language sql stable
 security invoker set search_path='' as $$select internal.public_get_intake_form(public_token)$$;
create or replace function api.public_submit_intake(public_token text,full_name text,phone text,email text,
 birth_date date,street_address text,postal_code text,city text,ip_hash text) returns jsonb language sql
 security invoker set search_path='' as
 $$select internal.public_submit_intake(public_token,full_name,phone,email,birth_date,street_address,postal_code,city,ip_hash)$$;

revoke all on function internal.actor_handles_intake(uuid,uuid),internal.get_intake_overview_for_actor(uuid),
 internal.create_intake_form_for_actor(uuid,uuid),internal.close_intake_form_for_actor(uuid),
 internal.accept_intake_submission_for_actor(uuid,uuid,text,uuid),internal.dismiss_intake_submission_for_actor(uuid),
 internal.public_get_intake_form(text),internal.public_submit_intake(text,text,text,text,date,text,text,text,text),
 api.get_intake_overview(uuid),api.create_intake_form(uuid,uuid),api.close_intake_form(uuid),
 api.accept_intake_submission(uuid,uuid,text,uuid),api.dismiss_intake_submission(uuid),
 api.public_get_intake_form(text),api.public_submit_intake(text,text,text,text,date,text,text,text,text)
 from public,anon,authenticated;
grant execute on function internal.actor_handles_intake(uuid,uuid),internal.get_intake_overview_for_actor(uuid),
 internal.create_intake_form_for_actor(uuid,uuid),internal.close_intake_form_for_actor(uuid),
 internal.accept_intake_submission_for_actor(uuid,uuid,text,uuid),internal.dismiss_intake_submission_for_actor(uuid),
 api.get_intake_overview(uuid),api.create_intake_form(uuid,uuid),api.close_intake_form(uuid),
 api.accept_intake_submission(uuid,uuid,text,uuid),api.dismiss_intake_submission(uuid)
 to authenticated;
grant execute on function internal.public_get_intake_form(text),
 internal.public_submit_intake(text,text,text,text,date,text,text,text,text),
 api.public_get_intake_form(text),api.public_submit_intake(text,text,text,text,date,text,text,text,text)
 to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261002090000_intake_forms','greenfield','TEAM-15 temporary contact pages on the public site and adding people to teams'
where not exists(select 1 from internal.migration_provenance where migration_name='20261002090000_intake_forms');
notify pgrst,'reload schema';
