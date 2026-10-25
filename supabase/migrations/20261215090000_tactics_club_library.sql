-- Tacticsboard's library, step 3 (decision package 13, TBL-03/08 as changed
-- by the product owner 2026-10-25): one library. When sharing an item of
-- your library you choose who sees it: the whole community (TeamZone's
-- library) or only one of your clubs. A club also offers its teams a
-- curated list, "Klubbens lista": items picked from the whole library, and
-- the items shared only with the club.
-- Who: every leader of a club (a leader of one of its teams or a club
-- functionary) shares with the club and uses its list. Those who manage
-- the club's members and teams (club.memberships.manage) keep the list:
-- they pick and unpick items and may remove what was shared with the club,
-- until the permissions review says who keeps the club's library
-- (docs/implementation/permissions-review.md).

alter table core.tactics_shared_items
  add column club_id uuid references core.clubs(id) on delete cascade;
create index tactics_shared_items_club on core.tactics_shared_items (club_id) where club_id is not null;

create table core.tactics_club_picks (
  club_id uuid not null references core.clubs(id) on delete cascade,
  shared_item_id uuid not null references core.tactics_shared_items(id) on delete cascade,
  picked_by uuid references core.profiles(id) on delete set null,
  picked_at timestamptz not null default now(),
  primary key (club_id, shared_item_id)
);
create index tactics_club_picks_item on core.tactics_club_picks (shared_item_id);
create index tactics_club_picks_picked_by on core.tactics_club_picks (picked_by);

-- Favourites: items of the library you mark, as additions to your own
-- library (the product owner, 2026-10-25).
create table core.tactics_favorites (
  profile_id uuid not null references core.profiles(id) on delete cascade,
  shared_item_id uuid not null references core.tactics_shared_items(id) on delete cascade,
  marked_at timestamptz not null default now(),
  primary key (profile_id, shared_item_id)
);
create index tactics_favorites_item on core.tactics_favorites (shared_item_id);
alter table core.tactics_favorites enable row level security;
revoke all on core.tactics_favorites from public, anon, authenticated;
create policy tactics_favorites_no_direct_access on core.tactics_favorites
  for all to authenticated using (false) with check (false);

alter table core.tactics_club_picks enable row level security;
revoke all on core.tactics_club_picks from public, anon, authenticated;
create policy tactics_club_picks_no_direct_access on core.tactics_club_picks
  for all to authenticated using (false) with check (false);

-- The clubs whose library you use: where you lead a team or are a club
-- functionary; and whether you keep the club's list.
create or replace function internal.tactics_actor_clubs()
returns table (club_id uuid, club_name text, can_manage boolean)
language sql stable security definer set search_path = '' as $$
  select distinct club.id, club.name, internal.actor_has_capability(club.id, null, 'club.memberships.manage')
  from core.person_account_links link
  join core.assignments assignment on assignment.club_id = link.club_id
    and assignment.club_person_id = link.club_person_id and assignment.state = 'active'
    and assignment.starts_at <= now() and (assignment.ends_at is null or assignment.ends_at > now())
    and assignment.role_package in ('leader', 'club_functionary')
  join core.clubs club on club.id = link.club_id
  where link.profile_id = auth.uid() and link.state = 'active'
$$;

-- Whether you see a shared item: shared with the community, or with a club
-- you lead in; hidden ones only by their writer.
create or replace function internal.tactics_shared_visible(item core.tactics_shared_items)
returns boolean language sql stable security definer set search_path = '' as $$
  select (not item.hidden or item.owner_id is not distinct from auth.uid())
    and (item.club_id is null or item.owner_id is not distinct from auth.uid()
      or exists (select 1 from internal.tactics_actor_clubs() club where club.club_id = item.club_id))
$$;

