-- TEAM-02 private team-image upload. Originals remain private and are never
-- reused as the later public-club-site variant without a separate media gate.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'team-profile-images','team-profile-images',false,5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict(id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

create table core.team_profile_images (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id) on delete cascade,
  team_id uuid not null references core.teams(id) on delete cascade,
  bucket_id text not null default 'team-profile-images'
    check(bucket_id='team-profile-images'),
  object_key text not null unique,
  mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp')),
  size_bytes bigint not null check(size_bytes between 1 and 5242880),
  state text not null default 'staged'
    check(state in ('staged','active','replaced','removed')),
  uploaded_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '30 minutes',
  activated_at timestamptz,
  retired_at timestamptz,
  revision bigint not null default 1 check(revision>0),
  constraint team_profile_images_team_club_fk
    foreign key(team_id,club_id) references core.teams(id,club_id)
);

alter table core.team_profile_images enable row level security;
revoke all on table core.team_profile_images from public,anon,authenticated;

alter table core.team_profiles
  add column image_asset_id uuid references core.team_profile_images(id);

create function internal.actor_can_upload_team_profile_image(
  target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(
    select 1
    from core.team_profile_images image
    where image.bucket_id=target_bucket
      and image.object_key=target_key
      and image.state='staged'
      and image.expires_at>now()
      and image.uploaded_by=auth.uid()
      and (
        internal.actor_has_capability(image.club_id,image.team_id,'team.roster.manage')
        or internal.actor_has_capability(image.club_id,image.team_id,'club.memberships.manage')
        or internal.actor_has_capability(image.club_id,null,'club.memberships.manage')
      )
  )
$$;

revoke all on function internal.actor_can_upload_team_profile_image(text,text)
  from public,anon,authenticated;
grant execute on function internal.actor_can_upload_team_profile_image(text,text)
  to authenticated;

create policy team_profile_images_insert on storage.objects
for insert to authenticated
with check(
  bucket_id='team-profile-images'
  and internal.actor_can_upload_team_profile_image(bucket_id,name)
);

create function internal.stage_team_profile_image_for_actor(
  target_team_id uuid,target_mime_type text,target_size_bytes bigint,
  idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid:=auth.uid(); team_row core.teams%rowtype;
  image_id uuid; object_key text; existing_result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select dedupe.result into existing_result
  from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id
    and dedupe.command_type='team.profile.image.stage.v1'
    and dedupe.idempotency_key=stage_team_profile_image_for_actor.idempotency_key;
  if existing_result is not null then return existing_result; end if;
  if target_mime_type not in ('image/jpeg','image/png','image/webp')
    or target_size_bytes not between 1 and 5242880
  then raise invalid_parameter_value using message='invalid_team_image'; end if;
  select * into team_row from core.teams team
  where team.id=target_team_id and team.status='active';
  if team_row.id is null or not (
    internal.actor_has_capability(team_row.club_id,team_row.id,'team.roster.manage')
    or internal.actor_has_capability(team_row.club_id,team_row.id,'club.memberships.manage')
    or internal.actor_has_capability(team_row.club_id,null,'club.memberships.manage')
  ) then raise insufficient_privilege using message='not_found'; end if;
  image_id:=gen_random_uuid();
  object_key:=team_row.id::text||'/'||image_id::text||'.upload';
  insert into core.team_profile_images(
    id,club_id,team_id,object_key,mime_type,size_bytes,uploaded_by
  ) values(
    image_id,team_row.club_id,team_row.id,object_key,target_mime_type,
    target_size_bytes,actor_id
  );
  existing_result:=jsonb_build_object(
    'image_id',image_id,'bucket_id','team-profile-images',
    'object_key',object_key,'expires_at',now()+interval '30 minutes'
  );
  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values(actor_id,idempotency_key,'team.profile.image.stage.v1',existing_result);
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision,metadata
  ) values(
    team_row.club_id,actor_id,'team.profile.image.stage.v1','team',team_row.id,
    0,jsonb_build_object('image_id',image_id,'mime_type',target_mime_type,
      'size_bytes',target_size_bytes)
  );
  return existing_result;
end
$$;

create function internal.update_team_profile_v2_for_actor(
  target_team_id uuid,new_team_type text,new_age_class text,new_summary text,
  image_action text,staged_image_id uuid,expected_revision bigint,
  idempotency_key uuid)
returns bigint language plpgsql security definer set search_path=''
as $$
declare
  actor_id uuid:=auth.uid(); team_row core.teams%rowtype;
  profile_row core.team_profiles%rowtype; image_row core.team_profile_images%rowtype;
  existing_result jsonb; normalized_type text:=nullif(btrim(coalesce(new_team_type,'')),'');
  normalized_age text:=nullif(btrim(coalesce(new_age_class,'')),'');
  normalized_summary text:=nullif(btrim(coalesce(new_summary,'')),'');
  next_image_id uuid; new_revision bigint;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select dedupe.result into existing_result
  from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id
    and dedupe.command_type='team.profile.update.v2'
    and dedupe.idempotency_key=update_team_profile_v2_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
  if expected_revision<0 or image_action not in ('keep','replace','remove')
    or length(coalesce(normalized_type,''))>80
    or length(coalesce(normalized_age,''))>80
    or length(coalesce(normalized_summary,''))>1000
    or (image_action='replace')<>(staged_image_id is not null)
  then raise invalid_parameter_value using message='invalid_team_profile'; end if;
  select * into team_row from core.teams team
  where team.id=target_team_id and team.status='active';
  if team_row.id is null or not (
    internal.actor_has_capability(team_row.club_id,team_row.id,'team.roster.manage')
    or internal.actor_has_capability(team_row.club_id,team_row.id,'club.memberships.manage')
    or internal.actor_has_capability(team_row.club_id,null,'club.memberships.manage')
  ) then raise insufficient_privilege using message='not_found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('team-profile:'||team_row.id::text,0));
  select * into profile_row from core.team_profiles profile
  where profile.team_id=team_row.id for update;
  if profile_row.team_id is null then
    if expected_revision<>0 then raise serialization_failure using message='stale_revision'; end if;
  elsif profile_row.revision<>expected_revision then
    raise serialization_failure using message='stale_revision';
  end if;
  next_image_id:=profile_row.image_asset_id;
  if image_action='replace' then
    select * into image_row from core.team_profile_images image
    where image.id=staged_image_id and image.team_id=team_row.id
      and image.club_id=team_row.club_id and image.uploaded_by=actor_id
      and image.state='staged' and image.expires_at>now()
    for update;
    if image_row.id is null or not exists(
      select 1 from storage.objects object
      where object.bucket_id=image_row.bucket_id and object.name=image_row.object_key
    ) then raise invalid_parameter_value using message='team_image_not_uploaded'; end if;
    update core.team_profile_images set state='replaced',retired_at=now(),revision=revision+1
    where id=profile_row.image_asset_id and state='active';
    update core.team_profile_images set state='active',activated_at=now(),revision=revision+1
    where id=image_row.id;
    next_image_id:=image_row.id;
  elsif image_action='remove' then
    update core.team_profile_images set state='removed',retired_at=now(),revision=revision+1
    where id=profile_row.image_asset_id and state='active';
    next_image_id:=null;
  end if;
  if profile_row.team_id is null then
    insert into core.team_profiles(
      team_id,team_type,age_class,summary,image_url,image_asset_id,updated_by
    ) values(
      team_row.id,normalized_type,normalized_age,normalized_summary,null,
      next_image_id,actor_id
    ) returning revision into new_revision;
  else
    update core.team_profiles set
      team_type=normalized_type,age_class=normalized_age,summary=normalized_summary,
      image_url=case when image_action='keep' then image_url else null end,
      image_asset_id=next_image_id,updated_at=now(),updated_by=actor_id,
      revision=revision+1
    where team_id=team_row.id returning revision into new_revision;
  end if;
  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values(
    actor_id,idempotency_key,'team.profile.update.v2',
    jsonb_build_object('team_id',team_row.id,'revision',new_revision)
  );
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision,metadata
  ) values(
    team_row.club_id,actor_id,'team.profile.update.v2','team',team_row.id,
    new_revision,jsonb_build_object('has_summary',normalized_summary is not null,
      'image_action',image_action,'image_asset_id',next_image_id)
  );
  return new_revision;
