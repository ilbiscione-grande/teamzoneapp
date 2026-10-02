-- CLI-generated; ordered after the contact-approval dependency.
-- Sensitive values never enter general roster/search/export source columns.
create table core.profile_addresses (
 id uuid primary key, profile_id uuid not null references core.profiles(id),
 label text not null check(length(btrim(label)) between 1 and 60),
 street text, postal text, city text, revision bigint not null default 1,
 unique(id,profile_id)
);
create index profile_addresses_owner_idx on core.profile_addresses(profile_id);
create table core.club_address_choices (
 profile_id uuid not null references core.profiles(id), club_id uuid not null references core.clubs(id),
 address_id uuid, primary key(profile_id,club_id),
 foreign key(address_id,profile_id) references core.profile_addresses(id,profile_id)
);
create index club_address_choices_address_idx on core.club_address_choices(address_id,profile_id);
create index club_address_choices_club_idx on core.club_address_choices(club_id);
create table core.profile_privacy (
 profile_id uuid primary key references core.profiles(id),
 enabled boolean not null default false, alias text not null,
 private_name text, safe_email text, safe_phone text,
 revision bigint not null default 1, updated_at timestamptz not null default now()
);
create table core.protected_person_bindings (
 person_id uuid primary key references core.club_people(id),
 profile_id uuid not null references core.profiles(id),
 private_birth_year smallint,private_birth_date date,private_age_class text
);
create index protected_person_bindings_profile_idx on core.protected_person_bindings(profile_id);
create table core.private_contact_grants (
 profile_id uuid not null references core.profiles(id), club_id uuid not null references core.clubs(id),
 viewer_id uuid not null references core.profiles(id),
 primary key(profile_id,club_id,viewer_id)
);
create index private_contact_grants_viewer_idx on core.private_contact_grants(viewer_id);
create index private_contact_grants_club_idx on core.private_contact_grants(club_id);
alter table core.profile_addresses enable row level security;
alter table core.club_address_choices enable row level security;
alter table core.profile_privacy enable row level security;
alter table core.protected_person_bindings enable row level security;
alter table core.private_contact_grants enable row level security;
revoke all on core.profile_addresses,core.club_address_choices,core.profile_privacy,
 core.protected_person_bindings,core.private_contact_grants from public,anon,authenticated;

-- Preserve the existing address and its existing club visibility. New addresses
-- are private until explicitly selected for a club. New clubs get no selection.
insert into core.profile_addresses(id,profile_id,label,street,postal,city)
select gen_random_uuid(),id,'Befintlig adress',street_address,postal_code,city from core.profiles
where street_address is not null or postal_code is not null or city is not null;
insert into core.club_address_choices(profile_id,club_id,address_id)
select distinct a.profile_id,l.club_id,a.id from core.profile_addresses a
join core.person_account_links l on l.profile_id=a.profile_id and l.state='active';
update core.profiles set street_address=null,postal_code=null,city=null;
-- Club-specific addresses are retained as separate options, not overwritten.
insert into core.profile_addresses(id,profile_id,label,street,postal,city)
select p.id,l.profile_id,'Tidigare klubbadress',p.street_address,p.postal_code,p.city
from core.club_people p join core.person_account_links l on l.club_person_id=p.id and l.state='active'
where p.street_address is not null or p.postal_code is not null or p.city is not null;
insert into core.club_address_choices(profile_id,club_id,address_id)
select l.profile_id,l.club_id,a.id from core.person_account_links l join core.profile_addresses a on a.id=l.club_person_id
where l.state='active' on conflict(profile_id,club_id) do nothing;
update core.club_people p set street_address=null,postal_code=null,city=null
where exists(select 1 from core.person_account_links l where l.club_person_id=p.id and l.state='active');

