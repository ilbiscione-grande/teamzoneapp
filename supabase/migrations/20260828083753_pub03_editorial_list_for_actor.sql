-- PUB-03 authenticated editor list. Local migration only until separately approved.
create function internal.list_editorial_articles_for_actor(target_club_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare actor_id uuid:=auth.uid(); result jsonb;
begin
  if actor_id is null or not internal.actor_has_capability(target_club_id,null,'publication.manage') then
    raise insufficient_privilege using message='not_found';
  end if;
  select coalesce(jsonb_agg(
    internal.editorial_snapshot(article)||jsonb_build_object(
      'teams',coalesce((select jsonb_agg(channel.team_id order by channel.team_id)
        from core.editorial_article_channels channel where channel.article_id=article.id),'[]'::jsonb)
    ) order by article.updated_at desc,article.id desc
  ),'[]'::jsonb) into result
  from core.editorial_articles article where article.club_id=target_club_id;
  return result;
end;$$;

create function api.list_editorial_articles(club_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $$select internal.list_editorial_articles_for_actor(club_id)$$;

revoke all on function internal.list_editorial_articles_for_actor(uuid),api.list_editorial_articles(uuid)
from public,anon,authenticated;
grant execute on function internal.list_editorial_articles_for_actor(uuid),api.list_editorial_articles(uuid)
to authenticated;
