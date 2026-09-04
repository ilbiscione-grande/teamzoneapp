-- CAL-10 must be self-contained even when older CAL-07 schema drift exists.
create or replace function internal.actor_callup_response_context(
  target_callup_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
 select coalesce((
  select case
   when exists(
    select 1 from core.person_account_links link
    where link.profile_id=auth.uid()
     and link.club_id=callup.club_id
     and link.club_person_id=callup.club_person_id
     and link.state='active'
   ) then jsonb_build_object(
    'can_respond',true,'acting_as_person_id',null,'response_role','self'
   )
   when exists(
    select 1
    from core.person_account_links link
    join core.guardian_relations relation
     on relation.club_id=link.club_id
     and relation.guardian_person_id=link.club_person_id
     and relation.child_person_id=callup.club_person_id
     and relation.state='active'
     and relation.starts_at<=now()
     and (relation.ends_at is null or relation.ends_at>now())
    where link.profile_id=auth.uid()
     and link.club_id=callup.club_id
     and link.state='active'
   ) then jsonb_build_object(
    'can_respond',true,
    'acting_as_person_id',callup.club_person_id,
    'response_role','guardian'
   )
   else jsonb_build_object(
    'can_respond',false,'acting_as_person_id',null,'response_role',null
   ) end
  from core.callups callup
  where callup.id=target_callup_id
 ),jsonb_build_object(
  'can_respond',false,'acting_as_person_id',null,'response_role',null
 ))
$$;

revoke all on function internal.actor_callup_response_context(uuid)
  from public,anon,authenticated;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values (
  '20260902115000_cal10_restore_callup_response_context_dependency',
  'greenfield',
  'CAL-10 explicit CAL-07 response-context dependency repair'
);

notify pgrst,'reload schema';
