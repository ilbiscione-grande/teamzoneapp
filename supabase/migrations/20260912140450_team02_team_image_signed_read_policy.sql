-- TEAM-02: Storage's signed-URL endpoint still evaluates SELECT RLS. Allow
-- only active images currently attached to a team the actor can access.

create function internal.actor_can_read_team_profile_image(
  target_bucket text,target_key text)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(
    select 1
    from core.team_profile_images image
    join core.team_profiles profile
      on profile.team_id=image.team_id and profile.image_asset_id=image.id
    where image.bucket_id=target_bucket
      and image.object_key=target_key
      and image.state='active'
      and internal.actor_has_club_access(image.club_id)
  )
$$;

revoke all on function internal.actor_can_read_team_profile_image(text,text)
  from public,anon,authenticated;
grant execute on function internal.actor_can_read_team_profile_image(text,text)
  to authenticated;

create policy team_profile_images_select on storage.objects
for select to authenticated
using(
  bucket_id='team-profile-images'
  and internal.actor_can_read_team_profile_image(bucket_id,name)
);

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260912140450_team02_team_image_signed_read_policy','greenfield',
  'TEAM-02 membership-scoped Storage SELECT for signed image delivery');

notify pgrst,'reload schema';
