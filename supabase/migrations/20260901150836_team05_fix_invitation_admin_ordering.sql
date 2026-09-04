-- TEAM-05: wrap the compound invitation projection before ordering it.

create or replace function internal.list_invitation_admin_for_actor(target_club_id uuid,target_team_id uuid)
returns table(invite_id uuid,invite_kind text,subject_name text,state text,expires_at timestamptz,revision bigint)
language plpgsql stable security definer set search_path=''
as $$ begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
    and not internal.actor_has_capability(target_club_id,target_team_id,'club.safeguarding.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 return query
 select item.invite_id,item.invite_kind,item.subject_name,item.state,item.expires_at,item.revision
 from (
   select invite.id as invite_id,'targeted'::text as invite_kind,person.display_name as subject_name,
     case when invite.state='issued' and invite.expires_at<=now() then 'expired' else invite.state end as state,
     invite.expires_at,invite.revision
   from core.roster_invites invite
   join core.club_people person on person.id=invite.club_person_id and person.club_id=invite.club_id
   where invite.club_id=target_club_id and exists(select 1 from core.team_assignments assignment
     where assignment.club_id=target_club_id and assignment.team_id=target_team_id
       and assignment.club_person_id=person.id)
   union all
   select invite.id,'guardian',guardian.display_name||' → '||child.display_name,
     case when invite.state='issued' and invite.expires_at<=now() then 'expired' else invite.state end,
     invite.expires_at,invite.revision
   from core.guardian_invites invite
   join core.club_people guardian on guardian.id=invite.guardian_person_id
   join core.club_people child on child.id=invite.child_person_id
   where invite.club_id=target_club_id and exists(select 1 from core.team_assignments assignment
     where assignment.club_id=target_club_id and assignment.team_id=target_team_id
       and assignment.club_person_id=child.id)
   union all
   select code.id,'team_code',team.name||' · '||code.requested_role,
     case when code.state='issued' and (code.expires_at<=now() or code.use_count>=code.max_uses)
       then 'expired' else code.state end,
     code.expires_at,code.revision
   from core.team_join_codes code
   join core.teams team on team.id=code.team_id
   where code.club_id=target_club_id and code.team_id=target_team_id
   union all
   select relation.id,'guardian_relation',guardian.display_name||' → '||child.display_name,
     relation.state,relation.ends_at,relation.revision
   from core.guardian_relations relation
   join core.club_people guardian on guardian.id=relation.guardian_person_id and guardian.club_id=relation.club_id
   join core.club_people child on child.id=relation.child_person_id and child.club_id=relation.club_id
   where relation.club_id=target_club_id and relation.state='active'
     and exists(select 1 from core.team_assignments assignment where assignment.club_id=target_club_id
       and assignment.team_id=target_team_id and assignment.club_person_id=child.id and assignment.state='active')
 ) as item
 order by item.expires_at desc nulls last,item.invite_id desc;
end $$;

revoke all on function internal.list_invitation_admin_for_actor(uuid,uuid)
  from public,anon,authenticated;
grant execute on function internal.list_invitation_admin_for_actor(uuid,uuid)
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260901150836_team05_fix_invitation_admin_ordering','greenfield',
  'TEAM-05 wrap compound invitation projection before ordering');

notify pgrst,'reload schema';
