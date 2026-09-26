-- PUB-03: draft save reached the API but failed with SQLSTATE 42702 because
-- article_id was both a PL/pgSQL variable and a column of the channel table.
-- Keep the existing signature, authorization, dedupe and audit behavior.
create or replace function internal.save_editorial_article_for_actor(
  target_club_id uuid,
  target_article_id uuid,
  new_slug text,
  new_title text,
  new_summary text,
  new_blocks jsonb,
  new_author_label text,
  new_publish_to_club boolean,
  new_team_ids uuid[],
  expected_revision bigint,
  idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  article core.editorial_articles%rowtype;
  existing jsonb;
  saved_article_id uuid;
  new_revision bigint;
begin
  if actor_id is null or not internal.actor_has_capability(target_club_id, null, 'publication.manage') then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if lower(btrim(coalesce(new_slug, ''))) !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
    or length(btrim(new_slug)) not between 2 and 100
    or length(btrim(new_title)) not between 1 and 160
    or (new_summary is not null and length(new_summary) > 1000)
    or not internal.editorial_blocks_valid(new_blocks)
    or cardinality(coalesce(new_team_ids, array[]::uuid[])) > 20
    or (not new_publish_to_club and cardinality(coalesce(new_team_ids, array[]::uuid[])) = 0)
  then
    raise invalid_parameter_value using message = 'invalid_article';
  end if;
  if exists (
    select 1
    from unnest(coalesce(new_team_ids, array[]::uuid[])) as selected_team(team_id)
    where not exists (
      select 1 from core.teams team
      where team.id = selected_team.team_id
        and team.club_id = target_club_id
        and team.status = 'active'
    )
  ) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select dedupe.result into existing
  from internal.command_deduplication dedupe
  where dedupe.actor_profile_id = actor_id
    and dedupe.command_type = 'publication.article.save.v1'
    and dedupe.idempotency_key = save_editorial_article_for_actor.idempotency_key;
  if existing is not null then return existing; end if;

  if target_article_id is null then
    insert into core.editorial_articles(
      club_id, slug, title, summary, body_blocks, author_label,
      publish_to_club, created_by, updated_by
    ) values (
      target_club_id, lower(btrim(new_slug)), btrim(new_title), nullif(btrim(new_summary), ''),
      new_blocks, nullif(btrim(new_author_label), ''), new_publish_to_club, actor_id, actor_id
    ) returning id, revision into saved_article_id, new_revision;
  else
    select * into article
    from core.editorial_articles candidate
    where candidate.id = target_article_id and candidate.club_id = target_club_id
    for update;
    if article.id is null then raise insufficient_privilege using message = 'not_found'; end if;
    if article.revision <> expected_revision then raise serialization_failure using message = 'stale_revision'; end if;
    if article.state = 'published' then raise check_violation using message = 'unpublish_before_edit'; end if;
    update core.editorial_articles set
      slug = lower(btrim(new_slug)), title = btrim(new_title),
      summary = nullif(btrim(new_summary), ''), body_blocks = new_blocks,
      author_label = nullif(btrim(new_author_label), ''), publish_to_club = new_publish_to_club,
      updated_by = actor_id, updated_at = now(), revision = revision + 1
    where id = article.id
    returning id, revision into saved_article_id, new_revision;
  end if;

  delete from core.editorial_article_channels channel
  where channel.article_id = saved_article_id;
  insert into core.editorial_article_channels(article_id, club_id, team_id)
  select saved_article_id, target_club_id, selected_team.team_id
  from unnest(coalesce(new_team_ids, array[]::uuid[])) as selected_team(team_id);
  select * into article
  from core.editorial_articles candidate
  where candidate.id = saved_article_id;
  insert into core.editorial_article_revisions(
    article_id, club_id, article_revision, action, snapshot, actor_profile_id
  ) values (
    saved_article_id, target_club_id, new_revision,
    case when new_revision = 1 then 'created' else 'saved' end,
    internal.editorial_snapshot(article), actor_id
  );
  existing := jsonb_build_object(
    'article_id', saved_article_id, 'state', article.state, 'revision', new_revision
  );
  insert into internal.command_deduplication(actor_profile_id, idempotency_key, command_type, result)
  values(actor_id, idempotency_key, 'publication.article.save.v1', existing);
  return existing;
end;
$$;
