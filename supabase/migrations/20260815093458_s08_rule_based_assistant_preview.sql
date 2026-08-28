-- S08 deterministic assistant preview. Definitions that need unresolved
-- methodology/privacy decisions remain inactive and produce no derived score.

create table core.signal_definitions (
  id uuid primary key default gen_random_uuid(),
  signal_key text not null check (signal_key ~ '^[a-z]+(\.[a-z_]+)+$'),
  version integer not null check (version > 0),
  label text not null check (length(btrim(label)) between 2 and 120),
  semantic_class text not null check (semantic_class in ('raw_fact', 'derived_indicator', 'self_report', 'medical')),
  state text not null default 'inactive' check (state in ('inactive', 'active', 'retired')),
  gate_code text,
  configuration jsonb not null default '{}'::jsonb check (jsonb_typeof(configuration) = 'object'),
  created_at timestamptz not null default now(),
  unique(signal_key, version),
  check (semantic_class = 'raw_fact' or state <> 'active'),
  check ((state = 'inactive' and gate_code is not null) or state <> 'inactive')
);

alter table core.signal_definitions enable row level security;

insert into core.signal_definitions(signal_key,version,label,semantic_class,state,gate_code) values
 ('attendance.raw_count',1,'Registrerade närvarotillfällen','raw_fact','active',null),
 ('match.goal.raw_count',1,'Registrerade mål','raw_fact','active',null),
 ('workload.watchpoint',1,'Belastningsbevakning','derived_indicator','inactive','PAR-METHOD-01'),
 ('player.self_rating',1,'Spelarens självskattning','self_report','inactive','PAR-PRIV-04'),
 ('health.clearance',1,'Medicinsk spelklarering','medical','inactive','PAR-METHOD-02');

create function internal.get_assistant_coach_preview_for_actor(target_club_id uuid,target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare attendance_count bigint; own_goals bigint; opponent_goals bigint;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'development.manage') then
   raise insufficient_privilege using message='not_found';
 end if;
 select count(*) into attendance_count
 from core.attendance_facts fact
 join core.event_teams event_team on event_team.event_id=fact.event_id and event_team.club_id=fact.club_id
 where fact.club_id=target_club_id and event_team.team_id=target_team_id;
 select count(*) filter(where fact.side='us'),count(*) filter(where fact.side='opponent')
 into own_goals,opponent_goals
 from core.match_facts fact
 join core.match_workspaces workspace on workspace.event_id=fact.event_id
 where workspace.club_id=target_club_id and workspace.team_id=target_team_id
   and fact.fact_type='goal' and fact.state='active';
 return jsonb_build_object(
   'mode','deterministic_raw_facts_v1',
   'generative_ai_enabled',false,
   'facts',jsonb_build_array(
     jsonb_build_object('key','attendance.raw_count','value',attendance_count,'unit','registrations'),
     jsonb_build_object('key','match.goal.raw_count','value',coalesce(own_goals,0),'unit','goals','side','us'),
     jsonb_build_object('key','match.goal.raw_count','value',coalesce(opponent_goals,0),'unit','goals','side','opponent')
   ),
   'blocked',jsonb_build_array(
     jsonb_build_object('gate','PAR-METHOD-01','feature','workload.watchpoint'),
     jsonb_build_object('gate','PAR-METHOD-02','feature','health_and_sanction'),
     jsonb_build_object('gate','PAR-PRIV-04','feature','player.self_rating'),
     jsonb_build_object('gate','PAR-AI-01/PAR-AI-02','feature','generative_ai')
   )
 );
end;
$$;

revoke all on function internal.get_assistant_coach_preview_for_actor(uuid,uuid) from public,anon,authenticated;
grant execute on function internal.get_assistant_coach_preview_for_actor(uuid,uuid) to authenticated;
create function api.get_assistant_coach_preview(target_club_id uuid,target_team_id uuid)
returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_assistant_coach_preview_for_actor(target_club_id,target_team_id)$$;
revoke all on function api.get_assistant_coach_preview(uuid,uuid) from public,anon;
grant execute on function api.get_assistant_coach_preview(uuid,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815093458_s08_rule_based_assistant_preview','greenfield',
  'S08 deterministic raw-fact preview; unresolved methodology/privacy/AI gates remain inactive');

notify pgrst,'reload schema';
