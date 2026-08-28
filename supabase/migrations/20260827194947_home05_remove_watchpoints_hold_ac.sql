-- HOME-05: retire Watchpoints and hold Assistant Coach behind the future AC-01 data gate.

update core.signal_definitions set signal_key='workload.future_review',label='Belastningsanalys (senare)',
 state='inactive',gate_code='AC-01'where signal_key='workload.watchpoint';
update core.signal_definitions set state='inactive',gate_code=coalesce(gate_code,'AC-01')
where semantic_class in('derived_indicator','self_report','medical');

drop function if exists api.get_assistant_coach_preview(uuid,uuid);
drop function if exists internal.get_assistant_coach_preview_for_actor(uuid,uuid);

create table internal.assistant_activation_gate(
 gate_key text primary key check(gate_key='AC-01'),state text not null check(state in('blocked','ready')),
 generative_ai_enabled boolean not null default false check(not generative_ai_enabled),
 workload_enabled boolean not null default false check(not workload_enabled),
 medical_enabled boolean not null default false check(not medical_enabled),
 reason text not null,updated_at timestamptz not null default now(),revision bigint not null default 1 check(revision>0)
);
insert into internal.assistant_activation_gate(gate_key,state,reason)
values('AC-01','blocked','Datakvalitet, ägande, freshness och rollbehörighet är ännu inte verifierade.');
alter table internal.assistant_activation_gate enable row level security;
revoke all on table internal.assistant_activation_gate from public,anon,authenticated;

-- Defense in depth: legacy or prematurely emitted items cannot enter delivery or the center.
update internal.notification_outbox set state='suppressed',recipient_profile_id=null,last_error_code='feature_retired',updated_at=now()
where state in('pending','failed')and(lower(event_type)like'%watchpoint%'or lower(event_type)like'%assistant%'
 or lower(event_type)like'%assistant_coach%'or lower(event_type)like'%ac_signal%');

create function internal.reject_retired_attention_events()
returns trigger language plpgsql security definer set search_path=''as $$
begin
 if lower(new.event_type)like'%watchpoint%'or lower(new.event_type)like'%assistant%'
  or lower(new.event_type)like'%assistant_coach%'or lower(new.event_type)like'%ac_signal%'
 then new.state:='suppressed';new.recipient_profile_id:=null;new.last_error_code:='feature_retired';end if;
 return new;
end$$;
create trigger notification_outbox_reject_retired_attention before insert or update of event_type
on internal.notification_outbox for each row execute function internal.reject_retired_attention_events();
revoke all on function internal.reject_retired_attention_events()from public,anon,authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827194947_home05_remove_watchpoints_hold_ac','greenfield','HOME-05 deterministic tasks remain; legacy Watchpoints retired; AC held for AC-01');
notify pgrst,'reload schema';
