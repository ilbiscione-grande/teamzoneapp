-- Approved planning rule: future scheduled events within 48 hours, with no
-- callup ever issued. Extends ordinary leader tasks, not the gated AC queue.
alter table core.events add column callups_required boolean not null default true;
comment on column core.events.callups_required is
  'Whether this occurrence needs callups. False suppresses the missing-callups planning task; it does not cancel or prohibit callups.';

do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('internal.event_snapshot(core.events)'::regprocedure);
  patched := replace(definition, '''state'', target_event.state,',
    '''state'', target_event.state, ''callups_required'', target_event.callups_required,');
  if patched = definition then raise exception 'event snapshot contract changed'; end if;
  execute patched;

  -- Reuse the revisioned, idempotent, audited event edit command. V3 passes
  -- this base field through to V2; omitted values preserve each occurrence.
  definition := pg_get_functiondef('internal.revise_event_v2_for_actor(uuid,text,jsonb,bigint,uuid)'::regprocedure);
  patched := replace(definition, '''location_name'',''audience_types''))',
    '''location_name'',''audience_types'',''callups_required''))
  or(patch?''callups_required'' and jsonb_typeof(patch->''callups_required'') is distinct from ''boolean'')');
  if patched = definition then raise exception 'event edit validation contract changed'; end if;
  definition := patched;
  patched := replace(definition, 'starts_at=new_start,ends_at=new_end,',
    'starts_at=new_start,ends_at=new_end,
   callups_required=case when patch?''callups_required'' then (patch->>''callups_required'')::boolean else callups_required end,');
  if patched = definition then raise exception 'event edit update contract changed'; end if;
  execute patched;

  definition := pg_get_functiondef('internal.get_leader_home_for_actor(uuid)'::regprocedure);
  patched := replace(definition, 'group by callup.event_id having count(*)>0)task)',
    'group by callup.event_id having count(*)>0
   union all
   select ''missing_callups'',3,''Kallelser har inte skickats'',1,
     ''/calendar?event=''||event_row.id::text
   from core.events event_row
   where can_manage_squad and event_row.club_id=context_row.club_id
     and event_row.owning_team_id=context_row.team_id
     and event_row.state=''scheduled'' and event_row.archived_at is null
     and event_row.callups_required
     and event_row.starts_at>observed_at
     and event_row.starts_at<=observed_at+interval ''48 hours''
     and not exists(select 1 from core.callups issued
       where issued.event_id=event_row.id and issued.club_id=event_row.club_id)
   )task)');
  if patched = definition then raise exception 'leader tasks contract changed'; end if;
  execute patched;
end;
$migration$;

-- Existing events_owner_time_idx bounds the 48-hour scan; the existing
-- callups_event_club_idx covers NOT EXISTS, including cancelled callups.
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261002121840_assistant_missing_callups.sql','greenfield',
  'Approved 48-hour planning task and explicit per-occurrence callup requirement');
notify pgrst,'reload schema';
