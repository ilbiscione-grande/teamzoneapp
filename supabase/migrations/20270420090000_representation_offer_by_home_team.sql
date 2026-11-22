-- Representation: the team that did not ask decides.
--
-- Until now every representation started 'pending' for the player's own
-- (home) team to approve, also when the home team itself offered the player
-- to another team: the A team's coach then approved their own offer, and
-- the receiving team never had a say. Now:
-- (1) core.play_eligibilities.decider_team_id names the team that decides.
--     A request from the receiving team (create_play_eligibility, as before)
--     is decided by the home team; existing rows keep the home team.
-- (2) api.offer_play_eligibility: the home team offers a player to another
--     team. The offer is the home team's consent, so it also marks the
--     player available for representation; the receiving team decides.
-- (3) Deciding, the representation list and the assistant's "decide" task
--     follow decider_team_id. The list offers Approve/Reject only in the
--     deciding team's own view, so a club admin does not see them in both.
-- (4) A stale revision raises PT409 (never 40001, which PostgREST retries).

alter table core.play_eligibilities
  add column if not exists decider_team_id uuid,
  add constraint play_eligibilities_decider_team_fk
    foreign key (decider_team_id, club_id) references core.teams(id, club_id);

update core.play_eligibilities set decider_team_id = home_team_id
where decider_team_id is null and home_team_id is not null;

-- A request created through the old path is decided by the home team.
create or replace function internal.default_play_eligibility_decider()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.decider_team_id := coalesce(new.decider_team_id, new.home_team_id);
  return new;
end $$;

drop trigger if exists play_eligibilities_default_decider on core.play_eligibilities;
create trigger play_eligibilities_default_decider
  before insert on core.play_eligibilities
  for each row execute function internal.default_play_eligibility_decider();

create or replace function internal.offer_play_eligibility_for_actor(
  target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
  eligibility_kind text,validity_kind text,starts_at timestamptz,ends_at timestamptz,
  season_ends_on date,review_due_at timestamptz,source_note text,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); eligibility_id uuid; existing jsonb; home_team_id uuid;
  requested_starts_at timestamptz:=starts_at;
  effective_end timestamptz:=coalesce(ends_at,review_due_at);
  person_revision bigint;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing from internal.command_deduplication where actor_profile_id=actor_id
  and command_type='roster.play_eligibility.offer.v1'
  and internal.command_deduplication.idempotency_key=offer_play_eligibility_for_actor.idempotency_key;
 if existing is not null then return (existing->>'eligibility_id')::uuid; end if;
 select assignment.team_id into home_team_id from core.team_assignments assignment
 where assignment.club_id=target_club_id and assignment.club_person_id=target_club_person_id
   and assignment.state='active' and assignment.starts_at<=requested_starts_at
   and (assignment.ends_at is null or assignment.ends_at>requested_starts_at)
 order by assignment.starts_at desc limit 1;
 -- Only the player's own team offers its player.
 if home_team_id is null or not (
     internal.actor_has_capability(target_club_id,home_team_id,'club.memberships.manage')
     or internal.actor_has_capability(target_club_id,home_team_id,'team.roster.manage'))
 then raise insufficient_privilege using message='not_found'; end if;
 if home_team_id=target_team_id
   or not exists(select 1 from core.club_people where id=target_club_person_id and club_id=target_club_id and status='active')
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
       && tstzrange(requested_starts_at,effective_end,'[)'))
 then raise exclusion_violation using message='overlapping_play_eligibility'; end if;
 -- Offering is the home team's consent: the player becomes available.
 update core.club_people set representation_available=true, revision=revision+1
 where id=target_club_person_id and club_id=target_club_id and not representation_available
 returning revision into person_revision;
 if person_revision is not null then
   insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
   values(target_club_id,actor_id,'roster.person.representation_available.set.v1','club_person',target_club_person_id,
     person_revision,jsonb_build_object('team_id',home_team_id,'available',true));
 end if;
 insert into core.play_eligibilities(club_id,team_id,home_team_id,decider_team_id,club_person_id,kind,source_club_id,source,
   state,starts_at,ends_at,validity_kind,season_ends_on,review_due_at,created_by)
 values(target_club_id,target_team_id,home_team_id,target_team_id,target_club_person_id,eligibility_kind,
   case when eligibility_kind in ('loan','guest') then target_club_id else null end,btrim(source_note),
   'pending',requested_starts_at,ends_at,validity_kind,season_ends_on,review_due_at,actor_id)
 returning id into eligibility_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.play_eligibility.offer.v1',jsonb_build_object('eligibility_id',eligibility_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'roster.play_eligibility.offer.v1','play_eligibility',eligibility_id,1,
  jsonb_build_object('home_team_id',home_team_id,'target_team_id',target_team_id,'validity_kind',validity_kind));
 return eligibility_id;
