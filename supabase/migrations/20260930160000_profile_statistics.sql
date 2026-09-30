-- PROF-05: statistics on the member profile, all about the person on the
-- profile: attendance, matches, goals, assists, cards, callup answers and
-- their app use (messages sent, active-day streak, through their own
-- account). Shown to the person and the team's leaders. Active days are
-- recorded once per day when the app is opened.

create table if not exists core.profile_activity_days (
  profile_id uuid not null references core.profiles(id) on delete cascade,
  day date not null,
  primary key(profile_id,day)
);
alter table core.profile_activity_days enable row level security;
revoke all on table core.profile_activity_days from public,anon,authenticated;

create or replace function internal.record_activity_for_actor()
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 insert into core.profile_activity_days(profile_id,day)
 values(auth.uid(),(now() at time zone 'Europe/Stockholm')::date)
 on conflict do nothing;
end$$;

create or replace function internal.get_person_statistics_for_actor(target_club_id uuid,target_team_id uuid,
 target_person_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare self boolean; account_id uuid; today date:=(now() at time zone 'Europe/Stockholm')::date;
 sport jsonb; callups jsonb; app jsonb;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.person_in_team(target_club_id,target_team_id,target_person_id)
 then raise insufficient_privilege using message='not_found'; end if;
 self:=internal.actor_owns_club_person(target_club_id,target_person_id);
 if not self and not internal.actor_leads_team(target_club_id,target_team_id)
 then raise insufficient_privilege using message='not_found'; end if;

 -- Attendance: the same participation rule as the attendance summary.
 select jsonb_build_object(
   'trainings_total',count(*) filter (where event_row.event_type='training'),
   'trainings_attended',count(*) filter (where event_row.event_type='training'
     and fact.status in ('present','late','partial')),
   'matches_total',count(*) filter (where event_row.event_type='match'),
   'matches_played',count(*) filter (where event_row.event_type='match'
     and fact.status in ('present','late','partial')))
 into sport
 from (
  select callup.event_id from core.callups callup
  where callup.club_id=target_club_id and callup.club_person_id=target_person_id and callup.state<>'cancelled'
  union
  select fact.event_id from core.attendance_facts fact
  where fact.club_id=target_club_id and fact.club_person_id=target_person_id and fact.status<>'unknown'
 ) participation
 join core.events event_row on event_row.id=participation.event_id and event_row.club_id=target_club_id
 left join core.attendance_facts fact on fact.event_id=participation.event_id
  and fact.club_person_id=target_person_id and fact.club_id=target_club_id
 where event_row.owning_team_id=target_team_id and event_row.state<>'cancelled' and event_row.starts_at<now();

 -- Match facts for the team's own side.
 sport:=sport||(select jsonb_build_object(
   'goals',count(*) filter (where match_fact.fact_type='goal' and match_fact.club_person_id=target_person_id),
   'assists',count(*) filter (where match_fact.fact_type='goal' and match_fact.secondary_club_person_id=target_person_id),
   'cards',count(*) filter (where match_fact.fact_type='card' and match_fact.club_person_id=target_person_id))
  from core.match_facts match_fact
  join core.events event_row on event_row.id=match_fact.event_id and event_row.owning_team_id=target_team_id
  where match_fact.club_id=target_club_id and match_fact.state='active'
   and coalesce(match_fact.side,'us')='us'
   and target_person_id in (match_fact.club_person_id,match_fact.secondary_club_person_id));

 -- Callup answers: first answer per callup, measured from when it was sent.
 select jsonb_build_object(
   'received',count(*),
   'accepted',count(*) filter (where callup.state='accepted'),
   'declined',count(*) filter (where callup.state='declined'),
   'answered',count(first_answer.created_at),
   'avg_response_minutes',round(avg(extract(epoch from first_answer.created_at-callup.sent_at)/60)
     filter (where first_answer.created_at is not null)))
 into callups
 from core.callups callup
 join core.events event_row on event_row.id=callup.event_id and event_row.owning_team_id=target_team_id
 left join lateral (select min(response.created_at) as created_at from core.callup_responses response
  where response.callup_id=callup.id) first_answer on true
 where callup.club_id=target_club_id and callup.club_person_id=target_person_id
  and callup.state<>'cancelled' and callup.sent_at is not null;

 -- App use of the person on the profile, through their own account.
 select link.profile_id into account_id from core.person_account_links link
 where link.club_person_id=target_person_id and link.club_id=target_club_id and link.state='active'
 order by link.created_at desc limit 1;
 if account_id is not null then
  with days as (
   select day, day-(row_number() over (order by day))::int as run
   from core.profile_activity_days where profile_id=account_id
  ), runs as (
   select min(day) as first_day,max(day) as last_day,count(*) as length from days group by run
  )
  select jsonb_build_object(
    'messages_sent',(select count(*) from core.messages message
      where message.sender_profile_id=account_id and message.state='sent'),
    'active_days_30',(select count(*) from core.profile_activity_days activity
      where activity.profile_id=account_id and activity.day>today-30),
    'current_streak',coalesce((select length from runs where last_day>=today-1 order by last_day desc limit 1),0),
    'longest_streak',coalesce((select max(length) from runs),0))
  into app;
 end if;

 return jsonb_strip_nulls(jsonb_build_object(
  'is_self',self,'sport',sport,'callups',callups,'app',app));
end$$;

create or replace function api.record_activity() returns void language sql security invoker
 set search_path='' as $$ select internal.record_activity_for_actor() $$;
create or replace function api.get_person_statistics(target_club_id uuid,target_team_id uuid,target_person_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select internal.get_person_statistics_for_actor(target_club_id,target_team_id,target_person_id) $$;

revoke all on function internal.record_activity_for_actor(),
 internal.get_person_statistics_for_actor(uuid,uuid,uuid),
 api.record_activity(),api.get_person_statistics(uuid,uuid,uuid)
from public,anon,authenticated;
grant execute on function internal.record_activity_for_actor(),
 internal.get_person_statistics_for_actor(uuid,uuid,uuid),
 api.record_activity(),api.get_person_statistics(uuid,uuid,uuid)
to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20260930160000_profile_statistics','greenfield',
 'PROF-05 member profile statistics (all about the person on the profile) and active-day tracking'
where not exists(select 1 from internal.migration_provenance
 where migration_name='20260930160000_profile_statistics');
notify pgrst,'reload schema';
