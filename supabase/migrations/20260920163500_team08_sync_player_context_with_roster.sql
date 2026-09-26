-- Keep the history-preserving home-team period and the account-facing player
-- context in sync. A club person/account link is intentionally retained: it
-- identifies the person in the club, while core.assignments controls current
-- app access and system-thread participation.

create or replace function internal.sync_player_context_from_team_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  effective_end timestamptz;
begin
  if tg_op <> 'INSERT'
     and old.state = 'active'
     and (
       tg_op = 'DELETE'
       or new.state <> 'active'
       or new.club_id is distinct from old.club_id
       or new.team_id is distinct from old.team_id
       or new.club_person_id is distinct from old.club_person_id
     )
  then
    effective_end := case
      when tg_op = 'DELETE' then now()
      else coalesce(new.ends_at, now())
    end;

    update core.assignments assignment
    set state = 'ended',
        ends_at = greatest(effective_end, assignment.starts_at + interval '1 microsecond'),
        revision = assignment.revision + 1
    where assignment.club_id = old.club_id
      and assignment.team_id = old.team_id
      and assignment.club_person_id = old.club_person_id
      and assignment.role_package = 'player'
      and assignment.state = 'active';
  end if;

  if tg_op <> 'DELETE' and new.state = 'active' then
    insert into core.assignments(
      club_id,
      team_id,
      club_person_id,
      role_package,
      state,
      starts_at,
      created_by
    )
    select
      new.club_id,
      new.team_id,
      new.club_person_id,
      'player',
      'active',
      new.starts_at,
      new.created_by
    where not exists(
      select 1
      from core.assignments assignment
      where assignment.club_id = new.club_id
        and assignment.team_id = new.team_id
        and assignment.club_person_id = new.club_person_id
        and assignment.role_package = 'player'
        and assignment.state = 'active'
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$$;

revoke all on function internal.sync_player_context_from_team_assignment()
from public, anon, authenticated;

drop trigger if exists team_assignments_sync_player_context
on core.team_assignments;
create trigger team_assignments_sync_player_context
after insert or update or delete on core.team_assignments
for each row execute function internal.sync_player_context_from_team_assignment();

-- Reconcile pre-trigger data. This also closes the access leak discovered by
-- physically archiving an account-linked player during the MSG-01 join/leave
-- walkthrough.
update core.assignments assignment
set state = 'ended',
    ends_at = greatest(now(), assignment.starts_at + interval '1 microsecond'),
    revision = assignment.revision + 1
where assignment.role_package = 'player'
  and assignment.state = 'active'
  and not exists(
    select 1
    from core.team_assignments roster_assignment
    where roster_assignment.club_id = assignment.club_id
      and roster_assignment.team_id = assignment.team_id
      and roster_assignment.club_person_id = assignment.club_person_id
      and roster_assignment.state = 'active'
  );

insert into core.assignments(
  club_id,
  team_id,
  club_person_id,
  role_package,
  state,
  starts_at,
  created_by
)
select
  roster_assignment.club_id,
  roster_assignment.team_id,
  roster_assignment.club_person_id,
  'player',
  'active',
  roster_assignment.starts_at,
  roster_assignment.created_by
from core.team_assignments roster_assignment
where roster_assignment.state = 'active'
  and not exists(
    select 1
    from core.assignments assignment
    where assignment.club_id = roster_assignment.club_id
      and assignment.team_id = roster_assignment.team_id
      and assignment.club_person_id = roster_assignment.club_person_id
      and assignment.role_package = 'player'
      and assignment.state = 'active'
  );

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
) values (
  '20260920163500_team08_sync_player_context_with_roster',
  'greenfield',
  'TEAM-08/MSG-01 physical join-leave access reconciliation'
);

notify pgrst, 'reload schema';
