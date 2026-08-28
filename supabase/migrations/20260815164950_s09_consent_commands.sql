-- S09 authenticated consent commands. Public reads remain disabled.

alter table core.publication_consents
  drop constraint publication_consents_state_check,
  add constraint publication_consents_state_check
    check (state in ('pending_guardian', 'active', 'withdrawn', 'expired', 'superseded'));

create function internal.verify_publication_age_band_for_actor(
  target_club_id uuid,
  target_club_person_id uuid,
  new_age_band text,
  new_valid_until date,
  evidence_sha256_hex text,
  p_idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid();
  existing jsonb;
  assertion_id uuid;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id, null, 'club.memberships.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if new_age_band not in ('through_15', '16_plus')
     or new_valid_until < current_date
     or new_valid_until > current_date + 366
     or evidence_sha256_hex !~ '^[0-9a-fA-F]{64}$' then
    raise check_violation using message = 'invalid_age_assertion';
  end if;
  if not exists (
    select 1 from core.club_people person
    where person.id = target_club_person_id and person.club_id = target_club_id
      and person.status = 'active'
  ) then raise insufficient_privilege using message = 'not_found'; end if;

  select result into existing from internal.command_deduplication dedupe
   where dedupe.actor_profile_id = actor_id
     and dedupe.command_type = 'publication.age_asserted.v1'
     and dedupe.idempotency_key = p_idempotency_key;
  if existing is not null then return (existing->>'assertion_id')::uuid; end if;

  update core.person_age_assertions
     set state = 'superseded', revision = revision + 1
   where club_id = target_club_id and club_person_id = target_club_person_id
     and state = 'active';

  update core.publication_consents
     set state = 'superseded', revision = revision + 1
   where club_id = target_club_id and subject_club_person_id = target_club_person_id
     and state in ('pending_guardian', 'active');

  insert into core.person_age_assertions(
    club_id, club_person_id, age_band, verified_at, valid_until,
    evidence_hash, verified_by
  ) values (
    target_club_id, target_club_person_id, new_age_band, now(), new_valid_until,
    decode(lower(evidence_sha256_hex), 'hex'), actor_id
  ) returning id into assertion_id;

  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,p_idempotency_key,'publication.age_asserted.v1',
    jsonb_build_object('assertion_id', assertion_id));
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata
  ) values (
    target_club_id,actor_id,'publication.age_asserted.v1','club_person',
    target_club_person_id,1,jsonb_build_object('age_band',new_age_band,'valid_until',new_valid_until)
  );
  return assertion_id;
end;
$$;

create function internal.give_publication_consent_for_actor(
  target_club_id uuid,
  target_subject_club_person_id uuid,
  new_field_class text,
  new_season_ends_on date,
  new_expires_at timestamptz,
  p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid();
  assertion core.person_age_assertions%rowtype;
  existing jsonb;
  consent_id uuid;
  consent_state text;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.actor_owns_club_person(target_club_id,target_subject_club_person_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if new_field_class not in ('name','profile_media','position','individual_statistics')
     or new_season_ends_on < current_date
     or new_expires_at <= now()
     or new_expires_at > now() + interval '366 days'
     or new_expires_at::date > new_season_ends_on then
    raise check_violation using message = 'invalid_consent';
  end if;

  select * into assertion from core.person_age_assertions age
   where age.club_id = target_club_id
     and age.club_person_id = target_subject_club_person_id
     and age.state = 'active' and age.valid_until >= new_expires_at::date;
  if assertion.id is null then raise check_violation using message = 'age_not_verified'; end if;

  select result into existing from internal.command_deduplication dedupe
   where dedupe.actor_profile_id = actor_id
     and dedupe.command_type = 'publication.consent.given.v1'
     and dedupe.idempotency_key = p_idempotency_key;
  if existing is not null then return existing; end if;

  update core.publication_consents
     set state = 'superseded', revision = revision + 1
   where club_id = target_club_id
     and subject_club_person_id = target_subject_club_person_id
     and field_class = new_field_class and purpose_code = 'public_team_profile_v1'
     and state in ('pending_guardian','active');

  consent_state := case when assertion.age_band = 'through_15'
    then 'pending_guardian' else 'active' end;
  insert into core.publication_consents(
    club_id,subject_club_person_id,field_class,state,subject_approved_at,
    subject_approved_by,age_assertion_id,season_ends_on,expires_at
  ) values (
    target_club_id,target_subject_club_person_id,new_field_class,consent_state,now(),
    actor_id,assertion.id,new_season_ends_on,new_expires_at
  ) returning id into consent_id;

  existing := jsonb_build_object('consent_id',consent_id,'state',consent_state,'revision',1);
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,p_idempotency_key,'publication.consent.given.v1',existing);
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata
  ) values (
    target_club_id,actor_id,'publication.consent.given.v1','publication_consent',consent_id,1,
    jsonb_build_object('field_class',new_field_class,'state',consent_state)
  );
  return existing;
