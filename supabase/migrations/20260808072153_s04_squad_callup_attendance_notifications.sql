-- S04 greenfield squad/callup/attendance aggregate. Teamzone6 is not a source or target.

create table core.squad_revisions (
  id uuid primary key default gen_random_uuid(), club_id uuid not null, event_id uuid not null,
  revision bigint not null check(revision > 0), state text not null default 'draft' check(state in ('draft','locked','sent','superseded')),
  eligibility_version timestamptz not null default now(), created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id), locked_at timestamptz, sent_at timestamptz,
  unique(id,club_id), unique(event_id,revision),
  foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade,
  check((state in ('locked','sent') and locked_at is not null) or state in ('draft','superseded')),
  check((state='sent' and sent_at is not null) or state<>'sent')
);
create unique index squad_revisions_one_active_idx on core.squad_revisions(event_id) where state in ('draft','locked');

create table core.squad_members (
  id uuid primary key default gen_random_uuid(), club_id uuid not null, event_id uuid not null,
  squad_revision_id uuid not null, club_person_id uuid not null, eligibility_id uuid,
  selection_state text not null default 'selected' check(selection_state in ('selected','reserve')),
  source text not null check(source in ('manual','all','group','generator')),
  eligibility_snapshot jsonb not null, created_at timestamptz not null default now(), created_by uuid not null references core.profiles(id),
  unique(squad_revision_id,club_person_id),
  foreign key(squad_revision_id,club_id) references core.squad_revisions(id,club_id) on delete cascade,
  foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade,
  foreign key(club_person_id,club_id) references core.club_people(id,club_id),
  foreign key(eligibility_id,club_id) references core.play_eligibilities(id,club_id)
);

create table core.callups (
  id uuid primary key default gen_random_uuid(), club_id uuid not null, event_id uuid not null,
  squad_revision_id uuid not null, club_person_id uuid not null,
  state text not null default 'draft' check(state in ('draft','pending','accepted','declined','cancelled')),
  sent_at timestamptz, expires_at timestamptz, cancelled_at timestamptz,
  created_at timestamptz not null default now(), created_by uuid not null references core.profiles(id), revision bigint not null default 1 check(revision>0),
  unique(id,club_id),
  foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade,
  foreign key(squad_revision_id,club_id) references core.squad_revisions(id,club_id),
  foreign key(club_person_id,club_id) references core.club_people(id,club_id),
  check((state='draft' and sent_at is null) or (state<>'draft' and sent_at is not null)),
  check(expires_at is null or sent_at is null or expires_at>sent_at)
);
create unique index callups_one_active_person_event_idx on core.callups(event_id,club_person_id) where state<>'cancelled';

create table core.callup_response_tokens (
  id uuid primary key default gen_random_uuid(), club_id uuid not null, callup_id uuid not null,
  token_hash bytea not null unique, state text not null default 'issued' check(state in ('issued','consumed','expired','revoked')),
  expires_at timestamptz not null, consumed_at timestamptz, created_at timestamptz not null default now(),
  foreign key(callup_id,club_id) references core.callups(id,club_id) on delete cascade,
  check(expires_at>created_at), check((state='consumed' and consumed_at is not null) or state<>'consumed')
);

create table core.callup_responses (
  id uuid primary key default gen_random_uuid(), club_id uuid not null, callup_id uuid not null,
  response text not null check(response in ('accepted','declined','tentative')),
  decline_reason_code text, decline_reason_text text,
  actor_profile_id uuid not null references core.profiles(id), acting_as_person_id uuid,
  revision bigint not null check(revision>0), created_at timestamptz not null default now(),
  unique(callup_id,revision), foreign key(callup_id,club_id) references core.callups(id,club_id) on delete cascade,
  foreign key(acting_as_person_id,club_id) references core.club_people(id,club_id),
  check(response='declined' or (decline_reason_code is null and decline_reason_text is null))
);

