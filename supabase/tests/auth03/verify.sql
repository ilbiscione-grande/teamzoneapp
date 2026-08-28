\set ON_ERROR_STOP on

do $$
declare
  leader_id constant uuid := '10000000-0000-0000-0000-000000000001';
  recipient_id constant uuid := '10000000-0000-0000-0000-000000000002';
  wrong_id constant uuid := '10000000-0000-0000-0000-000000000003';
  club_id constant uuid := '20000000-0000-0000-0000-000000000001';
  team_id constant uuid := '30000000-0000-0000-0000-000000000001';
  leader_person_id constant uuid := '40000000-0000-0000-0000-000000000001';
  target_person_id constant uuid := '40000000-0000-0000-0000-000000000002';
  leader_identity_id constant uuid := '41000000-0000-0000-0000-000000000001';
  target_identity_id constant uuid := '41000000-0000-0000-0000-000000000002';
  assignment_id constant uuid := '50000000-0000-0000-0000-000000000001';
  token constant text := 'auth03-valid-recipient-token-0000000000000001';
  mismatch_token constant text := 'auth03-mismatch-token-00000000000000000001';
  invite_id uuid;
  mismatch_invite_id uuid;
  result jsonb;
  repeated jsonb;
begin
  insert into auth.users(id,email,raw_user_meta_data) values
    (leader_id,'leader@example.test','{"display_name":"Leader"}'),
    (recipient_id,'recipient@example.test','{"display_name":"Recipient"}'),
    (wrong_id,'wrong@example.test','{"display_name":"Wrong"}');

  insert into core.clubs(id,name,slug,created_by)
  values(club_id,'Verifieringsklubben','verifieringsklubben',leader_id);
  insert into core.teams(id,club_id,name,created_by)
  values(team_id,club_id,'Verifieringslaget',leader_id);
  insert into core.persons(id,created_by) values
    (leader_identity_id,leader_id),(target_identity_id,leader_id);
  insert into core.club_people(id,club_id,person_id,display_name,created_by) values
    (leader_person_id,club_id,leader_identity_id,'Ledaren',leader_id),
    (target_person_id,club_id,target_identity_id,'Mottagaren',leader_id);
  insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at,created_by)
  values(club_id,leader_person_id,leader_id,'active',now(),leader_id);
  insert into core.assignments(id,club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
  values(assignment_id,club_id,team_id,leader_person_id,'leader','active',now()-interval '1 day',leader_id);
  insert into core.assignments(club_id,team_id,club_person_id,role_package,state,starts_at,created_by)
  values(club_id,team_id,target_person_id,'player','pending',now()-interval '1 day',leader_id);
  insert into core.capability_grants(club_id,assignment_id,capability,scope_type,scope_id,starts_at,created_by)
  values(club_id,assignment_id,'club.memberships.manage','club',club_id,now()-interval '1 day',leader_id);

  perform set_config('request.jwt.claim.sub',leader_id::text,true);
  invite_id := api.issue_roster_invitation_v2(
    target_person_id,' Recipient@Example.Test ',token,now()+interval '1 day',
    '60000000-0000-0000-0000-000000000001'
  );

  result := internal.preview_roster_invitation(token);
  if result->>'status' <> 'valid'
     or result->>'club_name' <> 'Verifieringsklubben'
     or result->>'team_name' <> 'Verifieringslaget'
     or result->>'person_name' <> 'Mottagaren' then
    raise exception 'valid preview failed: %', result;
  end if;
  if internal.preview_roster_invitation('too-short')->>'status' <> 'invalid'
     or internal.preview_roster_invitation('auth03-random-token-000000000000000000000')->>'status' <> 'invalid' then
    raise exception 'neutral invalid preview failed';
  end if;

  perform set_config('request.jwt.claim.sub',recipient_id::text,true);
  result := api.claim_roster_invitation_v2(token,'70000000-0000-0000-0000-000000000001');
  repeated := api.claim_roster_invitation_v2(token,'70000000-0000-0000-0000-000000000001');
  if result->>'status' <> 'claimed' or result <> repeated then
    raise exception 'claim/idempotency failed: %, %', result, repeated;
  end if;
  if not exists (
    select 1 from core.person_account_links
    where club_person_id=target_person_id and profile_id=recipient_id and state='active'
  ) or not exists (
    select 1 from core.roster_invites where id=invite_id and state='consumed' and consumed_by=recipient_id
  ) then
    raise exception 'claim persistence failed';
  end if;
  if internal.preview_roster_invitation(token)->>'status' <> 'invalid' then
    raise exception 'consumed invitation preview was not neutral';
  end if;

  perform set_config('request.jwt.claim.sub',leader_id::text,true);
  mismatch_invite_id := api.issue_roster_invitation_v2(
    leader_person_id,'recipient@example.test',mismatch_token,now()+interval '1 day',
    '60000000-0000-0000-0000-000000000002'
  );
  perform set_config('request.jwt.claim.sub',wrong_id::text,true);
  result := api.claim_roster_invitation_v2(mismatch_token,'70000000-0000-0000-0000-000000000002');
  if result->>'status' <> 'review_required' or not exists (
    select 1 from core.invitation_claim_reviews
    where invite_id=mismatch_invite_id and requesting_profile_id=wrong_id
      and reason_code='recipient_mismatch' and state='open'
  ) then
    raise exception 'recipient mismatch review failed: %', result;
  end if;
  if not exists(select 1 from core.roster_invites where id=mismatch_invite_id and state='issued') then
    raise exception 'review-required invitation was consumed';
  end if;

  perform set_config('request.jwt.claim.sub',wrong_id::text,true);
  begin
    perform api.issue_roster_invitation_v2(
      target_person_id,'wrong@example.test','auth03-unauthorized-token-0000000000000001',
      now()+interval '1 day','60000000-0000-0000-0000-000000000003'
    );
    raise exception 'unauthorized issuer unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end
$$;

do $$
begin
  if has_function_privilege('anon','api.preview_roster_invitation(text)','EXECUTE')
     or has_function_privilege('anon','api.claim_roster_invitation_v2(text,uuid)','EXECUTE')
     or has_function_privilege('anon','api.issue_roster_invitation_v2(uuid,text,text,timestamptz,uuid)','EXECUTE') then
    raise exception 'anonymous API execute grant detected';
  end if;
  if not has_function_privilege('service_role','api.preview_roster_invitation(text)','EXECUTE') then
    raise exception 'service role cannot execute preview';
  end if;
end
$$;

select 'AUTH-03 SQL verification passed' as result;
