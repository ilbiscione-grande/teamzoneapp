-- TEAM-05 invitation visibility/revoke, reviewed team codes and guardian ending.

create table core.team_join_codes(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  team_id uuid not null,
  token_hash bytea not null unique,
  requested_role text not null check(requested_role in ('player','leader','guardian','club_functionary')),
  state text not null default 'issued' check(state in ('issued','revoked','expired')),
  expires_at timestamptz not null,
  max_uses integer not null default 100 check(max_uses between 1 and 500),
  use_count integer not null default 0 check(use_count>=0 and use_count<=max_uses),
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  revision bigint not null default 1 check(revision>0),
  foreign key(team_id,club_id) references core.teams(id,club_id),
  check(expires_at>created_at)
);
alter table core.team_join_codes enable row level security;
create policy team_join_codes_no_direct_select on core.team_join_codes
for select to authenticated using(false);
revoke all on table core.team_join_codes from public,anon,authenticated;

create function internal.issue_team_join_code_for_actor(
  target_club_id uuid,target_team_id uuid,requested_role text,raw_token text,
  expires_at timestamptz,max_uses integer,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); code_id uuid; existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
    or not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active')
 then raise insufficient_privilege using message='not_found'; end if;
 if requested_role not in ('player','leader','guardian','club_functionary')
    or length(raw_token)<32 or expires_at<=now() or expires_at>now()+interval '90 days'
    or max_uses not between 1 and 500
 then raise invalid_parameter_value using message='invalid_input'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.team_code.issue.v1'
  and internal.command_deduplication.idempotency_key=issue_team_join_code_for_actor.idempotency_key;
 if existing is not null then return (existing->>'code_id')::uuid; end if;
 insert into core.team_join_codes(club_id,team_id,token_hash,requested_role,expires_at,max_uses,created_by)
 values(target_club_id,target_team_id,extensions.digest(raw_token,'sha256'),requested_role,expires_at,max_uses,actor_id)
 returning id into code_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.team_code.issue.v1',jsonb_build_object('code_id',code_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
 values(target_club_id,actor_id,'roster.team_code.issue.v1','team_join_code',code_id,1);
 return code_id;
end $$;

create function internal.claim_team_join_code_for_actor(raw_token text,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); code core.team_join_codes%rowtype; existing jsonb; application_id uuid;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.team_code.claim.v1'
  and internal.command_deduplication.idempotency_key=claim_team_join_code_for_actor.idempotency_key;
 if existing is not null then return (existing->>'application_id')::uuid; end if;
 select * into code from core.team_join_codes where token_hash=extensions.digest(raw_token,'sha256') for update;
 if code.id is null or code.state<>'issued' or code.expires_at<=now() or code.use_count>=code.max_uses
 then raise invalid_parameter_value using message='invalid_or_expired_token'; end if;
 if exists(select 1 from core.person_account_links where profile_id=actor_id and club_id=code.club_id and state='active')
 then raise invalid_parameter_value using message='relation_exists'; end if;
 insert into core.membership_applications(applicant_profile_id,club_id,team_id,requested_role)
 values(actor_id,code.club_id,code.team_id,code.requested_role)
 on conflict(applicant_profile_id,team_id,requested_role) where status='pending'
 do update set revision=core.membership_applications.revision+1 returning id into application_id;
 update core.team_join_codes set use_count=use_count+1,revision=revision+1 where id=code.id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.team_code.claim.v1',jsonb_build_object('application_id',application_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
 values(code.club_id,actor_id,'roster.team_code.claim.v1','membership_application',application_id,1);
 return application_id;
end $$;

