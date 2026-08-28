create function internal.actors_share_active_club(profile_a uuid,profile_b uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select profile_a is not null and profile_b is not null and exists(
    select 1
    from core.person_account_links a
    join core.person_account_links b on b.club_id=a.club_id and b.state='active'
    where a.profile_id=profile_a and a.state='active' and b.profile_id=profile_b
  );
$$;
revoke all on function internal.actors_share_active_club(uuid,uuid) from public,anon,authenticated;

create or replace function internal.list_cross_club_leaders_for_actor(search_text text)
returns table(profile_id uuid,display_name text,club_name text,team_name text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not internal.actor_is_verified_adult_leader(auth.uid()) then return; end if;
 return query select distinct profile.id,profile.display_name,club.name,team.name
 from core.profiles profile join core.leader_verifications verification on verification.profile_id=profile.id and verification.adult_verified and verification.state='active'
 join core.person_account_links link on link.profile_id=profile.id and link.state='active'
 join core.assignments assignment on assignment.club_id=link.club_id and assignment.club_person_id=link.club_person_id and assignment.role_package='leader' and assignment.state='active' and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())
 join core.clubs club on club.id=assignment.club_id join core.teams team on team.id=assignment.team_id and team.club_id=assignment.club_id
 where profile.id<>auth.uid() and not internal.actors_share_active_club(auth.uid(),profile.id)
 and profile.display_name ilike '%'||left(coalesce(search_text,''),80)||'%'
 and not exists(select 1 from core.contact_controls block where block.control_type='block' and block.state='active' and ((block.requester_profile_id=auth.uid() and block.target_profile_id=profile.id) or (block.target_profile_id=auth.uid() and block.requester_profile_id=profile.id)))
 order by profile.display_name limit 25;
end$$;

create or replace function internal.request_cross_club_contact_for_actor(target_leader_id uuid,reason_code text,request_text text,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare request_id uuid:=gen_random_uuid(); actor_id uuid:=auth.uid(); existing jsonb;
begin
 if not internal.actor_is_verified_adult_leader(actor_id)
 or not internal.actor_is_verified_adult_leader(target_leader_id)
 or internal.actors_share_active_club(actor_id,target_leader_id)
 or reason_code not in ('match','event','transfer','club_business','other')
 or length(coalesce(request_text,''))>160 then raise insufficient_privilege using message='not_found'; end if;
 if (select count(*) from core.contact_controls where requester_profile_id=actor_id and control_type='request' and created_at>now()-interval '24 hours')>=3
 or (select count(*) from core.contact_controls where requester_profile_id=actor_id and control_type='request' and created_at>now()-interval '30 days')>=10 then raise program_limit_exceeded using message='rate_limited'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type='message.contact.requested.v1' and internal.command_deduplication.idempotency_key=request_cross_club_contact_for_actor.idempotency_key;
 if existing is not null then return (existing->>'request_id')::uuid; end if;
 insert into core.contact_controls(id,requester_profile_id,target_profile_id,control_type,state,reason_code,request_text,expires_at) values(request_id,actor_id,target_leader_id,'request','pending',reason_code,nullif(btrim(request_text),''),now()+interval '14 days');
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'message.contact.requested.v1',jsonb_build_object('request_id',request_id));
 return request_id;
end$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815073726_s06_enforce_cross_club_boundary','greenfield',null);
