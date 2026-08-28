-- HOME-03: explicit child selection with relation-verified guardian acting-as.

create function internal.get_guardian_home_for_actor(target_context_id uuid,target_child_person_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=''as $$
declare actor_id uuid:=auth.uid();context_row record;guardian_person_id uuid;selected_child_id uuid;
 observed_at timestamptz:=statement_timestamp();
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into context_row from internal.get_my_contexts_for_actor()where context_id=target_context_id;
 if context_row.context_id is null or context_row.role_package<>'guardian'or context_row.team_id is null
 then raise insufficient_privilege using message='not_found';end if;
 select link.club_person_id into guardian_person_id from core.person_account_links link
 join core.assignments assignment on assignment.club_person_id=link.club_person_id and assignment.club_id=link.club_id
 where link.profile_id=actor_id and link.club_id=context_row.club_id and link.state='active'
  and assignment.team_id=context_row.team_id and assignment.role_package='guardian'and assignment.state='active'
  and assignment.starts_at<=observed_at and(assignment.ends_at is null or assignment.ends_at>observed_at)
 order by assignment.starts_at desc,assignment.id limit 1;
 if guardian_person_id is null then raise insufficient_privilege using message='not_found';end if;
 select child.id into selected_child_id from core.guardian_relations relation
 join core.club_people child on child.id=relation.child_person_id and child.club_id=relation.club_id
 where relation.club_id=context_row.club_id and relation.guardian_person_id=guardian_person_id
  and relation.state='active'and relation.starts_at<=observed_at and(relation.ends_at is null or relation.ends_at>observed_at)
  and(target_child_person_id is null or child.id=target_child_person_id)
  and exists(select 1 from core.team_assignments assignment where assignment.club_id=relation.club_id
   and assignment.team_id=context_row.team_id and assignment.club_person_id=child.id and assignment.state='active'
   and assignment.starts_at<=observed_at and(assignment.ends_at is null or assignment.ends_at>observed_at))
 order by child.display_name,child.id limit 1;
 if selected_child_id is null then raise insufficient_privilege using message='not_found';end if;
 return jsonb_build_object(
  'schema_version',1,'generated_at',observed_at,'role_package','guardian','context_id',target_context_id,
  'team',jsonb_build_object('team_id',context_row.team_id,'team_name',context_row.team_name,
   'club_name',context_row.club_name,'member_count',(select count(distinct assignment.club_person_id)
    from core.team_assignments assignment where assignment.club_id=context_row.club_id and assignment.team_id=context_row.team_id
     and assignment.state='active'and assignment.starts_at<=observed_at and(assignment.ends_at is null or assignment.ends_at>observed_at))),
  'children',coalesce((select jsonb_agg(jsonb_build_object('child_person_id',child.id,'display_name',child.display_name,
    'relation_kind',relation.kind)order by child.display_name,child.id)
   from core.guardian_relations relation join core.club_people child on child.id=relation.child_person_id and child.club_id=relation.club_id
   where relation.club_id=context_row.club_id and relation.guardian_person_id=guardian_person_id
    and relation.state='active'and relation.starts_at<=observed_at and(relation.ends_at is null or relation.ends_at>observed_at)
    and exists(select 1 from core.team_assignments assignment where assignment.club_id=relation.club_id
     and assignment.team_id=context_row.team_id and assignment.club_person_id=child.id and assignment.state='active'
     and assignment.starts_at<=observed_at and(assignment.ends_at is null or assignment.ends_at>observed_at))),'[]'::jsonb),
  'selected_child_id',selected_child_id,
  'next_event',(select jsonb_build_object('event_id',event_row.id,'title',event_row.title,'event_type',event_row.event_type,
    'state',event_row.state,'starts_at',event_row.starts_at,'ends_at',event_row.ends_at,'location_name',location.name,'address',location.address)
   from core.events event_row join core.event_teams relation on relation.event_id=event_row.id and relation.club_id=event_row.club_id
   left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
   where event_row.club_id=context_row.club_id and relation.team_id=context_row.team_id and event_row.state='scheduled'
    and event_row.starts_at>=observed_at order by event_row.starts_at,event_row.id limit 1),
  'child_callups',coalesce((select jsonb_agg(row_value order by starts_at,callup_id)from(
   select callup.id callup_id,callup.event_id,callup.state,callup.revision,callup.expires_at,
    event_row.title event_title,event_row.event_type,event_row.starts_at,event_row.ends_at,
    location.name location_name,location.address,
    callup.state in('pending','accepted','declined')and callup.expires_at>observed_at can_respond,
    selected_child_id acting_as_person_id,'guardian'::text response_role
   from core.callups callup join core.events event_row on event_row.id=callup.event_id and event_row.club_id=callup.club_id
   join core.event_teams team_relation on team_relation.event_id=event_row.id and team_relation.club_id=event_row.club_id
   left join core.event_locations location on location.id=event_row.location_id and location.club_id=event_row.club_id
   where callup.club_id=context_row.club_id and callup.club_person_id=selected_child_id
    and team_relation.team_id=context_row.team_id and callup.state<>'cancelled'and event_row.state<>'cancelled'
    and event_row.ends_at>=observed_at-interval'12 hours'
   order by event_row.starts_at,callup.id limit 12)row_value),'[]'::jsonb),
  'unread_message_count',coalesce((select sum(greatest(latest.revision-coalesce(reads.through_revision,1),0))
   from core.thread_participants participant join core.message_threads thread on thread.id=participant.thread_id
   join core.thread_scopes scope on scope.thread_id=thread.id and scope.club_id=context_row.club_id and scope.team_id=context_row.team_id
   left join core.message_reads reads on reads.thread_id=thread.id and reads.profile_id=actor_id
   left join core.thread_personal_visibility visibility on visibility.thread_id=thread.id and visibility.profile_id=actor_id
   left join lateral(select max(message.revision)revision from core.messages message where message.thread_id=thread.id)latest on true
   where participant.profile_id=actor_id and participant.state='active'and thread.state<>'hidden'
    and not coalesce(visibility.hidden,false)),0)
 );
end$$;

create function api.get_guardian_home(context_id uuid,child_person_id uuid default null)returns jsonb
language sql stable security invoker set search_path=''as
$$select internal.get_guardian_home_for_actor(context_id,child_person_id)$$;
revoke all on function internal.get_guardian_home_for_actor(uuid,uuid),api.get_guardian_home(uuid,uuid)from public,anon,authenticated;
grant execute on function internal.get_guardian_home_for_actor(uuid,uuid),api.get_guardian_home(uuid,uuid)to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260827193735_home03_guardian_home','greenfield','HOME-03 child switcher, relation-scoped data and visible acting-as');
notify pgrst,'reload schema';
