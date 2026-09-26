-- TEAM-04/08 compatibility: legacy roster people may not have a birth year.
-- jsonb_set with a SQL NULL replacement nulls the whole document, so only add
-- optional management fields when they actually exist.

create or replace function internal.get_roster_person_details_v3_for_actor(
  target_club_id uuid,
  target_team_id uuid,
  target_club_person_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  result jsonb;
  person_row core.club_people%rowtype;
begin
  result:=internal.get_roster_person_details_for_actor(
    target_club_id,
    target_team_id,
    target_club_person_id
  );
  if result ? 'person_revision' then
    select * into person_row
    from core.club_people
    where id=target_club_person_id and club_id=target_club_id;

    if person_row.birth_year is not null then
      result:=jsonb_set(
        result,
        '{management,birth_year}',
        to_jsonb(person_row.birth_year),
        true
      );
    end if;
    if person_row.birth_date is not null then
      result:=jsonb_set(
        result,
        '{management,birth_date}',
        to_jsonb(person_row.birth_date),
        true
      );
    end if;
  end if;
  return result;
end
$$;

revoke all on function internal.get_roster_person_details_v3_for_actor(
  uuid,uuid,uuid
) from public,anon,authenticated;
grant execute on function internal.get_roster_person_details_v3_for_actor(
  uuid,uuid,uuid
) to authenticated;

insert into internal.migration_provenance(
  migration_name,
  source_kind,
  source_reference
) values(
  '20260913133759_team04_null_safe_person_details',
  'greenfield',
  'TEAM-04/08 null-safe detail projection for legacy roster people'
);

notify pgrst,'reload schema';