create table core.attendance_facts (
  id uuid primary key default gen_random_uuid(), club_id uuid not null, event_id uuid not null, club_person_id uuid not null,
  status text not null default 'unknown' check(status in ('unknown','present','late','partial','absent')),
  minutes integer check(minutes between 0 and 1440), note text,
  revision bigint not null default 1 check(revision>0), recorded_at timestamptz not null default now(), recorded_by uuid not null references core.profiles(id),
  unique(id,club_id), unique(event_id,club_person_id),
  foreign key(event_id,club_id) references core.events(id,club_id) on delete cascade,
  foreign key(club_person_id,club_id) references core.club_people(id,club_id),
  check((status in ('late','partial') and minutes is not null) or (status not in ('late','partial') and minutes is null))
);
create table audit.attendance_revisions (
  id uuid primary key default gen_random_uuid(), club_id uuid not null, attendance_id uuid not null,
  event_id uuid not null, club_person_id uuid not null, status text not null, minutes integer, note text,
  revision bigint not null, actor_profile_id uuid not null references core.profiles(id), created_at timestamptz not null default now(),
  unique(attendance_id,revision), foreign key(attendance_id,club_id) references core.attendance_facts(id,club_id)
);

create table core.notification_endpoints (
  id uuid primary key default gen_random_uuid(), profile_id uuid not null references core.profiles(id),
  channel text not null check(channel in ('push','email','sms')), endpoint_hash bytea not null,
  state text not null default 'active' check(state in ('active','disabled')), created_at timestamptz not null default now(),
  unique(profile_id,channel,endpoint_hash)
);
create table core.notification_preferences (
  profile_id uuid not null references core.profiles(id), event_type text not null, channel text not null check(channel in ('push','email','sms')),
  enabled boolean not null default false, updated_at timestamptz not null default now(), primary key(profile_id,event_type,channel)
);
create table internal.notification_outbox (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references core.clubs(id),
  domain_event_id uuid not null, event_type text not null, aggregate_type text not null, aggregate_id uuid not null,
  recipient_profile_id uuid, recipient_person_id uuid not null, payload_ref jsonb not null default '{}'::jsonb,
  state text not null default 'pending' check(state in ('pending','processing','delivered','partial','failed','dead_letter','suppressed')),
  available_at timestamptz not null default now(), attempt_count integer not null default 0 check(attempt_count>=0),
  last_error_code text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(domain_event_id,recipient_person_id), foreign key(recipient_person_id,club_id) references core.club_people(id,club_id)
);
create table internal.delivery_attempts (
  id uuid primary key default gen_random_uuid(), outbox_id uuid not null references internal.notification_outbox(id) on delete cascade,
  channel text not null check(channel in ('push','email','sms')), endpoint_id uuid references core.notification_endpoints(id),
  attempt integer not null check(attempt>0), state text not null check(state in ('processing','delivered','failed','suppressed')),
  provider_ref_hash text, error_code text, started_at timestamptz not null default now(), finished_at timestamptz,
  unique(outbox_id,channel,endpoint_id,attempt)
);

create index squad_revisions_event_idx on core.squad_revisions(event_id,revision desc);
create index squad_members_person_idx on core.squad_members(club_person_id,event_id);
create index callups_person_idx on core.callups(club_person_id,event_id);
create index callup_responses_callup_idx on core.callup_responses(callup_id,revision desc);
create index attendance_event_idx on core.attendance_facts(event_id,status);
create index notification_outbox_worker_idx on internal.notification_outbox(state,available_at) where state in ('pending','failed');