end
$$;

create function internal.authorize_team_profile_image_for_actor(target_image_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); image_row core.team_profile_images%rowtype;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select image.* into image_row
  from core.team_profile_images image
  join core.team_profiles profile on profile.team_id=image.team_id
    and profile.image_asset_id=image.id
  where image.id=target_image_id and image.state='active';
  if image_row.id is null or not internal.actor_has_club_access(image_row.club_id)
  then raise insufficient_privilege using message='not_found'; end if;
  return jsonb_build_object(
    'bucket_id',image_row.bucket_id,'object_key',image_row.object_key,
    'expires_in_seconds',3600
  );
end
$$;

create or replace function internal.get_team_overview_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); target_club_id uuid; can_manage boolean; result jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select team.club_id into target_club_id from core.teams team
    where team.id=target_team_id and team.status='active';
  if target_club_id is null or not internal.actor_has_club_access(target_club_id)
  then raise insufficient_privilege using message='not_found'; end if;
  can_manage:=internal.actor_has_capability(target_club_id,target_team_id,'team.roster.manage')
    or internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
    or internal.actor_has_capability(target_club_id,null,'club.memberships.manage');
  select jsonb_build_object(
    'team_id',team.id,'club_id',team.club_id,'team_name',team.name,'club_name',club.name,
    'team_type',profile.team_type,'age_class',profile.age_class,'summary',profile.summary,
    'image_url',profile.image_url,'image_asset_id',profile.image_asset_id,'can_manage',can_manage,
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
      from core.roster_invites invite where invite.club_id=team.club_id
        and invite.state='issued' and invite.expires_at>now()
        and exists(select 1 from core.assignments assignment
          where assignment.club_id=team.club_id and assignment.team_id=team.id
            and assignment.club_person_id=invite.club_person_id
            and assignment.state in ('pending','active'))
    ) else 0 end,
    'pending_application_count',case when can_manage then (select count(*)
      from core.membership_applications application
      where application.club_id=team.club_id and application.team_id=team.id
        and application.status='pending') else 0 end
  ) into result
  from core.teams team join core.clubs club on club.id=team.club_id
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
    'image_asset_id',profile_row.image_asset_id,'revision',coalesce(profile_row.revision,0)
  );
