-- Generated with the CLI; ordered after TEAM-16's already-applied future timestamp.
-- An intake submission is a proposal, never authority to change an account.
create table core.contact_change_requests (
 id uuid primary key default gen_random_uuid(),
 submission_id uuid not null unique,
 profile_id uuid not null references core.profiles(id),
 club_id uuid not null references core.clubs(id),
 person_id uuid not null,
 team_id uuid not null,
 before_contact jsonb not null,
 proposed_contact jsonb not null,
 state text not null default 'pending' check(state in('pending','approved','rejected')),
 created_by uuid not null references core.profiles(id),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '14 days',
 decided_by uuid references core.profiles(id),
 decided_at timestamptz,
 foreign key(person_id,club_id) references core.club_people(id,club_id),
 foreign key(team_id,club_id) references core.teams(id,club_id)
);
create index contact_change_requests_pending on core.contact_change_requests(profile_id) where state='pending';
alter table core.contact_change_requests enable row level security;
revoke all on core.contact_change_requests from public,anon,authenticated;

create function internal.profile_contact_snapshot(target_profile_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('email',contact_email,'phone',phone,'street',street_address,'postal',postal_code,'city',city)
 from core.profiles where id=target_profile_id
$$;

create function internal.actor_approves_profile_contact(target_profile_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (auth.uid()=target_profile_id or exists(
  select 1 from core.person_account_links child
  join core.guardian_relations relation on relation.club_id=child.club_id and relation.child_person_id=child.club_person_id
   and relation.state='active' and relation.starts_at<=now() and (relation.ends_at is null or relation.ends_at>now())
  join core.person_account_links guardian on guardian.club_id=relation.club_id
   and guardian.club_person_id=relation.guardian_person_id and guardian.state='active' and guardian.profile_id=auth.uid()
  where child.profile_id=target_profile_id and child.state='active'))
$$;

-- Preserve the direct update only for people without an account.
alter function internal.update_person_from_intake_for_actor(uuid,uuid,uuid) rename to update_person_from_intake_unlinked_for_actor;
revoke all on function internal.update_person_from_intake_unlinked_for_actor(uuid,uuid,uuid) from public,anon,authenticated;

create function internal.process_intake_contact_update_for_actor(target_submission_id uuid,target_team_id uuid,target_person_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare submission core.intake_submissions%rowtype; account_id uuid; request_id uuid; contact jsonb; address jsonb; prior core.contact_change_requests%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 perform pg_advisory_xact_lock(hashtextextended('intake-contact:'||target_submission_id::text,0));
 select * into prior from core.contact_change_requests where submission_id=target_submission_id;
 if prior.id is not null then
  if prior.created_by<>auth.uid() or prior.person_id<>target_person_id or prior.team_id<>target_team_id
   or not internal.actor_handles_intake(prior.club_id,prior.team_id) then raise insufficient_privilege using message='not_found';end if;
  return jsonb_build_object('status','pending_approval','request_id',prior.id);
 end if;
 select * into submission from core.intake_submissions where id=target_submission_id for update;
 if submission.id is null or not internal.actor_handles_intake(submission.club_id,submission.team_id)
  or not internal.actor_handles_intake(submission.club_id,target_team_id)
  or not internal.person_in_team(submission.club_id,target_team_id,target_person_id)
  or not exists(select 1 from core.teams where id=target_team_id and club_id=submission.club_id and status='active')
 then raise insufficient_privilege using message='not_found';end if;
 select profile_id into account_id from core.person_account_links
 where club_id=submission.club_id and club_person_id=target_person_id and state='active' order by created_at desc limit 1;
 if account_id is null then
  perform internal.update_person_from_intake_unlinked_for_actor(target_submission_id,target_team_id,target_person_id);
  return jsonb_build_object('status','updated');
 end if;
 contact:=internal.normalized_contact(submission.email,submission.phone);
 address:=internal.normalized_address(submission.street_address,submission.postal_code,submission.city);
 perform 1 from core.profiles where id=account_id for update;
 insert into core.contact_change_requests(submission_id,profile_id,club_id,person_id,team_id,before_contact,proposed_contact,created_by)
 values(submission.id,account_id,submission.club_id,target_person_id,target_team_id,
  internal.profile_contact_snapshot(account_id),contact||address,auth.uid()) returning id into request_id;
 -- In-app notifications only; no raw contact data in delivery payloads.
 insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,aggregate_id,
  recipient_profile_id,recipient_person_id,payload_ref,state)
 select distinct link.club_id,request_id,'profile.contact.approval_requested.v1','contact_change',request_id,
  link.profile_id,link.club_person_id,jsonb_build_object('contact_change_id',request_id),'suppressed'
 from core.person_account_links link where link.state='active' and (
  (link.profile_id=account_id and link.club_id=submission.club_id and link.club_person_id=target_person_id)
  or exists(select 1 from core.guardian_relations relation join core.person_account_links child
   on child.club_id=relation.club_id and child.club_person_id=relation.child_person_id and child.state='active' and child.profile_id=account_id
   where relation.club_id=link.club_id and relation.guardian_person_id=link.club_person_id
    and relation.state='active' and relation.starts_at<=now() and (relation.ends_at is null or relation.ends_at>now())))
 on conflict(domain_event_id,recipient_person_id) do nothing;
 delete from core.intake_submissions where id=submission.id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(submission.club_id,auth.uid(),'profile.contact.proposed.v1','contact_change',request_id,1,'{}');
 return jsonb_build_object('status','pending_approval','request_id',request_id);
end$$;

create function internal.list_contact_change_requests_for_actor()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',p.display_name,'club_name',c.name,
  'before',r.before_contact,'proposed',r.proposed_contact,'expires_at',r.expires_at,
  'conflict',internal.profile_contact_snapshot(r.profile_id) is distinct from r.before_contact)
  order by r.created_at) from core.contact_change_requests r join core.profiles p on p.id=r.profile_id
  join core.clubs c on c.id=r.club_id where r.state='pending' and r.expires_at>now()
   and internal.actor_approves_profile_contact(r.profile_id)),'[]'::jsonb);
