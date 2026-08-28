create table core.leader_verifications(
  profile_id uuid primary key references core.profiles(id),
  adult_verified boolean not null default false,
  verification_method text not null check(verification_method in ('manual_club_admin','trusted_identity_provider')),
  state text not null default 'active' check(state in ('active','revoked')),
  verified_at timestamptz not null,
  verified_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check(revision>0)
);
alter table core.leader_verifications enable row level security;

create function internal.actor_is_verified_adult_leader(target_profile_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from core.leader_verifications verification where verification.profile_id=target_profile_id and verification.adult_verified and verification.state='active')
 and exists(select 1 from core.person_account_links link join core.assignments assignment on assignment.club_id=link.club_id and assignment.club_person_id=link.club_person_id
   where link.profile_id=target_profile_id and link.state='active' and assignment.role_package='leader' and assignment.state='active' and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now()));
$$;

create function internal.list_cross_club_leaders_for_actor(search_text text)
returns table(profile_id uuid,display_name text,club_name text,team_name text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not internal.actor_is_verified_adult_leader(auth.uid()) then return; end if;
 return query select distinct profile.id,profile.display_name,club.name,team.name
 from core.profiles profile join core.leader_verifications verification on verification.profile_id=profile.id and verification.adult_verified and verification.state='active'
 join core.person_account_links link on link.profile_id=profile.id and link.state='active'
 join core.assignments assignment on assignment.club_id=link.club_id and assignment.club_person_id=link.club_person_id and assignment.role_package='leader' and assignment.state='active' and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())
 join core.clubs club on club.id=assignment.club_id join core.teams team on team.id=assignment.team_id and team.club_id=assignment.club_id
 where profile.id<>auth.uid() and profile.display_name ilike '%'||left(coalesce(search_text,''),80)||'%'
 and not exists(select 1 from core.contact_controls block where block.control_type='block' and block.state='active' and ((block.requester_profile_id=auth.uid() and block.target_profile_id=profile.id) or (block.target_profile_id=auth.uid() and block.requester_profile_id=profile.id)))
 order by profile.display_name limit 25;
end$$;

create function internal.request_cross_club_contact_for_actor(target_leader_id uuid,reason_code text,request_text text,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare request_id uuid:=gen_random_uuid(); actor_id uuid:=auth.uid(); existing jsonb;
begin
 if not internal.actor_is_verified_adult_leader(actor_id) or not internal.actor_is_verified_adult_leader(target_leader_id) or reason_code not in ('match','event','transfer','club_business','other') or length(coalesce(request_text,''))>160 then raise insufficient_privilege using message='not_found'; end if;
 if (select count(*) from core.contact_controls where requester_profile_id=actor_id and control_type='request' and created_at>now()-interval '24 hours')>=3
 or (select count(*) from core.contact_controls where requester_profile_id=actor_id and control_type='request' and created_at>now()-interval '30 days')>=10 then raise program_limit_exceeded using message='rate_limited'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type='message.contact.requested.v1' and internal.command_deduplication.idempotency_key=request_cross_club_contact_for_actor.idempotency_key;
 if existing is not null then return (existing->>'request_id')::uuid; end if;
 insert into core.contact_controls(id,requester_profile_id,target_profile_id,control_type,state,reason_code,request_text,expires_at) values(request_id,actor_id,target_leader_id,'request','pending',reason_code,nullif(btrim(request_text),''),now()+interval '14 days');
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'message.contact.requested.v1',jsonb_build_object('request_id',request_id));
 return request_id;
end$$;

create function internal.decide_contact_request_for_actor(target_request_id uuid,decision text,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare request_row core.contact_controls%rowtype; actor_id uuid:=auth.uid(); thread_id uuid; requester_link record; target_link record;
begin
 select * into request_row from core.contact_controls where id=target_request_id and control_type='request' for update;
 if request_row.id is null or request_row.target_profile_id<>actor_id or request_row.state<>'pending' then raise insufficient_privilege using message='not_found'; end if;
 if request_row.expires_at<=now() then update core.contact_controls set state='expired',decided_at=now(),revision=revision+1 where id=request_row.id; return jsonb_build_object('state','expired'); end if;
 if decision not in ('accepted','declined','blocked') then raise invalid_parameter_value using message='invalid_decision'; end if;
 if decision='blocked' then insert into core.contact_controls(requester_profile_id,target_profile_id,control_type,state) values(actor_id,request_row.requester_profile_id,'block','active') on conflict do nothing; end if;
 update core.contact_controls set state=case when decision='blocked' then 'declined' else decision end,decided_at=now(),revision=revision+1 where id=request_row.id;
 if decision='accepted' then
   select link.club_id,link.club_person_id into requester_link from core.person_account_links link join core.assignments assignment on assignment.club_id=link.club_id and assignment.club_person_id=link.club_person_id where link.profile_id=request_row.requester_profile_id and link.state='active' and assignment.role_package='leader' and assignment.state='active' limit 1;
   select link.club_id,link.club_person_id into target_link from core.person_account_links link join core.assignments assignment on assignment.club_id=link.club_id and assignment.club_person_id=link.club_person_id where link.profile_id=actor_id and link.state='active' and assignment.role_package='leader' and assignment.state='active' limit 1;
   insert into core.message_threads(club_id,thread_type,created_by) values(null,'cross_club_direct',actor_id) returning id into thread_id;
   insert into core.thread_scopes(thread_id,club_id,scope_role) values(thread_id,requester_link.club_id,'peer'),(thread_id,target_link.club_id,'peer');
   insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role) values(thread_id,request_row.requester_profile_id,requester_link.club_id,requester_link.club_person_id,'member'),(thread_id,actor_id,target_link.club_id,target_link.club_person_id,'creator');
 end if;
 return jsonb_build_object('state',decision,'thread_id',thread_id);