end
$$;

create function api.stage_team_profile_image(
  target_team_id uuid,target_mime_type text,target_size_bytes bigint,idempotency_key uuid)
returns jsonb language sql security invoker set search_path=''
as $$select internal.stage_team_profile_image_for_actor(
  target_team_id,target_mime_type,target_size_bytes,idempotency_key)$$;

create function api.update_team_profile_v2(
  target_team_id uuid,new_team_type text,new_age_class text,new_summary text,
  image_action text,staged_image_id uuid,expected_revision bigint,idempotency_key uuid)
returns bigint language sql security invoker set search_path=''
as $$select internal.update_team_profile_v2_for_actor(
  target_team_id,new_team_type,new_age_class,new_summary,image_action,
  staged_image_id,expected_revision,idempotency_key)$$;

create function api.authorize_team_profile_image(target_image_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.authorize_team_profile_image_for_actor(target_image_id)$$;

revoke all on function
  internal.stage_team_profile_image_for_actor(uuid,text,bigint,uuid),
  internal.update_team_profile_v2_for_actor(uuid,text,text,text,text,uuid,bigint,uuid),
  internal.authorize_team_profile_image_for_actor(uuid),
  api.stage_team_profile_image(uuid,text,bigint,uuid),
  api.update_team_profile_v2(uuid,text,text,text,text,uuid,bigint,uuid),
  api.authorize_team_profile_image(uuid)
from public,anon,authenticated;

grant execute on function
  internal.stage_team_profile_image_for_actor(uuid,text,bigint,uuid),
  internal.update_team_profile_v2_for_actor(uuid,text,text,text,text,uuid,bigint,uuid),
  internal.authorize_team_profile_image_for_actor(uuid),
  api.stage_team_profile_image(uuid,text,bigint,uuid),
  api.update_team_profile_v2(uuid,text,text,text,text,uuid,bigint,uuid),
  api.authorize_team_profile_image(uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260912134327_team02_private_team_image_upload','greenfield',
  'TEAM-02 private capability-scoped team image upload and signed delivery');

notify pgrst,'reload schema';
