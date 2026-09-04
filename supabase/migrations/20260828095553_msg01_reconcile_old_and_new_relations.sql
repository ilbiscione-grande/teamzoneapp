-- MSG-01 reconcile both sides when identity/capability relations are moved.
create or replace function internal.sync_system_threads_from_link()
returns trigger language plpgsql security definer set search_path='' as $$
declare team_ids uuid[]:='{}'::uuid[];team_id_value uuid;
begin
 if tg_op<>'INSERT' then
  select coalesce(array_agg(distinct assignment.team_id),'{}'::uuid[]) into team_ids
  from core.assignments assignment where assignment.club_id=old.club_id
   and assignment.club_person_id=old.club_person_id and assignment.team_id is not null;
 end if;
 if tg_op<>'DELETE' then
  select array(select distinct value from unnest(team_ids||coalesce(array(
   select assignment.team_id from core.assignments assignment where assignment.club_id=new.club_id
    and assignment.club_person_id=new.club_person_id and assignment.team_id is not null
  ),'{}'::uuid[]))value) into team_ids;
 end if;
 foreach team_id_value in array team_ids loop perform internal.sync_team_system_threads(team_id_value);end loop;
 if tg_op='DELETE' then return old;end if;return new;
end;$$;

create or replace function internal.sync_system_threads_from_capability()
returns trigger language plpgsql security definer set search_path='' as $$
declare assignment_ids uuid[]:='{}'::uuid[];team_ids uuid[]:='{}'::uuid[];team_id_value uuid;
begin
 if tg_op<>'INSERT' and old.capability='team.roster.view' then assignment_ids:=array_append(assignment_ids,old.assignment_id);end if;
 if tg_op<>'DELETE' and new.capability='team.roster.view' then assignment_ids:=array_append(assignment_ids,new.assignment_id);end if;
 select coalesce(array_agg(distinct assignment.team_id),'{}'::uuid[]) into team_ids from core.assignments assignment
  where assignment.id=any(assignment_ids) and assignment.team_id is not null;
 foreach team_id_value in array team_ids loop perform internal.sync_team_system_threads(team_id_value);end loop;
 if tg_op='DELETE' then return old;end if;return new;
end;$$;

revoke all on function internal.sync_system_threads_from_link(),internal.sync_system_threads_from_capability()
from public,anon,authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260828095553_msg01_reconcile_old_and_new_relations','greenfield','MSG-01 old/new relation reconciliation hardening');