end$$;

create function internal.recall_message_for_actor(target_message_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare message_row core.messages%rowtype; next_version bigint;
begin
 select * into message_row from core.messages where id=target_message_id for update;
 if message_row.id is null or message_row.sender_profile_id<>auth.uid() or message_row.state<>'sent' or message_row.revision<>expected_revision or message_row.created_at<now()-interval '15 minutes' or not internal.actor_can_access_thread(message_row.thread_id,true) then raise insufficient_privilege using message='not_found'; end if;
 select coalesce(max(message_revision),0)+1 into next_version from audit.message_versions where message_id=target_message_id;
 insert into audit.message_versions(message_id,thread_id,message_revision,body_snapshot,body_hash,action,actor_profile_id) values(message_row.id,message_row.thread_id,next_version,message_row.body,encode(extensions.digest(message_row.body,'sha256'),'hex'),'recalled',auth.uid());
 update core.messages set body='[recalled]',state='recalled',recalled_at=now(),revision=revision+1 where id=message_row.id returning revision into expected_revision;
 update core.file_objects set state='withdrawn',expires_at=now(),revision=revision+1 where message_id=message_row.id and state='active';
 return expected_revision;
end$$;

create function internal.report_message_for_actor(target_message_id uuid,reason_code text,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare message_row core.messages%rowtype; report_id uuid:=gen_random_uuid();
begin
 select * into message_row from core.messages where id=target_message_id;
 if message_row.id is null or not internal.actor_can_access_thread(message_row.thread_id,false) or message_row.sender_profile_id=auth.uid() or reason_code not in ('harassment','sexual_content','threat','spam','other') then raise insufficient_privilege using message='not_found'; end if;
 insert into core.message_reports(id,thread_id,message_id,reporter_profile_id,reported_profile_id,reason_code,evidence_hash) values(report_id,message_row.thread_id,message_row.id,auth.uid(),message_row.sender_profile_id,reason_code,encode(extensions.digest(message_row.body,'sha256'),'hex'));
 insert into core.contact_controls(requester_profile_id,target_profile_id,control_type,state) values(auth.uid(),message_row.sender_profile_id,'block','active') on conflict do nothing;
 update core.message_threads set state='closed',closed_at=now(),revision=revision+1 where id=message_row.thread_id and thread_type in ('direct','cross_club_direct');
 return report_id;
end$$;

create function api.list_cross_club_leaders(query text) returns table(profile_id uuid,display_name text,club_name text,team_name text) language sql stable security invoker set search_path='' as $$select * from internal.list_cross_club_leaders_for_actor(query)$$;
create function api.request_cross_club_contact(target_leader_id uuid,reason_code text,request_text text,idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$select internal.request_cross_club_contact_for_actor(target_leader_id,reason_code,request_text,idempotency_key)$$;
create function api.decide_contact_request(request_id uuid,decision text,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as $$select internal.decide_contact_request_for_actor(request_id,decision,idempotency_key)$$;
create function api.recall_message(message_id uuid,expected_revision bigint,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$select internal.recall_message_for_actor(message_id,expected_revision,idempotency_key)$$;
create function api.report_message(message_id uuid,reason_code text,idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$select internal.report_message_for_actor(message_id,reason_code,idempotency_key)$$;

revoke all on function internal.actor_is_verified_adult_leader(uuid),internal.list_cross_club_leaders_for_actor(text),internal.request_cross_club_contact_for_actor(uuid,text,text,uuid),internal.decide_contact_request_for_actor(uuid,text,uuid),internal.recall_message_for_actor(uuid,bigint,uuid),internal.report_message_for_actor(uuid,text,uuid) from public,anon,authenticated;
grant execute on function internal.list_cross_club_leaders_for_actor(text),internal.request_cross_club_contact_for_actor(uuid,text,text,uuid),internal.decide_contact_request_for_actor(uuid,text,uuid),internal.recall_message_for_actor(uuid,bigint,uuid),internal.report_message_for_actor(uuid,text,uuid) to authenticated;
revoke all on function api.list_cross_club_leaders(text),api.request_cross_club_contact(uuid,text,text,uuid),api.decide_contact_request(uuid,text,uuid),api.recall_message(uuid,bigint,uuid),api.report_message(uuid,text,uuid) from public,anon;
grant execute on function api.list_cross_club_leaders(text),api.request_cross_club_contact(uuid,text,text,uuid),api.decide_contact_request(uuid,text,uuid),api.recall_message(uuid,bigint,uuid),api.report_message(uuid,text,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808144116_s06_cross_club_moderation','greenfield',null);
