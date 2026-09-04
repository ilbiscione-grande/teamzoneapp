-- PUB-05 authenticated domain status projection. No provider activation.
create function internal.get_publication_domains_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();club_setting core.club_publication_settings%rowtype;runtime internal.public_domain_runtime_state%rowtype;
begin
 if actor_id is null or not internal.actor_has_capability(target_club_id,null,'publication.manage') then
  raise insufficient_privilege using message='not_found';end if;
 select * into club_setting from core.club_publication_settings where club_id=target_club_id;
 select * into runtime from internal.public_domain_runtime_state where singleton;
 return jsonb_build_object(
  'path_address',case when club_setting.slug is null then null else 'https://teamzoneapp.se/'||club_setting.slug end,
  'club_published',coalesce(club_setting.mode='published' and club_setting.confirmation_id is not null,false),
  'custom_domain_request_available',true,
  'teamzone_subdomain_available',runtime.wildcard_dns_ready and runtime.wildcard_tls_ready and runtime.automatic_tenant_routing_ready,
  'domains',coalesce((select jsonb_agg(jsonb_build_object(
    'id',domain.id,'kind',domain.kind,'hostname',domain.hostname,'state',domain.state,
    'commercial_state',domain.commercial_state,'tls_state',domain.tls_state,'canonical',domain.canonical,
    'verification_record','_teamzone-verify.'||domain.hostname,'verification_expires_at',domain.verification_expires_at,
    'last_error_code',domain.last_error_code,'revision',domain.revision
   ) order by domain.created_at desc,domain.id) from core.publication_domains domain where domain.club_id=target_club_id),'[]'::jsonb)
 );
end;$$;

create function api.get_publication_domains(club_id uuid) returns jsonb language sql stable security invoker set search_path='' as
$$select internal.get_publication_domains_for_actor(club_id)$$;
revoke all on function internal.get_publication_domains_for_actor(uuid),api.get_publication_domains(uuid) from public,anon,authenticated;
grant execute on function internal.get_publication_domains_for_actor(uuid),api.get_publication_domains(uuid) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260828093026_pub05_domain_management_projection','greenfield','PUB-05 authenticated domain status projection');
notify pgrst,'reload schema';
