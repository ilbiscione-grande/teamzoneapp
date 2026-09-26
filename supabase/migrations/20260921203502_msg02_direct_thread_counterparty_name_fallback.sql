-- MSG-02: Direct thread titles must identify the other participant. Prefer
-- the account profile name, then the participant's club-local person name.
-- Also repair the exact hosted verification account if its profile name is
-- still blank; no existing user-selected name is overwritten.
do $$
declare
  target_id uuid;
begin
  select profile.id
  into target_id
  from auth.users account
  join core.profiles profile on profile.id = account.id
  where lower(account.email) = 'coach.emilson+tzleader@gmail.com';

  if target_id is null then
    raise exception 'msg02_thomas_leader_fixture_account_missing';
  end if;

  update core.profiles
  set display_name = 'Thomas-ledare',
      updated_at = now(),
      revision = revision + 1
  where id = target_id
    and nullif(btrim(display_name), '') is null;

  if not exists (
    select 1
    from core.profiles
    where id = target_id
      and nullif(btrim(display_name), '') is not null
  ) then
    raise exception 'msg02_thomas_leader_fixture_name_remains_blank';
  end if;
end
$$;

do $$
declare
  function_definition text;
  updated_definition text;
begin
  function_definition := pg_get_functiondef(
    'internal.list_threads_for_actor(uuid[],timestamp with time zone,integer)'::regprocedure
  );

  updated_definition := replace(
    function_definition,
    'join core.profiles other_profile
            on other_profile.id = other_participant.profile_id',
    'join core.profiles other_profile
            on other_profile.id = other_participant.profile_id
          left join core.club_people other_club_person
            on other_club_person.id = other_participant.club_person_id
           and other_club_person.club_id = other_participant.club_id'
  );

  if updated_definition = function_definition then
    raise exception 'msg02_counterparty_club_person_join_patch_not_applied';
  end if;

  function_definition := updated_definition;
  updated_definition := replace(
    function_definition,
    'other_profile.display_name',
    'COALESCE(NULLIF(btrim(other_profile.display_name), ''''), NULLIF(btrim(other_club_person.display_name), ''''), ''Deltagare'')'
  );

  if updated_definition = function_definition then
    raise exception 'msg02_counterparty_name_fallback_patch_not_applied';
  end if;

  execute updated_definition;
end
$$;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260921203502_msg02_direct_thread_counterparty_name_fallback',
  'greenfield',
  'MSG-02 direct thread titles identify the counterparty with a club-person fallback'
);

notify pgrst, 'reload schema';
