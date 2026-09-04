-- PUB-04 authenticated management projection. Local only until separately approved.
create function internal.get_publication_management_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid(); can_manage_club boolean; can_manage_team boolean; result jsonb;
begin
  can_manage_club:=actor_id is not null and internal.actor_has_capability(target_club_id,null,'publication.manage');
  select exists(
    select 1 from core.teams team
    where team.club_id=target_club_id
      and internal.actor_has_capability(target_club_id,team.id,'publication.manage')
  ) into can_manage_team;
  if actor_id is null or not (can_manage_club or can_manage_team) then
    raise insufficient_privilege using message='not_found';
  end if;
  select jsonb_build_object(
    'events',coalesce((select jsonb_agg(jsonb_build_object(
      'id',event_row.id,'team_id',event_row.owning_team_id,'team_name',team.name,
      'title',event_row.title,'event_type',event_row.event_type,'starts_at',event_row.starts_at,
      'event_state',event_row.state,'publication_state',coalesce(setting.state,'private'),
      'public_title',setting.public_title,'publish_location',coalesce(setting.publish_location,false),
      'revision',coalesce(setting.revision,0)
    ) order by event_row.starts_at,event_row.id)
      from core.events event_row join core.teams team on team.id=event_row.owning_team_id and team.club_id=event_row.club_id
      left join core.event_publication_settings setting on setting.event_id=event_row.id
      where event_row.club_id=target_club_id and event_row.state in('scheduled','completed')
        and event_row.starts_at between now()-interval '90 days' and now()+interval '365 days'
        and internal.actor_has_capability(target_club_id,event_row.owning_team_id,'publication.manage')),'[]'::jsonb),
    'partners',case when can_manage_club then coalesce((select jsonb_agg(jsonb_build_object(
      'id',partner.id,'name',partner.name,'website_url',partner.website_url,'state',partner.state,
      'sort_order',partner.sort_order,'revision',partner.revision,
      'media_status',case when asset.id is null then 'not_configured' else asset.variant_state end
    ) order by partner.sort_order,partner.id)
      from core.public_partners partner left join core.public_media_assets asset on asset.id=partner.logo_asset_id
      where partner.club_id=target_club_id),'[]'::jsonb) else '[]'::jsonb end,
    'can_manage_partners',can_manage_club,
    'media_upload_status','not_configured'
  ) into result;
  return result;
end;$$;

create function api.get_publication_management(club_id uuid) returns jsonb
language sql stable security invoker set search_path='' as
$$select internal.get_publication_management_for_actor(club_id)$$;

revoke all on function internal.get_publication_management_for_actor(uuid),api.get_publication_management(uuid)
from public,anon,authenticated;
grant execute on function internal.get_publication_management_for_actor(uuid),api.get_publication_management(uuid)
to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260828090546_pub04_publication_management_list','greenfield','PUB-04 authenticated publication management projection');
notify pgrst,'reload schema';