create function internal.profile_is_protected(target uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from core.profile_privacy where profile_id=target and enabled)
$$;
create function internal.private_contact_allowed(target uuid,club uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (internal.actor_approves_profile_contact(target) or exists(
  select 1 from core.private_contact_grants g where g.profile_id=target and g.club_id=club and g.viewer_id=auth.uid()
   and internal.actor_has_club_access(club)
   and exists(select 1 from core.person_account_links own where own.profile_id=target and own.club_id=club and own.state='active')
   and exists(select 1 from core.person_account_links l join core.assignments a on a.club_person_id=l.club_person_id and a.club_id=l.club_id
    where l.profile_id=auth.uid() and l.club_id=club and l.state='active' and a.state='active'
     and a.role_package in('leader','club_functionary') and a.starts_at<=now() and (a.ends_at is null or a.ends_at>now()))))
$$;

create function internal.get_address_privacy_for_actor(target uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not internal.actor_approves_profile_contact(target) then raise insufficient_privilege using message='not_found'; end if;
 select jsonb_build_object('profile_id',p.id,'name',p.display_name,
  'protected',coalesce(v.enabled,false),'alias',coalesce(v.alias,p.display_name),
  'private_name',v.private_name,'safe_email',v.safe_email,'safe_phone',v.safe_phone,
  'revision',coalesce(v.revision,0),
  'addresses',coalesce((select jsonb_agg(to_jsonb(a) order by a.label,a.id) from core.profile_addresses a where a.profile_id=target),'[]'),
  'clubs',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'address_id',s.address_id))
    from core.clubs c left join core.club_address_choices s on s.club_id=c.id and s.profile_id=target
    where exists(select 1 from core.person_account_links l where l.profile_id=target and l.club_id=c.id and l.state='active')),'[]'),
  'grants',coalesce((select jsonb_agg(jsonb_build_object('club_id',g.club_id,'viewer_id',g.viewer_id,'name',viewer.display_name))
    from core.private_contact_grants g join core.profiles viewer on viewer.id=g.viewer_id where g.profile_id=target),'[]'),
  'candidates',coalesce((select jsonb_agg(distinct jsonb_build_object('club_id',l.club_id,'viewer_id',l.profile_id,'name',viewer.display_name))
    from core.person_account_links l join core.profiles viewer on viewer.id=l.profile_id
    where l.state='active' and l.profile_id<>target
    and exists(select 1 from core.person_account_links own where own.profile_id=target and own.club_id=l.club_id and own.state='active')
    and exists(select 1 from core.assignments a where a.club_person_id=l.club_person_id and a.club_id=l.club_id
      and a.state='active' and a.role_package in('leader','club_functionary') and a.starts_at<=now() and (a.ends_at is null or a.ends_at>now()))),'[]')
 ) into result from core.profiles p left join core.profile_privacy v on v.profile_id=p.id where p.id=target;
 return result;
end$$;
create function internal.list_address_privacy_subjects_for_actor() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name)
  from core.profiles p where internal.actor_approves_profile_contact(p.id)),'[]');
end$$;

