-- 1. One attendance-rate rule everywhere: the rate is attended ÷ registered
--    among the people who were EXPECTED (called, or everyone when the event
--    used no callups — internal.attendance_is_expected). Attendance without a
--    callup no longer inflates the rate; it is reported separately as
--    "extra". Unregistered attendance is not counted at all.
--    Applies to the event follow-up (incl. team average and trend), profile
--    statistics, the participant attendance summary and team statistics.
-- 2. Callup corrections after the fact for squad managers: change the answer
--    (accepted / declined / no answer), add a callup someone never got, or
--    remove one. No notifications are sent; every change is audited.

-- Event follow-up summary -----------------------------------------------------
create or replace function internal.event_attendance_summary(target_event_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 with called as(
  select c.club_person_id,c.state from core.callups c where c.event_id=target_event_id and c.state<>'cancelled'
 ),facts as(
  select a.club_person_id,a.status,a.minutes,
   (not exists(select 1 from called) or exists(select 1 from called c where c.club_person_id=a.club_person_id)) as expected
  from core.attendance_facts a where a.event_id=target_event_id
 ),counts as(
  select
   (select count(*) from called) called,
   (select count(*) from called where state='accepted') accepted,
   (select count(*) from called where state='declined') declined,
   (select count(*) from called where state='pending') pending,
   (select count(*) from facts where expected and status='present') present,
   (select count(*) from facts where expected and status='late') late,
   (select count(*) from facts where expected and status='partial') partial,
   (select count(*) from facts where expected and status='absent') absent,
   (select count(*) from facts where expected and status<>'unknown') registered,
   (select count(*) from facts where not expected and status in('present','late','partial')) extra,
   (select round(avg(minutes)) from facts where expected and status='late') late_minutes,
   (select count(*) from called c where not exists(select 1 from facts f where f.club_person_id=c.club_person_id and f.status<>'unknown')) unregistered
 )
 select jsonb_build_object('called',called,'accepted',accepted,'declined',declined,'pending',pending,
  'present',present,'late',late,'partial',partial,'absent',absent,'registered',registered,
  'extra',extra,'unregistered',unregistered,'late_minutes_avg',late_minutes,
  'attendance_rate',case when registered=0 then null
   else round(100.0*(present+late+partial)/registered,1) end,
  'response_rate',case when called=0 then null else round(100.0*(accepted+declined)/called,1) end)
 from counts
$$;

-- Profile statistics (same body as before, new participation rule) ----------
create or replace function internal.get_person_statistics_for_actor(target_club_id uuid, target_team_id uuid, target_person_id uuid)
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

 -- Totals = registered attendance at events where the person was expected;
 -- attendance without a callup is reported as *_extra.
 select jsonb_build_object(
   'trainings_total',count(*) filter (where event_row.event_type='training' and expected),
   'trainings_attended',count(*) filter (where event_row.event_type='training' and expected and attended),
   'trainings_extra',count(*) filter (where event_row.event_type='training' and not expected and attended),
   'matches_total',count(*) filter (where event_row.event_type='match' and expected),
   'matches_played',count(*) filter (where event_row.event_type='match' and expected and attended),
   'matches_extra',count(*) filter (where event_row.event_type='match' and not expected and attended))
 into sport
 from (
  select fact.event_id, fact.status in('present','late','partial') as attended,
   internal.attendance_is_expected(fact.event_id,fact.club_person_id) as expected
  from core.attendance_facts fact
  where fact.club_id=target_club_id and fact.club_person_id=target_person_id
   and fact.status in('present','late','partial','absent')
 ) fact
 join core.events event_row on event_row.id=fact.event_id and event_row.club_id=target_club_id
 where event_row.owning_team_id=target_team_id and event_row.state<>'cancelled' and event_row.starts_at<now()
  and (fact.expected or fact.attended);

 sport:=sport||(select jsonb_build_object(
   'goals',count(*) filter (where match_fact.fact_type='goal' and match_fact.club_person_id=target_person_id),
   'assists',count(*) filter (where match_fact.fact_type='goal' and match_fact.secondary_club_person_id=target_person_id),
   'cards',count(*) filter (where match_fact.fact_type='card' and match_fact.club_person_id=target_person_id))
  from core.match_facts match_fact
  join core.events event_row on event_row.id=match_fact.event_id and event_row.owning_team_id=target_team_id
  where match_fact.club_id=target_club_id and match_fact.state='active'
   and coalesce(match_fact.side,'us')='us'
   and target_person_id in (match_fact.club_person_id,match_fact.secondary_club_person_id));

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

-- Participant details summary (same columns, new rule) ------------------------
create or replace function internal.get_person_attendance_summary_for_actor(target_club_id uuid, target_team_id uuid, target_club_person_id uuid)
returns table(trainings_total integer, trainings_attended integer, matches_total integer, matches_played integer)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_has_capability(target_club_id,target_team_id,'club.memberships.manage')
  and not internal.actor_owns_club_person(target_club_id,target_club_person_id)
 then raise insufficient_privilege using message='not_found'; end if;
 return query
 select
  count(*) filter (where event_row.event_type='training')::int,
  count(*) filter (where event_row.event_type='training' and fact.status in('present','late','partial'))::int,
  count(*) filter (where event_row.event_type='match')::int,
  count(*) filter (where event_row.event_type='match' and fact.status in('present','late','partial'))::int
 from core.attendance_facts fact
 join core.events event_row on event_row.id=fact.event_id and event_row.club_id=target_club_id
 where fact.club_id=target_club_id and fact.club_person_id=target_club_person_id
  and fact.status in('present','late','partial','absent')
  and internal.attendance_is_expected(fact.event_id,fact.club_person_id)
  and event_row.owning_team_id=target_team_id and event_row.state<>'cancelled' and event_row.starts_at<now();
end$$;

-- Team statistics (Laget → Statistik) -----------------------------------------
create or replace function internal.get_team_statistics_for_actor(target_team_id uuid, from_at timestamptz, to_at timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare club uuid; tz text; result jsonb;
begin
 select team.club_id, club_row.default_timezone into club, tz
 from core.teams team join core.clubs club_row on club_row.id = team.club_id
 where team.id = target_team_id;
 if auth.uid() is null or club is null or not (
   internal.actor_has_capability(club, target_team_id, 'event.attendance.manage')
   or internal.actor_has_capability(club, target_team_id, 'event.manage')
   or internal.actor_has_capability(club, target_team_id, 'team.roster.manage')) then
  raise insufficient_privilege using message = 'not_found';
 end if;
 if from_at is null or to_at is null or to_at <= from_at or to_at - from_at > interval '400 days' then
  raise invalid_parameter_value using message = 'invalid_period';
 end if;

 with events as (
  select event_row.id,
   case when event_row.event_type in ('training', 'match') then event_row.event_type else 'other' end as kind,
   event_row.starts_at
  from core.events event_row
  join core.event_teams relation on relation.event_id = event_row.id and relation.club_id = event_row.club_id
   and relation.team_id = target_team_id
  where event_row.club_id = club and event_row.state in ('scheduled', 'completed')
   and event_row.starts_at >= from_at and event_row.starts_at < least(to_at, now())
 ), roster as (
  select assignment.club_person_id as person_id, person.display_name as name,
   case when bool_or(assignment.role_package = 'player') then 'player' else 'leader' end as role
  from core.assignments assignment
  join core.club_people person on person.id = assignment.club_person_id and person.club_id = assignment.club_id
  where assignment.club_id = club and assignment.team_id = target_team_id and assignment.state = 'active'
   and assignment.role_package in ('player', 'leader') and person.status = 'active'
  group by assignment.club_person_id, person.display_name
 ), raw_facts as (
  select fact.club_person_id as person_id, ev.kind, ev.starts_at, fact.status,
   fact.status in ('present', 'late', 'partial') as present_like,
   internal.attendance_is_expected(fact.event_id, fact.club_person_id) as expected
  from core.attendance_facts fact
  join events ev on ev.id = fact.event_id
  join roster on roster.person_id = fact.club_person_id
  where fact.club_id = club and fact.status in ('present', 'late', 'partial', 'absent')
 ), facts as (
  select person_id, kind, starts_at, status,
   expected and present_like as attended,
   expected as counted,
   not expected and present_like as extra
  from raw_facts
 ), calls as (
  select callup.club_person_id as person_id, callup.state
  from core.callups callup
  join events ev on ev.id = callup.event_id
  join roster on roster.person_id = callup.club_person_id
  where callup.club_id = club and callup.state in ('pending', 'accepted', 'declined')
 ), player_facts as (
  select facts.* from facts join roster on roster.person_id = facts.person_id and roster.role = 'player'
 )
 select jsonb_build_object(
  'team_id', target_team_id, 'from', from_at, 'to', to_at, 'timezone', tz,
  'events', jsonb_build_object(
   'total', (select count(*) from events),
   'training', (select count(*) from events where kind = 'training'),
   'match', (select count(*) from events where kind = 'match'),
   'other', (select count(*) from events where kind = 'other')),
  -- Team rates are about the players; leaders are listed separately.
  'attendance_rate', (select round(100.0 * count(*) filter (where attended) / nullif(count(*) filter (where counted), 0), 1) from player_facts),
  'training_rate', (select round(100.0 * count(*) filter (where attended) / nullif(count(*) filter (where counted), 0), 1) from player_facts where kind = 'training'),
  'match_rate', (select round(100.0 * count(*) filter (where attended) / nullif(count(*) filter (where counted), 0), 1) from player_facts where kind = 'match'),
  'response_rate', (select round(100.0 * count(*) filter (where state in ('accepted', 'declined')) / nullif(count(*), 0), 1)
   from calls join roster on roster.person_id = calls.person_id and roster.role = 'player'),
  'late', (select count(*) from player_facts where counted and status = 'late'),
  'extra', (select count(*) from player_facts where extra),
  'months', coalesce((select jsonb_agg(month_row order by month_row->>'month') from (
   select jsonb_build_object(
    'month', to_char(date_trunc('month', starts_at at time zone tz), 'YYYY-MM'),
    'attendance_rate', round(100.0 * count(*) filter (where attended) / nullif(count(*) filter (where counted), 0), 1),
    'training_rate', round(100.0 * count(*) filter (where attended and kind = 'training')
      / nullif(count(*) filter (where counted and kind = 'training'), 0), 1),
    'match_rate', round(100.0 * count(*) filter (where attended and kind = 'match')
      / nullif(count(*) filter (where counted and kind = 'match'), 0), 1)) as month_row
   from player_facts where counted
   group by date_trunc('month', starts_at at time zone tz)) months), '[]'::jsonb),
  'people', coalesce((select jsonb_agg(jsonb_build_object(
    'person_id', roster.person_id, 'name', roster.name, 'role', roster.role,
    'attended', coalesce(agg.attended, 0), 'counted', coalesce(agg.counted, 0),
    'extra', coalesce(agg.extra, 0),
    'trainings_attended', coalesce(agg.trainings_attended, 0), 'trainings_counted', coalesce(agg.trainings_counted, 0),
    'matches_attended', coalesce(agg.matches_attended, 0), 'matches_counted', coalesce(agg.matches_counted, 0),
    'late', coalesce(agg.late, 0),
    'callups', coalesce(call_agg.received, 0), 'answered', coalesce(call_agg.answered, 0))
    order by roster.role desc, roster.name)
   from roster
   left join (
    select person_id,
     count(*) filter (where attended) as attended, count(*) filter (where counted) as counted,
     count(*) filter (where extra) as extra,
     count(*) filter (where attended and kind = 'training') as trainings_attended,
     count(*) filter (where counted and kind = 'training') as trainings_counted,
     count(*) filter (where attended and kind = 'match') as matches_attended,
     count(*) filter (where counted and kind = 'match') as matches_counted,
     count(*) filter (where counted and status = 'late') as late
    from facts group by person_id) agg on agg.person_id = roster.person_id
   left join (
    select person_id, count(*) as received, count(*) filter (where state in ('accepted', 'declined')) as answered
    from calls group by person_id) call_agg on call_agg.person_id = roster.person_id), '[]'::jsonb)
 ) into result;
 return result;
end$$;

-- Callup corrections ----------------------------------------------------------
-- new_state: accepted | declined | pending (no answer) | none (no callup).
create function internal.correct_callup_for_actor(target_event_id uuid, target_person_id uuid, new_state text,
 reason_code text, reason_text text, expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); event_row core.events%rowtype; callup core.callups%rowtype;
 sent_revision uuid; new_revision bigint; response_value text; clean_text text:=nullif(btrim(reason_text),'');
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or event_row.archived_at is not null or event_row.state='cancelled'
  or not internal.actor_can_manage_squad(target_event_id) then
  raise insufficient_privilege using message='not_found';
 end if;
 if new_state not in ('accepted','declined','pending','none') then
  raise invalid_parameter_value using message='invalid_state';
 end if;
 if new_state='declined' then
  if reason_code not in('illness','injury','unavailable','transport','other')
   or(reason_code='other' and(clean_text is null or length(clean_text) not between 2 and 500))
   or(reason_code<>'other' and clean_text is not null)
  then raise invalid_parameter_value using message='invalid_decline_reason'; end if;
 elsif reason_code is not null or clean_text is not null then
  raise invalid_parameter_value using message='unexpected_decline_reason';
 end if;
 if not exists(select 1 from core.club_people where id=target_person_id and club_id=event_row.club_id) then
  raise insufficient_privilege using message='not_found';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('event-callups:'||target_event_id::text,0));
 select * into callup from core.callups where event_id=target_event_id and club_person_id=target_person_id
  and state<>'cancelled' for update;
 if coalesce(callup.revision,0)<>expected_revision then
  raise serialization_failure using message='stale_revision';
 end if;

 if callup.id is null then
  if new_state='none' then return jsonb_build_object('revision',0,'state','none'); end if;
  -- Without any callups everyone is already expected; one late callup would
  -- turn everybody else into "not called".
  select id into sent_revision from core.squad_revisions where event_id=target_event_id and state='sent'
  order by revision desc limit 1;
  if sent_revision is null then raise invalid_parameter_value using message='event_without_callups'; end if;
  insert into core.squad_members(club_id,event_id,squad_revision_id,club_person_id,selection_state,source,
   eligibility_snapshot,created_by)
  values(event_row.club_id,target_event_id,sent_revision,target_person_id,'selected','manual',
   coalesce(internal.person_eligibility_at_event(target_event_id,target_person_id),'{}'::jsonb)
    ||jsonb_build_object('corrected_after_the_fact',true),actor_id)
  on conflict(squad_revision_id,club_person_id) do nothing;
  insert into core.callups(club_id,event_id,squad_revision_id,club_person_id,state,sent_at,created_by,revision)
  values(event_row.club_id,target_event_id,sent_revision,target_person_id,new_state,now(),actor_id,1)
  returning * into callup;
  new_revision:=1;
 elsif new_state='none' then
  new_revision:=callup.revision+1;
  update core.callups set state='cancelled',cancelled_at=now(),revision=new_revision where id=callup.id;
 else
  new_revision:=callup.revision+1;
  update core.callups set state=new_state,revision=new_revision where id=callup.id;
 end if;

 if new_state in ('accepted','declined','pending') then
  response_value:=case new_state when 'pending' then 'tentative' else new_state end;
  insert into core.callup_responses(club_id,callup_id,response,decline_reason_code,decline_reason_text,
   actor_profile_id,acting_as_person_id,revision)
  values(event_row.club_id,callup.id,response_value,
   case when new_state='declined' then reason_code end,case when new_state='declined' then clean_text end,
   actor_id,target_person_id,new_revision);
 end if;
 insert into audit.command_events(club_id,actor_profile_id,acting_as_person_id,command_type,aggregate_type,
  aggregate_id,aggregate_revision,metadata)
 values(event_row.club_id,actor_id,target_person_id,'callup.corrected','callup',callup.id,new_revision,
  jsonb_build_object('event_id',target_event_id,'state',new_state,'decline_reason_code',reason_code,
   'after_event',now()>event_row.ends_at));
 return jsonb_build_object('revision',case when new_state='none' then 0 else new_revision end,'state',new_state);
end$$;

create function api.correct_callup(event_id uuid, person_id uuid, state text, decline_reason_code text,
 decline_reason_text text, expected_revision bigint)
returns jsonb language sql security invoker set search_path='' as
$$select internal.correct_callup_for_actor(event_id, person_id, state, decline_reason_code, decline_reason_text, expected_revision)$$;

revoke all on function internal.correct_callup_for_actor(uuid,uuid,text,text,text,bigint),
 api.correct_callup(uuid,uuid,text,text,text,bigint) from public, anon;
grant execute on function internal.correct_callup_for_actor(uuid,uuid,text,text,text,bigint),
 api.correct_callup(uuid,uuid,text,text,text,bigint) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261017090000_attendance_rate_expected_and_callup_corrections','greenfield',
 'Attendance rate counts only expected people (extra reported separately); callup corrections after the fact');
notify pgrst,'reload schema';
