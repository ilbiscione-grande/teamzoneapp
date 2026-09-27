-- TEAM-06 follow-up, per product decision: a target team could grant
-- cross-team representation to any player in the club unilaterally. Two
-- changes:
-- (1) A player's own team must first mark them available for
--     representation (does not commit them to any specific team -- purely
--     an opt-in pool other teams may pick candidates from).
-- (2) A representation a target team creates from that pool now starts
--     'pending' (the 'pending'/'rejected' states already existed in the
--     original check constraint but were never used) and only becomes
--     'active' once the player's own team approves it. The home team can
--     also reject it. Either way, "my player may represent someone" never
--     means "that team must use them", and using them still needs my
--     team's sign-off.

alter table core.club_people
  add column representation_available boolean not null default false;

alter table core.play_eligibilities
  add column home_team_id uuid,
  add constraint play_eligibilities_home_team_fk
    foreign key (home_team_id, club_id) references core.teams(id, club_id);

create function internal.set_representation_available_for_actor(
  target_club_id uuid,
  target_team_id uuid,
  target_club_person_id uuid,
  available boolean,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  person core.club_people%rowtype;
  existing_result jsonb;
  new_revision bigint;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  if not internal.actor_has_capability(
      target_club_id, target_team_id, 'club.memberships.manage'
    )
    and not internal.actor_has_capability(
      target_club_id, target_team_id, 'team.roster.manage'
    )
  then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'roster.person.representation_available.set.v1'
    and internal.command_deduplication.idempotency_key =
      set_representation_available_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result ->> 'revision')::bigint;
  end if;

  select * into person
  from core.club_people
  where id = target_club_person_id
    and club_id = target_club_id
    and status = 'active'
  for update;
  if person.id is null or not exists (
    select 1
    from core.team_assignments assignment
    where assignment.club_id = target_club_id
      and assignment.team_id = target_team_id
      and assignment.club_person_id = person.id
      and assignment.state = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
  ) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if person.revision <> expected_revision then
    raise serialization_failure using message = 'stale_revision';
  end if;

  update core.club_people
  set representation_available = available,
      revision = revision + 1
  where id = person.id
  returning revision into new_revision;

  insert into internal.command_deduplication(
    actor_profile_id, idempotency_key, command_type, result
  ) values (
    actor_id, idempotency_key,
    'roster.person.representation_available.set.v1',
    jsonb_build_object('revision', new_revision)
  );
  insert into audit.command_events(
    club_id, actor_profile_id, command_type, aggregate_type, aggregate_id,
    aggregate_revision, metadata
  ) values (
    target_club_id, actor_id,
    'roster.person.representation_available.set.v1',
    'club_person', person.id, new_revision,
    jsonb_build_object('team_id', target_team_id, 'available', available)
  );
  return new_revision;
end;
$$;

create or replace function internal.create_play_eligibility_for_actor(
  target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
  eligibility_kind text,validity_kind text,starts_at timestamptz,ends_at timestamptz,
  season_ends_on date,review_due_at timestamptz,source_note text,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); eligibility_id uuid; existing jsonb; home_team_id uuid;
  representation_available boolean;
  effective_end timestamptz:=coalesce(ends_at,review_due_at);
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.play_eligibility.create.v1'
  and internal.command_deduplication.idempotency_key=create_play_eligibility_for_actor.idempotency_key;
 if existing is not null then return (existing->>'eligibility_id')::uuid; end if;
 select assignment.team_id into home_team_id from core.team_assignments assignment
 where assignment.club_id=target_club_id and assignment.club_person_id=target_club_person_id
   and assignment.state='active' and assignment.starts_at<=starts_at
   and (assignment.ends_at is null or assignment.ends_at>starts_at)
 order by assignment.starts_at desc limit 1;
 select person.representation_available into representation_available
 from core.club_people person where person.id=target_club_person_id and person.club_id=target_club_id;
 if home_team_id is null or home_team_id=target_team_id
   or coalesce(representation_available,false)=false
   or not exists(select 1 from core.teams where id=target_team_id and club_id=target_club_id and status='active')
   or eligibility_kind not in ('development','dispensation','loan','guest')
   or validity_kind not in ('season','fixed','indefinite')
   or starts_at>now()+interval '366 days' or length(btrim(source_note)) not between 2 and 80
   or (validity_kind='season' and (ends_at is null or season_ends_on is null or ends_at::date<>season_ends_on or review_due_at is not null))
   or (validity_kind='fixed' and (ends_at is null or season_ends_on is not null or review_due_at is not null))
   or (validity_kind='indefinite' and (ends_at is not null or season_ends_on is not null or review_due_at is null))
   or effective_end<=starts_at or effective_end>starts_at+interval '2 years'
 then raise invalid_parameter_value using message='invalid_input'; end if;
 perform pg_advisory_xact_lock(hashtextextended(target_club_id::text||':'||target_team_id::text||':'||target_club_person_id::text,0));
 if exists(select 1 from core.play_eligibilities current_row
   where current_row.club_id=target_club_id and current_row.team_id=target_team_id
     and current_row.club_person_id=target_club_person_id and current_row.state in ('pending','active')
     and tstzrange(current_row.starts_at,coalesce(current_row.ends_at,current_row.review_due_at),'[)')
       && tstzrange(starts_at,effective_end,'[)'))
 then raise exclusion_violation using message='overlapping_play_eligibility'; end if;
 insert into core.play_eligibilities(club_id,team_id,home_team_id,club_person_id,kind,source_club_id,source,
   state,starts_at,ends_at,validity_kind,season_ends_on,review_due_at,created_by)
 values(target_club_id,target_team_id,home_team_id,target_club_person_id,eligibility_kind,
   case when eligibility_kind in ('loan','guest') then target_club_id else null end,btrim(source_note),
   'pending',starts_at,ends_at,validity_kind,season_ends_on,review_due_at,actor_id)
 returning id into eligibility_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.play_eligibility.create.v1',jsonb_build_object('eligibility_id',eligibility_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'roster.play_eligibility.create.v1','play_eligibility',eligibility_id,1,
  jsonb_build_object('home_team_id',home_team_id,'target_team_id',target_team_id,'validity_kind',validity_kind));
 return eligibility_id;
