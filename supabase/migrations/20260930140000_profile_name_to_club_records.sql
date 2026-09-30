-- PROF-03: when you change your own name, the member records that are yours
-- (linked to your account) in every club follow, so squads, profiles and
-- event lists show the new name. Records of other people are never touched.

create or replace function internal.update_my_profile_details_for_actor(new_display_name text,
 new_contact_email text,new_phone text,avatar_action text,staged_avatar_id uuid,
 expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); profile_row core.profiles%rowtype; avatar_row core.profile_avatars%rowtype;
 contact jsonb; name text:=btrim(coalesce(new_display_name,'')); next_avatar uuid; existing_result jsonb;
 new_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select dedupe.result into existing_result from internal.command_deduplication dedupe
 where dedupe.actor_profile_id=actor_id and dedupe.command_type='profile.details.update.v1'
  and dedupe.idempotency_key=update_my_profile_details_for_actor.idempotency_key;
 if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
 if length(name) not between 1 and 120 or avatar_action not in ('keep','replace','remove')
  or (avatar_action='replace')<>(staged_avatar_id is not null)
 then raise invalid_parameter_value using message='invalid_profile'; end if;
 contact:=internal.normalized_contact(new_contact_email,new_phone);
 select * into profile_row from core.profiles where id=actor_id for update;
 if profile_row.revision<>expected_revision then raise serialization_failure using message='stale_revision'; end if;
 next_avatar:=profile_row.avatar_asset_id;
 if avatar_action='replace' then
  select * into avatar_row from core.profile_avatars avatar
  where avatar.id=staged_avatar_id and avatar.profile_id=actor_id and avatar.state='staged'
   and avatar.expires_at>now() for update;
  if avatar_row.id is null or not exists(select 1 from storage.objects object
    where object.bucket_id=avatar_row.bucket_id and object.name=avatar_row.object_key)
  then raise invalid_parameter_value using message='avatar_not_uploaded'; end if;
  update core.profile_avatars set state='replaced',retired_at=now()
  where id=profile_row.avatar_asset_id and state='active';
  update core.profile_avatars set state='active',activated_at=now() where id=avatar_row.id;
  next_avatar:=avatar_row.id;
 elsif avatar_action='remove' then
  update core.profile_avatars set state='removed',retired_at=now()
  where id=profile_row.avatar_asset_id and state='active';
  next_avatar:=null;
 end if;
 update core.profiles set display_name=name,contact_email=contact->>'email',phone=contact->>'phone',
  avatar_asset_id=next_avatar,updated_at=now(),revision=revision+1
 where id=actor_id returning revision into new_revision;
 -- Your own member records follow your name.
 update core.club_people person set display_name=name,revision=person.revision+1
 where person.display_name is distinct from name and person.status='active'
  and exists(select 1 from core.person_account_links link
   where link.club_person_id=person.id and link.club_id=person.club_id
    and link.profile_id=actor_id and link.state='active');
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'profile.details.update.v1',jsonb_build_object('revision',new_revision));
 return new_revision;
end$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260930140000_profile_name_to_club_records','greenfield',
 'PROF-03 own name change follows to the member records linked to the account');
notify pgrst,'reload schema';
