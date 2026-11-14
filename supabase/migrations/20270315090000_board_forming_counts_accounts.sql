-- Styrelsen bildas tills tre med mandat kan logga in.
--
-- Two approvals were needed as soon as three people held a mandate, even
-- when only one of them had an account in TeamZone, so nobody could
-- approve and a change stuck as pending (IF Eksjö Fotboll, 2026-11-14).
-- The board now counts as forming while fewer than three mandate holders
-- have an active account in the club: changes are registered at once, and
-- a change proposed before (still pending) can be applied without
-- approvals. Once three can sign in, two approvals are needed as before.

create or replace function internal.board_forming(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select count(distinct mandate.assignment_id)
    from core.board_mandates mandate
    join core.assignments assignment on assignment.id = mandate.assignment_id
      and assignment.club_id = mandate.club_id
    where mandate.club_id = target_club_id and mandate.state = 'active'
      and mandate.starts_at <= now() and mandate.ends_at > now()
      and exists (select 1 from core.person_account_links link
        where link.club_id = assignment.club_id
          and link.club_person_id = assignment.club_person_id
          and link.state = 'active')) < 3
$$;

do $patch$
declare
  def text;
  patched text;
begin
  -- A pending change may be applied without approvals while the board is
  -- forming; a rejection still stops it.
  def := pg_get_functiondef('internal.apply_board_mandate_change_for_actor(uuid,uuid)'::regprocedure);
  patched := regexp_replace(def,
    'if \(select count\(\*\) from core\.board_mandate_change_approvals approval\s+where approval\.change_id=change_row\.id and approval\.decision=''approved''\)<2 then',
    'if not internal.board_forming(change_row.club_id) and (select count(*) from core.board_mandate_change_approvals approval
   where approval.change_id=change_row.id and approval.decision=''approved'')<2 then');
  if patched = def then raise exception 'apply_board_mandate_change_for_actor not patched'; end if;
  execute patched;
end
$patch$;

notify pgrst, 'reload schema';
