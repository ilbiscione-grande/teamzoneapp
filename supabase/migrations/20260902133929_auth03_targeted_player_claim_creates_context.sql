-- A targeted player invite links an account to an existing roster person.
-- Ensure that the linked player also receives the app context required to
-- leave the waiting room.

create function internal.ensure_player_contexts_for_person(
  target_club_person_id uuid
)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  actor_id uuid:=auth.uid();
  roster_row record;
  new_assignment_id uuid;
  inserted_count integer:=0;
begin
  if actor_id is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  if not exists(
    select 1
    from core.person_account_links link
    where link.profile_id=actor_id
      and link.club_person_id=target_club_person_id
      and link.state='active'
  ) then
    raise insufficient_privilege using message='not_found';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(target_club_person_id::text||':player-context',0)
  );

  for roster_row in
    select roster.club_id,roster.team_id,roster.starts_at,
      coalesce(roster.created_by,actor_id) as created_by
    from core.team_assignments roster
    where roster.club_person_id=target_club_person_id
      and roster.state='active'
      and roster.starts_at<=now()
      and (roster.ends_at is null or roster.ends_at>now())
  loop
    if not exists(
      select 1
      from core.assignments assignment
      where assignment.club_id=roster_row.club_id
        and assignment.team_id=roster_row.team_id
        and assignment.club_person_id=target_club_person_id
        and assignment.role_package='player'
        and assignment.state='active'
        and assignment.starts_at<=now()
        and (assignment.ends_at is null or assignment.ends_at>now())
    ) then
      insert into core.assignments(
        club_id,team_id,club_person_id,role_package,state,starts_at,created_by
      ) values (
        roster_row.club_id,roster_row.team_id,target_club_person_id,
        'player','active',least(roster_row.starts_at,now()),roster_row.created_by
      ) returning id into new_assignment_id;

      insert into audit.command_events(
        club_id,actor_profile_id,command_type,aggregate_type,
        aggregate_id,aggregate_revision,metadata
      ) values (
        roster_row.club_id,actor_id,'roster.player_context.ensure.v1',
        'assignment',new_assignment_id,1,
        jsonb_build_object('club_person_id',target_club_person_id,
          'team_id',roster_row.team_id)
      );
      inserted_count:=inserted_count+1;
    end if;
  end loop;
  return inserted_count;
end;
$$;

alter function internal.claim_roster_invitation_v2(text,uuid)
  rename to claim_roster_invitation_link_only_v2;

create function internal.claim_roster_invitation_v2(
  raw_token text,
  idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  result:=internal.claim_roster_invitation_link_only_v2(
    raw_token,idempotency_key
  );
  if result->>'status'='claimed' and result ? 'club_person_id' then
    perform internal.ensure_player_contexts_for_person(
      (result->>'club_person_id')::uuid
    );
  end if;
  return result;
end;
$$;

revoke all on function
  internal.ensure_player_contexts_for_person(uuid),
  internal.claim_roster_invitation_link_only_v2(text,uuid),
  internal.claim_roster_invitation_v2(text,uuid)
  from public,anon,authenticated;
grant execute on function internal.claim_roster_invitation_v2(text,uuid)
  to authenticated;

-- Repair already claimed active player links that exhibit the same invariant
-- violation. This is intentionally constrained to active roster assignments.
do $$
declare
  target record;
begin
  for target in
    select distinct link.profile_id,link.club_person_id
    from core.person_account_links link
    join core.team_assignments roster
      on roster.club_id=link.club_id
     and roster.club_person_id=link.club_person_id
     and roster.state='active'
     and roster.starts_at<=now()
     and (roster.ends_at is null or roster.ends_at>now())
    where link.state='active'
      and not exists(
        select 1 from core.assignments assignment
        where assignment.club_id=roster.club_id
          and assignment.team_id=roster.team_id
          and assignment.club_person_id=roster.club_person_id
          and assignment.role_package='player'
          and assignment.state='active'
          and assignment.starts_at<=now()
          and (assignment.ends_at is null or assignment.ends_at>now())
      )
  loop
    perform set_config('request.jwt.claim.sub',target.profile_id::text,true);
    perform internal.ensure_player_contexts_for_person(target.club_person_id);
  end loop;
end;
$$;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
) values (
  '20260902133929_auth03_targeted_player_claim_creates_context',
  'greenfield',
  'AUTH-03 targeted player claim creates active player context'
);

notify pgrst,'reload schema';
