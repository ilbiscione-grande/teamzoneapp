create function internal.issue_callup_response_token_for_actor(target_callup_id uuid,raw_token text,expiry timestamptz,idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();callup core.callups%rowtype;token_id uuid;existing jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into callup from core.callups where id=target_callup_id;
 if callup.id is null or not internal.actor_can_manage_squad(callup.event_id) then raise insufficient_privilege using message='not_found';end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id and command_type='callup.response_token.issued.v1' and internal.command_deduplication.idempotency_key=issue_callup_response_token_for_actor.idempotency_key;
 if existing is not null then return(existing->>'token_id')::uuid;end if;
 if length(raw_token)<32 or expiry<=now() or expiry>least(callup.expires_at,now()+interval'14 days') then raise invalid_parameter_value using message='invalid_input';end if;
 insert into core.callup_response_tokens(club_id,callup_id,token_hash,expires_at)values(callup.club_id,callup.id,extensions.digest(raw_token,'sha256'),expiry)returning id into token_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)values(actor_id,idempotency_key,'callup.response_token.issued.v1',jsonb_build_object('token_id',token_id));
 return token_id;
end$$;
create function internal.respond_callup_with_token_for_actor(raw_token text,new_response text,acting_as_person_id uuid,decline_reason_code text,decline_reason_text text,expected_revision bigint,idempotency_key uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare token_row core.callup_response_tokens%rowtype;result_revision bigint;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into token_row from core.callup_response_tokens where token_hash=extensions.digest(raw_token,'sha256') for update;
 if token_row.id is null or token_row.state<>'issued' or token_row.expires_at<=now() then raise insufficient_privilege using message='invalid_or_expired_token';end if;
 result_revision:=internal.respond_callup_for_actor(token_row.callup_id,new_response,acting_as_person_id,decline_reason_code,decline_reason_text,expected_revision,idempotency_key);
 update core.callup_response_tokens set state='consumed',consumed_at=now() where id=token_row.id;
 return result_revision;
end$$;
revoke all on function internal.issue_callup_response_token_for_actor(uuid,text,timestamptz,uuid),internal.respond_callup_with_token_for_actor(text,text,uuid,text,text,bigint,uuid) from public,anon,authenticated;
grant execute on function internal.issue_callup_response_token_for_actor(uuid,text,timestamptz,uuid),internal.respond_callup_with_token_for_actor(text,text,uuid,text,text,bigint,uuid) to authenticated;
create function api.issue_callup_response_token(target_callup_id uuid,raw_token text,expiry timestamptz,idempotency_key uuid) returns uuid language sql security invoker set search_path='' as $$ select internal.issue_callup_response_token_for_actor(target_callup_id,raw_token,expiry,idempotency_key) $$;
create function api.respond_callup_with_token(raw_token text,new_response text,acting_as_person_id uuid,decline_reason_code text,decline_reason_text text,expected_revision bigint,idempotency_key uuid) returns bigint language sql security invoker set search_path='' as $$ select internal.respond_callup_with_token_for_actor(raw_token,new_response,acting_as_person_id,decline_reason_code,decline_reason_text,expected_revision,idempotency_key) $$;
revoke all on function api.issue_callup_response_token(uuid,text,timestamptz,uuid),api.respond_callup_with_token(text,text,uuid,text,text,bigint,uuid) from public,anon;
grant execute on function api.issue_callup_response_token(uuid,text,timestamptz,uuid),api.respond_callup_with_token(text,text,uuid,text,text,bigint,uuid) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)values('20260808075505_s04_response_tokens','greenfield',null);notify pgrst,'reload schema';
