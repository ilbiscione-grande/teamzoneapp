-- TEAM-08: global erasure is profile-wide even when legacy/test data contains
-- more than one core.person identity for the same Auth profile.

create or replace function api.review_global_person_erasure(
  target_request_id uuid,
  reviewer_profile_id uuid,
  decision text,
  reason text
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  request_row internal.global_person_erasure_requests%rowtype;
  club_person_row record;
begin
  if current_user not in('service_role','postgres') then
    raise insufficient_privilege using message='service_role_required';
  end if;
  select * into request_row
  from internal.global_person_erasure_requests
  where id=target_request_id
  for update;
  if request_row.id is null
    or request_row.state<>'requested'
    or reviewer_profile_id=request_row.requested_by
    or decision not in('approved','rejected')
    or length(btrim(coalesce(reason,''))) not between 2 and 500
  then
    raise check_violation using message='invalid_review';
  end if;
  if decision='rejected' then
    update internal.global_person_erasure_requests
    set state='rejected',reviewed_by=reviewer_profile_id,
        reviewed_at=now(),revision=revision+1
    where id=request_row.id;
    return;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('global-profile:'||request_row.requested_by::text,0)
  );
  for club_person_row in
    select distinct person.id
    from core.club_people person
    left join core.person_account_links link
      on link.club_person_id=person.id and link.club_id=person.club_id
    where person.person_id=request_row.person_id
       or link.profile_id=request_row.requested_by
  loop
    perform internal.anonymize_club_person(
      club_person_row.id,
      reviewer_profile_id
    );
  end loop;

  update core.persons person
  set status='ended',revision=revision+1
  where person.id=request_row.person_id
     or exists(
       select 1
       from core.club_people club_person
       join core.person_account_links link
         on link.club_person_id=club_person.id
        and link.club_id=club_person.club_id
       where club_person.person_id=person.id
         and link.profile_id=request_row.requested_by
     );
  update core.profiles
  set display_name='Raderad användare',revision=revision+1
  where id=request_row.requested_by;
  update internal.global_person_erasure_requests
  set state='approved',reviewed_by=reviewer_profile_id,
      reviewed_at=now(),revision=revision+1
  where id=request_row.id;
end
$$;

revoke all on function api.review_global_person_erasure(
  uuid,uuid,text,text
) from public,anon,authenticated;
grant execute on function api.review_global_person_erasure(
  uuid,uuid,text,text
) to service_role;

-- Repair already approved/completed requests using the same profile-wide rule.
do $$
declare
  request_row record;
  club_person_row record;
begin
  for request_row in
    select request.id,request.person_id,request.requested_by,request.reviewed_by
    from internal.global_person_erasure_requests request
    where request.state in('approved','completed')
      and request.reviewed_by is not null
  loop
    for club_person_row in
      select distinct person.id
      from core.club_people person
      join core.person_account_links link
        on link.club_person_id=person.id and link.club_id=person.club_id
      where link.profile_id=request_row.requested_by
        and (
          person.provenance<>'anonymized'
          or link.state in('active','pending')
        )
    loop
      perform internal.anonymize_club_person(
        club_person_row.id,
        request_row.reviewed_by
      );
    end loop;

    update core.persons person
    set status='ended',revision=revision+1
    where exists(
      select 1
      from core.club_people club_person
      join core.person_account_links link
        on link.club_person_id=club_person.id
       and link.club_id=club_person.club_id
      where club_person.person_id=person.id
        and link.profile_id=request_row.requested_by
    ) and person.status<>'ended';

    insert into audit.command_events(
      actor_profile_id,command_type,aggregate_type,aggregate_id,reason,metadata
    ) values(
      request_row.reviewed_by,
      'person.global_erasure.profile_scope_repaired.v1',
      'global_person_erasure',request_row.id,
      'Profile-wide cleanup for fragmented person identities',
      jsonb_build_object('requested_by',request_row.requested_by)
    );
  end loop;
end
$$;

insert into internal.migration_provenance(
  migration_name,source_kind,source_reference
)
values(
  '20260913193219_team08_profile_wide_global_erasure',
  'greenfield',
  'TEAM-08 physical finding: global erasure must cover every identity linked to the Auth profile'
)
on conflict do nothing;

notify pgrst,'reload schema';
