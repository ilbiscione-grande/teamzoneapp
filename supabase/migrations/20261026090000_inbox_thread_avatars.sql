-- Profile pictures in the inbox: for each thread the viewer can access, the
-- three most recently active other participants (name for initials, and the
-- picture's storage key where the viewer shares a club with them, the same
-- rule as internal.actor_can_read_profile_avatar) and how many others take
-- part. The app signs the keys; a key it may not read shows initials.

create or replace function internal.list_thread_avatars_for_actor(target_thread_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if target_thread_ids is null or cardinality(target_thread_ids) > 200 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'thread_id', ids.thread_id,
      'participant_count', (
        select count(*) from core.thread_participants participant
        where participant.thread_id = ids.thread_id and participant.state = 'active'
          and participant.profile_id <> actor_id),
      'people', coalesce((
        select jsonb_agg(jsonb_build_object('profile_id', ranked.profile_id, 'name', ranked.name,
          'object_key', ranked.object_key) order by ranked.rank)
        from (
          select participant.profile_id,
            coalesce(nullif(btrim(profile.display_name), ''), nullif(btrim(person.display_name), ''), '?') as name,
            case when internal.actor_shares_club_with_profile(participant.profile_id)
              then avatar.object_key end as object_key,
            row_number() over (order by last_sent.at desc nulls last, participant.joined_at) as rank
          from core.thread_participants participant
          join core.profiles profile on profile.id = participant.profile_id
          left join core.club_people person
            on person.id = participant.club_person_id and person.club_id = participant.club_id
          left join core.profile_avatars avatar
            on avatar.id = profile.avatar_asset_id and avatar.state = 'active'
          left join lateral (
            select max(message.created_at) as at from core.messages message
            where message.thread_id = participant.thread_id
              and message.sender_profile_id = participant.profile_id) last_sent on true
          where participant.thread_id = ids.thread_id and participant.state = 'active'
            and participant.profile_id <> actor_id
        ) ranked
        where ranked.rank <= 3), '[]'::jsonb)))
    from (select distinct unnest(target_thread_ids) as thread_id) ids
    where internal.actor_can_access_thread(ids.thread_id)), '[]'::jsonb);
end;$$;

create or replace function api.list_thread_avatars(target_thread_ids uuid[])
returns jsonb language sql stable security invoker set search_path = '' as
$$select internal.list_thread_avatars_for_actor(target_thread_ids)$$;

revoke all on function internal.list_thread_avatars_for_actor(uuid[]), api.list_thread_avatars(uuid[])
  from public, anon, authenticated;
grant execute on function internal.list_thread_avatars_for_actor(uuid[]), api.list_thread_avatars(uuid[])
  to authenticated;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261026090000_inbox_thread_avatars', 'greenfield',
  'Inbox profile pictures: three most recent participants per thread and the participant count'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261026090000_inbox_thread_avatars');
notify pgrst, 'reload schema';