create function internal.save_profile_address_for_actor(target uuid,address_id uuid,address_label text,
 new_street text,new_postal text,new_city text,expected_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare normalized jsonb; current_revision bigint;
begin
 if not internal.actor_approves_profile_contact(target) then raise insufficient_privilege using message='not_found';end if;
 perform 1 from core.profiles where id=target for update;
 if address_id is null or length(btrim(coalesce(address_label,''))) not between 1 and 60 then raise check_violation using message='invalid_address';end if;
 normalized:=internal.normalized_address(new_street,new_postal,new_city);
 if normalized=jsonb_build_object('street',null,'postal',null,'city',null) then raise check_violation using message='invalid_address';end if;
 select revision into current_revision from core.profile_addresses where id=address_id and profile_id=target;
 if coalesce(current_revision,0)<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 insert into core.profile_addresses(id,profile_id,label,street,postal,city)
 values(address_id,target,btrim(address_label),normalized->>'street',normalized->>'postal',normalized->>'city')
 on conflict(id) do update set label=excluded.label,street=excluded.street,postal=excluded.postal,city=excluded.city,
  revision=core.profile_addresses.revision+1 where core.profile_addresses.profile_id=target;
 if not found then raise insufficient_privilege using message='not_found';end if;
end$$;
create function internal.choose_club_address_for_actor(target uuid,club uuid,address_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not internal.actor_approves_profile_contact(target) or not exists(select 1 from core.person_account_links
  where profile_id=target and club_id=club and state='active') then raise insufficient_privilege using message='not_found';end if;
 perform 1 from core.profiles where id=target for update;
 insert into core.club_address_choices(profile_id,club_id,address_id) values(target,club,address_id)
 on conflict(profile_id,club_id) do update set address_id=excluded.address_id;
end$$;
create function internal.delete_profile_address_for_actor(target uuid,address_id uuid,expected_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not internal.actor_approves_profile_contact(target) then raise insufficient_privilege using message='not_found';end if;
 perform 1 from core.profiles where id=target for update;
 if not exists(select 1 from core.profile_addresses a where a.id=address_id and a.profile_id=target and a.revision=expected_revision)
 then raise serialization_failure using message='stale_revision';end if;
 update core.club_address_choices s set address_id=null where s.profile_id=target and s.address_id=delete_profile_address_for_actor.address_id;
 delete from core.profile_addresses a where a.id=address_id and a.profile_id=target;
end$$;

create function internal.set_private_contact_grant_for_actor(target uuid,club uuid,viewer uuid,allow_access boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not internal.actor_approves_profile_contact(target) or allow_access is null then raise insufficient_privilege using message='not_found';end if;
 perform 1 from core.profiles where id=target for update;
 if allow_access then
  if not exists(select 1 from core.person_account_links l where l.profile_id=target and l.club_id=club and l.state='active')
   or not exists(select 1 from core.person_account_links l join core.assignments a on a.club_person_id=l.club_person_id and a.club_id=l.club_id
    where l.profile_id=viewer and l.club_id=club and l.state='active' and a.state='active' and a.role_package in('leader','club_functionary')
     and a.starts_at<=now() and (a.ends_at is null or a.ends_at>now())) then raise insufficient_privilege using message='not_found';end if;
  insert into core.private_contact_grants values(target,club,viewer) on conflict do nothing;
 else delete from core.private_contact_grants where profile_id=target and club_id=club and viewer_id=viewer;
 end if;
end$$;

-- General source columns contain only the chosen alias. This covers roster,
-- event participants, member cards, searches and source-based exports alike.
create function internal.guard_private_profile_source() returns trigger language plpgsql security definer set search_path='' as $$
declare privacy core.profile_privacy%rowtype;
begin
 select * into privacy from core.profile_privacy where profile_id=new.id and enabled;
 if privacy.profile_id is not null then
  new.display_name:=privacy.alias;new.contact_email:=null;new.phone:=null;new.avatar_asset_id:=null;
 end if;
 if new.street_address is not null or new.postal_code is not null or new.city is not null then
   raise check_violation using message='use_address_settings';
 end if;
 return new;
end$$;
create trigger guard_private_profile_source before insert or update on core.profiles
for each row execute function internal.guard_private_profile_source();
create function internal.guard_private_person_source() returns trigger language plpgsql security definer set search_path='' as $$
declare privacy core.profile_privacy%rowtype;
begin
 select v.* into privacy from core.protected_person_bindings b join core.profile_privacy v on v.profile_id=b.profile_id
 join core.club_people original on original.id=b.person_id
 where (b.person_id=new.id or original.person_id=new.person_id) and v.enabled limit 1;
 if privacy.profile_id is not null then
  new.display_name:=privacy.alias;new.contact_email:=null;new.phone:=null;
  new.street_address:=null;new.postal_code:=null;new.city:=null;new.birth_year:=null;new.birth_date:=null;new.age_class:=null;
 end if;
 return new;
end$$;
create trigger guard_private_person_source before insert or update on core.club_people
for each row execute function internal.guard_private_person_source();

create function internal.save_profile_privacy_for_actor(target uuid,enable_protection boolean,new_alias text,
 new_private_name text,new_safe_email text,new_safe_phone text,expected_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare current_row core.profile_privacy%rowtype; contact jsonb;
begin
 if not internal.actor_approves_profile_contact(target) or enable_protection is null then raise insufficient_privilege using message='not_found';end if;
 perform 1 from core.profiles where id=target for update;
 select * into current_row from core.profile_privacy where profile_id=target;
 if coalesce(current_row.revision,0)<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 if length(btrim(coalesce(new_alias,''))) not between 1 and 120 or length(btrim(coalesce(new_private_name,'')))>120
 then raise check_violation using message='invalid_profile';end if;
 if enable_protection and lower(btrim(new_alias))=lower(btrim(coalesce(new_private_name,'')))
 then raise check_violation using message='choose_distinct_alias';end if;
 contact:=internal.normalized_contact(new_safe_email,new_safe_phone);
 insert into core.profile_privacy(profile_id,enabled,alias,private_name,safe_email,safe_phone)
 values(target,enable_protection,btrim(new_alias),nullif(btrim(new_private_name),''),contact->>'email',contact->>'phone')
 on conflict(profile_id) do update set enabled=excluded.enabled,alias=excluded.alias,private_name=excluded.private_name,
  safe_email=excluded.safe_email,safe_phone=excluded.safe_phone,revision=core.profile_privacy.revision+1,updated_at=now();
 if enable_protection then
  insert into core.protected_person_bindings(person_id,profile_id,private_birth_year,private_birth_date,private_age_class)
  select person.id,target,person.birth_year,person.birth_date,person.age_class from core.club_people person
  where exists(select 1 from core.person_account_links link join core.club_people original on original.id=link.club_person_id
   where link.profile_id=target and (link.club_person_id=person.id or original.person_id=person.person_id))
  on conflict(person_id) do nothing;
  update core.profiles set display_name=btrim(new_alias),contact_email=null,phone=null,avatar_asset_id=null,
   street_address=null,postal_code=null,city=null,revision=revision+1 where id=target;
  update core.club_people set display_name=btrim(new_alias),contact_email=null,phone=null,street_address=null,postal_code=null,city=null,
   birth_year=null,birth_date=null,age_class=null,revision=revision+1 where id in(select person_id from core.protected_person_bindings where profile_id=target);
  update core.profile_avatars set state='removed',retired_at=now() where profile_id=target and state in('active','staged');
  update core.publication_consents set state='withdrawn',withdrawn_at=now(),withdrawn_by=auth.uid(),
   withdrawal_reason='Inställningar ändrade',revision=revision+1
   where subject_club_person_id in(select person_id from core.protected_person_bindings where profile_id=target)
    and state in('active','pending_guardian');
  insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by)
  select p.club_id,'person',p.id,p.revision,'remove',array[]::text[],auth.uid() from core.club_people p
   join core.protected_person_bindings b on b.person_id=p.id where b.profile_id=target;
  update core.contact_change_requests set state='rejected',before_contact='{}',proposed_contact='{}',decided_by=auth.uid(),decided_at=now()
   where profile_id=target and state='pending';
  delete from core.private_contact_grants where profile_id=target and not coalesce(current_row.enabled,false);
  update internal.notification_outbox set state='suppressed',payload_ref='{}' where recipient_profile_id=target;
 end if;
 -- Turning protection off never republishes identity, photos or contact values.
 -- Those require separate deliberate edits afterwards.
 insert into audit.command_events(actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(auth.uid(),'profile.privacy.changed.v1','profile',target,coalesce(current_row.revision,0)+1,'{}');
end$$;

create function internal.guard_private_notification() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if internal.profile_is_protected(new.recipient_profile_id) then new.state:='suppressed';new.payload_ref:='{}';end if;
 return new;
end$$;
create trigger guard_private_notification before insert or update on internal.notification_outbox
for each row execute function internal.guard_private_notification();

-- Keep existing intake approval, but an address is a NEW option for its source
-- club, never a replacement of every residence. Protection blocks this route.
do $patch$
declare definition text;patched text;
begin
 definition:=pg_get_functiondef('internal.process_intake_contact_update_for_actor(uuid,uuid,uuid)'::regprocedure);
 patched:=replace(definition,'perform 1 from core.profiles where id=account_id for update;',
  'perform 1 from core.profiles where id=account_id for update; if internal.profile_is_protected(account_id) then raise insufficient_privilege using message=''not_available'';end if;');
 if patched=definition then raise exception 'intake protection patch missing';end if;execute patched;
 definition:=pg_get_functiondef('internal.decide_contact_change_for_actor(uuid,boolean)'::regprocedure);
 patched:=replace(definition,'contact:=request.proposed_contact;',
  'if internal.profile_is_protected(request.profile_id) then raise insufficient_privilege using message=''not_available'';end if; contact:=request.proposed_contact;
   if contact->>''street'' is not null or contact->>''postal'' is not null or contact->>''city'' is not null then
    insert into core.profile_addresses(id,profile_id,label,street,postal,city) values(request.id,request.profile_id,''Godkänd inskickad adress'',contact->>''street'',contact->>''postal'',contact->>''city'');
    insert into core.club_address_choices(profile_id,club_id,address_id) values(request.profile_id,request.club_id,request.id)
    on conflict(profile_id,club_id) do update set address_id=excluded.address_id;
   end if;');
 patched:=replace(patched,'street_address=contact->>''street'',postal_code=contact->>''postal'',city=contact->>''city'',','street_address=null,postal_code=null,city=null,');
 if patched=definition then raise exception 'approval address patch missing';end if;execute patched;
 definition:=pg_get_functiondef('internal.update_my_profile_details_for_actor(text,text,text,text,uuid,bigint,uuid)'::regprocedure);
 patched:=replace(definition,'contact:=internal.normalized_contact(new_contact_email,new_phone);',
  'if internal.profile_is_protected(actor_id) then raise check_violation using message=''use_privacy_settings'';end if; contact:=internal.normalized_contact(new_contact_email,new_phone);');
 if patched=definition then raise exception 'profile protection patch missing';end if;execute patched;
end$patch$;

-- Exclude protected accounts entirely from the directory of other clubs.
do $patch$
declare definition text;patched text;
begin
 definition:=pg_get_functiondef('internal.list_cross_club_leaders_for_actor(text)'::regprocedure);
 patched:=replace(definition,'where profile.id <> auth.uid()',
  'where profile.id <> auth.uid() and not internal.profile_is_protected(profile.id)');
 if patched=definition then raise exception 'cross-club directory privacy patch missing';end if;execute patched;
 definition:=pg_get_functiondef('internal.request_cross_club_contact_for_actor(uuid,text,text,uuid)'::regprocedure);
 patched:=replace(definition,'if not internal.actor_is_verified_adult_leader(actor_id)',
  'if internal.profile_is_protected(target_leader_id) or not internal.actor_is_verified_adult_leader(actor_id)');
 if patched=definition then raise exception 'cross-club request privacy patch missing';end if;execute patched;
end$patch$;

do $patch$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.get_my_profile_details_for_actor()'::regprocedure);
 patched:=replace(definition,'''profile_id'',profile.id,','''profile_id'',profile.id,''protected'',internal.profile_is_protected(profile.id),');
 if patched=definition then raise exception 'own profile privacy field missing';end if;execute patched;
end$patch$;

create or replace function internal.profile_contact_snapshot(target_profile_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('email',p.contact_email,'phone',p.phone,'street',null,'postal',null,'city',null,
  'address_version',md5(coalesce((select jsonb_agg(jsonb_build_array(a.id,a.revision) order by a.id)::text from core.profile_addresses a where a.profile_id=target_profile_id),'[]')
   ||coalesce((select jsonb_agg(jsonb_build_array(c.club_id,c.address_id) order by c.club_id)::text from core.club_address_choices c where c.profile_id=target_profile_id),'[]')))
 from core.profiles p where p.id=target_profile_id
$$;

-- No public consent may override protection, including future consent writes.
create function internal.guard_protected_consent() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.state='active' and exists(select 1 from core.protected_person_bindings b join core.profile_privacy v on v.profile_id=b.profile_id
  join core.club_people original on original.id=b.person_id join core.club_people subject on subject.id=new.subject_club_person_id
  where (b.person_id=subject.id or original.person_id=subject.person_id) and v.enabled) then raise check_violation using message='not_available';end if;
 return new;
end$$;
create trigger guard_protected_consent before insert or update on core.publication_consents
for each row execute function internal.guard_protected_consent();

-- Freshly linked records must get the same source protection in this transaction.
create function internal.protect_new_account_link() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if internal.profile_is_protected(new.profile_id) then
  insert into core.protected_person_bindings(person_id,profile_id,private_birth_year,private_birth_date,private_age_class)
  select id,new.profile_id,birth_year,birth_date,age_class from core.club_people where id=new.club_person_id on conflict(person_id) do nothing;
  update core.club_people set display_name=display_name where id=new.club_person_id;
 end if;
 return new;
end$$;
create trigger protect_new_account_link after insert or update on core.person_account_links
for each row execute function internal.protect_new_account_link();

-- Existing contact API remains the only member-card contact source.
alter function internal.get_person_contact_for_actor(uuid,uuid,uuid) rename to get_person_contact_without_address_privacy;
revoke all on function internal.get_person_contact_without_address_privacy(uuid,uuid,uuid) from public,anon,authenticated;
create function internal.get_person_contact_for_actor(target_club_id uuid,target_team_id uuid,target_person_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; account_id uuid; address core.profile_addresses%rowtype; privacy core.profile_privacy%rowtype; allowed boolean;
begin
 result:=internal.get_person_contact_without_address_privacy(target_club_id,target_team_id,target_person_id);
 select profile_id into account_id from core.person_account_links where club_person_id=target_person_id and state='active';
 if account_id is null then select profile_id into account_id from core.protected_person_bindings where person_id=target_person_id;end if;
 if account_id is null then return result;end if;
 result:=result-'street_address'-'postal_code'-'city';
 select * into privacy from core.profile_privacy where profile_id=account_id and enabled;
 allowed:=coalesce((result->>'can_see_contact')::boolean,false);
 if privacy.profile_id is not null then
  allowed:=internal.private_contact_allowed(account_id,target_club_id);
  result:=result-'contact_email'-'phone'-'avatar_profile_id'-'contact_source';
  result:=result||jsonb_build_object('can_see_contact',allowed,'can_edit_club_contact',false);
  if allowed then result:=result||jsonb_build_object('contact_email',privacy.safe_email,'phone',privacy.safe_phone);end if;
 end if;
 if allowed then
  select a.* into address from core.club_address_choices c join core.profile_addresses a on a.id=c.address_id and a.profile_id=c.profile_id
   where c.profile_id=account_id and c.club_id=target_club_id;
  result:=result||jsonb_build_object('street_address',address.street,'postal_code',address.postal,'city',address.city);
 end if;
 return jsonb_strip_nulls(result);
end$$;
create or replace function api.get_person_contact(target_club_id uuid,target_team_id uuid,target_person_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select internal.get_person_contact_for_actor(target_club_id,target_team_id,target_person_id)
$$;

-- Old clients may not change shared addresses or overwrite protected contact data.
-- Null addresses in the atomic profile RPC mean the address settings are unchanged.
create or replace function internal.update_my_address_for_actor(new_street text,new_postal text,new_city text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 if nullif(btrim(new_street),'') is not null or nullif(btrim(new_postal),'') is not null or nullif(btrim(new_city),'') is not null
 then raise check_violation using message='use_address_settings';end if;
end$$;

-- API wrappers and explicit grants; helpers and trigger functions remain private.
create function api.list_address_privacy_subjects() returns jsonb language sql stable security invoker set search_path='' as $$select internal.list_address_privacy_subjects_for_actor()$$;
create function api.get_address_privacy(target uuid) returns jsonb language sql stable security invoker set search_path='' as $$select internal.get_address_privacy_for_actor(target)$$;
create function api.save_profile_address(target uuid,address_id uuid,address_label text,new_street text,new_postal text,new_city text,expected_revision bigint)
returns void language sql security invoker set search_path='' as $$select internal.save_profile_address_for_actor(target,address_id,address_label,new_street,new_postal,new_city,expected_revision)$$;
create function api.choose_club_address(target uuid,club uuid,address_id uuid) returns void language sql security invoker set search_path='' as $$select internal.choose_club_address_for_actor(target,club,address_id)$$;
create function api.delete_profile_address(target uuid,address_id uuid,expected_revision bigint) returns void language sql security invoker set search_path='' as $$select internal.delete_profile_address_for_actor(target,address_id,expected_revision)$$;
create function api.save_profile_privacy(target uuid,enable_protection boolean,new_alias text,new_private_name text,new_safe_email text,new_safe_phone text,expected_revision bigint)
returns void language sql security invoker set search_path='' as $$select internal.save_profile_privacy_for_actor(target,enable_protection,new_alias,new_private_name,new_safe_email,new_safe_phone,expected_revision)$$;
create function api.set_private_contact_grant(target uuid,club uuid,viewer uuid,allow_access boolean) returns void language sql security invoker set search_path='' as $$select internal.set_private_contact_grant_for_actor(target,club,viewer,allow_access)$$;
do $$declare f record;begin
 for f in select p.oid::regprocedure signature,n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in('internal','api') and p.proname in('guard_private_notification','profile_is_protected','private_contact_allowed','guard_private_profile_source','guard_private_person_source','guard_protected_consent','protect_new_account_link',
 'list_address_privacy_subjects','list_address_privacy_subjects_for_actor','get_address_privacy','get_address_privacy_for_actor','save_profile_address','save_profile_address_for_actor',
 'choose_club_address','choose_club_address_for_actor','delete_profile_address','delete_profile_address_for_actor','save_profile_privacy','save_profile_privacy_for_actor',
 'set_private_contact_grant','set_private_contact_grant_for_actor','get_person_contact_for_actor') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 if f.nspname='api' or f.proname like '%_for_actor' then execute format('grant execute on function %s to authenticated',f.signature);end if;
 end loop;
end$$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261002120002_address_privacy_controls','greenfield','Multiple private addresses, club selection and restricted contact access');
notify pgrst,'reload schema';
