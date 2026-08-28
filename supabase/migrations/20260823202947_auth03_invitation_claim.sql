-- AUTH-03 local invitation preview and safe claim closure.
-- Teamzone6 and hosted Supabase are not sources or targets for this migration.

alter table core.roster_invites
  add column intended_email_hash bytea;

create table core.invitation_claim_reviews (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  invite_id uuid not null references core.roster_invites(id),
  requesting_profile_id uuid not null references core.profiles(id),
  reason_code text not null check (reason_code in ('recipient_mismatch','person_already_linked')),
  state text not null default 'open' check (state in ('open','approved','rejected','resolved')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (invite_id, requesting_profile_id, reason_code)
);

alter table core.invitation_claim_reviews enable row level security;
create policy invitation_claim_reviews_no_direct_select
on core.invitation_claim_reviews for select to authenticated using (false);

create function internal.preview_roster_invitation(raw_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare invite_row core.roster_invites%rowtype; result jsonb;
begin
  if length(coalesce(raw_token,'')) < 32 then
    return jsonb_build_object('status','invalid');
  end if;
  select invite.* into invite_row
  from core.roster_invites invite
  where invite.token_hash=extensions.digest(raw_token,'sha256');
  if invite_row.id is null or invite_row.state<>'issued' or invite_row.expires_at<=now() then
    return jsonb_build_object('status','invalid');
  end if;
  select jsonb_build_object(
    'status','valid',
    'club_name',club.name,
    'team_name',team.name,
    'person_name',person.display_name,
    'role_package',assignment.role_package,
    'expires_at',invite_row.expires_at
  ) into result
  from core.club_people person
  join core.clubs club on club.id=person.club_id
  left join lateral (
    select current_assignment.team_id,current_assignment.role_package
    from core.assignments current_assignment
    where current_assignment.club_id=person.club_id
      and current_assignment.club_person_id=person.id
      and current_assignment.state in ('pending','active')
      and current_assignment.starts_at<=now()
      and (current_assignment.ends_at is null or current_assignment.ends_at>now())
    order by (current_assignment.state='active') desc,current_assignment.created_at,current_assignment.id
    limit 1
  ) assignment on true
  left join core.teams team on team.id=assignment.team_id and team.club_id=person.club_id
  where person.id=invite_row.club_person_id and person.club_id=invite_row.club_id
    and person.status='active' and club.status='active'
    and (team.id is null or team.status='active');
  return coalesce(result,jsonb_build_object('status','invalid'));
end;
$$;

create function internal.claim_roster_invitation_v2(raw_token text,idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); actor_email text; invite_row core.roster_invites%rowtype;
 existing_result jsonb; linked_profile uuid; review_id uuid; claimed_person uuid;
begin
  if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
  select result into existing_result from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='roster.person.claim.v2'
    and internal.command_deduplication.idempotency_key=claim_roster_invitation_v2.idempotency_key;
  if existing_result is not null then return existing_result; end if;

  select * into invite_row from core.roster_invites
  where token_hash=extensions.digest(raw_token,'sha256') for update;
  if invite_row.id is null or invite_row.state<>'issued' or invite_row.expires_at<=now() then
    raise invalid_parameter_value using message='invalid_or_expired_token';
  end if;

  if invite_row.intended_email_hash is not null then
    select lower(email) into actor_email from auth.users where id=actor_id;
    if actor_email is null or extensions.digest(actor_email,'sha256')<>invite_row.intended_email_hash then
      insert into core.invitation_claim_reviews(club_id,invite_id,requesting_profile_id,reason_code)
      values(invite_row.club_id,invite_row.id,actor_id,'recipient_mismatch')
      on conflict(invite_id,requesting_profile_id,reason_code) do update set revision=core.invitation_claim_reviews.revision+1
      returning id into review_id;
      existing_result:=jsonb_build_object('status','review_required','review_id',review_id);
    end if;
  end if;

  if existing_result is null then
    select profile_id into linked_profile from core.person_account_links
    where club_id=invite_row.club_id and club_person_id=invite_row.club_person_id and state='active';
    if linked_profile is not null and linked_profile<>actor_id then
      insert into core.invitation_claim_reviews(club_id,invite_id,requesting_profile_id,reason_code)
      values(invite_row.club_id,invite_row.id,actor_id,'person_already_linked')
      on conflict(invite_id,requesting_profile_id,reason_code) do update set revision=core.invitation_claim_reviews.revision+1
      returning id into review_id;
      existing_result:=jsonb_build_object('status','review_required','review_id',review_id);
    elsif linked_profile=actor_id then
      existing_result:=jsonb_build_object('status','claimed','club_person_id',invite_row.club_person_id);
    else
      insert into core.person_account_links(club_id,club_person_id,profile_id,state,verified_at,created_by)
      values(invite_row.club_id,invite_row.club_person_id,actor_id,'active',now(),actor_id)
      returning club_person_id into claimed_person;
      update core.roster_invites set state='consumed',consumed_at=now(),consumed_by=actor_id,revision=revision+1
      where id=invite_row.id;
      insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision)
      values(invite_row.club_id,actor_id,'roster.person.claim.v2','club_person',claimed_person,1);
      existing_result:=jsonb_build_object('status','claimed','club_person_id',claimed_person);
    end if;
  end if;

  insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
  values(actor_id,idempotency_key,'roster.person.claim.v2',existing_result);
  return existing_result;
end;
$$;

create function internal.issue_roster_invitation_v2(
  target_club_person_id uuid,intended_email text,raw_token text,
  expires_at timestamptz,idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path='' as $$
declare invite_id uuid; normalized_email text:=lower(btrim(intended_email));
begin
  if normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     or length(normalized_email)>320 then
    raise invalid_parameter_value using message='invalid_recipient';
  end if;
  invite_id:=internal.issue_roster_invite_for_actor(
    target_club_person_id,raw_token,expires_at,idempotency_key
  );
  update core.roster_invites
  set intended_email_hash=extensions.digest(normalized_email,'sha256')
  where id=invite_id and intended_email_hash is null;
  return invite_id;
end;
$$;

create function api.preview_roster_invitation(raw_token text)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.preview_roster_invitation(raw_token)$$;

create function api.claim_roster_invitation_v2(raw_token text,idempotency_key uuid)
returns jsonb language sql security invoker set search_path=''
as $$select internal.claim_roster_invitation_v2(raw_token,idempotency_key)$$;

create function api.issue_roster_invitation_v2(
  target_club_person_id uuid,intended_email text,raw_token text,
  expires_at timestamptz,idempotency_key uuid
)
returns uuid language sql security invoker set search_path=''
as $$select internal.issue_roster_invitation_v2(target_club_person_id,intended_email,raw_token,expires_at,idempotency_key)$$;

revoke all on table core.invitation_claim_reviews from public,anon,authenticated;
revoke all on function internal.preview_roster_invitation(text),internal.claim_roster_invitation_v2(text,uuid),internal.issue_roster_invitation_v2(uuid,text,text,timestamptz,uuid) from public,anon,authenticated;
revoke all on function api.preview_roster_invitation(text),api.claim_roster_invitation_v2(text,uuid),api.issue_roster_invitation_v2(uuid,text,text,timestamptz,uuid) from public,anon;
grant execute on function internal.preview_roster_invitation(text) to service_role;
grant execute on function internal.claim_roster_invitation_v2(text,uuid),internal.issue_roster_invitation_v2(uuid,text,text,timestamptz,uuid) to authenticated;
grant execute on function api.preview_roster_invitation(text) to service_role;
grant execute on function api.claim_roster_invitation_v2(text,uuid),api.issue_roster_invitation_v2(uuid,text,text,timestamptz,uuid) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260823202947_auth03_invitation_claim','greenfield','AUTH-03 local invitation preview and claim closure');
