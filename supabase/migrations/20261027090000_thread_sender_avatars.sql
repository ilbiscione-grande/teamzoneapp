-- Profile pictures before the sender's name in a conversation: the storage
-- keys of the pictures of everyone in a thread the viewer can access
-- (including people who have left, whose messages remain), where the viewer
-- shares a club with them (the rule of internal.actor_can_read_profile_avatar).
-- The app signs the keys; anyone without one shows initials.

create or replace function internal.list_thread_sender_avatars_for_actor(target_thread_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_can_access_thread(target_thread_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('profile_id', member.profile_id, 'object_key', avatar.object_key)
      order by member.profile_id)
    from (select distinct participant.profile_id from core.thread_participants participant
      where participant.thread_id = target_thread_id) member
    join core.profiles profile on profile.id = member.profile_id
    join core.profile_avatars avatar on avatar.id = profile.avatar_asset_id and avatar.state = 'active'
    where internal.actor_shares_club_with_profile(member.profile_id)), '[]'::jsonb);
end;$$;

create or replace function api.list_thread_sender_avatars(target_thread_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as
$$select internal.list_thread_sender_avatars_for_actor(target_thread_id)$$;

revoke all on function internal.list_thread_sender_avatars_for_actor(uuid), api.list_thread_sender_avatars(uuid)
  from public, anon, authenticated;
grant execute on function internal.list_thread_sender_avatars_for_actor(uuid), api.list_thread_sender_avatars(uuid)
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261027090000_thread_sender_avatars', 'greenfield',
  'Profile pictures before the sender name in a conversation'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261027090000_thread_sender_avatars');
notify pgrst, 'reload schema';