end;
$$;

create function internal.approve_guardian_publication_consent_for_actor(
  target_consent_id uuid,
  acting_as_guardian_club_person_id uuid,
  expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid();
  consent core.publication_consents%rowtype;
  assertion core.person_age_assertions%rowtype;
  existing jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into consent from core.publication_consents where id = target_consent_id for update;
  if consent.id is null
     or not internal.actor_owns_club_person(consent.club_id,acting_as_guardian_club_person_id)
     or not exists (
       select 1 from core.guardian_relations relation
        where relation.club_id = consent.club_id
          and relation.guardian_person_id = acting_as_guardian_club_person_id
          and relation.child_person_id = consent.subject_club_person_id
          and relation.state = 'active' and relation.starts_at <= now()
          and (relation.ends_at is null or relation.ends_at > now())
     ) then raise insufficient_privilege using message = 'not_found'; end if;

  select result into existing from internal.command_deduplication dedupe
   where dedupe.actor_profile_id = actor_id
     and dedupe.command_type = 'publication.consent.guardian_approved.v1'
     and dedupe.idempotency_key = p_idempotency_key;
  if existing is not null then return existing; end if;

  select * into assertion from core.person_age_assertions
   where id = consent.age_assertion_id and club_id = consent.club_id
     and state = 'active' and age_band = 'through_15' and valid_until >= current_date;
  if assertion.id is null or consent.state <> 'pending_guardian' or consent.expires_at <= now() then
    raise check_violation using message = 'consent_not_approvable';
  end if;
  if consent.revision <> expected_revision then
    raise serialization_failure using message = 'stale_revision';
  end if;

  update core.publication_consents set
    state = 'active', guardian_club_person_id = acting_as_guardian_club_person_id,
    guardian_approved_at = now(), guardian_approved_by = actor_id,
    revision = revision + 1
   where id = consent.id;
  existing := jsonb_build_object('consent_id',consent.id,'state','active',
    'revision',consent.revision + 1);
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,p_idempotency_key,'publication.consent.guardian_approved.v1',existing);
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata
  ) values (
    consent.club_id,actor_id,'publication.consent.guardian_approved.v1',
    'publication_consent',consent.id,consent.revision + 1,
    jsonb_build_object('guardian_club_person_id',acting_as_guardian_club_person_id)
  );
  return existing;
end;
$$;

