-- TEAM-02 private role-aware team overview projection.

create table core.team_profiles (
  team_id uuid primary key references core.teams(id) on delete cascade,
  summary text check (summary is null or length(btrim(summary)) between 1 and 1000),
  team_type text check (team_type is null or length(btrim(team_type)) between 1 and 80),
  age_class text check (age_class is null or length(btrim(age_class)) between 1 and 80),
  image_url text check (image_url is null or image_url ~ '^https://'),
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0)
);
alter table core.team_profiles enable row level security;
revoke all on table core.team_profiles from public,anon,authenticated;

create function internal.get_team_overview_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); target_club_id uuid; can_manage boolean; result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select team.club_id into target_club_id from core.teams team
    where team.id=target_team_id and team.status='active';
  if target_club_id is null or not internal.actor_has_club_access(target_club_id) then
    raise insufficient_privilege using message='not_found';
  end if;
  can_manage:=internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
    or internal.actor_has_capability(target_club_id,null,'club.memberships.manage');
  select jsonb_build_object(
    'team_id',team.id,'club_id',team.club_id,'team_name',team.name,'club_name',club.name,
    'team_type',profile.team_type,'age_class',profile.age_class,'summary',profile.summary,
    'image_url',profile.image_url,'can_manage',can_manage,
    'leaders',coalesce((select jsonb_agg(jsonb_build_object(
      'person_id',person.id,'display_name',person.display_name
    ) order by person.display_name,person.id)
      from core.assignments assignment
      join core.club_people person on person.id=assignment.club_person_id
        and person.club_id=assignment.club_id and person.status='active'
      where assignment.club_id=team.club_id and assignment.team_id=team.id
        and assignment.role_package='leader' and assignment.state='active'
        and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now())
    ),'[]'::jsonb),
    'member_count',(select count(*) from core.assignments assignment
      where assignment.club_id=team.club_id and assignment.team_id=team.id
        and assignment.state='active' and assignment.starts_at<=now()
        and (assignment.ends_at is null or assignment.ends_at>now())),
    'active_invitation_count',case when can_manage then (select count(*)
      from core.roster_invites invite
      where invite.club_id=team.club_id and invite.state='issued' and invite.expires_at>now()
        and exists(select 1 from core.assignments assignment
          where assignment.club_id=team.club_id and assignment.team_id=team.id
            and assignment.club_person_id=invite.club_person_id and assignment.state in ('pending','active'))
    ) else 0 end,
    'pending_application_count',case when can_manage then (select count(*)
      from core.membership_applications application
      where application.club_id=team.club_id and application.team_id=team.id
        and application.status='pending') else 0 end
  ) into result
  from core.teams team
  join core.clubs club on club.id=team.club_id
  left join core.team_profiles profile on profile.team_id=team.id
  where team.id=target_team_id and team.club_id=target_club_id;
  return result;
end
$$;

create function api.get_team_overview(target_team_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.get_team_overview_for_actor(target_team_id)$$;

revoke all on function internal.get_team_overview_for_actor(uuid),
  api.get_team_overview(uuid) from public,anon,authenticated;
grant execute on function internal.get_team_overview_for_actor(uuid),
  api.get_team_overview(uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260824151510_team02_role_based_overview','greenfield','TEAM-02 private role-aware team overview projection');
