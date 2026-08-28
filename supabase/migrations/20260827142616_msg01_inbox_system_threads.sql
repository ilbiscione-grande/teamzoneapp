-- MSG-01 deterministic team/leader threads and inbox-level private invalidation.

create table core.system_thread_bindings(
 team_id uuid not null,club_id uuid not null,thread_kind text not null check(thread_kind in('team','leader')),
 thread_id uuid not null unique references core.message_threads(id) on delete cascade,
 created_at timestamptz not null default now(),revision bigint not null default 1 check(revision>0),
 primary key(team_id,thread_kind),foreign key(team_id,club_id) references core.teams(id,club_id)
);
create index system_thread_bindings_club_idx on core.system_thread_bindings(club_id,team_id,thread_kind);
alter table core.system_thread_bindings enable row level security;
create policy system_thread_bindings_no_client_access on core.system_thread_bindings
 for all to authenticated using(false) with check(false);
revoke all on table core.system_thread_bindings from public,anon,authenticated;

create function internal.sync_team_system_threads(target_team_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare team_row core.teams%rowtype;kind_value text;thread_id_value uuid;created_count integer:=0;participant_count integer:=0;
begin
 select * into team_row from core.teams where id=target_team_id for update;
 if team_row.id is null then raise no_data_found using message='team_not_found';end if;
 if team_row.status<>'active' then
  update core.thread_participants participant set state='removed',left_at=coalesce(left_at,now()),revision=revision+1
  where participant.thread_id in(select binding.thread_id from core.system_thread_bindings binding where binding.team_id=team_row.id)
   and participant.state='active';
  update core.message_threads thread set state='closed',closed_at=coalesce(closed_at,now()),revision=revision+1
  where thread.id in(select binding.thread_id from core.system_thread_bindings binding where binding.team_id=team_row.id) and thread.state='active';
  return jsonb_build_object('team_id',team_row.id,'state','closed');
 end if;
 foreach kind_value in array array['team','leader'] loop
  select binding.thread_id into thread_id_value from core.system_thread_bindings binding
   where binding.team_id=team_row.id and binding.thread_kind=kind_value;
  if thread_id_value is null then
   insert into core.message_threads(club_id,thread_type,subject,created_by)
   values(team_row.club_id,kind_value,team_row.name||case kind_value when 'leader' then ' – Ledarchatt' else ' – Lagchatt' end,team_row.created_by)
   returning id into thread_id_value;
   insert into core.thread_scopes(thread_id,club_id,team_id,scope_role)
   values(thread_id_value,team_row.club_id,team_row.id,'owner');
   insert into core.system_thread_bindings(team_id,club_id,thread_kind,thread_id)
   values(team_row.id,team_row.club_id,kind_value,thread_id_value);
   created_count:=created_count+1;
  end if;
  update core.message_threads set subject=team_row.name||case kind_value when 'leader' then ' – Ledarchatt' else ' – Lagchatt' end
  where id=thread_id_value and subject is distinct from team_row.name||case kind_value when 'leader' then ' – Ledarchatt' else ' – Lagchatt' end;
  update core.message_threads set state='active',closed_at=null where id=thread_id_value and state='closed';
  with eligible as(
   select distinct on(link.profile_id) link.profile_id,link.club_id,link.club_person_id
   from core.assignments assignment
   join core.person_account_links link on link.club_id=assignment.club_id
    and link.club_person_id=assignment.club_person_id and link.state='active'
   where assignment.team_id=team_row.id and assignment.club_id=team_row.club_id
    and assignment.state='active' and assignment.starts_at<=now()
    and(assignment.ends_at is null or assignment.ends_at>now())
    and(kind_value='team' or(assignment.role_package='leader' and exists(
     select 1 from core.capability_grants grant_row where grant_row.assignment_id=assignment.id
      and grant_row.club_id=assignment.club_id and grant_row.capability='team.roster.view'
      and grant_row.scope_type='team' and grant_row.scope_id=team_row.id
      and grant_row.starts_at<=now() and(grant_row.ends_at is null or grant_row.ends_at>now()))))
   order by link.profile_id,assignment.starts_at desc,assignment.id
  )
  insert into core.thread_participants(thread_id,profile_id,club_id,club_person_id,participant_role,state,left_at)
  select thread_id_value,eligible.profile_id,eligible.club_id,eligible.club_person_id,'member','active',null from eligible
  on conflict(thread_id,profile_id) do update set club_id=excluded.club_id,club_person_id=excluded.club_person_id,
   state='active',left_at=null,revision=core.thread_participants.revision+1;
  with eligible as(
   select distinct link.profile_id from core.assignments assignment
   join core.person_account_links link on link.club_id=assignment.club_id
    and link.club_person_id=assignment.club_person_id and link.state='active'
   where assignment.team_id=team_row.id and assignment.club_id=team_row.club_id
    and assignment.state='active' and assignment.starts_at<=now()
    and(assignment.ends_at is null or assignment.ends_at>now())
    and(kind_value='team' or(assignment.role_package='leader' and exists(
     select 1 from core.capability_grants grant_row where grant_row.assignment_id=assignment.id
      and grant_row.capability='team.roster.view' and grant_row.scope_type='team' and grant_row.scope_id=team_row.id
      and grant_row.starts_at<=now() and(grant_row.ends_at is null or grant_row.ends_at>now()))))
  )
  update core.thread_participants participant set state='removed',left_at=now(),revision=revision+1
  where participant.thread_id=thread_id_value and participant.state='active'
   and not exists(select 1 from eligible where eligible.profile_id=participant.profile_id);
  select count(*) into participant_count from core.thread_participants where thread_id=thread_id_value and state='active';
 end loop;
 return jsonb_build_object('team_id',team_row.id,'threads_created',created_count,'last_participant_count',participant_count);
end;$$;

create function internal.sync_system_threads_from_team()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform internal.sync_team_system_threads(new.id);
 return new;
end;$$;
create trigger teams_sync_system_threads after insert or update of name,status on core.teams
 for each row execute function internal.sync_system_threads_from_team();

create function internal.sync_system_threads_from_assignment()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op<>'DELETE' and new.team_id is not null then perform internal.sync_team_system_threads(new.team_id);end if;
 if tg_op<>'INSERT' and old.team_id is not null and(tg_op='DELETE' or old.team_id is distinct from new.team_id)
 then perform internal.sync_team_system_threads(old.team_id);end if;
 if tg_op='DELETE' then return old;end if;return new;
end;$$;
create trigger assignments_sync_system_threads after insert or update or delete on core.assignments
 for each row execute function internal.sync_system_threads_from_assignment();

create function internal.sync_system_threads_from_link()
returns trigger language plpgsql security definer set search_path='' as $$
declare person_id uuid:=case when tg_op='DELETE' then old.club_person_id else new.club_person_id end;
 club_id_value uuid:=case when tg_op='DELETE' then old.club_id else new.club_id end;team_id_value uuid;
begin
 for team_id_value in select distinct assignment.team_id from core.assignments assignment
  where assignment.club_id=club_id_value and assignment.club_person_id=person_id and assignment.team_id is not null
 loop perform internal.sync_team_system_threads(team_id_value);end loop;
 if tg_op='DELETE' then return old;end if;return new;
end;$$;
create trigger person_links_sync_system_threads after insert or update or delete on core.person_account_links
 for each row execute function internal.sync_system_threads_from_link();

create function internal.sync_system_threads_from_capability()
returns trigger language plpgsql security definer set search_path='' as $$
declare assignment_id_value uuid:=case when tg_op='DELETE' then old.assignment_id else new.assignment_id end;team_id_value uuid;
begin
 if(tg_op='DELETE' and old.capability='team.roster.view')
  or(tg_op='INSERT' and new.capability='team.roster.view')
  or(tg_op='UPDATE' and(old.capability='team.roster.view' or new.capability='team.roster.view')) then
  select assignment.team_id into team_id_value from core.assignments assignment where assignment.id=assignment_id_value;
  if team_id_value is not null then perform internal.sync_team_system_threads(team_id_value);end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end;$$;
create trigger capability_grants_sync_system_threads after insert or update or delete on core.capability_grants
 for each row execute function internal.sync_system_threads_from_capability();

create or replace function internal.actor_can_access_thread(target_thread_id uuid,require_send boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from core.thread_participants participant
  join core.person_account_links link on link.profile_id=participant.profile_id and link.club_id=participant.club_id
   and link.club_person_id=participant.club_person_id and link.state='active'
  join core.message_threads thread on thread.id=participant.thread_id
  where participant.thread_id=target_thread_id and participant.profile_id=auth.uid() and participant.state='active'
   and(not require_send or thread.state='active')
   and exists(select 1 from core.assignments assignment
    join core.thread_scopes scope on scope.thread_id=participant.thread_id and scope.club_id=assignment.club_id
     and(scope.team_id is null or scope.team_id=assignment.team_id)
    where assignment.club_person_id=participant.club_person_id and assignment.club_id=participant.club_id
     and assignment.state='active' and assignment.starts_at<=now() and(assignment.ends_at is null or assignment.ends_at>now()))
   and(not exists(select 1 from core.system_thread_bindings binding where binding.thread_id=thread.id and binding.thread_kind='leader')
    or exists(select 1 from core.system_thread_bindings binding where binding.thread_id=thread.id and binding.thread_kind='leader'
     and internal.actor_has_capability(binding.club_id,binding.team_id,'team.roster.view')))
   and not exists(select 1 from core.contact_controls block where block.control_type='block' and block.state='active'
    and((block.requester_profile_id=auth.uid() and block.target_profile_id in(select profile_id from core.thread_participants where thread_id=target_thread_id and state='active'))
     or(block.target_profile_id=auth.uid() and block.requester_profile_id in(select profile_id from core.thread_participants where thread_id=target_thread_id and state='active'))))
 );
$$;

create function internal.broadcast_inbox_invalidation()
returns trigger language plpgsql security definer set search_path='' as $$
declare target_thread_id uuid:=case when tg_table_name='messages' then new.thread_id else coalesce(new.thread_id,old.thread_id) end;
 participant record;
begin
 for participant in select profile_id from core.thread_participants where thread_id=target_thread_id and state='active'
 loop perform realtime.send(jsonb_build_object('thread_id',target_thread_id),'invalidate','message:inbox:'||participant.profile_id::text,true);end loop;
 return null;
end;$$;
create trigger messages_inbox_invalidation after insert on core.messages for each row execute function internal.broadcast_inbox_invalidation();
create trigger participants_inbox_invalidation after insert or update on core.thread_participants for each row execute function internal.broadcast_inbox_invalidation();
create trigger mutes_inbox_invalidation after insert or update on core.thread_mutes for each row execute function internal.broadcast_inbox_invalidation();
create policy teamzone_inbox_broadcast_select on realtime.messages for select to authenticated using(
 realtime.messages.extension='broadcast' and(select realtime.topic())='message:inbox:'||auth.uid()::text
);

select internal.sync_team_system_threads(team.id) from core.teams team where team.status='active';

revoke all on function internal.sync_team_system_threads(uuid),internal.sync_system_threads_from_team(),internal.sync_system_threads_from_assignment(),
 internal.sync_system_threads_from_link(),internal.sync_system_threads_from_capability(),internal.broadcast_inbox_invalidation()
 from public,anon,authenticated;
grant execute on function internal.sync_team_system_threads(uuid) to service_role;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827142616_msg01_inbox_system_threads','greenfield','MSG-01 deterministic system threads, relation reconciliation and private inbox invalidation');
notify pgrst,'reload schema';
