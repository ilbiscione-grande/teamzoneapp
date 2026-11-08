-- Explicit owner opt-in. Existing resources and reservations are untouched.
alter table core.booking_resources add column pitch_layout jsonb;
alter table core.booking_resources drop constraint booking_resource_disposition_shape;
alter table core.booking_resources add constraint booking_resource_disposition_shape check (
  (available_until is null or available_from is not null and available_until>=available_from)
  and (ownership_kind<>'external' or owner_name is not null and available_from is not null)
);
create or replace function internal.save_booking_resource_v2_for_actor(
  target_organization_id uuid,target_resource_id uuid,details jsonb,expected_revision bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare current_resource core.booking_resources; saved uuid; half_id uuid; quarter_id uuid; parts jsonb:='{}'; side text; n integer; ownership text:=details->>'ownership_kind';
begin
  perform internal.lock_booking_organization(target_organization_id);
  if internal.booking_actor_role(target_organization_id) is distinct from 'admin' then
    raise insufficient_privilege using message='not_admin'; end if;
  if jsonb_typeof(details) is distinct from 'object' or ownership is null
    or ownership not in ('unspecified','owned','external') or nullif(btrim(details->>'timezone'),'') is null
    or (ownership='external' and (nullif(btrim(details->>'owner_name'),'') is null
      or nullif(details->>'available_from','') is null))
    or (nullif(details->>'available_from','') is null and nullif(details->>'available_until','') is not null) then
    raise invalid_parameter_value using message='invalid_disposition'; end if;
  if target_resource_id is not null then
    select * into current_resource from core.booking_resources
      where id=target_resource_id and organization_id=target_organization_id for update;
    if current_resource.id is null then raise insufficient_privilege using message='not_found'; end if;
    if expected_revision is null then raise invalid_parameter_value using message='revision_required'; end if;
    if current_resource.revision<>expected_revision then raise sqlstate 'PT409' using message='stale_revision'; end if;
  end if;
  if ownership='unspecified' and current_resource.ownership_kind is distinct from 'unspecified' then
    raise invalid_parameter_value using message='invalid_disposition'; end if;
  if nullif(details->>'available_from','')::date > nullif(details->>'available_until','')::date then
    raise invalid_parameter_value using message='invalid_disposition'; end if;
  if target_resource_id is null then
    insert into core.booking_resources(organization_id,name,category,description,location,capacity,requires_approval,active,
      ownership_kind,owner_name,timezone,available_from,available_until,availability,parent_resource_id)
    values(target_organization_id,btrim(details->>'name'),details->>'category',nullif(btrim(details->>'description'),''),
      nullif(btrim(details->>'location'),''),(details->>'capacity')::integer,coalesce((details->>'requires_approval')::boolean,false),
      coalesce((details->>'active')::boolean,true),ownership,nullif(btrim(details->>'owner_name'),''),details->>'timezone',
      nullif(details->>'available_from','')::date,nullif(details->>'available_until','')::date,coalesce(details->'availability','{"mode":"always","weekly":[],"exceptions":[]}'::jsonb),nullif(details->>'parent_resource_id','')::uuid) returning id into saved;
  else
    update core.booking_resources set name=btrim(details->>'name'),category=details->>'category',
      description=nullif(btrim(details->>'description'),''),location=nullif(btrim(details->>'location'),''),
      capacity=(details->>'capacity')::integer,requires_approval=coalesce((details->>'requires_approval')::boolean,false),
      active=coalesce((details->>'active')::boolean,true),ownership_kind=ownership,owner_name=nullif(btrim(details->>'owner_name'),''),
      timezone=details->>'timezone',available_from=nullif(details->>'available_from','')::date,
      available_until=nullif(details->>'available_until','')::date,
      availability=coalesce(details->'availability',current_resource.availability),
      parent_resource_id=case when details ? 'parent_resource_id' then nullif(details->>'parent_resource_id','')::uuid else current_resource.parent_resource_id end,revision=revision+1 where id=current_resource.id returning id into saved;
  end if;
  if details->>'pitch_setup'='quarters' then
    if details->>'category'<>'pitch' or nullif(details->>'parent_resource_id','') is not null
      or exists(select 1 from core.booking_resources where parent_resource_id=saved)
      or current_resource.pitch_layout is not null then
      raise invalid_parameter_value using message='pitch_layout_exists';end if;
    foreach side in array array['A','B'] loop
      insert into core.booking_resources(organization_id,name,category,parent_resource_id,ownership_kind,timezone,location,requires_approval)
      values(target_organization_id,'Halvplan '||side,'pitch',saved,'owned',details->>'timezone',nullif(details->>'location',''),coalesce((details->>'requires_approval')::boolean,false)) returning id into half_id;
      parts:=parts||jsonb_build_object(side,half_id);
      for n in 1..2 loop
        insert into core.booking_resources(organization_id,name,category,parent_resource_id,ownership_kind,timezone,location,requires_approval)
        values(target_organization_id,'Fjärdedelsplan '||side||n,'pitch',half_id,'owned',details->>'timezone',nullif(details->>'location',''),coalesce((details->>'requires_approval')::boolean,false)) returning id into quarter_id;
        parts:=parts||jsonb_build_object(side||n,quarter_id);
      end loop;
    end loop;
    update core.booking_resources set pitch_layout=parts,revision=revision+1 where id=saved;
  end if;
  return saved;
end; $$;

create or replace function internal.get_booking_organization_for_actor(target_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor_role text := internal.booking_actor_role(target_organization_id);
begin
  if actor_role is null then raise insufficient_privilege using message = 'not_found'; end if;
  return (
    select jsonb_build_object(
      'id', org.id, 'name', org.name, 'kind', org.kind, 'sport', org.sport,
      'teamzone_club_id', org.teamzone_club_id,
      'teamzone_club_name', (select club.name from core.clubs club where club.id = org.teamzone_club_id),
      'club_members_can_book', org.club_members_can_book,
      'role', actor_role,
      'resources', coalesce((select jsonb_agg(jsonb_build_object(
          'id', resource.id, 'parent_resource_id',resource.parent_resource_id, 'name', resource.name, 'category', resource.category,
          'description', resource.description, 'location', resource.location,
          'capacity', resource.capacity, 'requires_approval', resource.requires_approval,
          'pitch_layout',resource.pitch_layout,'active', resource.active, 'revision', resource.revision,
          'ownership_kind',resource.ownership_kind,'owner_name',resource.owner_name,'timezone',resource.timezone,
          'availability',resource.availability,'available_from',resource.available_from,'available_until',resource.available_until
        ) order by resource.active desc, resource.category, resource.name)
        from core.booking_resources resource
        where resource.organization_id = org.id and (resource.active or actor_role = 'admin')), '[]'::jsonb),
      'members', case when actor_role = 'admin' then coalesce((select jsonb_agg(jsonb_build_object(
          'profile_id', member.profile_id, 'name', internal.booking_person_name(member.profile_id),
          'role', member.role, 'is_self', member.profile_id = auth.uid()
        ) order by member.role, internal.booking_person_name(member.profile_id))
        from core.booking_members member where member.organization_id = org.id), '[]'::jsonb) end,
      'teams', coalesce((select jsonb_agg(jsonb_build_object('team_id', t.team_id, 'name', t.team_name) order by t.team_name)
        from (select team.id team_id, team.name team_name from core.teams team where team.club_id = org.teamzone_club_id and team.status = 'active' and internal.booking_actor_can_book_team(org.id, team.id)) t), '[]'::jsonb),
      'pending_count', case when actor_role = 'admin' then (select count(*) from core.booking_bookings booking
        where booking.organization_id = org.id and booking.status = 'pending' and booking.ends_at > now()) end
    )
    from core.booking_organizations org where org.id = target_organization_id
  );
end;
$$;