end $$;

create function internal.decide_play_eligibility_for_actor(
  target_eligibility_id uuid,
  approve boolean,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  eligibility core.play_eligibilities%rowtype;
  existing_result jsonb;
  new_revision bigint;
begin
  if actor_id is null then
    raise insufficient_privilege using message = 'unauthenticated';
  end if;
  select result into existing_result
  from internal.command_deduplication
  where actor_profile_id = actor_id
    and command_type = 'roster.play_eligibility.decide.v1'
    and internal.command_deduplication.idempotency_key =
      decide_play_eligibility_for_actor.idempotency_key;
  if existing_result is not null then
    return (existing_result ->> 'revision')::bigint;
  end if;

  select * into eligibility
  from core.play_eligibilities
  where id = target_eligibility_id
  for update;
  if eligibility.id is null or eligibility.home_team_id is null or not (
      internal.actor_has_capability(
        eligibility.club_id, eligibility.home_team_id, 'club.memberships.manage'
      )
      or internal.actor_has_capability(
        eligibility.club_id, eligibility.home_team_id, 'team.roster.manage'
      )
    )
  then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if eligibility.revision <> expected_revision then
    raise serialization_failure using message = 'stale_revision';
  end if;
  if eligibility.state <> 'pending' then
    raise check_violation using message = 'invalid_transition';
  end if;

  update core.play_eligibilities
  set state = case when approve then 'active' else 'rejected' end,
    revision = revision + 1
  where id = eligibility.id
  returning revision into new_revision;

  insert into internal.command_deduplication(
    actor_profile_id, idempotency_key, command_type, result
  ) values (
    actor_id, idempotency_key, 'roster.play_eligibility.decide.v1',
    jsonb_build_object('revision', new_revision)
  );
  insert into audit.command_events(
    club_id, actor_profile_id, command_type, aggregate_type, aggregate_id,
    aggregate_revision, metadata
  ) values (
    eligibility.club_id, actor_id, 'roster.play_eligibility.decide.v1',
    'play_eligibility', eligibility.id, new_revision,
    jsonb_build_object(
      'approve', approve, 'target_team_id', eligibility.team_id,
      'home_team_id', eligibility.home_team_id
    )
  );
  return new_revision;
end;
$$;

drop function if exists internal.list_play_eligibilities_for_actor(uuid, uuid);
drop function if exists api.list_play_eligibilities(uuid, uuid);

create function internal.list_play_eligibilities_for_actor(target_club_id uuid,target_team_id uuid)
returns table(eligibility_id uuid,club_person_id uuid,person_name text,eligibility_team_id uuid,target_team_name text,
  home_team_id uuid,home_team_name text,
  eligibility_kind text,validity_kind text,state text,starts_at timestamptz,ends_at timestamptz,
  season_ends_on date,review_due_at timestamptz,revision bigint,can_decide boolean)
language plpgsql stable security definer set search_path=''
as $$ begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'team.roster.view')
   and not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
 then raise insufficient_privilege using message='not_found'; end if;
 return query select eligibility.id,person.id,person.display_name,team.id,team.name,
   eligibility.home_team_id,home_team.name,
   eligibility.kind,eligibility.validity_kind,
   case when eligibility.state='active' and coalesce(eligibility.ends_at,eligibility.review_due_at)<=now()
     then case when eligibility.validity_kind='indefinite' then 'review_due' else 'ended' end
     else eligibility.state end,
   eligibility.starts_at,eligibility.ends_at,eligibility.season_ends_on,eligibility.review_due_at,eligibility.revision,
   eligibility.state='pending' and (
     internal.actor_has_capability(target_club_id,eligibility.home_team_id,'club.memberships.manage')
     or internal.actor_has_capability(target_club_id,eligibility.home_team_id,'team.roster.manage')
   )
 from core.play_eligibilities eligibility
 join core.club_people person on person.id=eligibility.club_person_id and person.club_id=eligibility.club_id
 join core.teams team on team.id=eligibility.team_id and team.club_id=eligibility.club_id
 left join core.teams home_team on home_team.id=eligibility.home_team_id and home_team.club_id=eligibility.club_id
 where eligibility.club_id=target_club_id
   and (eligibility.team_id=target_team_id or eligibility.home_team_id=target_team_id)
 order by (eligibility.state='pending') desc,(eligibility.state='active') desc,
   coalesce(eligibility.ends_at,eligibility.review_due_at) desc,person.display_name;