create function internal.person_eligibility_at_event(target_event_id uuid,target_person_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(
    (select jsonb_build_object('kind','team_assignment','id',assignment.id,'team_id',assignment.team_id,'starts_at',assignment.starts_at,'ends_at',assignment.ends_at)
     from core.events event_row join core.team_assignments assignment on assignment.club_id=event_row.club_id and assignment.team_id=event_row.owning_team_id
     where event_row.id=target_event_id and assignment.club_person_id=target_person_id and assignment.state='active'
       and assignment.starts_at<=event_row.starts_at and (assignment.ends_at is null or assignment.ends_at>event_row.starts_at) limit 1),
    (select jsonb_build_object('kind',eligibility.kind,'id',eligibility.id,'team_id',eligibility.team_id,'starts_at',eligibility.starts_at,'ends_at',eligibility.ends_at)
     from core.events event_row join core.play_eligibilities eligibility on eligibility.club_id=event_row.club_id and eligibility.team_id=event_row.owning_team_id
     where event_row.id=target_event_id and eligibility.club_person_id=target_person_id and eligibility.state='active'
       and eligibility.starts_at<=event_row.starts_at and eligibility.ends_at>event_row.starts_at limit 1)
  );
$$;

create function internal.actor_can_manage_squad(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select internal.actor_can_manage_event(target_event_id) or exists(
    select 1 from core.events event_row where event_row.id=target_event_id
      and internal.actor_has_capability(event_row.club_id,event_row.owning_team_id,'event.squad.manage'));
$$;
create function internal.actor_can_manage_attendance(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select internal.actor_can_manage_event(target_event_id) or exists(
    select 1 from core.events event_row where event_row.id=target_event_id
      and internal.actor_has_capability(event_row.club_id,event_row.owning_team_id,'event.attendance.manage'));
$$;

create function internal.save_squad_draft_for_actor(target_event_id uuid,member_ids uuid[],selection_source text,expected_revision bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); event_row core.events%rowtype; current_row core.squad_revisions%rowtype; new_id uuid; new_revision bigint; existing jsonb; matched integer;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select * into event_row from core.events where id=target_event_id for update;
  if event_row.id is null or not internal.actor_can_manage_squad(target_event_id) then raise insufficient_privilege using message='not_found'; end if;
  if event_row.state not in ('draft','scheduled') or member_ids is null or cardinality(member_ids)=0 or cardinality(member_ids)>100
     or selection_source not in ('manual','all','group','generator')
     or (select count(distinct value) from unnest(member_ids)value)<>cardinality(member_ids)
  then raise invalid_parameter_value using message='invalid_input'; end if;
  select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type='squad.draft.saved.v1' and internal.command_deduplication.idempotency_key=save_squad_draft_for_actor.idempotency_key;
  if existing is not null then return existing; end if;
  select * into current_row from core.squad_revisions where event_id=target_event_id and state in ('draft','locked') for update;
  if current_row.id is not null and (current_row.state<>'draft' or expected_revision is distinct from current_row.revision) then raise serialization_failure using message='stale_revision'; end if;
  if current_row.id is null and expected_revision is not null then raise serialization_failure using message='stale_revision'; end if;
  select count(*) into matched from unnest(member_ids) person_id where internal.person_eligibility_at_event(target_event_id,person_id) is not null;
  if matched<>cardinality(member_ids) then raise check_violation using message='member_not_eligible'; end if;
  new_revision:=coalesce((select max(revision)+1 from core.squad_revisions where event_id=target_event_id),1);
  if current_row.id is not null then update core.squad_revisions set state='superseded' where id=current_row.id; end if;
  insert into core.squad_revisions(club_id,event_id,revision,created_by) values(event_row.club_id,target_event_id,new_revision,actor_id) returning id into new_id;
  insert into core.squad_members(club_id,event_id,squad_revision_id,club_person_id,eligibility_id,source,eligibility_snapshot,created_by)
  select event_row.club_id,target_event_id,new_id,person_id,
    case when eligibility->>'kind'='team_assignment' then null else (eligibility->>'id')::uuid end,
    selection_source,eligibility,actor_id from (select person_id,internal.person_eligibility_at_event(target_event_id,person_id) eligibility from unnest(member_ids)person_id)s;
  existing:=jsonb_build_object('squad_revision_id',new_id,'revision',new_revision,'member_count',cardinality(member_ids));
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result) values(actor_id,idempotency_key,'squad.draft.saved.v1',existing);
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata) values(event_row.club_id,actor_id,'squad.draft.saved.v1','squad',new_id,new_revision,jsonb_build_object('source',selection_source,'member_count',cardinality(member_ids)));
  return existing;
end; $$;

create function internal.lock_squad_for_actor(target_event_id uuid,expected_revision bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); squad core.squad_revisions%rowtype; existing jsonb; invalid_count integer;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_can_manage_squad(target_event_id) then raise insufficient_privilege using message='not_found'; end if;
 select * into squad from core.squad_revisions where event_id=target_event_id and state='draft' for update;
 if squad.id is null or squad.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
 select count(*) into invalid_count from core.squad_members member where member.squad_revision_id=squad.id and internal.person_eligibility_at_event(target_event_id,member.club_person_id) is null;
 if invalid_count>0 then raise check_violation using message='member_not_eligible'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type='squad.locked.v1' and internal.command_deduplication.idempotency_key=lock_squad_for_actor.idempotency_key;
 if existing is not null then return existing; end if;
 update core.squad_revisions set state='locked',locked_at=now(),eligibility_version=now() where id=squad.id;
 existing:=jsonb_build_object('squad_revision_id',squad.id,'revision',squad.revision,'state','locked');
 insert into internal.command_deduplication values(actor_id,idempotency_key,'squad.locked.v1',existing,now());
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision) values(squad.club_id,actor_id,'squad.locked.v1','squad',squad.id,squad.revision);
 return existing;
