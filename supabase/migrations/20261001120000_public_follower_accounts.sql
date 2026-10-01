-- AUTH-08: follower accounts. Someone who only wants to follow public club
-- and team pages creates an account on the public site; it belongs to no club
-- or team and has no role in one. Only the public site's server (holding the
-- service key, behind captcha and an origin check) can mark an account as a
-- follower. A follower who later joins a club in the app becomes a member;
-- the same account keeps following its pages.

alter table core.profiles
 add column if not exists account_type text not null default 'member'
  check (account_type in ('member','follower'));

create or replace function internal.mark_public_follower_account(target_profile_id uuid,legal_accepted boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare profile_row core.profiles%rowtype; terms_version text; privacy_version text;
begin
 if legal_accepted is not true then raise invalid_parameter_value using message='legal_required'; end if;
 select * into profile_row from core.profiles where id=target_profile_id for update;
 -- Only a brand-new account without any club connection can become a
 -- follower; an existing account is never changed this way.
 if profile_row.id is null or profile_row.created_at<now()-interval '15 minutes'
  or exists(select 1 from core.person_account_links link where link.profile_id=target_profile_id) then
  return jsonb_build_object('marked',false);
 end if;
 update core.profiles set account_type='follower',updated_at=now(),revision=revision+1
 where id=target_profile_id and account_type<>'follower';
 select version into terms_version from internal.legal_document_versions where document_type='terms' and active;
 select version into privacy_version from internal.legal_document_versions where document_type='privacy' and active;
 if terms_version is not null and privacy_version is not null then
  insert into core.legal_acceptances(profile_id,document_type,document_version,source)
  values(target_profile_id,'terms',terms_version,'web'),(target_profile_id,'privacy',privacy_version,'web')
  on conflict do nothing;
 end if;
 insert into core.communication_preferences(profile_id,marketing_opt_in) values(target_profile_id,false)
 on conflict(profile_id) do nothing;
 insert into audit.command_events(actor_profile_id,command_type,aggregate_type,aggregate_id,aggregate_revision,metadata)
 values(target_profile_id,'identity.follower_account.created.v1','profile',target_profile_id,1,
  jsonb_build_object('source','public_site','terms_version',terms_version,'privacy_version',privacy_version));
 return jsonb_build_object('marked',true);
end$$;

create or replace function api.mark_public_follower_account(target_profile_id uuid,legal_accepted boolean)
returns jsonb language sql security invoker set search_path='' as
$$select internal.mark_public_follower_account(target_profile_id,legal_accepted)$$;

revoke all on function internal.mark_public_follower_account(uuid,boolean),
 api.mark_public_follower_account(uuid,boolean) from public,anon,authenticated;
grant execute on function internal.mark_public_follower_account(uuid,boolean),
 api.mark_public_follower_account(uuid,boolean) to service_role;

-- Joining a club makes a follower a member.
create or replace function internal.follower_becomes_member()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.state='active' then
  update core.profiles set account_type='member',updated_at=now(),revision=revision+1
  where id=new.profile_id and account_type='follower';
 end if;
 return new;
end$$;
revoke all on function internal.follower_becomes_member() from public,anon,authenticated;
drop trigger if exists person_account_links_follower_becomes_member on core.person_account_links;
create trigger person_account_links_follower_becomes_member
after insert or update of state on core.person_account_links
for each row execute function internal.follower_becomes_member();

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
select '20261001120000_public_follower_accounts','greenfield',
 'AUTH-08 follower accounts created on the public site'
where not exists(select 1 from internal.migration_provenance
 where migration_name='20261001120000_public_follower_accounts');
notify pgrst,'reload schema';