end $$;

create function api.list_play_eligibilities(target_club_id uuid,target_team_id uuid)
returns table(eligibility_id uuid,club_person_id uuid,person_name text,eligibility_team_id uuid,target_team_name text,
  home_team_id uuid,home_team_name text,
  eligibility_kind text,validity_kind text,state text,starts_at timestamptz,ends_at timestamptz,
  season_ends_on date,review_due_at timestamptz,revision bigint,can_decide boolean)
language sql stable security invoker set search_path=''
as $$ select * from internal.list_play_eligibilities_for_actor(target_club_id,target_team_id) $$;

create or replace function internal.list_play_eligibility_candidates_for_actor(
  target_club_id uuid,
  target_team_id uuid
)
returns table(
  club_person_id uuid,
  display_name text,
  age_class text,
  safeguarding_required boolean,
  team_id uuid,
  team_name text,
  assignment_state text
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null then
    raise insufficient_privilege using message='unauthenticated';
  end if;
  if not internal.actor_has_capability(
    target_club_id,target_team_id,'club.memberships.manage'
  ) then
    raise insufficient_privilege using message='not_found';
  end if;
  if not exists(
    select 1 from core.teams team
    where team.id=target_team_id and team.club_id=target_club_id
      and team.status='active'
  ) then
    raise insufficient_privilege using message='not_found';
  end if;

  return query
  select person.id,person.display_name,
    coalesce(person.birth_year::text,person.age_class),
    person.safeguarding_required,assignment.team_id,team.name,assignment.state
  from core.team_assignments assignment
  join core.club_people person
    on person.id=assignment.club_person_id and person.club_id=assignment.club_id
  join core.teams team
    on team.id=assignment.team_id and team.club_id=assignment.club_id
  where assignment.club_id=target_club_id
    and assignment.team_id<>target_team_id
    and assignment.state='active'
    and assignment.starts_at<=now()
    and (assignment.ends_at is null or assignment.ends_at>now())
    and person.status='active'
    and person.representation_available=true
    and team.status='active'
  order by person.display_name,team.name,person.id;
end
$$;

create function api.set_representation_available(
  target_club_id uuid,
  target_team_id uuid,
  target_club_person_id uuid,
  available boolean,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language sql
security invoker
set search_path = ''
as $$
  select internal.set_representation_available_for_actor(
    target_club_id,target_team_id,target_club_person_id,available,
    expected_revision,idempotency_key
  )
$$;

create function api.decide_play_eligibility(
  target_eligibility_id uuid,
  approve boolean,
  expected_revision bigint,
  idempotency_key uuid
)
returns bigint
language sql
security invoker
set search_path = ''
as $$
  select internal.decide_play_eligibility_for_actor(
    target_eligibility_id,approve,expected_revision,idempotency_key
  )
$$;

revoke all on function internal.set_representation_available_for_actor(uuid,uuid,uuid,boolean,bigint,uuid),
  internal.decide_play_eligibility_for_actor(uuid,boolean,bigint,uuid),
  internal.list_play_eligibilities_for_actor(uuid,uuid)
  from public,anon,authenticated;
grant execute on function internal.set_representation_available_for_actor(uuid,uuid,uuid,boolean,bigint,uuid),
  internal.decide_play_eligibility_for_actor(uuid,boolean,bigint,uuid),
  internal.list_play_eligibilities_for_actor(uuid,uuid)
  to authenticated;
revoke all on function api.set_representation_available(uuid,uuid,uuid,boolean,bigint,uuid),
  api.decide_play_eligibility(uuid,boolean,bigint,uuid),
  api.list_play_eligibilities(uuid,uuid)
  from public,anon;
grant execute on function api.set_representation_available(uuid,uuid,uuid,boolean,bigint,uuid),
  api.decide_play_eligibility(uuid,boolean,bigint,uuid),
  api.list_play_eligibilities(uuid,uuid)
  to authenticated;

insert into internal.migration_provenance(
  migration_name, source_kind, source_reference
) values (
  '20260927140000_team06_representation_availability_and_approval',
  'greenfield',
  'TEAM-06 product decision: home team opts a player in, target team proposes, home team approves'
);

notify pgrst, 'reload schema';
