-- Ledargrupper: the groups page says whether the viewer is in each group,
-- so "Öppna chatten" shows only to members (the chat lets members only).

do $patch$
declare
  def text;
  patched text;
begin
  def := pg_get_functiondef('internal.list_leader_groups_for_actor(uuid)'::regprocedure);
  patched := replace(def,
    '''member_count'', (select count(*) from internal.leader_group_member_people(group_row.id)),',
    '''member_count'', (select count(*) from internal.leader_group_member_people(group_row.id)),
        ''is_member'', exists (select 1 from internal.leader_group_member_people(group_row.id) member
          join core.person_account_links link on link.club_person_id = member.club_person_id
            and link.club_id = group_row.club_id and link.profile_id = auth.uid() and link.state = ''active''),');
  if patched = def then raise exception 'list_leader_groups_for_actor not patched'; end if;
  execute patched;
end
$patch$;
