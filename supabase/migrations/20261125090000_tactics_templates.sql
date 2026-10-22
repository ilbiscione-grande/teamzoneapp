-- Webtools Tacticsboard: your own templates. A template is one or more
-- boards saved under a name, to start a new project from or to add to one.
-- It is the document's boards without the squad or ties to TeamZone
-- players (Webtools strips them before saving). Saving under a name you
-- already have replaces that template.

create table core.tactics_templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references core.profiles(id),
  name text not null check (length(btrim(name)) between 1 and 80),
  kind text not null default 'match' check (kind in ('match', 'training', 'education')),
  document jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(document) = 'object' and jsonb_typeof(document->'boards') = 'array'),
  check (pg_column_size(document) <= 4000000)
);
create unique index tactics_templates_owner_name on core.tactics_templates (owner_id, lower(btrim(name)));

alter table core.tactics_templates enable row level security;
revoke all on core.tactics_templates from public, anon, authenticated;

-- Your templates, the latest first: names and the boards' names, no documents.
create or replace function internal.list_my_tactics_templates_for_actor()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', template.id, 'name', template.name, 'kind', template.kind,
    'boards', (select coalesce(jsonb_agg(jsonb_build_object('id', board->>'id', 'name', board->>'name')), '[]'::jsonb)
               from jsonb_array_elements(template.document->'boards') board),
    'updated_at', template.updated_at
  ) order by template.updated_at desc), '[]'::jsonb)
  from core.tactics_templates template where template.owner_id = auth.uid()
$$;

create or replace function internal.get_tactics_template_for_actor(target_template_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare template core.tactics_templates;
begin
  select * into template from core.tactics_templates where id = target_template_id;
  if template.id is null or template.owner_id is distinct from auth.uid() then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object('id', template.id, 'name', template.name, 'kind', template.kind, 'document', template.document);
end;
$$;

-- Saves a template; the same name again replaces it. At most 100 each.
create or replace function internal.save_tactics_template_for_actor(template_name text, template_kind text, template_document jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare saved uuid;
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'not_signed_in'; end if;
  if template_kind not in ('match', 'training', 'education') then raise invalid_parameter_value using message = 'invalid_kind'; end if;
  if jsonb_typeof(coalesce(template_document, 'null')) <> 'object' or jsonb_typeof(template_document->'boards') <> 'array'
    or jsonb_array_length(template_document->'boards') = 0 then
    raise invalid_parameter_value using message = 'invalid_document';
  end if;
  if length(btrim(coalesce(template_name, ''))) not between 1 and 80 then raise invalid_parameter_value using message = 'invalid_name'; end if;
  update core.tactics_templates set name = btrim(template_name), kind = template_kind, document = template_document, updated_at = now()
  where owner_id = auth.uid() and lower(btrim(name)) = lower(btrim(template_name))
  returning id into saved;
  if saved is not null then return saved; end if;
  if (select count(*) from core.tactics_templates where owner_id = auth.uid()) >= 100 then
    raise check_violation using message = 'too_many_templates';
  end if;
  insert into core.tactics_templates (owner_id, name, kind, document)
  values (auth.uid(), btrim(template_name), template_kind, template_document)
  returning id into saved;
  return saved;
end;
$$;

create or replace function internal.delete_tactics_template_for_actor(target_template_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from core.tactics_templates where id = target_template_id and owner_id = auth.uid();
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
end;
$$;

create or replace function api.list_my_tactics_templates() returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.list_my_tactics_templates_for_actor() $$;
create or replace function api.get_tactics_template(target_template_id uuid) returns jsonb language sql stable security invoker set search_path = '' as
$$ select internal.get_tactics_template_for_actor(target_template_id) $$;
create or replace function api.save_tactics_template(template_name text, template_kind text, template_document jsonb)
returns uuid language sql security invoker set search_path = '' as
$$ select internal.save_tactics_template_for_actor(template_name, template_kind, template_document) $$;
create or replace function api.delete_tactics_template(target_template_id uuid) returns void language sql security invoker set search_path = '' as
$$ select internal.delete_tactics_template_for_actor(target_template_id) $$;

revoke all on function
  internal.list_my_tactics_templates_for_actor(), internal.get_tactics_template_for_actor(uuid),
  internal.save_tactics_template_for_actor(text, text, jsonb), internal.delete_tactics_template_for_actor(uuid),
  api.list_my_tactics_templates(), api.get_tactics_template(uuid),
  api.save_tactics_template(text, text, jsonb), api.delete_tactics_template(uuid)
from public, anon, authenticated;
grant execute on function
  internal.list_my_tactics_templates_for_actor(), internal.get_tactics_template_for_actor(uuid),
  internal.save_tactics_template_for_actor(text, text, jsonb), internal.delete_tactics_template_for_actor(uuid),
  api.list_my_tactics_templates(), api.get_tactics_template(uuid),
  api.save_tactics_template(text, text, jsonb), api.delete_tactics_template(uuid)
to authenticated;
