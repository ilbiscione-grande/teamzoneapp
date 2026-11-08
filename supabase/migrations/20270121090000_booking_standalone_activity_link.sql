-- Attach one existing standalone occurrence, including its grouped resources.
-- Times, approval and series membership are retained; later event edits use
-- the established atomic event/booking synchronization trigger.
create function internal.preview_booking_activity_link_for_actor(target_booking_id uuid,target_team_id uuid,target_event_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b core.booking_bookings;e core.events;rows jsonb;ids uuid[];
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into b from core.booking_bookings where id=target_booking_id;
 if b.id is null or internal.booking_actor_can_cancel(b) is not true then raise insufficient_privilege using message='not_allowed';end if;
 if internal.booking_actor_can_book_team(b.organization_id,target_team_id) is not true
  or internal.actor_can_manage_event(target_event_id) is not true then raise insufficient_privilege using message='event_move_not_allowed';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-series:'||coalesce((select recurrence_id from core.events where id=target_event_id),target_event_id)::text,0));
 select * into e from core.events where id=target_event_id for update;
 if e.id is null or e.archived_at is not null or e.state not in('draft','scheduled')
  or not exists(select 1 from core.booking_organizations o join core.event_teams t on t.club_id=o.teamzone_club_id
    where o.id=b.organization_id and t.event_id=e.id and t.team_id=target_team_id)
  or internal.actor_can_read_event(e.id) is not true then raise insufficient_privilege using message='event_not_found';end if;
 perform internal.lock_booking_organization(b.organization_id);
 select * into b from core.booking_bookings where id=target_booking_id;
 perform 1 from core.booking_bookings x where x.id=b.id or (b.group_id is not null and x.group_id=b.group_id) order by x.id for update;
 select * into b from core.booking_bookings where id=target_booking_id;
 if b.event_id is not null or b.status not in('pending','confirmed') or b.starts_at<=now() or e.starts_at<=now() then raise check_violation using message='activity_link_not_standalone';end if;
 select array_agg(x.id order by x.id) into ids from core.booking_bookings x
 where x.status in('pending','confirmed') and (x.id=b.id or (b.group_id is not null and x.group_id=b.group_id));
 if exists(select 1 from core.booking_bookings x where x.id=any(ids) and
  (internal.booking_actor_can_cancel(x) is not true or x.organization_id<>b.organization_id or x.event_id is not null or x.starts_at<=now()))
 then raise insufficient_privilege using message='activity_link_not_standalone';end if;
 if exists(select 1 from core.booking_bookings x join core.booking_bookings y on x.resource_id=y.resource_id
   where x.id=any(ids) and y.event_id=e.id and y.status in('pending','confirmed') and not y.id=any(ids))
 then raise check_violation using message='activity_resource_already_booked';end if;
 select jsonb_agg(jsonb_build_object('id',x.id,'revision',x.revision,'resource_id',x.resource_id,'resource_name',r.name,
  'starts_at',x.starts_at,'ends_at',x.ends_at,'status',x.status,'team_id',x.team_id,'series_id',x.series_id) order by x.id)
 into rows from core.booking_bookings x join core.booking_resources r on r.id=x.resource_id where x.id=any(ids);
 return jsonb_build_object('target_booking_id',b.id,'team_id',target_team_id,'event_id',e.id,'event_revision',e.revision,
  'event_title',e.title,'event_starts_at',e.starts_at,'event_ends_at',e.ends_at,'bookings',rows);
end;$$;
revoke all on function internal.preview_booking_activity_link_for_actor(uuid,uuid,uuid) from public,anon,authenticated;

create function api.preview_booking_activity_link(target_booking_id uuid,target_team_id uuid,target_event_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select internal.preview_booking_activity_link_for_actor(target_booking_id,target_team_id,target_event_id)
$$;
revoke all on function api.preview_booking_activity_link(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.preview_booking_activity_link(uuid,uuid,uuid),internal.preview_booking_activity_link_for_actor(uuid,uuid,uuid) to authenticated;

create function internal.link_booking_activity_for_actor(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plan jsonb;
begin
 plan:=internal.preview_booking_activity_link_for_actor((p->>'target_booking_id')::uuid,(p->>'target_team_id')::uuid,(p->>'target_event_id')::uuid);
 if p->'expected_plan' is distinct from plan then raise sqlstate 'PT409' using message='stale_revision';end if;
 update core.booking_bookings set event_id=(plan->>'event_id')::uuid,team_id=(plan->>'team_id')::uuid,revision=revision+1
 where id in(select (value->>'id')::uuid from jsonb_array_elements(plan->'bookings'));
 return plan;
end;$$;
revoke all on function internal.link_booking_activity_for_actor(jsonb) from public,anon,authenticated;
do $route$
declare definition text;marker text:='  case command_type';
begin
 definition:=pg_get_functiondef('internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb)'::regprocedure);
 if position(marker in definition)=0 then raise exception 'Booking executor contract missing';end if;
 execute replace(definition,marker,marker||E'\n    when ''link_booking_activity'' then result := internal.link_booking_activity_for_actor(p);');
end;$route$;