end $$;

create or replace function api.offer_play_eligibility(target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
 eligibility_kind text,validity_kind text,starts_at timestamptz,ends_at timestamptz,season_ends_on date,
 review_due_at timestamptz,source_note text,idempotency_key uuid)
returns uuid language sql security invoker set search_path='' as $$
 select internal.offer_play_eligibility_for_actor(target_club_id,target_team_id,target_club_person_id,eligibility_kind,
   validity_kind,starts_at,ends_at,season_ends_on,review_due_at,source_note,idempotency_key)
$$;

revoke all on function internal.offer_play_eligibility_for_actor(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid)
  from public,anon,authenticated;
grant execute on function internal.offer_play_eligibility_for_actor(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid)
  to authenticated;
revoke all on function api.offer_play_eligibility(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid)
  from public,anon;
grant execute on function api.offer_play_eligibility(uuid,uuid,uuid,text,text,timestamptz,timestamptz,date,timestamptz,text,uuid)
  to authenticated;
revoke all on function internal.default_play_eligibility_decider() from public,anon,authenticated;

create or replace function internal.decide_play_eligibility_for_actor(
  target_eligibility_id uuid,approve boolean,expected_revision bigint,idempotency_key uuid
) returns bigint language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); eligibility core.play_eligibilities%rowtype; existing_result jsonb;
  new_revision bigint; decider uuid;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select result into existing_result from internal.command_deduplication
 where actor_profile_id=actor_id and command_type='roster.play_eligibility.decide.v1'
   and internal.command_deduplication.idempotency_key=decide_play_eligibility_for_actor.idempotency_key;
 if existing_result is not null then return (existing_result->>'revision')::bigint; end if;
 select * into eligibility from core.play_eligibilities where id=target_eligibility_id for update;
 decider:=coalesce(eligibility.decider_team_id,eligibility.home_team_id);
 if eligibility.id is null or decider is null or not (
     internal.actor_has_capability(eligibility.club_id,decider,'club.memberships.manage')
     or internal.actor_has_capability(eligibility.club_id,decider,'team.roster.manage'))
 then raise insufficient_privilege using message='not_found'; end if;
 if eligibility.revision<>expected_revision then
   raise sqlstate 'PT409' using message='stale_revision';
 end if;
 if eligibility.state<>'pending' then raise check_violation using message='invalid_transition'; end if;
 update core.play_eligibilities set state=case when approve then 'active' else 'rejected' end,revision=revision+1
 where id=eligibility.id returning revision into new_revision;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.play_eligibility.decide.v1',jsonb_build_object('revision',new_revision));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(eligibility.club_id,actor_id,'roster.play_eligibility.decide.v1','play_eligibility',eligibility.id,new_revision,
   jsonb_build_object('approve',approve,'target_team_id',eligibility.team_id,'home_team_id',eligibility.home_team_id,
     'decider_team_id',decider));
 return new_revision;
end $$;

-- The list gains decider_team_id, so both functions are recreated.
drop function if exists api.list_play_eligibilities(uuid,uuid);
drop function if exists internal.list_play_eligibilities_for_actor(uuid,uuid);