create function internal.list_invitation_admin_for_actor(target_club_id uuid,target_team_id uuid)
returns table(invite_id uuid,invite_kind text,subject_name text,state text,expires_at timestamptz,revision bigint)
language plpgsql stable security definer set search_path=''
as $$ begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
    and not internal.actor_has_capability(target_club_id,target_team_id,'club.safeguarding.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 return query
 select invite.id,'targeted'::text,person.display_name,
   case when invite.state='issued' and invite.expires_at<=now() then 'expired' else invite.state end,
   invite.expires_at,invite.revision
 from core.roster_invites invite join core.club_people person on person.id=invite.club_person_id and person.club_id=invite.club_id
 where invite.club_id=target_club_id and exists(select 1 from core.team_assignments assignment
   where assignment.club_id=target_club_id and assignment.team_id=target_team_id and assignment.club_person_id=person.id)
 union all
 select invite.id,'guardian',guardian.display_name||' → '||child.display_name,
   case when invite.state='issued' and invite.expires_at<=now() then 'expired' else invite.state end,
   invite.expires_at,invite.revision
 from core.guardian_invites invite join core.club_people guardian on guardian.id=invite.guardian_person_id
 join core.club_people child on child.id=invite.child_person_id
 where invite.club_id=target_club_id and exists(select 1 from core.team_assignments assignment
   where assignment.club_id=target_club_id and assignment.team_id=target_team_id and assignment.club_person_id=child.id)
 union all
 select code.id,'team_code',team.name||' · '||code.requested_role,
   case when code.state='issued' and (code.expires_at<=now() or code.use_count>=code.max_uses) then 'expired' else code.state end,
   code.expires_at,code.revision from core.team_join_codes code join core.teams team on team.id=code.team_id
 where code.club_id=target_club_id and code.team_id=target_team_id
 union all
 select relation.id,'guardian_relation',guardian.display_name||' → '||child.display_name,
   relation.state,relation.ends_at,relation.revision
 from core.guardian_relations relation
 join core.club_people guardian on guardian.id=relation.guardian_person_id and guardian.club_id=relation.club_id
 join core.club_people child on child.id=relation.child_person_id and child.club_id=relation.club_id
 where relation.club_id=target_club_id and relation.state='active'
   and exists(select 1 from core.team_assignments assignment where assignment.club_id=target_club_id
     and assignment.team_id=target_team_id and assignment.club_person_id=child.id and assignment.state='active')
 order by expires_at desc,invite_id desc;
end $$;

create function internal.revoke_invitation_for_actor(invite_kind text,target_invite_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); target_club_id uuid; target_team_id uuid; current_state text; current_revision bigint; existing jsonb; new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.invitation.revoke.v1'
  and internal.command_deduplication.idempotency_key=revoke_invitation_for_actor.idempotency_key;
 if existing is not null then return (existing->>'revision')::bigint; end if;
 if invite_kind='team_code' then
  select club_id,team_id,state,revision into target_club_id,target_team_id,current_state,current_revision from core.team_join_codes where id=target_invite_id for update;
 elsif invite_kind='targeted' then
  select invite.club_id,assignment.team_id,invite.state,invite.revision into target_club_id,target_team_id,current_state,current_revision
  from core.roster_invites invite join lateral(select team_id from core.team_assignments where club_person_id=invite.club_person_id order by state='active' desc,starts_at desc limit 1) assignment on true where invite.id=target_invite_id for update of invite;
 elsif invite_kind='guardian' then
  select invite.club_id,assignment.team_id,invite.state,invite.revision into target_club_id,target_team_id,current_state,current_revision
  from core.guardian_invites invite join lateral(select team_id from core.team_assignments where club_person_id=invite.child_person_id order by state='active' desc,starts_at desc limit 1) assignment on true where invite.id=target_invite_id for update of invite;
 else raise invalid_parameter_value using message='invalid_kind'; end if;
 if target_club_id is null or (not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
   and not internal.actor_has_capability(target_club_id,target_team_id,'club.safeguarding.manage'))
 then raise insufficient_privilege using message='not_found'; end if;
 if current_revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
 if current_state<>'issued' then raise check_violation using message='invalid_transition'; end if;
 if invite_kind='team_code' then update core.team_join_codes set state='revoked',revision=revision+1 where id=target_invite_id returning revision into new_revision;
 elsif invite_kind='targeted' then update core.roster_invites set state='revoked',revision=revision+1 where id=target_invite_id returning revision into new_revision;
 else update core.guardian_invites set state='revoked',revision=revision+1 where id=target_invite_id returning revision into new_revision; end if;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.invitation.revoke.v1',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'roster.invitation.revoke.v1',invite_kind,target_invite_id,new_revision,jsonb_build_object('team_id',target_team_id));
 return new_revision;
end $$;

create function internal.end_guardian_relation_for_actor(target_relation_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); relation core.guardian_relations%rowtype; existing jsonb; new_revision bigint; actor_is_guardian boolean;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.guardian_relation.end.v1'
  and internal.command_deduplication.idempotency_key=end_guardian_relation_for_actor.idempotency_key;
 if existing is not null then return (existing->>'revision')::bigint; end if;
 select * into relation from core.guardian_relations where id=target_relation_id for update;
 select exists(select 1 from core.person_account_links where club_id=relation.club_id
   and club_person_id=relation.guardian_person_id and profile_id=actor_id and state='active') into actor_is_guardian;
 if relation.id is null or (not actor_is_guardian and not internal.actor_has_capability(relation.club_id,null,'club.safeguarding.manage'))
 then raise insufficient_privilege using message='not_found'; end if;
 if relation.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
 if relation.state<>'active' then raise check_violation using message='invalid_transition'; end if;
 update core.guardian_relations set state='ended',ends_at=greatest(now(),starts_at+interval '1 microsecond'),revision=revision+1
 where id=relation.id returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.guardian_relation.end.v1',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(relation.club_id,actor_id,'roster.guardian_relation.end.v1','guardian_relation',relation.id,new_revision,
  jsonb_build_object('acting_as_guardian_person_id',case when actor_is_guardian then relation.guardian_person_id else null end,'child_person_id',relation.child_person_id));
 return new_revision;
