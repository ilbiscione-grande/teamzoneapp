-- A player's assignment never automatically received `team.roster.view`.
-- Leaders get it via assignments_materialize_leader_capabilities and
-- guardians get it via internal.ensure_guardian_context_for_relation; the
-- approved role contract (REL02-RD-06/09, 2026-08-31) requires the same
-- limited, read-only team list for players too, but that was only ever
-- granted as one-off manual rows for that day's specific test fixtures —
-- any player assignment created since (directly, via TEAM-04 dedupe/birth-
-- date fixtures, TEAM-06 representation, TEAM-07 moves or TEAM-08 erasure
-- recreation) never got it, physically reproduced 2026-09-26 as "Truppen
-- är inte tillgänglig" for a real player account. Only the read-only
-- capability is granted — never team.roster.manage.

create or replace function internal.materialize_player_roster_view_from_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role_package = 'player'
     and new.team_id is not null
     and new.state = 'active'
     and new.starts_at <= now()
     and (new.ends_at is null or new.ends_at > now())
  then
    insert into core.capability_grants(
      club_id,
      assignment_id,
      capability,
      scope_type,
      scope_id,
      starts_at,
      ends_at,
      created_by
    ) values (
      new.club_id,
      new.id,
      'team.roster.view',
      'team',
      new.team_id,
      greatest(new.starts_at, now()),
      new.ends_at,
      new.created_by
    )
    on conflict(assignment_id, capability, scope_type, scope_id) do nothing;
  end if;
  return new;
end
$$;

revoke all on function internal.materialize_player_roster_view_from_assignment()
from public, anon, authenticated;

drop trigger if exists assignments_materialize_player_roster_view
on core.assignments;
create trigger assignments_materialize_player_roster_view
after insert or update of role_package, state, team_id, starts_at, ends_at
on core.assignments
for each row execute function internal.materialize_player_roster_view_from_assignment();

-- Reconcile already-active player assignments that predate this trigger.
-- Existing explicit grants and explicit revocations are retained: only
-- entirely missing rows are inserted.
insert into core.capability_grants(
  club_id,
  assignment_id,
  capability,
  scope_type,
  scope_id,
  starts_at,
  ends_at,
  created_by
)
select
  assignment.club_id,
  assignment.id,
  'team.roster.view',
  'team',
  assignment.team_id,
  greatest(assignment.starts_at, now()),
  assignment.ends_at,
  assignment.created_by
from core.assignments assignment
where assignment.role_package = 'player'
  and assignment.team_id is not null
  and assignment.state = 'active'
  and assignment.starts_at <= now()
  and (assignment.ends_at is null or assignment.ends_at > now())
on conflict(assignment_id, capability, scope_type, scope_id) do nothing;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
) values (
  '20260926190000_team03_materialize_player_roster_view_capability',
  'greenfield',
  'TEAM-03 physical verification: player role could not open Trupp ("Truppen är inte tillgänglig")'
);

notify pgrst, 'reload schema';