end$$;

create function internal.decide_contact_change_for_actor(target_request_id uuid,approve boolean)
returns text language plpgsql security definer set search_path='' as $$
declare request core.contact_change_requests%rowtype; contact jsonb; account_row core.profiles%rowtype; notice_id uuid:=gen_random_uuid();
begin
 if auth.uid() is null or approve is null then raise insufficient_privilege using message='not_found';end if;
 select * into request from core.contact_change_requests where id=target_request_id for update;
 if request.id is null or not internal.actor_approves_profile_contact(request.profile_id)
 then raise insufficient_privilege using message='not_found';end if;
 if request.state<>'pending' then return request.state;end if;
 if request.expires_at<=now() then raise check_violation using message='request_expired';end if;
 select * into account_row from core.profiles where id=request.profile_id for update;
 if approve then
  if internal.profile_contact_snapshot(request.profile_id) is distinct from request.before_contact
  then raise serialization_failure using message='stale_contact';end if;
  contact:=request.proposed_contact;
  update core.profiles set contact_email=contact->>'email',phone=contact->>'phone',
   street_address=contact->>'street',postal_code=contact->>'postal',city=contact->>'city',
   revision=revision+1,updated_at=now() where id=request.profile_id;
  -- Keep linked club records consistent with the single shared account.
  update core.club_people person set contact_email=contact->>'email',phone=contact->>'phone',
   street_address=contact->>'street',postal_code=contact->>'postal',city=contact->>'city',revision=person.revision+1
  where exists(select 1 from core.person_account_links link where link.profile_id=request.profile_id and link.state='active'
   and link.club_person_id=person.id and link.club_id=person.club_id);
  -- Notify current leaders of each team the account belongs to, and the account itself.
  insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,aggregate_id,
   recipient_profile_id,recipient_person_id,payload_ref,state)
  select distinct member.club_id,notice_id,'profile.contact.updated.v1','contact_change',request.id,
   recipient.profile_id,recipient.club_person_id,jsonb_build_object('contact_change_id',request.id),'suppressed'
  from core.person_account_links member
  join core.person_account_links recipient on recipient.club_id=member.club_id and recipient.state='active'
  where member.profile_id=request.profile_id and member.state='active' and (recipient.profile_id=request.profile_id
   or exists(select 1 from core.assignments own_team join core.assignments leader on leader.club_id=own_team.club_id
     and leader.team_id=own_team.team_id and leader.club_person_id=recipient.club_person_id
     and leader.role_package in('leader','club_functionary') and leader.state='active'
     and leader.starts_at<=now() and (leader.ends_at is null or leader.ends_at>now())
    where own_team.club_id=member.club_id and own_team.club_person_id=member.club_person_id and own_team.state='active'
     and own_team.starts_at<=now() and (own_team.ends_at is null or own_team.ends_at>now())))
  on conflict(domain_event_id,recipient_person_id) do update set event_type=excluded.event_type,
   payload_ref=excluded.payload_ref,created_at=now();
 end if;
 update core.contact_change_requests set state=case when approve then 'approved' else 'rejected' end,
  decided_by=auth.uid(),decided_at=now(),before_contact='{}',proposed_contact='{}' where id=request.id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(request.club_id,auth.uid(),'profile.contact.decided.v1','contact_change',request.id,2,jsonb_build_object('approved',approve));
 return case when approve then 'approved' else 'rejected' end;
