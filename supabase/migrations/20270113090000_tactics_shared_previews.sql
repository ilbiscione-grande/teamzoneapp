-- TeamZone's library as a grid (the product owner, 2026-10-31): each item
-- shows a small picture of its first board, as projects do on the start
-- page (20270109090000). The item's summary carries the preview of its
-- first board: the board's view, teams and first frame's objects.

-- The summary as in 20261215090000, now with the preview.
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
    'updated_at', item.updated_at,
    'preview', internal.tactics_board_preview(item.document, null)
  )
$$;
