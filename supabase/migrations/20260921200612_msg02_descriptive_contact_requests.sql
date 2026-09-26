drop function if exists api.list_contact_requests();

create function api.list_contact_requests()
returns table(
  id uuid,
  requester_name text,
  requester_affiliation text,
  reason_code text,
  request_text text,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    request.id,
    coalesce(nullif(btrim(profile.display_name), ''), 'Verifierad ledare'),
    coalesce(affiliation.label, 'Extern klubb'),
    request.reason_code,
    request.request_text,
    request.expires_at
  from core.contact_controls request
  join core.profiles profile on profile.id = request.requester_profile_id
  left join lateral (
    select string_agg(labels.label, ', ' order by labels.label) as label
    from (
      select distinct
        club.name || case
          when team.name is null then ''
          else ' · ' || team.name
        end as label
      from core.person_account_links link
      join core.assignments assignment
        on assignment.club_id = link.club_id
       and assignment.club_person_id = link.club_person_id
       and assignment.role_package = 'leader'
       and assignment.state = 'active'
       and assignment.starts_at <= now()
       and (assignment.ends_at is null or assignment.ends_at > now())
      join core.clubs club on club.id = assignment.club_id
      left join core.teams team
        on team.id = assignment.team_id
       and team.club_id = assignment.club_id
      where link.profile_id = request.requester_profile_id
        and link.state = 'active'
    ) labels
  ) affiliation on true
  where request.target_profile_id = auth.uid()
    and request.control_type = 'request'
    and request.state = 'pending'
    and request.expires_at > now()
  order by request.created_at desc;
$$;

revoke all on function api.list_contact_requests() from public, anon;
grant execute on function api.list_contact_requests() to authenticated;

insert into internal.migration_provenance (
  migration_name,
  source_kind,
  source_reference
)
values (
  '20260921200612_msg02_descriptive_contact_requests',
  'greenfield',
  'MSG-02 descriptive contact requests with server-derived leader affiliations'
);

notify pgrst, 'reload schema';
