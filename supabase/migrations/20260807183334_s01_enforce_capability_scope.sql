alter table core.assignments
  add constraint assignments_id_club_id_key unique (id, club_id);

alter table core.capability_grants
  drop constraint capability_grants_assignment_id_fkey,
  add constraint capability_grants_assignment_id_club_id_fkey
    foreign key (assignment_id, club_id)
    references core.assignments (id, club_id);

create function internal.enforce_capability_scope()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  assignment_team_id uuid;
begin
  select assignment.team_id
  into assignment_team_id
  from core.assignments assignment
  where assignment.id = new.assignment_id
    and assignment.club_id = new.club_id;

  if not found then
    raise foreign_key_violation using message = 'capability_assignment_scope_mismatch';
  end if;

  if new.scope_type = 'club' and new.scope_id <> new.club_id then
    raise check_violation using message = 'capability_club_scope_mismatch';
  end if;

  if new.scope_type = 'team'
     and (assignment_team_id is null or new.scope_id <> assignment_team_id) then
    raise check_violation using message = 'capability_team_scope_mismatch';
  end if;

  return new;
end;
$$;

revoke all on function internal.enforce_capability_scope()
  from public, anon, authenticated;

create trigger capability_grants_enforce_scope
before insert or update of club_id, assignment_id, scope_type, scope_id
on core.capability_grants
for each row execute function internal.enforce_capability_scope();
