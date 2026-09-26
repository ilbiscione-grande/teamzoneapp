-- MANUAL ONLY: requires explicit approval for global runtime in hgcshgunvooyudvrcpig.
-- Apply both PUB-02 worker migrations and drain jobs BEFORE executing this file.
begin;
do $$
begin
 if internal.public_runtime_enabled() then raise exception 'Runtime is already active';end if;
 if (select count(*) from core.club_publication_settings where mode<>'private')<>1
  or (select count(*) from core.team_publication_settings where mode<>'private')<>1
  or (select count(*) from public_api.club_projections)<>1
  or (select count(*) from public_api.team_projections)<>1 then
  raise exception 'Unexpected publication scope; review required';
 end if;
 if not exists(select 1 from public_api.club_projections p
  join core.club_publication_settings s on s.public_id=p.public_id
  join core.publication_confirmations c on c.id=s.confirmation_id
  where p.slug='thomas-klubb-6379829a' and p.visibility='published'
   and s.mode='published' and p.source_revision=s.revision and c.state='active' and c.expires_at>now())
  or not exists(select 1 from public_api.team_projections p
  join core.team_publication_settings s on s.public_id=p.public_id
  join core.publication_confirmations c on c.id=s.confirmation_id
  where p.club_slug='thomas-klubb-6379829a' and p.slug='thomas-lag'
   and p.visibility='published' and s.mode='published' and p.source_revision=s.revision
   and c.state='active' and c.expires_at>now()) then
  raise exception 'Pilot projections or confirmations are not ready';
 end if;
 if exists(select 1 from internal.publication_projection_jobs where state<>'completed') then
  raise exception 'Unfinished projection/cache jobs';
 end if;
end;$$;
alter table internal.publication_runtime_state drop constraint publication_runtime_state_enabled_check;
update internal.publication_runtime_state set enabled=true,
 gate_version='pub02-audit-web-pilot-2026-09-25',revision=revision+1,changed_at=now()
 where singleton;
commit;
