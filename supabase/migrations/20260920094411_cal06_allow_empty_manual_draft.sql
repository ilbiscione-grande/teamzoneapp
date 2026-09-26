-- A leader must be able to clear an unlocked manual participant draft.
-- Automated selection modes remain non-empty and keep their stronger
-- server-side validation.
create or replace function internal.save_squad_draft_v2_for_actor(target_event_id uuid,member_ids uuid[],
 selection_source text,selection_context jsonb,expected_revision bigint,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;current_row core.squad_revisions%rowtype;
 new_id uuid;new_revision bigint;existing jsonb;matched integer;group_key text;target_count integer;
 generated_ids uuid[];dispatch_value text;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='squad.draft.saved.v2'
  and internal.command_deduplication.idempotency_key=save_squad_draft_v2_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or event_row.archived_at is not null or not internal.actor_can_manage_squad(target_event_id)
 then raise insufficient_privilege using message='not_found';end if;
 if event_row.state not in('draft','scheduled') or member_ids is null
  or cardinality(member_ids) not between 0 and 100
  or(selection_source<>'manual' and cardinality(member_ids)=0)
  or selection_source not in('manual','all','group','generator')
  or selection_context is null or jsonb_typeof(selection_context)<>'object'
  or(select count(distinct value) from unnest(member_ids)value)<>cardinality(member_ids)
 then raise invalid_parameter_value using message='invalid_input';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-squad:'||target_event_id::text,0));
 select * into current_row from core.squad_revisions where event_id=target_event_id
  and state in('draft','locked') order by revision desc limit 1 for update;
 if current_row.id is not null and(current_row.state<>'draft' or expected_revision is distinct from current_row.revision)
 then raise serialization_failure using message='stale_revision';end if;
 if current_row.id is null and expected_revision is not null
 then raise serialization_failure using message='stale_revision';end if;
 select count(*) into matched from unnest(member_ids)person_id
  where internal.person_eligibility_at_event(target_event_id,person_id) is not null;
 if matched<>cardinality(member_ids) then raise check_violation using message='member_not_eligible';end if;
 if selection_source='all' then
  if cardinality(member_ids)<>(select count(*) from core.club_people person where person.club_id=event_row.club_id
   and person.status='active' and internal.person_eligibility_at_event(target_event_id,person.id) is not null)
  then raise check_violation using message='selection_mismatch';end if;
 elsif selection_source='group' then
  group_key:=selection_context->>'eligibility_kind';
  if group_key not in('team_assignment','development','dispensation','loan','guest','cross_team')
   or exists(select 1 from unnest(member_ids)person_id
    where internal.person_eligibility_at_event(target_event_id,person_id)->>'kind'<>group_key)
   or cardinality(member_ids)<>(select count(*) from core.club_people person
    where person.club_id=event_row.club_id and person.status='active'
     and internal.person_eligibility_at_event(target_event_id,person.id)->>'kind'=group_key)
  then raise check_violation using message='selection_mismatch';end if;
 elsif selection_source='generator' then
  begin target_count:=(selection_context->>'target_count')::integer;
  exception when others then raise invalid_parameter_value using message='invalid_generator';end;
  if selection_context->>'generator'<>'balanced_v1' or target_count not between 1 and 100
   or target_count<>cardinality(member_ids)
  then raise invalid_parameter_value using message='invalid_generator';end if;
  select array_agg(candidate.id order by candidate.priority,candidate.name,candidate.id) into generated_ids
  from(select person.id,person.display_name name,
    case when internal.person_eligibility_at_event(target_event_id,person.id)->>'kind'='team_assignment' then 0 else 1 end priority
   from core.club_people person where person.club_id=event_row.club_id and person.status='active'
    and internal.person_eligibility_at_event(target_event_id,person.id) is not null
   order by priority,person.display_name,person.id limit target_count)candidate;
  if member_ids is distinct from generated_ids then raise check_violation using message='selection_mismatch';end if;
 end if;
 new_revision:=coalesce((select max(revision)+1 from core.squad_revisions where event_id=target_event_id),1);
 dispatch_value:=case when exists(select 1 from core.callups where event_id=target_event_id) then 'late' else 'initial' end;
 if current_row.id is not null then update core.squad_revisions set state='superseded' where id=current_row.id;end if;
 insert into core.squad_revisions(club_id,event_id,revision,created_by,selection_source,selection_context,dispatch_kind)
 values(event_row.club_id,target_event_id,new_revision,actor_id,selection_source,selection_context,dispatch_value)
 returning id into new_id;
 insert into core.squad_members(club_id,event_id,squad_revision_id,club_person_id,eligibility_id,
  source,eligibility_snapshot,created_by)
 select event_row.club_id,target_event_id,new_id,person_id,
  case when eligibility->>'kind'='team_assignment' then null else(eligibility->>'id')::uuid end,
  selection_source,eligibility,actor_id from(select person_id,
   internal.person_eligibility_at_event(target_event_id,person_id)eligibility from unnest(member_ids)person_id)s;
 existing:=jsonb_build_object('squad_revision_id',new_id,'revision',new_revision,
  'member_count',cardinality(member_ids),'dispatch_kind',dispatch_value,'selection_source',selection_source);
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'squad.draft.saved.v2',existing);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata) values(event_row.club_id,actor_id,'squad.draft.saved.v2','squad',new_id,
   new_revision,jsonb_build_object('source',selection_source,'context',selection_context,
    'member_count',cardinality(member_ids),'dispatch_kind',dispatch_value));
 return existing;
end;$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260920094411_cal06_allow_empty_manual_draft','greenfield','CAL-06 permit clearing an unlocked manual participant draft');

notify pgrst,'reload schema';
