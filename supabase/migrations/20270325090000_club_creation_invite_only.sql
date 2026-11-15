-- Nya klubbar bara för utvalda (2026-11-15): när TeamZone-appen flyttar till
-- produktionen är den bara öppen för inbjudna. Den som inte är inbjuden kan
-- inte skapa en egen klubb, utom konton som står i core.club_creators.
-- Utan rad i core.club_creation_policy är det öppet som förut, så testet
-- påverkas inte; produktionen stänger med en rad där open = false.

create table core.club_creation_policy (
  id boolean primary key default true check (id),
  open boolean not null default true,
  updated_at timestamptz not null default now()
);

create table core.club_creators (
  profile_id uuid primary key references auth.users(id) on delete cascade,
  note text not null default '' check (length(note) <= 200),
  added_at timestamptz not null default now()
);

alter table core.club_creation_policy enable row level security;
alter table core.club_creators enable row level security;
revoke all on core.club_creation_policy, core.club_creators from public, anon, authenticated;

-- Whether the asker may start a club of their own.
create or replace function internal.club_creation_allowed()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select policy.open from core.club_creation_policy policy), true)
    or exists (select 1 from core.club_creators creator where creator.profile_id = auth.uid())
$$;

-- The old function does the work; the new one with its name checks first,
-- so api.create_club_with_first_team keeps calling it unchanged.
alter function internal.create_club_with_first_team_for_actor(text, text, uuid)
  rename to create_club_with_first_team_unchecked_for_actor;

create or replace function internal.create_club_with_first_team_for_actor(
  club_name text, team_name text, idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  if not internal.club_creation_allowed() then
    raise insufficient_privilege using message = 'club_creation_closed';
  end if;
  return internal.create_club_with_first_team_unchecked_for_actor(club_name, team_name, idempotency_key);
end;
$$;

revoke all on function
  internal.club_creation_allowed(),
  internal.create_club_with_first_team_unchecked_for_actor(text, text, uuid),
  internal.create_club_with_first_team_for_actor(text, text, uuid)
from public, anon, authenticated;
grant execute on function internal.create_club_with_first_team_for_actor(text, text, uuid) to authenticated;

notify pgrst, 'reload schema';
