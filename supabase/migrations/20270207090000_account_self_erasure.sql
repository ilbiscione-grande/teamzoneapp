-- Ending one's own account from Webtools (plan item 9, 2026-11-03), for
-- the accounts Tacticsboard is sold to: not linked to a club in TeamZone.
-- A club-linked account keeps the reviewed erasure (TEAM-08), since club
-- records need the club's decisions.
--
-- The account-deletion Edge function calls this twice: first as a dry run,
-- which does everything and rolls it back, so Stripe is only cancelled when
-- the erasure will go through; then for real, before it deletes the Auth
-- user. Receipts stay with Stripe, as bookkeeping requires.

create function internal.erase_own_account_for_server(target_profile_id uuid, dry_run boolean)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from core.profiles where id = target_profile_id) then
    return 'ok';  -- already erased: the Auth user may still need deleting
  end if;
  if exists (select 1 from core.person_account_links where profile_id = target_profile_id) then
    return 'club_linked';
  end if;
  begin
    -- Tacticsboard: what the person made goes, with what hangs on it
    -- (versions, links, live lessons, folders, the library and its picks).
    delete from core.tactics_live_sessions where host_id = target_profile_id;
    delete from core.tactics_share_links where created_by = target_profile_id;
    delete from core.tactics_folder_share_links where created_by = target_profile_id;
    delete from core.tactics_shared_items where owner_id = target_profile_id;
    delete from core.tactics_library_items where owner_id = target_profile_id;
    delete from core.tactics_projects where owner_id = target_profile_id;
    delete from core.tactics_folders where owner_id = target_profile_id;
    delete from core.tactics_templates where owner_id = target_profile_id;
    -- The audit keeps what happened, no longer who did it.
    update audit.command_events set actor_profile_id = null where actor_profile_id = target_profile_id;
    delete from internal.command_deduplication where actor_profile_id = target_profile_id;
    -- Billing, legal acceptances and preferences follow by cascade.
    delete from core.profiles where id = target_profile_id;
    if dry_run then raise exception using errcode = 'P0001', message = 'dry_run_ok'; end if;
  exception
    when foreign_key_violation then return 'needs_support';
    when raise_exception then
      if sqlerrm = 'dry_run_ok' then return 'ok'; end if;
      raise;
  end;
  insert into audit.command_events (command_type, aggregate_type, metadata)
  values ('account.self_erased.v1', 'profile', '{}'::jsonb);
  return 'ok';
end;
$$;

create function api.erase_own_account(target_profile_id uuid, dry_run boolean) returns text
language sql security invoker set search_path = '' as
$$ select internal.erase_own_account_for_server(target_profile_id, dry_run) $$;

revoke all on function internal.erase_own_account_for_server(uuid, boolean), api.erase_own_account(uuid, boolean)
  from public, anon, authenticated;
grant execute on function internal.erase_own_account_for_server(uuid, boolean), api.erase_own_account(uuid, boolean)
  to service_role;
notify pgrst, 'reload schema';