end; $$;

create function internal.send_callups_for_actor(target_squad_revision_id uuid,expiry timestamptz,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); squad core.squad_revisions%rowtype; existing jsonb; created_count integer; domain_id uuid:=gen_random_uuid();
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into squad from core.squad_revisions where id=target_squad_revision_id for update;
 if squad.id is null or not internal.actor_can_manage_squad(squad.event_id) then raise insufficient_privilege using message='not_found'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type='callup.callup.sent.v1' and internal.command_deduplication.idempotency_key=send_callups_for_actor.idempotency_key;
 if existing is not null then return existing; end if;
 if squad.state<>'locked' or expiry<=now() then raise invalid_parameter_value using message='invalid_state'; end if;
 if exists(select 1 from core.squad_members member where member.squad_revision_id=squad.id and internal.person_eligibility_at_event(squad.event_id,member.club_person_id) is null) then raise check_violation using message='member_not_eligible'; end if;
 insert into core.callups(club_id,event_id,squad_revision_id,club_person_id,state,sent_at,expires_at,created_by)
 select squad.club_id,squad.event_id,squad.id,member.club_person_id,'pending',now(),expiry,actor_id from core.squad_members member where member.squad_revision_id=squad.id and member.selection_state='selected'
 on conflict do nothing; get diagnostics created_count=row_count;
 update core.squad_revisions set state='sent',sent_at=now() where id=squad.id;
 insert into internal.notification_outbox(id,club_id,domain_event_id,event_type,aggregate_type,aggregate_id,recipient_profile_id,recipient_person_id,payload_ref)
 select gen_random_uuid(),callup.club_id,domain_id,'callup.callup.sent.v1','callup',callup.id,link.profile_id,callup.club_person_id,jsonb_build_object('callup_id',callup.id,'event_id',callup.event_id)
 from core.callups callup left join core.person_account_links link on link.club_id=callup.club_id and link.club_person_id=callup.club_person_id and link.state='active'
 where callup.squad_revision_id=squad.id on conflict do nothing;
 insert into internal.domain_outbox(id,club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload) values(domain_id,squad.club_id,'callup.callup.sent.v1','squad',squad.id,squad.revision,jsonb_build_object('count',created_count));
 existing:=jsonb_build_object('squad_revision_id',squad.id,'created_callups',created_count,'state','sent');
 insert into internal.command_deduplication values(actor_id,idempotency_key,'callup.callup.sent.v1',existing,now());
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata) values(squad.club_id,actor_id,'callup.callup.sent.v1','squad',squad.id,squad.revision,jsonb_build_object('count',created_count));
 return existing;
end; $$;