end$$;

create function internal.update_person_from_intake_for_actor(target_submission_id uuid,target_team_id uuid,target_person_id uuid)
returns void language plpgsql security definer set search_path='' as $$begin
 perform internal.process_intake_contact_update_for_actor(target_submission_id,target_team_id,target_person_id);
end$$;
-- Rebind the existing endpoint; renaming must not leave it pointing to the old direct-write function.
create or replace function api.update_person_from_intake(target_submission_id uuid,target_team_id uuid,target_person_id uuid)
returns void language sql security invoker set search_path='' as $$
 select internal.update_person_from_intake_for_actor(target_submission_id,target_team_id,target_person_id)
$$;
create function api.process_intake_contact_update(target_submission_id uuid,target_team_id uuid,target_person_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select internal.process_intake_contact_update_for_actor(target_submission_id,target_team_id,target_person_id)
$$;
create function api.list_contact_change_requests() returns jsonb language sql stable security invoker set search_path='' as $$
 select internal.list_contact_change_requests_for_actor()
$$;
create function api.decide_contact_change(target_request_id uuid,approve boolean) returns text language sql security invoker set search_path='' as $$
 select internal.decide_contact_change_for_actor(target_request_id,approve)
$$;
revoke all on function internal.profile_contact_snapshot(uuid),internal.actor_approves_profile_contact(uuid),
 internal.process_intake_contact_update_for_actor(uuid,uuid,uuid),internal.list_contact_change_requests_for_actor(),
 internal.decide_contact_change_for_actor(uuid,boolean),internal.update_person_from_intake_for_actor(uuid,uuid,uuid),
 api.process_intake_contact_update(uuid,uuid,uuid),api.list_contact_change_requests(),api.decide_contact_change(uuid,boolean)
 from public,anon,authenticated;
grant execute on function internal.process_intake_contact_update_for_actor(uuid,uuid,uuid),internal.list_contact_change_requests_for_actor(),
 internal.decide_contact_change_for_actor(uuid,boolean),internal.update_person_from_intake_for_actor(uuid,uuid,uuid),
 api.process_intake_contact_update(uuid,uuid,uuid),api.list_contact_change_requests(),api.decide_contact_change(uuid,boolean) to authenticated;

do $patch$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.notification_title(text)'::regprocedure);
 patched:=replace(definition,'select case', $text$select case
  when event_type='profile.contact.approval_requested.v1' then 'Godkänn kontaktuppgifter'
  when event_type='profile.contact.updated.v1' then 'Kontaktuppgifter uppdaterade'$text$);
 if patched=definition then raise exception 'notification title patch missing';end if;execute patched;
 definition:=pg_get_functiondef('internal.notification_preview(text)'::regprocedure);
 patched:=replace(definition,'select case', $text$select case
  when event_type='profile.contact.approval_requested.v1' then 'Granska ändringsförslaget under Inställningar → Profil → Kontaktuppdateringar.'
  when event_type='profile.contact.updated.v1' then 'En medlem har uppdaterat sina gemensamma kontaktuppgifter. Öppna personens profil för aktuella uppgifter.'$text$);
 if patched=definition then raise exception 'notification preview patch missing';end if;execute patched;
 definition:=pg_get_functiondef('internal.notification_deep_link(internal.notification_outbox)'::regprocedure);
 patched:=replace(definition,'select case', $text$select case
  when outbox.event_type='profile.contact.approval_requested.v1' then '/settings?tab=profile'$text$);
 if patched=definition then raise exception 'notification link patch missing';end if;execute patched;
end$patch$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261002120001_intake_contact_approval','greenfield','Account or active guardian approves global contact changes from intake');
notify pgrst,'reload schema';
