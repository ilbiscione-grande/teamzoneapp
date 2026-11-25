-- Spelarsamtal, the first part of the individual development plan (product
-- owner, 2026-11-25): a team's leaders write down a talk with a player.
--
--   what         the day, the leaders who were there, optionally the survey
--                answer the talk starts from, the leaders' own notes, and
--                apart from them what was agreed;
--   who          the team's leaders with Säsongsplanering (development.manage,
--                module.team_development), never the player the talk is
--                about. Nothing is shared with the player or a guardian;
--   apart        the notes are kept apart from core.development_plans, which
--                the player can read. What was agreed is a column of its own,
--                so that it can be shared later without the notes;
--   kept         until a leader deletes the talk or the person is erased. A
--                talk stays when its survey answer is deleted;
--   erasure      an erased (anonymized) person's talks, survey answers and
--                survey links are deleted.

create table core.player_talks(
 id uuid primary key,
 club_id uuid not null,
 team_id uuid not null references core.teams(id) on delete cascade,
 club_person_id uuid not null references core.club_people(id) on delete cascade,
 survey_response_id uuid references core.team_survey_responses(id) on delete set null,
 talked_on date not null,
 leader_ids uuid[] not null default '{}' check(cardinality(leader_ids)<=20),
 leader_notes text not null default '' check(length(leader_notes)<=20000),
 agreed text not null default '' check(length(agreed)<=8000),
 created_by uuid not null,
 created_at timestamptz not null default now(),
 updated_by uuid not null,
 updated_at timestamptz not null default now(),
 revision bigint not null default 1 check(revision>0)
);
create index player_talks_player on core.player_talks(team_id,club_person_id,talked_on desc);
create index player_talks_person on core.player_talks(club_person_id);
create index player_talks_response on core.player_talks(survey_response_id) where survey_response_id is not null;
alter table core.player_talks enable row level security;
revoke all on core.player_talks from public,anon,authenticated;

-- The team's club for a leader who may read the talks with a player; with
-- [edit], also change them. Never the player's own.
create function internal.player_talk_club(target_team_id uuid,target_person_id uuid,edit boolean)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare club uuid;
begin
 club:=internal.team_survey_club(target_team_id,edit);
 if not exists(select 1 from core.club_people person where person.id=target_person_id and person.club_id=club)
  or internal.actor_owns_club_person(club,target_person_id) then
  raise insufficient_privilege using message='not_found'; end if;
 return club;
end$$;

create function internal.player_talk_leaders(target_team_id uuid)
returns table(person_id uuid,name text) language sql stable security definer set search_path='' as $$
 select person.id,person.display_name
 from core.club_people person join core.teams team on team.id=target_team_id and team.club_id=person.club_id
 where person.status='active' and exists(select 1 from core.assignments assignment
  where assignment.club_id=person.club_id and assignment.team_id=target_team_id
   and assignment.club_person_id=person.id and assignment.role_package='leader' and assignment.state='active'
   and assignment.starts_at<=now() and (assignment.ends_at is null or assignment.ends_at>now()))
$$;