create function internal.respond_callup_for_actor(target_callup_id uuid,new_response text,acting_as_person_id uuid,decline_reason_code text,decline_reason_text text,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); callup core.callups%rowtype; actor_person uuid; new_revision bigint; existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into callup from core.callups where id=target_callup_id for update;
 if callup.id is null then raise insufficient_privilege using message='not_found'; end if;
 select link.club_person_id into actor_person from core.person_account_links link where link.profile_id=actor_id and link.club_id=callup.club_id and link.state='active';
 if actor_person=callup.club_person_id then
   if acting_as_person_id is not null then raise insufficient_privilege using message='invalid_acting_as'; end if;
 elsif acting_as_person_id=callup.club_person_id and exists(select 1 from core.guardian_relations relation where relation.club_id=callup.club_id and relation.guardian_person_id=actor_person and relation.child_person_id=callup.club_person_id and relation.state='active' and relation.starts_at<=now() and (relation.ends_at is null or relation.ends_at>now())) then null;
 else raise insufficient_privilege using message='not_found'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type='callup.response.recorded.v1' and internal.command_deduplication.idempotency_key=respond_callup_for_actor.idempotency_key;
 if existing is not null then return (existing->>'revision')::bigint; end if;
 if callup.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
 if callup.state not in ('pending','accepted','declined') or callup.expires_at<=now() or new_response not in ('accepted','declined','tentative') then raise invalid_parameter_value using message='invalid_state'; end if;
 new_revision:=callup.revision+1;
 insert into core.callup_responses(club_id,callup_id,response,decline_reason_code,decline_reason_text,actor_profile_id,acting_as_person_id,revision) values(callup.club_id,callup.id,new_response,nullif(decline_reason_code,''),nullif(decline_reason_text,''),actor_id,acting_as_person_id,new_revision);
 update core.callups set state=case when new_response='tentative' then 'pending' else new_response end,revision=new_revision where id=callup.id;
 insert into internal.command_deduplication values(actor_id,idempotency_key,'callup.response.recorded.v1',jsonb_build_object('revision',new_revision),now());
 insert into audit.command_events(club_id,actor_profile_id,acting_as_person_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata) values(callup.club_id,actor_id,acting_as_person_id,'callup.response.recorded.v1','callup',callup.id,new_revision,jsonb_build_object('response',new_response));
 return new_revision;
end; $$;

create function internal.cancel_or_remind_callup_for_actor(target_callup_id uuid,action text,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); callup core.callups%rowtype; new_revision bigint; command_name text; domain_id uuid:=gen_random_uuid(); existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into callup from core.callups where id=target_callup_id for update;
 if callup.id is null or not internal.actor_can_manage_squad(callup.event_id) then raise insufficient_privilege using message='not_found'; end if;
 if action not in ('cancel','remind') then raise invalid_parameter_value using message='invalid_input'; end if;
 command_name:=case action when 'cancel' then 'callup.callup.cancelled.v1' else 'callup.callup.reminded.v1' end;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type=command_name and internal.command_deduplication.idempotency_key=cancel_or_remind_callup_for_actor.idempotency_key;
 if existing is not null then return (existing->>'revision')::bigint; end if;
 if callup.revision<>expected_revision or callup.state='cancelled' then raise serialization_failure using message='stale_revision'; end if;
 new_revision:=callup.revision+1;
 if action='cancel' then update core.callups set state='cancelled',cancelled_at=now(),revision=new_revision where id=callup.id; else update core.callups set revision=new_revision where id=callup.id; end if;
 insert into internal.domain_outbox(id,club_id,event_type,aggregate_type,aggregate_id,aggregate_revision,payload) values(domain_id,callup.club_id,command_name,'callup',callup.id,new_revision,'{}');
 insert into internal.notification_outbox(club_id,domain_event_id,event_type,aggregate_type,aggregate_id,recipient_profile_id,recipient_person_id,payload_ref)
 select callup.club_id,domain_id,command_name,'callup',callup.id,link.profile_id,callup.club_person_id,jsonb_build_object('callup_id',callup.id,'event_id',callup.event_id) from (select 1)x left join core.person_account_links link on link.club_id=callup.club_id and link.club_person_id=callup.club_person_id and link.state='active';
 insert into internal.command_deduplication values(actor_id,idempotency_key,command_name,jsonb_build_object('revision',new_revision),now());
 return new_revision;
end; $$;

