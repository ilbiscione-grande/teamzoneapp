-- Shared transaction-local helpers for hosted SQL rollback tests.
-- Include after BEGIN with: \ir support/xqa_fixtures.sql

create temporary table if not exists xqa_fixture_session (
  singleton boolean primary key default true check (singleton),
  actor_profile_id uuid
) on commit drop;

create or replace function pg_temp.xqa_set_actor(profile_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', profile_id::text, true);
  insert into xqa_fixture_session(singleton,actor_profile_id)
  values(true,profile_id)
  on conflict(singleton) do update set actor_profile_id=excluded.actor_profile_id;
end$$;

create or replace function pg_temp.xqa_clear_actor()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  delete from xqa_fixture_session;
end$$;

create or replace function pg_temp.xqa_fixture_uuid(slice_number integer, entity_number integer)
returns uuid language plpgsql immutable strict as $$
begin
  if slice_number not between 0 and 99 or entity_number not between 0 and 999999999999 then
    raise exception 'xqa fixture identifier out of range';
  end if;
  return format('%s0000000-0000-4000-8000-%s',
    lpad(slice_number::text,2,'0'),lpad(entity_number::text,12,'0'))::uuid;
end$$;

