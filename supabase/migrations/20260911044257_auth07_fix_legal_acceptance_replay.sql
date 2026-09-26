-- AUTH-07: an already completed legal acceptance must remain replay-safe even
-- when a later legal document version has become active. A new stale command
-- is still rejected after the actor-scoped dedupe lookup misses.

create or replace function internal.accept_current_legal_for_actor(
  terms_version text,privacy_version text,marketing_opt_in boolean,idempotency_key uuid
)
returns void language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); current_terms text; current_privacy text;
 existing jsonb;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;

  select result into existing from internal.command_deduplication dedupe
  where dedupe.actor_profile_id=actor_id
    and dedupe.command_type='identity.legal.accept.v1'
    and dedupe.idempotency_key=accept_current_legal_for_actor.idempotency_key;
  if existing is not null then return; end if;

  select version into current_terms from internal.legal_document_versions
  where document_type='terms' and active;
  select version into current_privacy from internal.legal_document_versions
  where document_type='privacy' and active;
  if terms_version is distinct from current_terms
    or privacy_version is distinct from current_privacy then
    raise serialization_failure using message='legal_version_changed';
  end if;
  insert into core.legal_acceptances(profile_id,document_type,document_version)
  values(actor_id,'terms',current_terms),(actor_id,'privacy',current_privacy)
  on conflict do nothing;
  insert into core.communication_preferences(profile_id,marketing_opt_in)
  values(actor_id,coalesce(marketing_opt_in,false))
  on conflict(profile_id) do update set marketing_opt_in=excluded.marketing_opt_in,
    decided_at=now(),revision=core.communication_preferences.revision+1;
  insert into internal.command_deduplication(
    actor_profile_id,idempotency_key,command_type,result
  ) values(
    actor_id,idempotency_key,'identity.legal.accept.v1',jsonb_build_object(
      'terms_version',current_terms,'privacy_version',current_privacy
    )
  );
  insert into audit.command_events(
    actor_profile_id,command_type,aggregate_type,aggregate_id,
    aggregate_revision,metadata
  ) values(
    actor_id,'identity.legal.accept.v1','profile',actor_id,1,
    jsonb_build_object(
      'terms_version',current_terms,'privacy_version',current_privacy,
      'marketing_opt_in',coalesce(marketing_opt_in,false)
    )
  );
end
$$;

revoke all on function internal.accept_current_legal_for_actor(text,text,boolean,uuid)
  from public,anon,authenticated;
grant execute on function internal.accept_current_legal_for_actor(text,text,boolean,uuid)
  to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values(
  '20260911044257_auth07_fix_legal_acceptance_replay',
  'greenfield',
  'AUTH-07 legal acceptance checks actor idempotency before active document versions'
);