create function internal.withdraw_publication_consent_for_actor(
  target_consent_id uuid,
  new_reason text,
  expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid();
  consent core.publication_consents%rowtype;
  existing jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select * into consent from core.publication_consents where id = target_consent_id for update;
  if consent.id is null or not (
    internal.actor_owns_club_person(consent.club_id,consent.subject_club_person_id)
    or (consent.guardian_club_person_id is not null
      and internal.actor_owns_club_person(consent.club_id,consent.guardian_club_person_id))
  ) then raise insufficient_privilege using message = 'not_found'; end if;

  select result into existing from internal.command_deduplication dedupe
   where dedupe.actor_profile_id = actor_id
     and dedupe.command_type = 'publication.consent.withdrawn.v1'
     and dedupe.idempotency_key = p_idempotency_key;
  if existing is not null then return existing; end if;

  if consent.state not in ('pending_guardian','active')
     or length(btrim(coalesce(new_reason,''))) not between 2 and 500 then
    raise check_violation using message = 'consent_not_withdrawable';
  end if;
  if consent.revision <> expected_revision then
    raise serialization_failure using message = 'stale_revision';
  end if;

  update core.publication_consents set
    state = 'withdrawn', withdrawn_at = now(), withdrawn_by = actor_id,
    withdrawal_reason = btrim(new_reason), revision = revision + 1
   where id = consent.id;
  insert into internal.publication_projection_jobs(
    club_id,aggregate_type,aggregate_id,requested_revision,action,affected_paths,created_by
  ) values (
    consent.club_id,'person',consent.subject_club_person_id,consent.revision + 1,
    'remove',array[]::text[],actor_id
  );
  existing := jsonb_build_object('consent_id',consent.id,'state','withdrawn',
    'revision',consent.revision + 1,'invalidation_state','pending');
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,p_idempotency_key,'publication.consent.withdrawn.v1',existing);
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,reason,metadata
  ) values (
    consent.club_id,actor_id,'publication.consent.withdrawn.v1','publication_consent',
    consent.id,consent.revision + 1,btrim(new_reason),
    jsonb_build_object('field_class',consent.field_class,'invalidation_state','pending')
  );
  return existing;
end;
$$;

revoke all on function
  internal.verify_publication_age_band_for_actor(uuid,uuid,text,date,text,uuid),
  internal.give_publication_consent_for_actor(uuid,uuid,text,date,timestamptz,uuid),
  internal.approve_guardian_publication_consent_for_actor(uuid,uuid,bigint,uuid),
  internal.withdraw_publication_consent_for_actor(uuid,text,bigint,uuid)
from public, anon, authenticated;
grant execute on function
  internal.verify_publication_age_band_for_actor(uuid,uuid,text,date,text,uuid),
  internal.give_publication_consent_for_actor(uuid,uuid,text,date,timestamptz,uuid),
  internal.approve_guardian_publication_consent_for_actor(uuid,uuid,bigint,uuid),
  internal.withdraw_publication_consent_for_actor(uuid,text,bigint,uuid)
to authenticated;

create function api.verify_publication_age_band(
  club_id uuid,club_person_id uuid,age_band text,valid_until date,
  evidence_sha256_hex text,idempotency_key uuid
) returns uuid language sql security invoker set search_path = '' as $$
  select internal.verify_publication_age_band_for_actor(
    club_id,club_person_id,age_band,valid_until,evidence_sha256_hex,idempotency_key
  )
$$;
create function api.give_publication_consent(
  club_id uuid,subject_club_person_id uuid,field_class text,season_ends_on date,
  expires_at timestamptz,idempotency_key uuid
) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.give_publication_consent_for_actor(
    club_id,subject_club_person_id,field_class,season_ends_on,expires_at,idempotency_key
  )
$$;
create function api.approve_guardian_publication_consent(
  consent_id uuid,acting_as_guardian_club_person_id uuid,
  expected_revision bigint,idempotency_key uuid
) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.approve_guardian_publication_consent_for_actor(
    consent_id,acting_as_guardian_club_person_id,expected_revision,idempotency_key
  )
$$;
create function api.withdraw_publication_consent(
  consent_id uuid,reason text,expected_revision bigint,idempotency_key uuid
) returns jsonb language sql security invoker set search_path = '' as $$
  select internal.withdraw_publication_consent_for_actor(
    consent_id,reason,expected_revision,idempotency_key
  )
$$;

revoke all on function
  api.verify_publication_age_band(uuid,uuid,text,date,text,uuid),
  api.give_publication_consent(uuid,uuid,text,date,timestamptz,uuid),
  api.approve_guardian_publication_consent(uuid,uuid,bigint,uuid),
  api.withdraw_publication_consent(uuid,text,bigint,uuid)
from public, anon;
grant execute on function
  api.verify_publication_age_band(uuid,uuid,text,date,text,uuid),
  api.give_publication_consent(uuid,uuid,text,date,timestamptz,uuid),
  api.approve_guardian_publication_consent(uuid,uuid,bigint,uuid),
  api.withdraw_publication_consent(uuid,text,bigint,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260815164950_s09_consent_commands','greenfield',
  'Separate subject and guardian actors; age 16+ self-consent; publication remains disabled'
);
