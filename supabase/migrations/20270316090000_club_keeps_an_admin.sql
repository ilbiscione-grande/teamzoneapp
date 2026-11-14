-- Varje klubb behåller minst en klubbadmin med konto.
--
-- Klubbadmin is the right Medlemmar och lag (club.memberships.manage over
-- the club). Klubbens behörigheter and the club roles already refused to
-- take it from the last holder (last_memberships_manager), but it could
-- still go by other ways: the assignment ending (leaving a team, being
-- removed), the account being unlinked or erased, or a grant given an end
-- date. A club could then be left with nobody who can add board members,
-- leaders or other admins.
--
-- Now any change that takes the right from someone is refused when the
-- club would be left without an admin who can sign in and whose right has
-- no end date. The check runs at commit, so a hand-over in one command
-- (giving the right to someone and taking it from oneself) works. The
-- error is the same last_memberships_manager, which the app already
-- explains. Asking to have one's account erased is refused up front for
-- the club's last admin. Support can let a change through in an emergency
-- with set_config('teamzone.allow_no_club_admin', 'on', true).

-- Has the club an admin who can sign in, without an end date?
create or replace function internal.club_has_admin_with_account(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from core.capability_grants grant_row
    join core.assignments assignment on assignment.id = grant_row.assignment_id
      and assignment.club_id = grant_row.club_id and assignment.state = 'active'
      and assignment.starts_at <= now() and assignment.ends_at is null
    join core.person_account_links link on link.club_person_id = assignment.club_person_id
      and link.club_id = assignment.club_id and link.state = 'active'
    where grant_row.club_id = target_club_id and grant_row.capability = 'club.memberships.manage'
      and grant_row.scope_type = 'club' and grant_row.scope_id = target_club_id
      and grant_row.starts_at <= now() and grant_row.ends_at is null)
$$;

-- Is this assignment (or any of this person's) a club admin's?
create or replace function internal.assignment_holds_club_admin(target_assignment_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from core.capability_grants grant_row
    where grant_row.assignment_id = target_assignment_id
      and grant_row.capability = 'club.memberships.manage' and grant_row.scope_type = 'club')
$$;

create or replace function internal.guard_club_keeps_admin()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  relevant boolean;
begin
  if current_setting('teamzone.allow_no_club_admin', true) = 'on' then
    return null;
  end if;
  if tg_table_name = 'capability_grants' then
    relevant := old.capability = 'club.memberships.manage' and old.scope_type = 'club';
  elsif tg_table_name = 'assignments' then
    relevant := internal.assignment_holds_club_admin(old.id);
  else
    relevant := exists (select 1 from core.assignments assignment
      where assignment.club_person_id = old.club_person_id and assignment.club_id = old.club_id
        and internal.assignment_holds_club_admin(assignment.id));
  end if;
  if relevant
    and exists (select 1 from core.clubs club where club.id = old.club_id and club.status = 'active')
    and not internal.club_has_admin_with_account(old.club_id) then
    raise check_violation using message = 'last_memberships_manager';
  end if;
  return null;
end
$$;

revoke all on function
  internal.club_has_admin_with_account(uuid),
  internal.assignment_holds_club_admin(uuid),
  internal.guard_club_keeps_admin()
from public, anon, authenticated;

drop trigger if exists capability_grants_club_keeps_admin on core.capability_grants;
create constraint trigger capability_grants_club_keeps_admin
  after update or delete on core.capability_grants
  deferrable initially deferred
  for each row execute function internal.guard_club_keeps_admin();

drop trigger if exists assignments_club_keeps_admin on core.assignments;
create constraint trigger assignments_club_keeps_admin
  after update or delete on core.assignments
  deferrable initially deferred
  for each row execute function internal.guard_club_keeps_admin();

drop trigger if exists person_account_links_club_keeps_admin on core.person_account_links;
create constraint trigger person_account_links_club_keeps_admin
  after update or delete on core.person_account_links
  deferrable initially deferred
  for each row execute function internal.guard_club_keeps_admin();

-- Asking to have one's account erased: refused up front for the last
-- admin of a club, before support has to decide.
do $patch$
declare
  def text;
  patched text;
begin
  def := pg_get_functiondef('internal.request_global_person_erasure_for_actor(text,uuid)'::regprocedure);
  patched := replace(def,
    ' insert into internal.global_person_erasure_requests(person_id,requested_by,reason)',
    ' if exists (select 1 from core.person_account_links link
   join core.assignments assignment on assignment.club_person_id = link.club_person_id
    and assignment.club_id = link.club_id and assignment.state = ''active'' and assignment.ends_at is null
   join core.capability_grants grant_row on grant_row.assignment_id = assignment.id
    and grant_row.capability = ''club.memberships.manage'' and grant_row.scope_type = ''club''
    and grant_row.starts_at <= now() and grant_row.ends_at is null
   where link.profile_id = actor_id and link.state = ''active''
    and not exists (select 1 from core.capability_grants other_grant
     join core.assignments other on other.id = other_grant.assignment_id and other.state = ''active''
      and other.starts_at <= now() and other.ends_at is null
     join core.person_account_links other_link on other_link.club_person_id = other.club_person_id
      and other_link.club_id = other.club_id and other_link.state = ''active''
     where other_grant.club_id = link.club_id and other_grant.capability = ''club.memberships.manage''
      and other_grant.scope_type = ''club'' and other_grant.starts_at <= now() and other_grant.ends_at is null
      and other_link.profile_id <> actor_id))
 then raise check_violation using message = ''last_memberships_manager''; end if;
 insert into internal.global_person_erasure_requests(person_id,requested_by,reason)');
  if patched = def then raise exception 'request_global_person_erasure_for_actor not patched'; end if;
  execute patched;
end
$patch$;

notify pgrst, 'reload schema';