-- As in step 2, with who sees it, and for the clubs whose list you keep
-- whether it is in their list.
create or replace function internal.tactics_shared_summary(item core.tactics_shared_items)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', item.id, 'kind', item.kind, 'title', item.title, 'details', item.details, 'version', item.version,
    'author', case when item.owner_id is null then 'TeamZone'
      else coalesce((select nullif(btrim(profile.display_name), '') from core.profiles profile where profile.id = item.owner_id),
        'En tränare') end,
    'starter', item.owner_id is null,
    'mine', item.owner_id is not distinct from auth.uid() and item.owner_id is not null,
    'hidden', item.hidden,
    'club_id', item.club_id,
    'club_name', (select club.name from core.clubs club where club.id = item.club_id),
    'favorite', exists (select 1 from core.tactics_favorites favorite
      where favorite.profile_id = auth.uid() and favorite.shared_item_id = item.id),
    'picked_by_clubs', coalesce((select jsonb_agg(pick.club_id) from core.tactics_club_picks pick
      join internal.tactics_actor_clubs() mine on mine.club_id = pick.club_id
      where pick.shared_item_id = item.id), '[]'::jsonb),
    'can_remove', (item.owner_id is not distinct from auth.uid() and item.owner_id is not null)
      or (item.club_id is not null and exists (select 1 from internal.tactics_actor_clubs() club
        where club.club_id = item.club_id and club.can_manage)),
    'board_count', jsonb_array_length(item.document->'boards'),
    'boards', (select coalesce(jsonb_agg(jsonb_build_object('id', board->>'id', 'name', board->>'name')), '[]'::jsonb)
               from jsonb_array_elements(item.document->'boards') board),
    'updated_at', item.updated_at
  )
$$;

-- As in step 2, with whom the item is shared with.
create or replace function internal.tactics_library_summary(item core.tactics_library_items)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', item.id, 'kind', item.kind, 'title', item.title, 'details', item.details, 'version', item.version,
    'source_project_id', item.source_project_id, 'source_board_id', item.source_board_id,
    'board_count', jsonb_array_length(item.document->'boards'),
    'boards', (select coalesce(jsonb_agg(jsonb_build_object('id', board->>'id', 'name', board->>'name')), '[]'::jsonb)
               from jsonb_array_elements(item.document->'boards') board),
    'shared', (select jsonb_build_object('id', shared.id, 'version', shared.version, 'hidden', shared.hidden,
        'current', shared.updated_at >= item.updated_at, 'club_id', shared.club_id,
        'club_name', (select club.name from core.clubs club where club.id = shared.club_id))
      from core.tactics_shared_items shared where shared.library_item_id = item.id),
    'updated_at', item.updated_at
  )
$$;

create or replace function internal.list_my_tactics_clubs_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('club_id', club.club_id, 'club_name', club.club_name,
      'can_manage', club.can_manage) order by club.club_name)
    from internal.tactics_actor_clubs() club), '[]'::jsonb);
end;
$$;

