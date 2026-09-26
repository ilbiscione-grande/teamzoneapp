-- AUTH-06: an identical verification request retry must return its original
-- result even though the first execution has already moved the club to pending.

create or replace function internal.request_club_verification_for_actor(
  target_club_id uuid,evidence_summary text,idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); request_id uuid; existing_result jsonb;
 normalized_evidence text:=btrim(evidence_summary);
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  if not internal.actor_has_capability(target_club_id,null,'club.memberships.manage') then
    raise insufficient_privilege using message='not_found';
  end if;
  if length(normalized_evidence) not between 20 and 1000 then
    raise invalid_parameter_value using message='invalid_evidence';
  end if;

  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='club.verification.request.v1'
    and internal.command_deduplication.idempotency_key=request_club_verification_for_actor.idempotency_key;
  if existing_result is not null then return (existing_result->>'request_id')::uuid; end if;

  if not exists(select 1 from core.clubs where id=target_club_id
      and status='active' and verification_status in ('unofficial','rejected','revoked')) then
    raise invalid_parameter_value using message='invalid_status';
  end if;
  insert into core.club_verification_requests(club_id,requested_by,evidence_summary)
  values(target_club_id,actor_id,normalized_evidence)
  on conflict(club_id) where status='pending'
  do update set evidence_summary=excluded.evidence_summary,
    revision=core.club_verification_requests.revision+1
  returning id into request_id;
  update core.clubs set verification_status='pending',revision=revision+1
  where id=target_club_id;
  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'club.verification.request.v1',jsonb_build_object('request_id',request_id));
  insert into audit.command_events(
    club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision
  ) values(
    target_club_id,actor_id,'club.verification.request.v1',
    'club_verification_request',request_id,1
  );
  return request_id;
end
$$;

revoke all on function internal.request_club_verification_for_actor(uuid,text,uuid)
  from public,anon,authenticated;
grant execute on function internal.request_club_verification_for_actor(uuid,text,uuid)
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260910202427_auth06_fix_verification_request_replay',
  'greenfield',
  'AUTH-06 verification request checks actor idempotency before pending status'
);
