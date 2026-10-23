-- Module foundation (decision package 11, MFD-02/03): the app's modules and
-- the Tacticsboard link in a catalog, each club's access to them, and the
-- level each area of the app shows for a team. A module open in beta is
-- open to every club through the same check that will later read the
-- club's purchase (core.club_entitlements); there is no separate path for
-- paying. Access to a module never replaces a person's capabilities in the
-- team: they still decide who reads or changes what.

create table core.module_catalog (
  key text primary key check (key ~ '^(module|webtool)\.[a-z0-9_]+$'),
  title text not null check (length(title) between 1 and 60),
  description text not null default '' check (length(description) <= 200),
  beta_open boolean not null default false,
  sort integer not null default 0
);
alter table core.module_catalog enable row level security;
revoke all on core.module_catalog from public, anon, authenticated;

insert into core.module_catalog (key, title, description, beta_open, sort) values
  ('module.match_workspace', 'Match', 'Matchplan, uppställning på planen, nyckeltal och matchuppföljning', true, 10),
  ('module.team_development', 'Team Development Plan', 'Säsongsmål, perioder med tillfälliga utvecklingsmål och lagets spelprinciper', true, 20),
  ('module.training', 'Träning', 'Träningspass med övningar, övningsbibliotek och utvärdering', true, 30),
  ('module.player_development', 'IDP', 'Spelarnas utvecklingsplaner med mål, aktiviteter och avstämningar', true, 40),
  -- Closed until the Tacticsboard link is built (its own decision package).
  ('webtool.tacticsboard_link', 'Tacticsboard i TeamZone', 'Tavlor från Tacticsboard i matchplaner, träningar och utvecklingsplaner', false, 90);

-- A club's access to a module or web tool link: open in beta, else what
-- the club has bought (write, read-only after it ended, or none).
create or replace function internal.club_module_access(target_club_id uuid, target_key text)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from core.module_catalog catalog where catalog.key = target_key and catalog.beta_open) then 'write'
    else coalesce((
      select case when entitlement.access_mode = 'write' and (entitlement.expires_at is null or entitlement.expires_at > now()) then 'write'
                  when entitlement.access_mode in ('write', 'read_only') then 'read_only'
                  else 'none' end
      from core.club_entitlements entitlement
      where entitlement.club_id = target_club_id and entitlement.entitlement_key = target_key
    ), 'none')
  end
$$;

-- For a module's own commands: writing needs write access, reading at least read-only.
create or replace function internal.module_allows_write(target_club_id uuid, target_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.club_module_access(target_club_id, target_key) = 'write'
$$;
create or replace function internal.module_allows_read(target_club_id uuid, target_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select internal.club_module_access(target_club_id, target_key) in ('write', 'read_only')
$$;

-- The areas of the app and the module each deepens; whether Tacticsboard can take over its visual part.
create or replace function internal.module_areas()
returns table (area text, module_key text, tacticsboard boolean) language sql immutable set search_path = '' as $$
  values
    ('lineup', 'module.match_workspace', true),
    ('match_preparation', 'module.match_workspace', true),
    ('match_followup', 'module.match_workspace', false),
    ('team_development', 'module.team_development', true),
    ('training', 'module.training', true),
    ('player_development', 'module.player_development', true)
$$;

-- What a team's people see: each module with the club's access, and the
-- level of each area: 'tacticsboard' where the link is open and the area
-- has a visual part, 'module' where the club has the module, else 'base'.
create or replace function internal.get_team_modules_for_actor(target_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  club uuid;
  linked boolean;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  select team.club_id into club from core.teams team where team.id = target_team_id;
  if club is null or not internal.actor_has_club_access(club) then raise insufficient_privilege using message = 'not_found'; end if;
  linked := internal.club_module_access(club, 'webtool.tacticsboard_link') = 'write';
  return jsonb_build_object(
    'team_id', target_team_id,
    'club_id', club,
    'modules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', catalog.key, 'title', catalog.title, 'description', catalog.description,
        'beta', catalog.beta_open, 'access', internal.club_module_access(club, catalog.key)
      ) order by catalog.sort)
      from core.module_catalog catalog), '[]'::jsonb),
    'levels', (
      select jsonb_object_agg(areas.area, case
        when areas.tacticsboard and linked then 'tacticsboard'
        when internal.module_allows_read(club, areas.module_key) then 'module'
        else 'base' end)
      from internal.module_areas() areas)
  );
end;
$$;

create or replace function api.get_team_modules(target_team_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_team_modules_for_actor(target_team_id) $$;

revoke all on function
  internal.club_module_access(uuid, text), internal.module_allows_write(uuid, text), internal.module_allows_read(uuid, text),
  internal.module_areas(), internal.get_team_modules_for_actor(uuid), api.get_team_modules(uuid)
from public, anon, authenticated;
grant execute on function
  internal.club_module_access(uuid, text), internal.module_allows_write(uuid, text), internal.module_allows_read(uuid, text),
  internal.module_areas(), internal.get_team_modules_for_actor(uuid), api.get_team_modules(uuid)
to authenticated;
