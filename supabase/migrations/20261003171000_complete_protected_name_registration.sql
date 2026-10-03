-- Let support finish a protected-name review instead of leaving the requester
-- with a resolved ticket and a manual "contact support" dead end.

alter table internal.protected_name_support_cases
  add column resolved_club_id uuid references core.clubs(id),
  add column resolved_team_id uuid references core.teams(id),
  add column resolution_kind text
    check (resolution_kind in ('created_official_club','linked_official_club'));

create function internal.approve_protected_name_support_case_for_admin(
  target_case_id uuid,
  case_resolution_note text,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  row_value internal.protected_name_support_cases%rowtype;
  protected_row internal.protected_club_names%rowtype;
  existing_result jsonb;
  target_club_id uuid;
  target_team_id uuid;
  person_id uuid;
  target_club_person_id uuid;
  target_assignment_id uuid;
  matching_clubs integer;
  next_revision bigint;
  normalized_note text:=btrim(case_resolution_note);
  slug_base text;
  club_slug text;
  case_resolution_kind text;
  capability_name text;
begin
  if actor_id is null or not internal.actor_is_support_admin() then
    raise insufficient_privilege using message='not_found';
  end if;
  if idempotency_key is null or length(normalized_note) not between 5 and 1000 then
    raise invalid_parameter_value using message='invalid_decision';
  end if;

  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id=actor_id
    and command_type='support.protected_name.approve.v1'
    and internal.command_deduplication.idempotency_key=
      approve_protected_name_support_case_for_admin.idempotency_key;
  if existing_result is not null then
    return (existing_result->>'revision')::bigint;
  end if;

  select * into row_value
  from internal.protected_name_support_cases
  where id=target_case_id
  for update;
  if row_value.id is null then
    raise invalid_parameter_value using message='not_found';
  end if;
  if row_value.revision<>expected_revision then
    raise serialization_failure using message='stale_revision';
  end if;
  if row_value.status not in ('pending','in_review') then
    raise invalid_parameter_value using message='invalid_status';
  end if;
  if not exists(
    select 1 from auth.users user_row
    where user_row.id=row_value.requester_profile_id
      and user_row.email_confirmed_at is not null
  ) then
    raise invalid_parameter_value using message='requester_unavailable';
  end if;

  select * into protected_row
  from internal.protected_club_names protected
  where protected.normalized_name=row_value.normalized_club_name
    and protected.state='active'
  for update;

  if protected_row.club_id is not null then
    target_club_id:=protected_row.club_id;
  else
    select count(*) into matching_clubs
    from core.clubs club
    where internal.normalize_club_name(club.name)=row_value.normalized_club_name
      and club.status='active';
    if matching_clubs>1 then
      raise invalid_parameter_value using message='ambiguous_club';
    end if;
    if matching_clubs=1 then
      select club.id into target_club_id
      from core.clubs club
      where internal.normalize_club_name(club.name)=row_value.normalized_club_name
        and club.status='active'
      for update;
    end if;
  end if;

  if target_club_id is not null then
    if not exists(
      select 1 from core.clubs club
      where club.id=target_club_id
        and club.status='active'
        and club.verification_status='official'
    ) then
      raise invalid_parameter_value using message='club_not_official';
    end if;
    case_resolution_kind:='linked_official_club';
  else
    target_club_id:=gen_random_uuid();
    slug_base:=trim(both '-' from regexp_replace(
      translate(lower(btrim(row_value.candidate_club_name)),'åäö','aao'),
      '[^a-z0-9]+','-','g'
    ));
    if length(slug_base)<2 then slug_base:='klubb'; end if;
    club_slug:=left(slug_base,70)||'-'||left(target_club_id::text,8);

    -- The protected-name trigger rejects an unlinked reservation. Releasing
    -- the locked row inside this transaction permits exactly this insert;
    -- rollback restores it automatically if any later step fails.
    if protected_row.normalized_name is not null then
      update internal.protected_club_names
      set state='released',revision=revision+1
      where normalized_name=row_value.normalized_club_name;
    end if;
    insert into core.clubs(id,name,slug,verification_status,created_by)
    values(
      target_club_id,btrim(row_value.candidate_club_name),club_slug,'official',
      row_value.requester_profile_id
    );
    case_resolution_kind:='created_official_club';
  end if;

  select team.id into target_team_id
  from core.teams team
  where team.club_id=target_club_id
    and lower(btrim(team.name))=lower(btrim(row_value.candidate_team_name))
    and team.status='active'
  order by team.created_at,team.id
  limit 1
  for update;
  if target_team_id is null then
    insert into core.teams(club_id,name,created_by)
    values(
      target_club_id,btrim(row_value.candidate_team_name),
      row_value.requester_profile_id
    ) returning id into target_team_id;
  end if;

  select link.club_person_id into target_club_person_id
  from core.person_account_links link
  join core.club_people club_person
    on club_person.id=link.club_person_id and club_person.club_id=link.club_id
  where link.club_id=target_club_id
    and link.profile_id=row_value.requester_profile_id
    and link.state='active'
    and club_person.status='active'
  order by link.created_at,link.id
  limit 1
  for update of link;
  if target_club_person_id is null then
    insert into core.persons(created_by)
    values(row_value.requester_profile_id)
    returning id into person_id;
    insert into core.club_people(
      club_id,person_id,display_name,created_by
    )
    select target_club_id,person_id,
      coalesce(nullif(btrim(profile.display_name),''),'Klubbadministratör'),
      row_value.requester_profile_id
    from core.profiles profile
    where profile.id=row_value.requester_profile_id
    returning id into target_club_person_id;
    insert into core.person_account_links(
      club_id,club_person_id,profile_id,state,verified_at,created_by
    ) values(
      target_club_id,target_club_person_id,row_value.requester_profile_id,
      'active',now(),actor_id
    );
  end if;

  select assignment.id into target_assignment_id
  from core.assignments assignment
  where assignment.club_id=target_club_id
    and assignment.club_person_id=target_club_person_id
    and assignment.role_package='club_functionary'
    and assignment.state='active'
  order by assignment.created_at,assignment.id
  limit 1
  for update;
  if target_assignment_id is null then
    insert into core.assignments(
      club_id,team_id,club_person_id,role_package,state,starts_at,created_by
    ) values(
      target_club_id,target_team_id,target_club_person_id,'club_functionary',
      'active',now(),actor_id
    ) returning id into target_assignment_id;
  end if;

  foreach capability_name in array array[
    'club.memberships.manage','event.manage',
    'event.attendance.correct_late','development.manage'
  ] loop
    insert into core.capability_grants(
      club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by
    ) values(
      target_club_id,target_assignment_id,capability_name,'club',target_club_id,now(),actor_id
    ) on conflict(assignment_id,capability,scope_type,scope_id) do nothing;
  end loop;

  insert into internal.protected_club_names(
    normalized_name,canonical_name,club_id,state,source,created_by
  ) values(
    row_value.normalized_club_name,btrim(row_value.candidate_club_name),
    target_club_id,'active','official_club',actor_id
  )
  on conflict(normalized_name) do update set
    canonical_name=excluded.canonical_name,
    club_id=excluded.club_id,
    state='active',
    source='official_club',
    revision=internal.protected_club_names.revision+1;

  next_revision:=row_value.revision+1;
  update internal.protected_name_support_cases set
    status='resolved',revision=next_revision,updated_at=now(),
    handled_by=actor_id,resolution_note=normalized_note,resolved_at=now(),
    resolved_club_id=target_club_id,resolved_team_id=target_team_id,
    resolution_kind=case_resolution_kind
  where id=row_value.id;

  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values(
    actor_id,idempotency_key,'support.protected_name.approve.v1',
    jsonb_build_object(
      'revision',next_revision,'club_id',target_club_id,
      'team_id',target_team_id,'resolution_kind',case_resolution_kind
    )
  );
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision,reason,metadata
  ) values(
    target_club_id,actor_id,'support.protected_name.approve.v1',
    'protected_name_support_case',row_value.id,next_revision,normalized_note,
    jsonb_build_object(
      'team_id',target_team_id,'requester_profile_id',row_value.requester_profile_id,
      'resolution_kind',case_resolution_kind
    )
  );
  return next_revision;
end
$$;

create function api.approve_protected_name_support_case(
  target_case_id uuid,
  case_resolution_note text,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language sql
security invoker
set search_path=''
as $$
  select internal.approve_protected_name_support_case_for_admin(
    target_case_id,case_resolution_note,expected_revision,idempotency_key
  )
$$;

revoke all on function
  internal.approve_protected_name_support_case_for_admin(uuid,text,bigint,uuid),
  api.approve_protected_name_support_case(uuid,text,bigint,uuid)
from public,anon,authenticated;
grant execute on function
  internal.approve_protected_name_support_case_for_admin(uuid,text,bigint,uuid),
  api.approve_protected_name_support_case(uuid,text,bigint,uuid)
to authenticated;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
)
values(
  '20261003171000_complete_protected_name_registration','greenfield',
  'Support-admin approval atomically creates or links the official club, first team, requester access and protected-name case resolution'
);

notify pgrst,'reload schema';
