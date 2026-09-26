-- The API wrapper is security invoker. Authenticated callers therefore need
-- EXECUTE on the hardened internal command, which still validates identity,
-- active context, author role, club capability, audience and relationships.
grant execute on function internal.create_role_group_announcement_for_actor(
  uuid, text, text, text[], uuid
) to authenticated;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260922074609_msg03_grant_role_group_announcement_execution',
  'greenfield',
  'MSG-03 allow security-invoker API wrapper to reach hardened internal command'
);

notify pgrst, 'reload schema';