-- Shares an item of your library with the community (target_club_id null)
-- or only with one of your clubs; again, it shares the latest version and
-- who sees it may change.
drop function api.share_tactics_library_item(uuid);
drop function internal.share_tactics_library_item_for_actor(uuid);
create function internal.share_tactics_library_item_for_actor(target_item_id uuid, target_club_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare item core.tactics_library_items; shared core.tactics_shared_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into item from core.tactics_library_items where id = target_item_id and owner_id = auth.uid();
  if item.id is null then raise insufficient_privilege using message = 'not_found'; end if;
  if target_club_id is not null and not exists (
      select 1 from internal.tactics_actor_clubs() club where club.club_id = target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  update core.tactics_shared_items set title = item.title, details = item.details, document = item.document,
    kind = item.kind, club_id = target_club_id, version = version + 1, updated_at = now()
  where library_item_id = item.id and owner_id = auth.uid() and not hidden_by_support
  returning * into shared;
  if shared.id is null then
    if exists (select 1 from core.tactics_shared_items where library_item_id = item.id) then
      raise insufficient_privilege using message = 'hidden_by_support';
    end if;
    if (select count(*) from core.tactics_shared_items where owner_id = auth.uid()) >= 200 then
      raise check_violation using message = 'too_many_shared';
    end if;
    insert into core.tactics_shared_items (owner_id, library_item_id, kind, title, details, document, club_id)
    values (auth.uid(), item.id, item.kind, item.title, item.details, item.document, target_club_id)
    returning * into shared;
  end if;
  -- Shared only with a club, it leaves the lists of other clubs.
  if target_club_id is not null then
    delete from core.tactics_club_picks where shared_item_id = shared.id and club_id <> target_club_id;
  end if;
  return internal.tactics_shared_summary(shared);
end;
$$;

-- Removes a shared item: its writer, or for an item shared with a club one
-- who keeps the club's list. Those who used it keep their copies.
create or replace function internal.unshare_tactics_item_for_actor(target_shared_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare item core.tactics_shared_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into item from core.tactics_shared_items where id = target_shared_id;
  if item.id is null or not (coalesce(item.owner_id = auth.uid(), false)
      or (item.club_id is not null and exists (select 1 from internal.tactics_actor_clubs() club
        where club.club_id = item.club_id and club.can_manage))) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  delete from core.tactics_shared_items where id = item.id;
end;
$$;

-- Searches the library you see. With target_club_id: that club's list, the
-- items picked for it and those shared only with it; with only_favorites,
-- the items you marked. Shared by coaches
-- before TeamZone's own, newest first, 30 at a time.
drop function api.search_tactics_shared_items(text, text, text, text, text, text, integer);
drop function internal.search_tactics_shared_items_for_actor(text, text, text, text, text, text, integer);
create function internal.search_tactics_shared_items_for_actor(
  search_text text, item_kind text, exercise_part text, game_phase text, age_class text, game_form text,
  target_club_id uuid, only_favorites boolean, page integer
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare words text[];
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if length(coalesce(search_text, '')) > 100 or coalesce(page, 0) not between 0 and 100 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  if target_club_id is not null and not exists (
      select 1 from internal.tactics_actor_clubs() club where club.club_id = target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  words := array_remove(regexp_split_to_array(lower(btrim(coalesce(search_text, ''))), '\s+'), '');
  return coalesce((
    select jsonb_agg(internal.tactics_shared_summary(hit) order by hit.owner_id is null, hit.updated_at desc)
    from (
      select item.* from core.tactics_shared_items item
      where internal.tactics_shared_visible(item)
        and (target_club_id is null or item.club_id = target_club_id
          or exists (select 1 from core.tactics_club_picks pick
            where pick.club_id = target_club_id and pick.shared_item_id = item.id))
        and (not coalesce(only_favorites, false) or exists (select 1 from core.tactics_favorites favorite
          where favorite.profile_id = auth.uid() and favorite.shared_item_id = item.id))
        and (item_kind is null or item.kind = item_kind)
        and (exercise_part is null or item.details->>'part' = exercise_part
          or exists (select 1 from jsonb_array_elements(coalesce(item.details->'exercises', '[]'::jsonb)) exercise
            where exercise->>'part' = exercise_part))
        and (game_phase is null or item.details->>'phase' = game_phase
          or exists (select 1 from jsonb_array_elements(coalesce(item.details->'exercises', '[]'::jsonb)) exercise
            where exercise->>'phase' = game_phase))
        and (age_class is null or coalesce(item.details->'age_classes', '[]'::jsonb) ? age_class
          or exists (select 1 from jsonb_array_elements(coalesce(item.details->'exercises', '[]'::jsonb)) exercise
            where coalesce(exercise->'age_classes', '[]'::jsonb) ? age_class))
        and (game_form is null or coalesce(item.details->'game_forms', '[]'::jsonb) ? game_form
          or exists (select 1 from jsonb_array_elements(coalesce(item.details->'exercises', '[]'::jsonb)) exercise
            where coalesce(exercise->'game_forms', '[]'::jsonb) ? game_form))
        and not exists (select 1 from unnest(words) word
          where position(word in lower(item.title || ' ' || coalesce(item.details->>'organisation', '') || ' '
            || coalesce(item.details->>'coaching_points', '') || ' ' || coalesce(item.details->>'theme', ''))) = 0)
      order by item.owner_id is null, item.updated_at desc
      limit 30 offset coalesce(page, 0) * 30
    ) hit
  ), '[]'::jsonb);
end;
$$;

-- As in step 2, for those who see the item.
create or replace function internal.get_tactics_shared_item_for_actor(target_shared_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare item core.tactics_shared_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into item from core.tactics_shared_items where id = target_shared_id;
  if item.id is null or not internal.tactics_shared_visible(item) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return internal.tactics_shared_summary(item) || jsonb_build_object('document', item.document);
end;
$$;

-- As in step 2: only what you see can be reported.
create or replace function internal.report_tactics_shared_item_for_actor(target_shared_id uuid, report_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare item core.tactics_shared_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  select * into item from core.tactics_shared_items where id = target_shared_id;
  if item.id is null or item.hidden or item.owner_id is not distinct from auth.uid()
    or not internal.tactics_shared_visible(item) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if length(btrim(coalesce(report_reason, ''))) not between 1 and 500 then
    raise invalid_parameter_value using message = 'invalid_input';
  end if;
  insert into core.tactics_shared_reports (shared_item_id, reporter_id, reason)
  values (item.id, auth.uid(), btrim(report_reason))
  on conflict (shared_item_id, reporter_id) do nothing;
  if (select count(*) from core.tactics_shared_reports report
      where report.shared_item_id = item.id and report.resolved_at is null) >= 3 then
    update core.tactics_shared_items set hidden = true where id = item.id;
  end if;
end;
$$;

-- Puts an item of the whole library in a club's list, or takes it out: for
-- those who keep the club's list. At most 1000 a club.
create or replace function internal.set_tactics_club_pick_for_actor(target_club_id uuid, target_shared_id uuid, picked boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare item core.tactics_shared_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if picked is null or not exists (select 1 from internal.tactics_actor_clubs() club
      where club.club_id = target_club_id and club.can_manage) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if not picked then
    delete from core.tactics_club_picks where club_id = target_club_id and shared_item_id = target_shared_id;
    return;
  end if;
  select * into item from core.tactics_shared_items where id = target_shared_id;
  if item.id is null or item.hidden or not (item.club_id is null or item.club_id = target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if (select count(*) from core.tactics_club_picks where club_id = target_club_id) >= 1000 then
    raise check_violation using message = 'too_many_picks';
  end if;
  insert into core.tactics_club_picks (club_id, shared_item_id, picked_by)
  values (target_club_id, item.id, auth.uid())
  on conflict (club_id, shared_item_id) do nothing;
end;
$$;

create function api.share_tactics_library_item(target_item_id uuid, target_club_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select internal.share_tactics_library_item_for_actor(target_item_id, target_club_id) $$;
create function api.search_tactics_shared_items(search_text text, item_kind text, exercise_part text,
  game_phase text, age_class text, game_form text, target_club_id uuid, only_favorites boolean, page integer) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.search_tactics_shared_items_for_actor(search_text, item_kind, exercise_part, game_phase, age_class,
    game_form, target_club_id, only_favorites, page) $$;
-- Marks an item you see as a favourite, or unmarks it. At most 500.
create or replace function internal.set_tactics_favorite_for_actor(target_shared_id uuid, marked boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare item core.tactics_shared_items;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if marked is null then raise invalid_parameter_value using message = 'invalid_input'; end if;
  if not marked then
    delete from core.tactics_favorites where profile_id = auth.uid() and shared_item_id = target_shared_id;
    return;
  end if;
  select * into item from core.tactics_shared_items where id = target_shared_id;
  if item.id is null or not internal.tactics_shared_visible(item) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if (select count(*) from core.tactics_favorites where profile_id = auth.uid()) >= 500 then
    raise check_violation using message = 'too_many_favorites';
  end if;
  insert into core.tactics_favorites (profile_id, shared_item_id) values (auth.uid(), item.id)
  on conflict (profile_id, shared_item_id) do nothing;
end;
$$;
create or replace function api.set_tactics_favorite(target_shared_id uuid, marked boolean) returns void
language sql security invoker set search_path = '' as $$ select internal.set_tactics_favorite_for_actor(target_shared_id, marked) $$;
create or replace function api.list_my_tactics_clubs() returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.list_my_tactics_clubs_for_actor() $$;
create or replace function api.set_tactics_club_pick(target_club_id uuid, target_shared_id uuid, picked boolean) returns void
language sql security invoker set search_path = '' as $$ select internal.set_tactics_club_pick_for_actor(target_club_id, target_shared_id, picked) $$;

revoke all on function
  internal.tactics_actor_clubs(), internal.tactics_shared_visible(core.tactics_shared_items),
  internal.list_my_tactics_clubs_for_actor(), internal.share_tactics_library_item_for_actor(uuid, uuid),
  internal.search_tactics_shared_items_for_actor(text, text, text, text, text, text, uuid, boolean, integer),
  internal.set_tactics_favorite_for_actor(uuid, boolean),
  internal.set_tactics_club_pick_for_actor(uuid, uuid, boolean),
  api.share_tactics_library_item(uuid, uuid),
  api.search_tactics_shared_items(text, text, text, text, text, text, uuid, boolean, integer),
  api.set_tactics_favorite(uuid, boolean),
  api.list_my_tactics_clubs(), api.set_tactics_club_pick(uuid, uuid, boolean)
from public, anon, authenticated;
grant execute on function
  internal.list_my_tactics_clubs_for_actor(), internal.share_tactics_library_item_for_actor(uuid, uuid),
  internal.search_tactics_shared_items_for_actor(text, text, text, text, text, text, uuid, boolean, integer),
  internal.set_tactics_favorite_for_actor(uuid, boolean),
  internal.set_tactics_club_pick_for_actor(uuid, uuid, boolean),
  api.share_tactics_library_item(uuid, uuid),
  api.search_tactics_shared_items(text, text, text, text, text, text, uuid, boolean, integer),
  api.set_tactics_favorite(uuid, boolean),
  api.list_my_tactics_clubs(), api.set_tactics_club_pick(uuid, uuid, boolean)
to authenticated;
notify pgrst, 'reload schema';
