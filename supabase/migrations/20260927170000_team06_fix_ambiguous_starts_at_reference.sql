-- Fix a pre-existing plpgsql bug (present since the original TEAM-06
-- migration, inherited into the representation-approval rewrite): the
-- `starts_at` parameter shares its name with a `starts_at` column on both
-- core.team_assignments and core.play_eligibilities. Two queries in this
-- function reference the bare parameter inside a scope where those columns
-- are also visible, which plpgsql's default variable_conflict=error setting
-- rejects outright as "column reference is ambiguous" -- so every
-- create_play_eligibility_for_actor call has always failed at runtime.
-- Fixed by copying the parameter into a distinctly-named local variable
-- before it's used inside any query.

create or replace function internal.create_play_eligibility_for_actor(
  target_club_id uuid,target_team_id uuid,target_club_person_id uuid,
  eligibility_kind text,validity_kind text,starts_at timestamptz,ends_at timestamptz,
  season_ends_on date,review_due_at timestamptz,source_note text,idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=''
as $$
declare actor_id uuid:=auth.uid(); eligibility_id uuid; existing jsonb; home_team_id uuid;
  representation_available boolean;
  requested_starts_at timestamptz:=starts_at;
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
   and assignment.state='active' and assignment.starts_at<=requested_starts_at
   and (assignment.ends_at is null or assignment.ends_at>requested_starts_at)
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
       && tstzrange(requested_starts_at,effective_end,'[)'))
 then raise exclusion_violation using message='overlapping_play_eligibility'; end if;
 insert into core.play_eligibilities(club_id,team_id,home_team_id,club_person_id,kind,source_club_id,source,
   state,starts_at,ends_at,validity_kind,season_ends_on,review_due_at,created_by)
 values(target_club_id,target_team_id,home_team_id,target_club_person_id,eligibility_kind,
   case when eligibility_kind in ('loan','guest') then target_club_id else null end,btrim(source_note),
   'pending',requested_starts_at,ends_at,validity_kind,season_ends_on,review_due_at,actor_id)
 returning id into eligibility_id;
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'roster.play_eligibility.create.v1',jsonb_build_object('eligibility_id',eligibility_id));
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_club_id,actor_id,'roster.play_eligibility.create.v1','play_eligibility',eligibility_id,1,
  jsonb_build_object('home_team_id',home_team_id,'target_team_id',target_team_id,'validity_kind',validity_kind));
 return eligibility_id;
end $$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260927170000_team06_fix_ambiguous_starts_at_reference','greenfield','TEAM-06 fix pre-existing ambiguous starts_at column reference');

notify pgrst,'reload schema';