create function internal.list_player_talks_for_actor(target_team_id uuid,target_person_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare club uuid;
begin
 club:=internal.player_talk_club(target_team_id,target_person_id,false);
 return jsonb_build_object(
  'name',(select person.display_name from core.club_people person where person.id=target_person_id),
  'can_edit',internal.tdp_can_edit(club),
  'is_player',exists(select 1 from internal.team_survey_players(target_team_id) player
   where player.person_id=target_person_id),
  'leaders',coalesce((select jsonb_agg(jsonb_build_object('person_id',leader.person_id,'name',leader.name,
    'self',internal.actor_owns_club_person(club,leader.person_id)) order by leader.name,leader.person_id)
   from internal.player_talk_leaders(target_team_id) leader),'[]'::jsonb),
  'talks',coalesce((select jsonb_agg(jsonb_build_object('id',talk.id,'talked_on',talk.talked_on,
    'response_id',response.id,'survey_title',survey.title,
    'leaders',coalesce((select jsonb_agg(jsonb_build_object('person_id',person.id,'name',person.display_name)
      order by person.display_name,person.id) from core.club_people person where person.id=any(talk.leader_ids)),'[]'::jsonb),
    'leader_notes',talk.leader_notes,'agreed',talk.agreed,
    'updated_at',talk.updated_at,'revision',talk.revision) order by talk.talked_on desc,talk.created_at desc,talk.id)
   from core.player_talks talk
   -- An answer since linked to another player is not shown.
   left join core.team_survey_responses response on response.id=talk.survey_response_id
    and response.club_person_id=talk.club_person_id
   left join core.team_surveys survey on survey.id=response.survey_id
   where talk.team_id=target_team_id and talk.club_person_id=target_person_id),'[]'::jsonb));
end$$;

-- The audit trail says that a talk was written, changed or deleted, never
-- what was written.
create function internal.player_talk_audit(talk core.player_talks,command text)
returns void language sql security definer set search_path='' as $$
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(talk.club_id,auth.uid(),command,'player_talk',talk.id,talk.revision,
  jsonb_build_object('team_id',talk.team_id,'club_person_id',talk.club_person_id))
$$;

-- A new talk when [expected_revision] is null. The caller chooses the id, so
-- a save that is sent again after a lost answer does not make a second talk.
create function internal.save_player_talk_for_actor(target_team_id uuid,target_person_id uuid,target_talk_id uuid,
 expected_revision bigint,new_talked_on date,new_leader_ids uuid[],new_response_id uuid,new_notes text,new_agreed text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare club uuid; talk core.player_talks; clean_leaders uuid[];
begin
 club:=internal.player_talk_club(target_team_id,target_person_id,true);
 if target_talk_id is null then raise invalid_parameter_value using message='invalid_talk'; end if;
 if new_talked_on is null or new_talked_on not between date '2000-01-01' and current_date+366 then
  raise invalid_parameter_value using message='invalid_date'; end if;
 if length(coalesce(new_notes,''))>20000 or length(coalesce(new_agreed,''))>8000 then
  raise invalid_parameter_value using message='text_too_long'; end if;
 perform pg_advisory_xact_lock(hashtextextended('player_talk:'||target_talk_id::text,0));
 select * into talk from core.player_talks t where t.id=target_talk_id for update;
 if talk.id is not null and (talk.team_id<>target_team_id or talk.club_person_id<>target_person_id) then
  raise insufficient_privilege using message='not_found'; end if;
 if talk.id is null and expected_revision is not null then
  raise sqlstate 'PT409' using message='stale_revision'; end if;
 if talk.id is not null and not (talk.revision is not distinct from expected_revision
   or (expected_revision is null and talk.revision=1 and talk.created_by=auth.uid())) then
  raise sqlstate 'PT409' using message='stale_revision'; end if;
 if talk.id is null and not exists(select 1 from internal.team_survey_players(target_team_id) player
   where player.person_id=target_person_id) then
  raise check_violation using message='talk_needs_player_role'; end if;
 -- The team's leaders; one who has left stays on a talk they were at.
 select coalesce(array_agg(distinct leader order by leader),'{}') into clean_leaders
 from unnest(coalesce(new_leader_ids,'{}'::uuid[])) leader where leader is not null;
 if cardinality(clean_leaders)>20 or exists(select 1 from unnest(clean_leaders) leader
   where leader<>all(coalesce(talk.leader_ids,'{}'::uuid[]))
    and leader not in(select l.person_id from internal.player_talk_leaders(target_team_id) l)) then
  raise check_violation using message='invalid_leaders'; end if;
 -- The player's own answer, in one of this team's surveys.
 if new_response_id is not null and not exists(select 1 from core.team_survey_responses response
   join core.team_surveys survey on survey.id=response.survey_id
   where response.id=new_response_id and response.club_person_id=target_person_id and survey.team_id=target_team_id) then
  raise check_violation using message='invalid_response'; end if;
 if talk.id is null then
  insert into core.player_talks(id,club_id,team_id,club_person_id,survey_response_id,talked_on,leader_ids,
   leader_notes,agreed,created_by,updated_by)
  values(target_talk_id,club,target_team_id,target_person_id,new_response_id,new_talked_on,clean_leaders,
   coalesce(new_notes,''),coalesce(new_agreed,''),auth.uid(),auth.uid()) returning * into talk;
  perform internal.player_talk_audit(talk,'player.talk.created.v1');
 else
  update core.player_talks t set survey_response_id=new_response_id,talked_on=new_talked_on,leader_ids=clean_leaders,
   leader_notes=coalesce(new_notes,''),agreed=coalesce(new_agreed,''),updated_by=auth.uid(),updated_at=now(),
   revision=t.revision+1 where t.id=talk.id returning * into talk;
 end if;
 return jsonb_build_object('id',talk.id,'revision',talk.revision,'updated_at',talk.updated_at);
end$$;

create function internal.delete_player_talk_for_actor(target_talk_id uuid,expected_revision bigint)
returns void language plpgsql security definer set search_path='' as $$
declare talk core.player_talks;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 select * into talk from core.player_talks t where t.id=target_talk_id for update;
 if talk.id is null then raise insufficient_privilege using message='not_found'; end if;
 perform internal.player_talk_club(talk.team_id,talk.club_person_id,true);
 if talk.revision is distinct from expected_revision then
  raise sqlstate 'PT409' using message='stale_revision'; end if;
 delete from core.player_talks t where t.id=talk.id;
 perform internal.player_talk_audit(talk,'player.talk.deleted.v1');
end$$;

-- An erased person's talks, survey answers and survey links go with the
-- person's name (internal.anonymize_club_person sets the provenance).
create function internal.erase_player_talks_and_surveys()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 delete from core.player_talks where club_person_id=new.id;
 delete from core.team_survey_responses where club_person_id=new.id;
 delete from core.team_survey_invites where club_person_id=new.id;
 return null;
end$$;
create trigger erase_player_talks_and_surveys after update of provenance on core.club_people
 for each row when (new.provenance='anonymized' and old.provenance is distinct from new.provenance)
 execute function internal.erase_player_talks_and_surveys();

create function api.list_player_talks(target_team_id uuid,target_person_id uuid) returns jsonb language sql stable
 security invoker set search_path='' as $$select internal.list_player_talks_for_actor(target_team_id,target_person_id)$$;
create function api.save_player_talk(target_team_id uuid,target_person_id uuid,target_talk_id uuid,
 expected_revision bigint,new_talked_on date,new_leader_ids uuid[],new_response_id uuid,new_notes text,new_agreed text)
 returns jsonb language sql security invoker set search_path='' as $$select internal.save_player_talk_for_actor(
  target_team_id,target_person_id,target_talk_id,expected_revision,new_talked_on,new_leader_ids,new_response_id,
  new_notes,new_agreed)$$;
create function api.delete_player_talk(target_talk_id uuid,expected_revision bigint) returns void language sql
 security invoker set search_path='' as $$select internal.delete_player_talk_for_actor(target_talk_id,expected_revision)$$;

revoke all on function internal.player_talk_club(uuid,uuid,boolean),internal.player_talk_leaders(uuid),
 internal.list_player_talks_for_actor(uuid,uuid),internal.player_talk_audit(core.player_talks,text),
 internal.save_player_talk_for_actor(uuid,uuid,uuid,bigint,date,uuid[],uuid,text,text),
 internal.delete_player_talk_for_actor(uuid,bigint),internal.erase_player_talks_and_surveys(),
 api.list_player_talks(uuid,uuid),api.save_player_talk(uuid,uuid,uuid,bigint,date,uuid[],uuid,text,text),
 api.delete_player_talk(uuid,bigint)
 from public,anon,authenticated;
grant execute on function internal.list_player_talks_for_actor(uuid,uuid),
 internal.save_player_talk_for_actor(uuid,uuid,uuid,bigint,date,uuid[],uuid,text,text),
 internal.delete_player_talk_for_actor(uuid,bigint),
 api.list_player_talks(uuid,uuid),api.save_player_talk(uuid,uuid,uuid,bigint,date,uuid[],uuid,text,text),
 api.delete_player_talk(uuid,bigint)
 to authenticated;

notify pgrst,'reload schema';
