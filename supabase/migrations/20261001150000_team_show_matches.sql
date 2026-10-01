-- PUB-10: a team can show all its matches on its public page, upcoming and
-- played, like training times. Title as in the app (e.g. "vs Sävsjö FF") or
-- the match's own public title; the place only when published for that match.
-- A match made private in the editorial view stays hidden. Off by default.

alter table core.team_event_visibility
 add column if not exists show_matches boolean not null default false;

do $patch$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.get_team_event_visibility_for_actor(uuid)'::regprocedure);
 patched:=replace(replace(definition,
  'jsonb_build_object(''show_results'',show_results,''show_training'',show_training,''revision'',revision)',
  'jsonb_build_object(''show_results'',show_results,''show_training'',show_training,''show_matches'',show_matches,''revision'',revision)'),
  'jsonb_build_object(''show_results'',false,''show_training'',false,''revision'',0)',
  'jsonb_build_object(''show_results'',false,''show_training'',false,''show_matches'',false,''revision'',0)');
 if patched=definition then raise exception 'get_team_event_visibility_for_actor: patch point not found'; end if;
 execute patched;

 definition:=pg_get_functiondef('internal.sync_team_public_event(uuid)'::regprocedure);
 patched:=replace(definition,
  '(e.event_type=''match'' and (manual.state=''published'' or (preference.show_results and completed and score.event_id is not null)))',
  '(e.event_type=''match'' and (manual.state=''published''
     or (preference.show_matches and manual.state is distinct from ''private'')
     or (preference.show_results and completed and score.event_id is not null)))');
 if patched=definition then raise exception 'sync_team_public_event: patch point not found'; end if;
 execute patched;
end$patch$;

create or replace function internal.set_team_event_visibility_v2_for_actor(target_team_id uuid,new_show_results boolean,
 new_show_training boolean,new_show_matches boolean,expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare current_settings jsonb; e record; club uuid; next_revision bigint;
begin
 perform pg_advisory_xact_lock(hashtextextended('team-event-visibility:'||target_team_id::text,0));
 current_settings:=internal.get_team_event_visibility_for_actor(target_team_id);
 if (current_settings->>'revision')::bigint<>expected_revision then raise serialization_failure using message='revision_conflict';end if;
 if new_show_results is null or new_show_training is null or new_show_matches is null then
  raise invalid_parameter_value using message='invalid_visibility';end if;
 insert into core.team_event_visibility(team_id,show_results,show_training,show_matches,changed_by)
 values(target_team_id,new_show_results,new_show_training,new_show_matches,auth.uid())
 on conflict(team_id) do update set show_results=excluded.show_results,show_training=excluded.show_training,
  show_matches=excluded.show_matches,revision=core.team_event_visibility.revision+1,
  changed_by=excluded.changed_by,changed_at=now()
 returning revision into next_revision;
 for e in select id from core.events where owning_team_id=target_team_id and event_type in('training','match') order by id loop
  perform internal.sync_team_public_event(e.id);
 end loop;
 select club_id into club from core.teams where id=target_team_id;
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(club,auth.uid(),'publication.team.events.configure','team',target_team_id,next_revision,
  jsonb_build_object('show_results',new_show_results,'show_training',new_show_training,'show_matches',new_show_matches));
 return internal.get_team_event_visibility_for_actor(target_team_id);
end;$$;

-- Older clients keep the team's match choice as it is.
create or replace function internal.set_team_event_visibility_for_actor(target_team_id uuid,new_show_results boolean,
 new_show_training boolean,expected_revision bigint)
returns jsonb language sql security definer set search_path='' as $$
 select internal.set_team_event_visibility_v2_for_actor(target_team_id,new_show_results,new_show_training,
  coalesce((select show_matches from core.team_event_visibility where team_id=target_team_id),false),expected_revision)
$$;

create or replace function api.set_team_event_visibility_v2(team_id uuid,show_results boolean,show_training boolean,
 show_matches boolean,expected_revision bigint)
returns jsonb language sql security invoker set search_path='' as
$$select internal.set_team_event_visibility_v2_for_actor(team_id,show_results,show_training,show_matches,expected_revision)$$;

revoke all on function internal.set_team_event_visibility_v2_for_actor(uuid,boolean,boolean,boolean,bigint),
 api.set_team_event_visibility_v2(uuid,boolean,boolean,boolean,bigint) from public,anon,authenticated;
grant execute on function internal.set_team_event_visibility_v2_for_actor(uuid,boolean,boolean,boolean,bigint),
 api.set_team_event_visibility_v2(uuid,boolean,boolean,boolean,bigint) to authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261001150000_team_show_matches','greenfield','PUB-10 teams show all their matches on the public page'
where not exists(select 1 from internal.migration_provenance where migration_name='20261001150000_team_show_matches');
notify pgrst,'reload schema';