create function internal.list_play_eligibilities_for_actor(target_club_id uuid,target_team_id uuid)
returns table(eligibility_id uuid,club_person_id uuid,person_name text,eligibility_team_id uuid,target_team_name text,
  home_team_id uuid,home_team_name text,
  eligibility_kind text,validity_kind text,state text,starts_at timestamptz,ends_at timestamptz,
  season_ends_on date,review_due_at timestamptz,revision bigint,can_decide boolean,decider_team_id uuid)
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
   -- Only in the deciding team's own view.
   eligibility.state='pending'
     and coalesce(eligibility.decider_team_id,eligibility.home_team_id)=target_team_id and (
     internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
     or internal.actor_has_capability(target_club_id,target_team_id,'team.roster.manage')
   ),
   coalesce(eligibility.decider_team_id,eligibility.home_team_id)
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
  season_ends_on date,review_due_at timestamptz,revision bigint,can_decide boolean,decider_team_id uuid)
language sql stable security invoker set search_path=''
as $$ select * from internal.list_play_eligibilities_for_actor(target_club_id,target_team_id) $$;

revoke all on function internal.list_play_eligibilities_for_actor(uuid,uuid) from public,anon,authenticated;
grant execute on function internal.list_play_eligibilities_for_actor(uuid,uuid) to authenticated;
revoke all on function api.list_play_eligibilities(uuid,uuid) from public,anon;
grant execute on function api.list_play_eligibilities(uuid,uuid) to authenticated;

-- The assistant's "decide" task counts what this team decides.
create or replace function internal.list_my_representation_tasks_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  return coalesce((
    with my_teams as (
      select distinct team.id team_id, team.club_id
      from core.person_account_links link
      join core.assignments assignment on assignment.club_person_id = link.club_person_id
        and assignment.club_id = link.club_id and assignment.role_package = 'leader'
        and assignment.state = 'active' and assignment.starts_at <= now()
        and (assignment.ends_at is null or assignment.ends_at > now())
      join core.teams team on team.id = assignment.team_id and team.club_id = assignment.club_id
        and team.status = 'active'
      where link.profile_id = auth.uid() and link.state = 'active'
    ), tasks as (
      select mine.club_id, mine.team_id, 'decide' kind, (
        select count(*) from core.play_eligibilities eligibility
        where eligibility.club_id = mine.club_id
          and coalesce(eligibility.decider_team_id, eligibility.home_team_id) = mine.team_id
          and eligibility.state = 'pending'
          and coalesce(eligibility.ends_at, eligibility.review_due_at) > now()
      ) count
      from my_teams mine
      where internal.actor_has_capability(mine.club_id, mine.team_id, 'club.memberships.manage')
         or internal.actor_has_capability(mine.club_id, mine.team_id, 'team.roster.manage')
      union all
      select mine.club_id, mine.team_id, 'available', (
        select count(distinct person.id) from core.club_people person
        join core.team_assignments home on home.club_person_id = person.id and home.club_id = person.club_id
          and home.state = 'active' and home.starts_at <= now()
          and (home.ends_at is null or home.ends_at > now()) and home.team_id <> mine.team_id
        join core.teams home_team on home_team.id = home.team_id and home_team.status = 'active'
        where person.club_id = mine.club_id and person.status = 'active'
          and person.representation_available
          and person.representation_available_at > now() - interval '14 days'
          and not exists (select 1 from core.team_assignments own
            where own.club_person_id = person.id and own.team_id = mine.team_id and own.state = 'active'
              and own.starts_at <= now() and (own.ends_at is null or own.ends_at > now()))
          and not exists (select 1 from core.play_eligibilities eligibility
            where eligibility.club_id = mine.club_id and eligibility.team_id = mine.team_id
              and eligibility.club_person_id = person.id and eligibility.state in ('pending', 'active')
              and coalesce(eligibility.ends_at, eligibility.review_due_at) > now())
      )
      from my_teams mine
      where internal.actor_has_capability(mine.club_id, mine.team_id, 'club.memberships.manage')
    )
    select jsonb_agg(jsonb_build_object('club_id', club_id, 'team_id', team_id, 'kind', kind,
      'count', count) order by team_id, kind)
    from tasks where count > 0
  ), '[]'::jsonb);
end $$;

notify pgrst, 'reload schema';
