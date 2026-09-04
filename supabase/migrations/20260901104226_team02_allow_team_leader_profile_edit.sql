-- TEAM-02: allow a team-scoped leader to maintain that team's profile.

create or replace function internal.get_team_overview_for_actor(target_team_id uuid)
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
  can_manage:=internal.actor_has_capability(target_club_id,target_team_id,'team.roster.manage')
    or internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
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

create or replace function internal.get_team_profile_edit_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); team_row core.teams%rowtype; profile_row core.team_profiles%rowtype;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select * into team_row from core.teams team where team.id=target_team_id and team.status='active';
  if team_row.id is null or not (
    internal.actor_has_capability(team_row.club_id,team_row.id,'team.roster.manage')
    or internal.actor_has_capability(team_row.club_id,team_row.id,'club.memberships.manage')
    or internal.actor_has_capability(team_row.club_id,null,'club.memberships.manage')
  ) then raise insufficient_privilege using message='not_found'; end if;
  select * into profile_row from core.team_profiles profile where profile.team_id=team_row.id;
  return jsonb_build_object(
    'team_id',team_row.id,'team_type',profile_row.team_type,'age_class',profile_row.age_class,
    'summary',profile_row.summary,'image_url',profile_row.image_url,
    'revision',coalesce(profile_row.revision,0)
  );
end
$$;

create or replace function internal.update_team_profile_for_actor(
  target_team_id uuid,new_team_type text,new_age_class text,new_summary text,new_image_url text,
  expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); team_row core.teams%rowtype; profile_row core.team_profiles%rowtype;
  existing_result jsonb; normalized_type text:=nullif(btrim(coalesce(new_team_type,'')),'');
  normalized_age text:=nullif(btrim(coalesce(new_age_class,'')),'');
  normalized_summary text:=nullif(btrim(coalesce(new_summary,'')),'');
  normalized_image text:=nullif(btrim(coalesce(new_image_url,'')),''); new_revision bigint;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select dedupe.result into existing_result from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id and dedupe.command_type='team.profile.update.v1'
    and dedupe.idempotency_key=update_team_profile_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
  if expected_revision<0 or length(coalesce(normalized_type,''))>80 or length(coalesce(normalized_age,''))>80
    or length(coalesce(normalized_summary,''))>1000 or length(coalesce(normalized_image,''))>2048
    or (normalized_image is not null and normalized_image!~'^https://')
  then raise invalid_parameter_value using message='invalid_team_profile'; end if;
  select * into team_row from core.teams team where team.id=target_team_id and team.status='active';
  if team_row.id is null or not (
    internal.actor_has_capability(team_row.club_id,team_row.id,'team.roster.manage')
    or internal.actor_has_capability(team_row.club_id,team_row.id,'club.memberships.manage')
    or internal.actor_has_capability(team_row.club_id,null,'club.memberships.manage')
  ) then raise insufficient_privilege using message='not_found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('team-profile:'||team_row.id::text,0));
  select * into profile_row from core.team_profiles profile where profile.team_id=team_row.id for update;
  if profile_row.team_id is null then
    if expected_revision<>0 then raise serialization_failure using message='stale_revision'; end if;
    insert into core.team_profiles(team_id,team_type,age_class,summary,image_url,updated_by)
    values(team_row.id,normalized_type,normalized_age,normalized_summary,normalized_image,actor_id)
    returning revision into new_revision;
  else
    if profile_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
    update core.team_profiles set team_type=normalized_type,age_class=normalized_age,summary=normalized_summary,
      image_url=normalized_image,updated_at=now(),updated_by=actor_id,revision=revision+1
    where team_id=team_row.id returning revision into new_revision;
  end if;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'team.profile.update.v1',jsonb_build_object('team_id',team_row.id,'revision',new_revision));
  insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
  values(team_row.club_id,actor_id,'team.profile.update.v1','team',team_row.id,new_revision,
    jsonb_build_object('has_summary',normalized_summary is not null,'has_image',normalized_image is not null));
  return new_revision;
end
$$;

revoke all on function internal.get_team_overview_for_actor(uuid),
  internal.get_team_profile_edit_for_actor(uuid),
  internal.update_team_profile_for_actor(uuid,text,text,text,text,bigint,uuid)
  from public,anon,authenticated;
grant execute on function internal.get_team_overview_for_actor(uuid),
  internal.get_team_profile_edit_for_actor(uuid),
  internal.update_team_profile_for_actor(uuid,text,text,text,text,bigint,uuid)
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260901104226_team02_allow_team_leader_profile_edit','greenfield',
  'TEAM-02 team-scoped leader profile edit correction');

notify pgrst,'reload schema';
