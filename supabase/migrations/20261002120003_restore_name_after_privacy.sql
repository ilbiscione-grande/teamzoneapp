-- CLI-generated; ordered after the privacy migration it extends.
-- The original name is distinct from the editable private name and alias.
alter table core.profile_privacy add column previous_name text,
 add column previous_member_names jsonb not null default '{}';
-- Older activations did not retain a separate original-name snapshot. Use the
-- private name already provided by the owner/guardian, never guess from aliases.
update core.profile_privacy set previous_name=nullif(btrim(private_name),'')
where nullif(btrim(private_name),'') is not null and private_name is distinct from alias;

create function internal.restore_pre_privacy_names(target uuid) returns void
language plpgsql security definer set search_path='' as $$
declare privacy core.profile_privacy%rowtype;
begin
 select * into privacy from core.profile_privacy where profile_id=target and not enabled;
 if privacy.profile_id is null or nullif(btrim(privacy.previous_name),'') is null then return;end if;
 update core.profiles set display_name=privacy.previous_name,revision=revision+1,updated_at=now()
 where id=target and display_name=privacy.alias;
 update core.club_people person set display_name=coalesce(nullif(privacy.previous_member_names->>person.id::text,''),privacy.previous_name),
  revision=person.revision+1
 where person.display_name=privacy.alias and (
  exists(select 1 from core.protected_person_bindings b join core.club_people original on original.id=b.person_id
   where b.profile_id=target and (b.person_id=person.id or original.person_id=person.person_id))
  or exists(select 1 from core.person_account_links l where l.profile_id=target and l.club_person_id=person.id));
end$$;
revoke all on function internal.restore_pre_privacy_names(uuid) from public,anon,authenticated;

do $patch$
declare definition text;patched text;
begin
 definition:=pg_get_functiondef('internal.save_profile_privacy_for_actor(uuid,boolean,text,text,text,text,bigint)'::regprocedure);
 patched:=replace(definition,'declare current_row core.profile_privacy%rowtype; contact jsonb;',
  'declare current_row core.profile_privacy%rowtype; contact jsonb; original_name text; member_names jsonb;');
 patched:=replace(patched,'contact:=internal.normalized_contact(new_safe_email,new_safe_phone);',
  'if enable_protection and not coalesce(current_row.enabled,false) then
    select display_name into original_name from core.profiles where id=target;
    select coalesce(jsonb_object_agg(person.id::text,person.display_name),''{}''::jsonb) into member_names
    from core.club_people person where exists(select 1 from core.person_account_links link
     join core.club_people original on original.id=link.club_person_id
     where link.profile_id=target and (link.club_person_id=person.id or original.person_id=person.person_id));
   end if;
   contact:=internal.normalized_contact(new_safe_email,new_safe_phone);');
 patched:=replace(patched,'if enable_protection then',
  'if enable_protection and not coalesce(current_row.enabled,false) then
    update core.profile_privacy set previous_name=original_name,previous_member_names=member_names where profile_id=target;
   end if;
   if enable_protection then');
 patched:=replace(patched,'alias=excluded.alias','alias=case when excluded.enabled then excluded.alias else core.profile_privacy.alias end');
 patched:=replace(patched,'-- Turning protection off never republishes identity, photos or contact values.',
  'if not enable_protection then perform internal.restore_pre_privacy_names(target);end if;
   -- Names are restored; photos, contact values and consents remain unchanged.');
 if patched=definition or position('perform internal.restore_pre_privacy_names(target)' in patched)=0
 then raise exception 'privacy name restoration patch missing';end if;
 execute patched;
end$patch$;
-- Repair earlier deactivations only when the displayed name is still the alias.
do $$declare item record;begin
 for item in select profile_id from core.profile_privacy where not enabled and previous_name is not null loop
  perform internal.restore_pre_privacy_names(item.profile_id);
 end loop;
end$$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261002120003_restore_name_after_privacy','greenfield','Restore pre-protection account and member names on deactivation');
notify pgrst,'reload schema';