create function internal.record_attendance_for_actor(target_event_id uuid,changes jsonb,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); event_row core.events%rowtype; change jsonb; person_id uuid; old_row core.attendance_facts%rowtype; new_revision bigint; result jsonb; count_value integer:=0;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or not internal.actor_can_manage_attendance(target_event_id) then raise insufficient_privilege using message='not_found'; end if;
 if jsonb_typeof(changes)<>'array' or jsonb_array_length(changes)=0 or jsonb_array_length(changes)>100 then raise invalid_parameter_value using message='invalid_input'; end if;
 if (select count(distinct item->>'person_id') from jsonb_array_elements(changes)item)<>jsonb_array_length(changes) then raise invalid_parameter_value using message='invalid_input'; end if;
 if exists(select 1 from jsonb_array_elements(changes)item where item->>'status' not in ('unknown','present','late','partial','absent') or not exists(select 1 from core.callups callup where callup.event_id=target_event_id and callup.club_person_id=(item->>'person_id')::uuid and callup.state<>'cancelled')) then raise check_violation using message='invalid_attendance_subject'; end if;
 select dedupe.result into result from internal.command_deduplication dedupe where dedupe.actor_profile_id=actor_id and dedupe.command_type='attendance.bulk.recorded.v1' and dedupe.idempotency_key=record_attendance_for_actor.idempotency_key;
 if result is not null then return result; end if;
 for change in select * from jsonb_array_elements(changes) loop
   person_id:=(change->>'person_id')::uuid;
   select * into old_row from core.attendance_facts where event_id=target_event_id and club_person_id=person_id for update;
   new_revision:=coalesce(old_row.revision+1,1);
   insert into core.attendance_facts(club_id,event_id,club_person_id,status,minutes,note,revision,recorded_by)
   values(event_row.club_id,target_event_id,person_id,change->>'status',case when change->>'status' in ('late','partial') then (change->>'minutes')::integer end,nullif(change->>'note',''),new_revision,actor_id)
   on conflict(event_id,club_person_id) do update set status=excluded.status,minutes=excluded.minutes,note=excluded.note,revision=excluded.revision,recorded_at=now(),recorded_by=excluded.recorded_by returning * into old_row;
   insert into audit.attendance_revisions(club_id,attendance_id,event_id,club_person_id,status,minutes,note,revision,actor_profile_id) values(event_row.club_id,old_row.id,target_event_id,person_id,old_row.status,old_row.minutes,old_row.note,new_revision,actor_id);
   count_value:=count_value+1;
 end loop;
 result:=jsonb_build_object('updated',count_value);
 insert into internal.command_deduplication values(actor_id,idempotency_key,'attendance.bulk.recorded.v1',result,now());
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata) values(event_row.club_id,actor_id,'attendance.bulk.recorded.v1','event',event_row.id,event_row.revision,jsonb_build_object('updated',count_value));
 return result;
end; $$;

