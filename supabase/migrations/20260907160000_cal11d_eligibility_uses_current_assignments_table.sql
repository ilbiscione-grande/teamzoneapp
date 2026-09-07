-- CAL-11 follow-up: person_eligibility_at_event's team_assignment branch
-- checked core.team_assignments, but get_event_squad_for_actor's own
-- 'roster' key (added in cal11) is built from core.assignments — a
-- different, role_package-scoped table. The two tables aren't kept in
-- sync: every row currently in core.team_assignments has a matching
-- core.assignments row, but not the reverse (confirmed against the
-- hosted DB), so anyone whose only assignment lives in core.assignments
-- shows up in the roster as an eligible, selectable person, then gets
-- rejected at save time with member_not_eligible/stale_revision —
-- surfaced to the user as a generic "kunde inte sparas" with no
-- indication why. Reported live: adding an active team leader
-- ("Coach Emilson", created via the roster/invite flow that only ever
-- wrote to core.assignments) to a squad draft always failed.
--
-- Fixed by pointing the team_assignment branch at core.assignments
-- instead, matching the same role_package filter the roster query
-- already uses (player/leader only — a guardian or club_functionary
-- row on the same person must not make them callup-eligible).

create or replace function internal.person_eligibility_at_event(target_event_id uuid,target_person_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(
  (select jsonb_build_object('kind','team_assignment','id',assignment.id,'team_id',assignment.team_id,'starts_at',assignment.starts_at,'ends_at',assignment.ends_at)
   from core.events event_row
   join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   join core.assignments assignment on assignment.club_id=event_row.club_id and assignment.team_id=relation.team_id
    and assignment.role_package in ('player','leader')
   where event_row.id=target_event_id and assignment.club_person_id=target_person_id and assignment.state='active'
    and assignment.starts_at<=event_row.starts_at and (assignment.ends_at is null or assignment.ends_at>event_row.starts_at)
   order by (relation.relation='primary') desc,assignment.starts_at desc limit 1),
  (select jsonb_build_object('kind',eligibility.kind,'id',eligibility.id,'team_id',eligibility.team_id,
    'starts_at',eligibility.starts_at,'ends_at',eligibility.ends_at,'validity_kind',eligibility.validity_kind)
   from core.events event_row
   join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   join core.play_eligibilities eligibility on eligibility.club_id=event_row.club_id and eligibility.team_id=relation.team_id
   where event_row.id=target_event_id and eligibility.club_person_id=target_person_id and eligibility.state='active'
    and eligibility.starts_at<=event_row.starts_at
    and (eligibility.ends_at is null or eligibility.ends_at>event_row.starts_at)
    and (eligibility.review_due_at is null or eligibility.review_due_at>event_row.starts_at)
   order by (relation.relation='primary') desc,eligibility.starts_at desc,eligibility.id limit 1)
 );
$$;