end $$;

create function api.issue_team_join_code(target_club_id uuid,target_team_id uuid,requested_role text,raw_token text,expires_at timestamptz,max_uses integer,idempotency_key uuid)
returns uuid language sql security invoker set search_path='' as $$select internal.issue_team_join_code_for_actor(target_club_id,target_team_id,requested_role,raw_token,expires_at,max_uses,idempotency_key)$$;
create function api.claim_team_join_code(raw_token text,idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$select internal.claim_team_join_code_for_actor(raw_token,idempotency_key)$$;
create function api.list_invitation_admin(target_club_id uuid,target_team_id uuid)
returns table(invite_id uuid,invite_kind text,subject_name text,state text,expires_at timestamptz,revision bigint)
language sql stable security invoker set search_path='' as $$select * from internal.list_invitation_admin_for_actor(target_club_id,target_team_id)$$;
create function api.revoke_invitation(invite_kind text,invite_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$select internal.revoke_invitation_for_actor(invite_kind,invite_id,expected_revision,idempotency_key)$$;
create function api.end_guardian_relation(relation_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path='' as $$select internal.end_guardian_relation_for_actor(relation_id,expected_revision,idempotency_key)$$;

revoke all on function internal.issue_team_join_code_for_actor(uuid,uuid,text,text,timestamptz,integer,uuid),internal.claim_team_join_code_for_actor(text,uuid),internal.list_invitation_admin_for_actor(uuid,uuid),internal.revoke_invitation_for_actor(text,uuid,bigint,uuid),internal.end_guardian_relation_for_actor(uuid,bigint,uuid) from public,anon,authenticated;
revoke all on function api.issue_team_join_code(uuid,uuid,text,text,timestamptz,integer,uuid),api.claim_team_join_code(text,uuid),api.list_invitation_admin(uuid,uuid),api.revoke_invitation(text,uuid,bigint,uuid),api.end_guardian_relation(uuid,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.issue_team_join_code_for_actor(uuid,uuid,text,text,timestamptz,integer,uuid),internal.claim_team_join_code_for_actor(text,uuid),internal.list_invitation_admin_for_actor(uuid,uuid),internal.revoke_invitation_for_actor(text,uuid,bigint,uuid),internal.end_guardian_relation_for_actor(uuid,bigint,uuid) to authenticated;
grant execute on function api.issue_team_join_code(uuid,uuid,text,text,timestamptz,integer,uuid),api.claim_team_join_code(text,uuid),api.list_invitation_admin(uuid,uuid),api.revoke_invitation(text,uuid,bigint,uuid),api.end_guardian_relation(uuid,bigint,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260826203502_team05_invite_guardian_lifecycle','greenfield','TEAM-05 reviewed team codes, invitation revoke and guardian ending');
notify pgrst,'reload schema';
