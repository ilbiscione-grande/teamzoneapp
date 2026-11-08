-- Change only the resource of one future booking, retaining its identity,
-- time, group, series occurrence and activity association.
create function internal.preview_booking_resource_for_actor(target_booking_id uuid,new_resource_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare booked core.booking_bookings; destination core.booking_resources; previous core.booking_resources;
 activity core.events; actor_role text; versions jsonb; conflicts jsonb:='[]'; next_status text;
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated';end if;
 select * into booked from core.booking_bookings where id=target_booking_id;
 if booked.id is null or internal.booking_actor_can_cancel(booked) is not true
  or (internal.booking_actor_role(booked.organization_id) is null and internal.booking_actor_leads_team(booked.organization_id,booked.team_id) is not true) then
  raise insufficient_privilege using message='not_allowed';end if;
 -- Match activity revision lock order, including recurring activity moves.
 if booked.event_id is not null then
  perform pg_advisory_xact_lock(hashtextextended('event-series:'||coalesce(
   (select recurrence_id from core.events where id=booked.event_id),booked.event_id)::text,0));
  select * into activity from core.events where id=booked.event_id for update;
  if activity.id is null or activity.state not in ('draft','scheduled') or activity.archived_at is not null
   or internal.actor_can_read_event(activity.id) is not true then raise insufficient_privilege using message='event_not_found';end if;
 end if;
 perform internal.lock_booking_organization(booked.organization_id);
 select * into booked from core.booking_bookings where id=target_booking_id for update;
 actor_role:=internal.booking_actor_role(booked.organization_id);
 if internal.booking_actor_can_cancel(booked) is not true
  or (actor_role is null and internal.booking_actor_leads_team(booked.organization_id,booked.team_id) is not true) then
  raise insufficient_privilege using message='not_allowed';end if;
 if booked.starts_at<=now() then raise invalid_parameter_value using message='resource_change_requires_future';end if;
 if booked.team_id is not null and internal.booking_actor_can_book_team(booked.organization_id,booked.team_id) is not true then
  raise insufficient_privilege using message='not_team_leader';end if;
 select * into destination from core.booking_resources where id=new_resource_id and organization_id=booked.organization_id;
 if destination.id is null then raise insufficient_privilege using message='resource_change_not_found';end if;
 if destination.id=booked.resource_id then raise invalid_parameter_value using message='resource_change_same';end if;
 select * into previous from core.booking_resources where id=booked.resource_id;
 if not destination.active then conflicts:=conflicts||jsonb_build_array('resource_inactive');end if;
 if not internal.booking_within_disposition(destination,booked.starts_at,booked.ends_at) then
  conflicts:=conflicts||jsonb_build_array('resource_outside_disposition');end if;
 if exists(select 1 from core.booking_bookings b where b.id<>booked.id and b.organization_id=booked.organization_id
  and b.status in ('pending','confirmed') and b.starts_at<booked.ends_at and b.ends_at>booked.starts_at
  and internal.booking_resources_overlap(destination.id,b.resource_id)) then conflicts:=conflicts||jsonb_build_array('resource_busy');end if;
 next_status:=case when destination.requires_approval and actor_role is distinct from 'admin' then 'pending' else 'confirmed' end;
 select jsonb_object_agg(r.id::text,r.revision) into versions from core.booking_resources r where r.id in
  (select a.id from internal.booking_resource_ancestors(booked.resource_id) a union select a.id from internal.booking_resource_ancestors(destination.id) a);
 return jsonb_build_object('target_booking_id',booked.id,'revision',booked.revision,'organization_id',booked.organization_id,
  'old_resource_id',booked.resource_id,'old_resource_name',previous.name,'new_resource_id',destination.id,'new_resource_name',destination.name,
  'starts_at',booked.starts_at,'ends_at',booked.ends_at,'old_status',booked.status,'status',next_status,
  'requires_approval',destination.requires_approval,'series_id',booked.series_id,'series_sequence',booked.series_sequence,'group_id',booked.group_id,
  'event_id',booked.event_id,'event_revision',activity.revision,'event_starts_at',activity.starts_at,'event_ends_at',activity.ends_at,
  'resources',versions,'conflicts',conflicts);
end;$$;
revoke all on function internal.preview_booking_resource_for_actor(uuid,uuid) from public,anon,authenticated;

create function api.preview_booking_resource(target_booking_id uuid,new_resource_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin return internal.preview_booking_resource_for_actor(target_booking_id,new_resource_id);end;$$;
revoke all on function api.preview_booking_resource(uuid,uuid) from public,anon,authenticated;
grant execute on function api.preview_booking_resource(uuid,uuid) to authenticated;

create function internal.change_booking_resource_for_actor(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plan jsonb; booked core.booking_bookings;
begin
 if jsonb_typeof(p->'expected_plan') is distinct from 'object' then raise invalid_parameter_value using message='revision_required';end if;
 plan:=internal.preview_booking_resource_for_actor((p->>'target_booking_id')::uuid,(p->>'new_resource_id')::uuid);
 if jsonb_array_length(plan->'conflicts')>0 then raise check_violation using message='resource_change_conflicts';end if;
 if plan is distinct from p->'expected_plan' then raise sqlstate 'PT409' using message='stale_revision';end if;
 update core.booking_bookings set resource_id=(plan->>'new_resource_id')::uuid,status=plan->>'status',revision=revision+1,
  decided_by=case when plan->>'status'='pending' then null else auth.uid() end,
  decided_at=case when plan->>'status'='pending' then null else now() end
  where id=(plan->>'target_booking_id')::uuid returning * into booked;
 perform internal.booking_notify(booked.id,'resource_changed',array[booked.booked_by]);
 if booked.status='pending' then perform internal.booking_notify(booked.id,'requested',
  array(select profile_id from internal.booking_admin_profiles(booked.organization_id)));end if;
 return plan;
end;$$;
revoke all on function internal.change_booking_resource_for_actor(jsonb) from public,anon,authenticated;

do $command$
declare definition text; marker text:='  case command_type';
begin
 definition:=pg_get_functiondef('internal.execute_booking_command_for_actor(uuid,text,jsonb,jsonb)'::regprocedure);
 if position(marker in definition)=0 then raise exception 'Booking command route missing';end if;
 execute replace(definition,marker,marker||E'\n    when ''change_booking_resource'' then result := internal.change_booking_resource_for_actor(p);');
end;$command$;

alter table core.booking_notifications drop constraint booking_notifications_kind_check;
alter table core.booking_notifications add constraint booking_notifications_kind_check
 check(kind in ('requested','approved','declined','cancelled','rescheduled','resource_changed'));

do $notification$
declare definition text; patched text;
begin
 definition:=pg_get_functiondef('internal.push_message_for_outbox(uuid)'::regprocedure);
 patched:=replace(definition,'when ''booking.requested.v1'' then',
  'when ''booking.resource_changed.v1'' then case when swedish then U&''Bokningen har bytt resurs'' else ''Booking resource changed'' end
      when ''booking.requested.v1'' then');
 if patched=definition then raise exception 'Booking push formatter contract changed';end if;execute patched;
 definition:=pg_get_functiondef('internal.notification_title(text)'::regprocedure);
 patched:=replace(definition,'when event_type = ''booking.requested.v1'' then',
  'when event_type = ''booking.resource_changed.v1'' then ''Bokningen har bytt resurs''
  when event_type = ''booking.requested.v1'' then');
 if patched=definition then raise exception 'Booking title formatter contract changed';end if;execute patched;
 definition:=pg_get_functiondef('internal.notification_preview(text)'::regprocedure);
 patched:=replace(definition,'when event_type = ''booking.requested.v1'' then',
  'when event_type = ''booking.resource_changed.v1'' then U&''Se den nya resursen i Bokningshanteraren. Bokningens tider och aktivitetskoppling \00e4r kvar.''
  when event_type = ''booking.requested.v1'' then');
 if patched=definition then raise exception 'Booking preview formatter contract changed';end if;execute patched;
end;$notification$;