create function internal.get_event_squad_for_actor(target_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event_row core.events%rowtype; squad core.squad_revisions%rowtype;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into event_row from core.events where id=target_event_id;
 if event_row.id is null or not internal.actor_can_read_event(target_event_id) then raise insufficient_privilege using message='not_found'; end if;
 select * into squad from core.squad_revisions where event_id=target_event_id order by revision desc limit 1;
 return jsonb_build_object(
  'event_id',target_event_id,'squad_revision_id',squad.id,'squad_revision',squad.revision,'squad_state',coalesce(squad.state,'empty'),
  'members',coalesce((select jsonb_agg(jsonb_build_object('person_id',member.club_person_id,'name',person.display_name,'selection_state',member.selection_state,'source',member.source) order by person.display_name) from core.squad_members member join core.club_people person on person.id=member.club_person_id where member.squad_revision_id=squad.id),'[]'::jsonb),
  'callups',coalesce((select jsonb_agg(jsonb_build_object('callup_id',callup.id,'person_id',callup.club_person_id,'name',person.display_name,'state',callup.state,'revision',callup.revision,'expires_at',callup.expires_at,'delivery_state',coalesce(outbox.state,'pending')) order by person.display_name) from core.callups callup join core.club_people person on person.id=callup.club_person_id left join lateral(select state from internal.notification_outbox where aggregate_id=callup.id order by created_at desc limit 1)outbox on true where callup.event_id=target_event_id),'[]'::jsonb),
  'attendance',coalesce((select jsonb_agg(jsonb_build_object('person_id',callup.club_person_id,'name',person.display_name,'status',coalesce(attendance.status,'unknown'),'minutes',attendance.minutes,'revision',coalesce(attendance.revision,0)) order by person.display_name) from core.callups callup join core.club_people person on person.id=callup.club_person_id left join core.attendance_facts attendance on attendance.event_id=callup.event_id and attendance.club_person_id=callup.club_person_id where callup.event_id=target_event_id and callup.state<>'cancelled'),'[]'::jsonb),
  'caller_actions',case when internal.actor_can_manage_squad(target_event_id) then array['save_squad','lock_squad','send_callups','cancel_callup','remind_callup']::text[] else array[]::text[] end || case when internal.actor_can_manage_attendance(target_event_id) then array['record_attendance']::text[] else array[]::text[] end
 );
end; $$;

create function internal.claim_notification_batch(batch_size integer default 25)
returns setof internal.notification_outbox language plpgsql security definer set search_path='' as $$
begin
 if current_user not in ('postgres','service_role') then raise insufficient_privilege; end if;
 return query with claimed as (select id from internal.notification_outbox where state in ('pending','failed') and available_at<=now() and attempt_count<5 order by available_at,id for update skip locked limit greatest(1,least(batch_size,100)))
 update internal.notification_outbox outbox set state='processing',attempt_count=attempt_count+1,updated_at=now() from claimed where outbox.id=claimed.id returning outbox.*;
end; $$;
create function internal.finish_notification_attempt(target_outbox_id uuid,target_state text,error_code text default null,provider_reference text default null)
returns void language plpgsql security definer set search_path='' as $$
declare outbox internal.notification_outbox%rowtype;
begin
 if current_user not in ('postgres','service_role') then raise insufficient_privilege; end if;
 select * into outbox from internal.notification_outbox where id=target_outbox_id for update;
 if outbox.id is null or target_state not in ('delivered','failed','suppressed') then raise invalid_parameter_value; end if;
 insert into internal.delivery_attempts(outbox_id,channel,attempt,state,provider_ref_hash,error_code,finished_at) values(outbox.id,'push',outbox.attempt_count,target_state,case when provider_reference is null then null else encode(digest(provider_reference,'sha256'),'hex') end,left(error_code,80),now());
 update internal.notification_outbox set state=case when target_state='failed' and attempt_count>=5 then 'dead_letter' else target_state end,last_error_code=left(error_code,80),available_at=case when target_state='failed' then now()+make_interval(secs=>least(3600,30*(2^attempt_count)::integer)) else available_at end,updated_at=now() where id=outbox.id;
end; $$;

alter table core.squad_revisions enable row level security; alter table core.squad_members enable row level security;
alter table core.callups enable row level security; alter table core.callup_response_tokens enable row level security;
alter table core.callup_responses enable row level security; alter table core.attendance_facts enable row level security;
alter table core.notification_endpoints enable row level security; alter table core.notification_preferences enable row level security;
alter table audit.attendance_revisions enable row level security;
create policy squad_revisions_read on core.squad_revisions for select to authenticated using((select internal.actor_can_read_event(event_id)));
create policy squad_members_read on core.squad_members for select to authenticated using((select internal.actor_can_read_event(event_id)));
create policy callups_read on core.callups for select to authenticated using((select internal.actor_can_read_event(event_id)) and (internal.actor_can_manage_squad(event_id) or exists(select 1 from core.person_account_links link where link.profile_id=(select auth.uid()) and link.club_id=callups.club_id and link.club_person_id=callups.club_person_id and link.state='active')));
create policy callup_responses_read on core.callup_responses for select to authenticated using(exists(select 1 from core.callups callup where callup.id=callup_responses.callup_id and internal.actor_can_read_event(callup.event_id)));
create policy attendance_read on core.attendance_facts for select to authenticated using((select internal.actor_can_read_event(event_id)));
create policy notification_endpoints_own on core.notification_endpoints for select to authenticated using(profile_id=(select auth.uid()));
create policy notification_preferences_own on core.notification_preferences for select to authenticated using(profile_id=(select auth.uid()));
create policy attendance_revisions_read on audit.attendance_revisions for select to authenticated using((select internal.actor_can_read_event(event_id)));

revoke all on all tables in schema core,internal,audit from public,anon,authenticated;
revoke all on all sequences in schema core,internal,audit from public,anon,authenticated;
revoke all on function internal.person_eligibility_at_event(uuid,uuid),internal.actor_can_manage_squad(uuid),internal.actor_can_manage_attendance(uuid),internal.save_squad_draft_for_actor(uuid,uuid[],text,bigint,uuid),internal.lock_squad_for_actor(uuid,bigint,uuid),internal.send_callups_for_actor(uuid,timestamptz,uuid),internal.respond_callup_for_actor(uuid,text,uuid,text,text,bigint,uuid),internal.cancel_or_remind_callup_for_actor(uuid,text,bigint,uuid),internal.record_attendance_for_actor(uuid,jsonb,uuid),internal.get_event_squad_for_actor(uuid),internal.claim_notification_batch(integer),internal.finish_notification_attempt(uuid,text,text,text) from public,anon,authenticated;
grant execute on function internal.save_squad_draft_for_actor(uuid,uuid[],text,bigint,uuid),internal.lock_squad_for_actor(uuid,bigint,uuid),internal.send_callups_for_actor(uuid,timestamptz,uuid),internal.respond_callup_for_actor(uuid,text,uuid,text,text,bigint,uuid),internal.cancel_or_remind_callup_for_actor(uuid,text,bigint,uuid),internal.record_attendance_for_actor(uuid,jsonb,uuid),internal.get_event_squad_for_actor(uuid) to authenticated;
grant execute on function internal.claim_notification_batch(integer),internal.finish_notification_attempt(uuid,text,text,text) to service_role;

create function api.save_squad_draft(target_event_id uuid,member_ids uuid[],selection_source text,expected_revision bigint,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as $$select internal.save_squad_draft_for_actor(target_event_id,member_ids,selection_source,expected_revision,idempotency_key)$$;
create function api.lock_squad(target_event_id uuid,expected_revision bigint,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as $$select internal.lock_squad_for_actor(target_event_id,expected_revision,idempotency_key)$$;
create function api.send_callups(target_squad_revision_id uuid,expiry timestamptz,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as $$select internal.send_callups_for_actor(target_squad_revision_id,expiry,idempotency_key)$$;
create function api.respond_callup(target_callup_id uuid,new_response text,acting_as_person_id uuid,decline_reason_code text,decline_reason_text text,expected_revision bigint,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$select internal.respond_callup_for_actor(target_callup_id,new_response,acting_as_person_id,decline_reason_code,decline_reason_text,expected_revision,idempotency_key)$$;
create function api.manage_callup(target_callup_id uuid,action text,expected_revision bigint,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$select internal.cancel_or_remind_callup_for_actor(target_callup_id,action,expected_revision,idempotency_key)$$;
create function api.record_attendance(target_event_id uuid,changes jsonb,idempotency_key uuid) returns jsonb language sql security invoker set search_path='' as $$select internal.record_attendance_for_actor(target_event_id,changes,idempotency_key)$$;
create function api.get_event_squad(target_event_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select internal.get_event_squad_for_actor(target_event_id)$$;
revoke all on function api.save_squad_draft(uuid,uuid[],text,bigint,uuid),api.lock_squad(uuid,bigint,uuid),api.send_callups(uuid,timestamptz,uuid),api.respond_callup(uuid,text,uuid,text,text,bigint,uuid),api.manage_callup(uuid,text,bigint,uuid),api.record_attendance(uuid,jsonb,uuid),api.get_event_squad(uuid) from public,anon;
grant execute on function api.save_squad_draft(uuid,uuid[],text,bigint,uuid),api.lock_squad(uuid,bigint,uuid),api.send_callups(uuid,timestamptz,uuid),api.respond_callup(uuid,text,uuid,text,text,bigint,uuid),api.manage_callup(uuid,text,bigint,uuid),api.record_attendance(uuid,jsonb,uuid),api.get_event_squad(uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808072153_s04_squad_callup_attendance_notifications','greenfield',null);
notify pgrst,'reload schema';
