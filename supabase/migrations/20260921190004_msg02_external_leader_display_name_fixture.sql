-- Give the exact hosted cross-club test account a temporary visible name.
-- Fail closed rather than overwriting a name that the user has already set.
do $$
declare
  target_id uuid;
  changed_rows integer;
begin
  select profile.id
  into target_id
  from auth.users account
  join core.profiles profile on profile.id = account.id
  where lower(account.email) = 'coach.emilson+tzexternal@gmail.com';

  if target_id is null then
    raise exception 'msg02_external_fixture_account_missing';
  end if;

  update core.profiles
  set display_name = 'Extern ledare'
  where id = target_id
    and nullif(btrim(display_name), '') is null;

  get diagnostics changed_rows = row_count;
  if changed_rows <> 1 then
    raise exception 'msg02_external_fixture_name_was_not_blank';
  end if;
end
$$;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260921190004_msg02_external_leader_display_name_fixture',
  'greenfield',
  'MSG-02 exact hosted test account temporary display name'
);
