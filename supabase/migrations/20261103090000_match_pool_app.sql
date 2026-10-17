-- POOL-01, the app: match pool conversations in the app's inbox (the list
-- and each conversation reuse the pool's own functions), notifications that
-- open the conversation, and a one-time sign-in code so a leader who goes
-- from the app to teamzoneapp.se is signed in there too.
--
-- The sign-in code: the app asks for it as the signed-in user, opens the
-- web page with it in the URL fragment (never sent to a server log), and
-- the site's server exchanges it once for a session for that same user.
-- 32 random bytes, only the hash stored, valid two minutes, single use.

create table if not exists internal.web_handoffs (
  code_hash bytea primary key,
  profile_id uuid not null references core.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz
);
create index if not exists web_handoffs_profile_idx on internal.web_handoffs(profile_id, created_at);
alter table internal.web_handoffs enable row level security;
revoke all on internal.web_handoffs from public, anon, authenticated;

create or replace function internal.create_web_handoff_for_actor()
returns text language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); code text;
begin
  if actor_id is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  delete from internal.web_handoffs where expires_at < now() - interval '1 day';
  if (select count(*) from internal.web_handoffs where profile_id = actor_id
      and created_at > now() - interval '10 minutes') >= 10 then
    raise insufficient_privilege using message = 'rate_limited';
  end if;
  code := encode(extensions.gen_random_bytes(32), 'hex');
  insert into internal.web_handoffs(code_hash, profile_id, expires_at)
  values (extensions.digest(code, 'sha256'), actor_id, now() + interval '2 minutes');
  return code;
end;$$;

-- The site's server only: the code's user, once, or null.
create or replace function internal.consume_web_handoff(handoff_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare owner uuid;
begin
  if current_user not in ('postgres', 'service_role') then raise insufficient_privilege; end if;
  if handoff_code is null or handoff_code !~ '^[0-9a-f]{64}$' then return null; end if;
  update internal.web_handoffs set consumed_at = now()
  where code_hash = extensions.digest(handoff_code, 'sha256') and consumed_at is null and expires_at > now()
  returning profile_id into owner;
  return owner;
end;$$;

-- Every conversation the leader's teams are part of, newest first.
create or replace function internal.list_match_pool_conversations_for_actor()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege using message = 'unauthenticated'; end if;
  return coalesce((select jsonb_agg(item order by sort_at desc) from (
    select internal.match_pool_interest_json(interest, side.value)
        || jsonb_build_object('my_side', side.value,
          'other_team_name', case when side.value = 'listing' then interest_team.name else listing_team.name end,
          'other_club_name', case when side.value = 'listing' then interest_club.name else listing_club.name end,
          'other_verified', case when side.value = 'listing' then interest_club.verification_status = 'official'
            else listing_club.verification_status = 'official' end,
          'listing', internal.match_pool_listing_json(listing, null, null,
            side.value = 'listing' or interest.state = 'accepted')) as item,
      coalesce((select max(message.created_at) from internal.match_pool_messages message
        where message.interest_id = interest.id), interest.updated_at) as sort_at
    from internal.match_pool_interests interest
    join internal.match_pool_listings listing on listing.id = interest.listing_id
    join core.teams listing_team on listing_team.id = listing.team_id
    join core.clubs listing_club on listing_club.id = listing_team.club_id
    join core.teams interest_team on interest_team.id = interest.team_id
    join core.clubs interest_club on interest_club.id = interest_team.club_id
    cross join lateral (select internal.match_pool_actor_side(interest.id) as value) side
    where side.value is not null and interest.state <> 'withdrawn'
      and interest.updated_at > now() - interval '30 days'
    order by sort_at desc limit 200) rows), '[]'::jsonb);
end;$$;

-- As in 20260924143236, with match pool conversations.
create or replace function internal.notification_deep_link(
  outbox internal.notification_outbox)
returns text
language sql
stable
set search_path=''
as $$
  select case
    when outbox.event_type='message.message.sent.v1'
      and outbox.payload_ref->>'thread_id'~'^[0-9a-fA-F-]{36}$'
      then '/inbox?thread='||(outbox.payload_ref->>'thread_id')
    when outbox.event_type like 'matchpool.%'
      and outbox.payload_ref->>'interest_id'~'^[0-9a-fA-F-]{36}$'
      then '/inbox?pool='||(outbox.payload_ref->>'interest_id')
    when outbox.event_type like 'callup.%'
      and outbox.payload_ref->>'event_id'~'^[0-9a-fA-F-]{36}$'
      then '/calendar/event/'||(outbox.payload_ref->>'event_id')
    when outbox.aggregate_type='event'
      then '/calendar/event/'||outbox.aggregate_id::text
    else '/inbox'
  end;
$$;

create or replace function api.create_web_handoff()
returns text language sql security invoker set search_path = '' as
$$select internal.create_web_handoff_for_actor()$$;
create or replace function api.consume_web_handoff(handoff_code text)
returns uuid language sql security invoker set search_path = '' as
$$select internal.consume_web_handoff(handoff_code)$$;
create or replace function api.list_match_pool_conversations()
returns jsonb language sql security invoker set search_path = '' as
$$select internal.list_match_pool_conversations_for_actor()$$;

revoke all on function internal.create_web_handoff_for_actor(), internal.consume_web_handoff(text),
  internal.list_match_pool_conversations_for_actor(), internal.notification_deep_link(internal.notification_outbox),
  api.create_web_handoff(), api.consume_web_handoff(text), api.list_match_pool_conversations()
  from public, anon, authenticated;
grant execute on function internal.create_web_handoff_for_actor(), internal.list_match_pool_conversations_for_actor(),
  api.create_web_handoff(), api.list_match_pool_conversations()
  to authenticated;
grant execute on function internal.consume_web_handoff(text), api.consume_web_handoff(text) to service_role;

insert into internal.migration_provenance (migration_name, source_kind, source_reference)
select '20261103090000_match_pool_app', 'greenfield',
  'POOL-01: match pool conversations in the app and sign-in from the app to the web'
where not exists (select 1 from internal.migration_provenance where migration_name = '20261103090000_match_pool_app');
notify pgrst, 'reload schema';
