create function internal.ensure_club_person_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into core.persons (id, created_by)
  values (new.person_id, new.created_by)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function internal.ensure_club_person_identity()
from public, anon, authenticated;

create trigger club_people_ensure_person_identity
before insert on core.club_people
for each row execute function internal.ensure_club_person_identity();

insert into internal.migration_provenance (migration_name)
values ('20260807220425_s02_ensure_person_identity');
