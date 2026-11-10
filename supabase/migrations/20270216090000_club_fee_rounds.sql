-- Avgiftsomgångar och familjer (club-members-and-fees.md, step 2).
-- A round is a membership fee (an amount per category, with a family rule)
-- or a team fee (an amount per player). It is a draft until it is issued;
-- then one fee per person is created with the amounts frozen. Nobody is told
-- yet: reminders are steps 4-5, payments step 3.
-- Families: members linked through guardians (siblings with a shared
-- guardian, a parent who is a member) form one family; the club can merge
-- and split families by hand, which then holds until reset.
-- Own tables, not core.fee_obligations: those belong to an economy account
-- (the Economy module), while fees are part of the base app.
-- Handled by club admin and treasurer (club.memberships.manage or
-- economy.manage) until the permissions review.

create table core.club_family_overrides (
  club_person_id uuid primary key,
  club_id uuid not null references core.clubs(id),
  family_key uuid not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id),
  foreign key (club_person_id, club_id) references core.club_people(id, club_id)
);
create index club_family_overrides_club_idx on core.club_family_overrides(club_id);
alter table core.club_family_overrides enable row level security;
revoke all on core.club_family_overrides from public, anon, authenticated;

-- Amounts in öre (SEK).
create table core.club_fee_rounds (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  kind text not null check (kind in ('membership', 'team')),
  team_id uuid,
  title text not null check (length(btrim(title)) between 1 and 120),
  due_on date not null,
  amount_youth bigint check (amount_youth >= 0),
  amount_adult bigint check (amount_adult >= 0),
  amount_supporter bigint check (amount_supporter >= 0),
  amount_player bigint check (amount_player >= 0),
  family_cap bigint check (family_cap > 0),
  sibling_discount_percent smallint check (sibling_discount_percent between 1 and 100),
  state text not null default 'draft' check (state in ('draft', 'issued', 'cancelled')),
  created_at timestamptz not null default now(),
  created_by uuid references core.profiles(id),
  updated_at timestamptz not null default now(),
  issued_at timestamptz,
  issued_by uuid references core.profiles(id),
  revision bigint not null default 1 check (revision > 0),
  unique (id, club_id),
  foreign key (team_id, club_id) references core.teams(id, club_id),
  check ((kind = 'team') = (team_id is not null)),
  check (kind = 'membership' or (family_cap is null and sibling_discount_percent is null)),
  check ((state = 'issued') = (issued_at is not null))
);
create index club_fee_rounds_club_idx on core.club_fee_rounds(club_id, created_at desc);
alter table core.club_fee_rounds enable row level security;
revoke all on core.club_fee_rounds from public, anon, authenticated;

-- waived: nothing to pay, for example covered by the family cap.
create table core.club_fees (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null,
  club_id uuid not null references core.clubs(id),
  club_person_id uuid not null,
  family_key uuid,
  category text check (category in ('youth', 'adult', 'supporter')),
  base_amount bigint not null check (base_amount >= 0),
  discount_amount bigint not null check (discount_amount >= 0),
  amount bigint not null check (amount >= 0 and amount = base_amount - discount_amount),
  state text not null default 'open' check (state in ('open', 'paid', 'waived', 'cancelled')),
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (round_id, club_person_id),
  foreign key (round_id, club_id) references core.club_fee_rounds(id, club_id),
  foreign key (club_person_id, club_id) references core.club_people(id, club_id)
);
create index club_fees_person_idx on core.club_fees(club_id, club_person_id);
alter table core.club_fees enable row level security;
revoke all on core.club_fees from public, anon, authenticated;

create or replace function internal.actor_can_manage_club_fees(target_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (internal.actor_has_capability(target_club_id, null, 'club.memberships.manage')
    or internal.actor_has_capability(target_club_id, null, 'economy.manage'))
$$;

-- Everyone active, with their family: the club's own choice, otherwise the
-- smallest person id among those linked through guardian relations.
create or replace function internal.club_family_keys(target_club_id uuid)
returns table (person_id uuid, family_key uuid, manual boolean)
language sql stable security definer set search_path = '' as $$
  with recursive people as (
    select person.id from core.club_people person
    where person.club_id = target_club_id and person.status = 'active'
  ), edges as (
    select relation.guardian_person_id as a, relation.child_person_id as b
    from core.guardian_relations relation
    join people guardian on guardian.id = relation.guardian_person_id
    join people child on child.id = relation.child_person_id
    where relation.club_id = target_club_id and relation.state = 'active'
      and (relation.ends_at is null or relation.ends_at > now())
  ), links as (
    select a, b from edges union select b, a from edges
  ), reach (start_id, node_id) as (
    select id, id from people
    union
    select reach.start_id, links.b from reach join links on links.a = reach.node_id
  ), derived as (
    select start_id, min(node_id::text)::uuid as key from reach group by start_id
  )
  select derived.start_id, coalesce(override.family_key, derived.key), override.club_person_id is not null
  from derived
  left join core.club_family_overrides override
    on override.club_person_id = derived.start_id and override.club_id = target_club_id
$$;

-- The members with their category, as the register shows them.
create or replace function internal.club_effective_members(target_club_id uuid)
returns table (person_id uuid, name text, category text)
language sql stable security definer set search_path = '' as $$
  select person.id, person.display_name,
    coalesce(membership.category, internal.club_member_default_category(person.birth_year))
  from core.club_people person
  left join core.club_memberships membership on membership.club_person_id = person.id
  where person.club_id = target_club_id and person.status = 'active'
    and coalesce(membership.is_member, internal.club_person_is_default_member(target_club_id, person.id))
$$;

-- The fees a round gives. Family rule (membership rounds): the most
-- expensive fee in a family is whole, the sibling discount applies to the
-- rest; then the cap limits the total of a family with two or more fees,
-- taken from the last fees.
create or replace function internal.club_fee_round_lines(target_round_id uuid)
returns table (person_id uuid, name text, category text, family_key uuid, base_amount bigint,
  discount_amount bigint, amount bigint)
language sql stable security definer set search_path = '' as $$
  with fee_round as (
    select * from core.club_fee_rounds where id = target_round_id
  ), candidates as (
    select member.person_id, member.name, member.category,
      case member.category when 'youth' then fee_round.amount_youth when 'adult' then fee_round.amount_adult
        when 'supporter' then fee_round.amount_supporter end as base_amount
    from fee_round cross join internal.club_effective_members(fee_round.club_id) member
    where fee_round.kind = 'membership'
    union all
    select person.id, person.display_name,
      coalesce(membership.category, internal.club_member_default_category(person.birth_year)), fee_round.amount_player
    from fee_round
    join core.team_assignments assignment on assignment.team_id = fee_round.team_id
      and assignment.club_id = fee_round.club_id and assignment.state = 'active'
    join core.club_people person on person.id = assignment.club_person_id and person.status = 'active'
    left join core.club_memberships membership on membership.club_person_id = person.id
    where fee_round.kind = 'team'
  ), keyed as (
    select distinct on (candidates.person_id) candidates.*,
      case when fee_round.kind = 'membership' then family.family_key else candidates.person_id end as family_key
    from candidates cross join fee_round
    left join internal.club_family_keys(fee_round.club_id) family on family.person_id = candidates.person_id
    where candidates.base_amount > 0
  ), ranked as (
    select keyed.*, row_number() over (partition by keyed.family_key
      order by keyed.base_amount desc, keyed.name, keyed.person_id) as position,
      count(*) over (partition by keyed.family_key) as family_size
    from keyed
  ), discounted as (
    select ranked.*, ranked.base_amount - case when ranked.position > 1 and fee_round.sibling_discount_percent is not null
        then round(ranked.base_amount * fee_round.sibling_discount_percent / 100.0)::bigint else 0 end as after_discount,
      fee_round.family_cap
    from ranked cross join fee_round
  ), capped as (
    select discounted.*, coalesce(sum(discounted.after_discount) over (partition by discounted.family_key
      order by discounted.position rows between unbounded preceding and 1 preceding), 0) as before_this
    from discounted
  ), finished as (
    select capped.*, case when capped.family_cap is null or capped.family_size < 2 then capped.after_discount
      else greatest(0, least(capped.after_discount, capped.family_cap - capped.before_this)) end as final_amount
    from capped
  )
  select finished.person_id, finished.name, finished.category, finished.family_key, finished.base_amount,
    finished.base_amount - finished.final_amount, finished.final_amount
  from finished
$$;

create or replace function internal.club_person_guardian_names(target_club_id uuid, target_person_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(distinct guardian.display_name), '[]'::jsonb)
  from core.guardian_relations relation
  join core.club_people guardian on guardian.id = relation.guardian_person_id and guardian.status = 'active'
  where relation.club_id = target_club_id and relation.child_person_id = target_person_id and relation.state = 'active'
    and (relation.ends_at is null or relation.ends_at > now())
$$;

create or replace function internal.club_fee_round_json(fee_round core.club_fee_rounds)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('round_id', fee_round.id, 'kind', fee_round.kind, 'team_id', fee_round.team_id,
    'team_name', (select team.name from core.teams team where team.id = fee_round.team_id),
    'title', fee_round.title, 'due_on', fee_round.due_on,
    'amounts', jsonb_strip_nulls(jsonb_build_object('youth', fee_round.amount_youth, 'adult', fee_round.amount_adult,
      'supporter', fee_round.amount_supporter, 'player', fee_round.amount_player)),
    'family_cap', fee_round.family_cap, 'sibling_discount_percent', fee_round.sibling_discount_percent,
    'state', fee_round.state, 'issued_at', fee_round.issued_at, 'revision', fee_round.revision)
$$;

create or replace function internal.get_club_families_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object('members', coalesce((select jsonb_agg(jsonb_build_object(
      'person_id', member.person_id, 'name', member.name, 'category', member.category,
      'family_key', family.family_key, 'manual', family.manual,
      'guardians', internal.club_person_guardian_names(target_club_id, member.person_id))
      order by member.name, member.person_id)
    from internal.club_effective_members(target_club_id) member
    join internal.club_family_keys(target_club_id) family on family.person_id = member.person_id), '[]'::jsonb));
end;
$$;

-- The members in the families of the given people.
create or replace function internal.club_family_members_of(target_club_id uuid, target_person_ids uuid[])
returns table (person_id uuid) language sql stable security definer set search_path = '' as $$
  with family as (select * from internal.club_family_keys(target_club_id))
  select member.person_id from internal.club_effective_members(target_club_id) member
  join family on family.person_id = member.person_id
  where family.family_key in (select chosen.family_key from family chosen where chosen.person_id = any(target_person_ids))
$$;

-- merge: the families of the given people become one. split: each given
-- person gets a family of their own. reset: the families of the given
-- people follow the guardians again.
create or replace function internal.change_club_family_for_actor(target_club_id uuid, change text,
  target_person_ids uuid[], idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); cached jsonb; result jsonb; merged_key uuid := gen_random_uuid(); affected int;
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if idempotency_key is null or change is null or change not in ('merge', 'split', 'reset')
    or coalesce(cardinality(target_person_ids), 0) = 0 or cardinality(target_person_ids) > 100
    or (change = 'merge' and cardinality(target_person_ids) < 2) then
    raise invalid_parameter_value using message = 'invalid_family_change';
  end if;
  select d.result into cached from internal.command_deduplication d where d.actor_profile_id = actor_id
    and d.command_type = 'club.family.changed.v1' and d.idempotency_key = change_club_family_for_actor.idempotency_key;
  if cached is not null then return cached; end if;
  perform pg_advisory_xact_lock(hashtextextended('club-families:' || target_club_id::text, 0));
  if exists (select 1 from unnest(target_person_ids) given(id)
      where not exists (select 1 from internal.club_effective_members(target_club_id) member where member.person_id = given.id)) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if change = 'split' then
    insert into core.club_family_overrides (club_person_id, club_id, family_key, updated_by)
    select given.id, target_club_id, gen_random_uuid(), actor_id from unnest(target_person_ids) given(id)
    on conflict (club_person_id) do update set family_key = excluded.family_key, updated_at = now(), updated_by = excluded.updated_by;
  elsif change = 'merge' then
    insert into core.club_family_overrides (club_person_id, club_id, family_key, updated_by)
    select target.person_id, target_club_id, merged_key, actor_id
    from internal.club_family_members_of(target_club_id, target_person_ids) target
    on conflict (club_person_id) do update set family_key = excluded.family_key, updated_at = now(), updated_by = excluded.updated_by;
  else
    delete from core.club_family_overrides override
    where override.club_id = target_club_id and override.club_person_id in (
      select target.person_id from internal.club_family_members_of(target_club_id, target_person_ids) target);
  end if;
  get diagnostics affected = row_count;
  result := jsonb_build_object('change', change, 'affected', affected);
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'club.family.changed.v1', result);
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  values (target_club_id, actor_id, 'club.family.changed.v1', 'club', target_club_id, 1,
    jsonb_build_object('change', change, 'people', to_jsonb(target_person_ids)));
  return result;
end;
$$;

create or replace function internal.get_club_fee_rounds_for_actor(target_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  return jsonb_build_object('rounds', coalesce((select jsonb_agg(internal.club_fee_round_json(fee_round)
      || (select jsonb_build_object('fee_count', count(*) filter (where totals.amount > 0),
        'total', coalesce(sum(totals.amount), 0))
        from (select line.amount from internal.club_fee_round_lines(fee_round.id) line where fee_round.state = 'draft'
          union all
          select fee.amount from core.club_fees fee where fee.round_id = fee_round.id and fee_round.state = 'issued') totals)
      order by fee_round.created_at desc)
    from core.club_fee_rounds fee_round
    where fee_round.club_id = target_club_id and fee_round.state <> 'cancelled'), '[]'::jsonb));
end;
$$;

-- One round with its fees: computed while a draft, as created once issued.
-- missing: members a membership round cannot charge (no category known).
create or replace function internal.get_club_fee_round_for_actor(target_club_id uuid, target_round_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare fee_round core.club_fee_rounds%rowtype;
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  select * into fee_round from core.club_fee_rounds where id = target_round_id and club_id = target_club_id and state <> 'cancelled';
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  return internal.club_fee_round_json(fee_round) || jsonb_build_object(
    'fees', coalesce((select jsonb_agg(jsonb_build_object('person_id', line.person_id, 'name', line.name,
        'category', line.category, 'family_key', line.family_key, 'base_amount', line.base_amount,
        'discount_amount', line.discount_amount, 'amount', line.amount, 'state', line.state,
        'guardians', internal.club_person_guardian_names(target_club_id, line.person_id))
        order by line.name, line.person_id)
      from (
        select computed.*, case when computed.amount = 0 then 'waived' else 'open' end as state
        from internal.club_fee_round_lines(fee_round.id) computed where fee_round.state = 'draft'
        union all
        select fee.club_person_id, person.display_name, fee.category, fee.family_key, fee.base_amount,
          fee.discount_amount, fee.amount, fee.state
        from core.club_fees fee join core.club_people person on person.id = fee.club_person_id
        where fee.round_id = fee_round.id and fee_round.state = 'issued') line), '[]'::jsonb),
    'missing', case when fee_round.kind = 'membership' and fee_round.state = 'draft' then
      coalesce((select jsonb_agg(member.name order by member.name)
        from internal.club_effective_members(target_club_id) member where member.category is null), '[]'::jsonb)
      else '[]'::jsonb end);
end;
$$;

-- payload: kind, team_id, title, due_on (yyyy-mm-dd), amount_youth,
-- amount_adult, amount_supporter, amount_player (öre), family_cap (öre),
-- sibling_discount_percent. target_round_id null creates a draft.
create or replace function internal.save_club_fee_round_for_actor(target_club_id uuid, target_round_id uuid,
  payload jsonb, expected_revision bigint, idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); cached jsonb; current_round core.club_fee_rounds%rowtype; result jsonb;
  new_kind text; new_team uuid; new_title text; new_due date; youth bigint; adult bigint; supporter bigint;
  player bigint; cap bigint; discount smallint;
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if idempotency_key is null or expected_revision is null or jsonb_typeof(payload) is distinct from 'object' then
    raise invalid_parameter_value using message = 'invalid_fee_round';
  end if;
  select d.result into cached from internal.command_deduplication d where d.actor_profile_id = actor_id
    and d.command_type = 'club.fee_round.saved.v1' and d.idempotency_key = save_club_fee_round_for_actor.idempotency_key;
  if cached is not null then return cached; end if;
  begin
    new_kind := payload->>'kind';
    new_team := nullif(payload->>'team_id', '')::uuid;
    new_title := btrim(coalesce(payload->>'title', ''));
    new_due := (payload->>'due_on')::date;
    youth := (payload->>'amount_youth')::bigint;
    adult := (payload->>'amount_adult')::bigint;
    supporter := (payload->>'amount_supporter')::bigint;
    player := (payload->>'amount_player')::bigint;
    cap := (payload->>'family_cap')::bigint;
    discount := (payload->>'sibling_discount_percent')::smallint;
  exception when others then
    raise invalid_parameter_value using message = 'invalid_fee_round';
  end;
  if new_kind is null or new_kind not in ('membership', 'team') or new_due is null
    or length(new_title) not between 1 and 120
    or least(youth, adult, supporter, player) < 0 or cap <= 0 or discount not between 1 and 100
    or (new_kind = 'membership' and (new_team is not null or player is not null
      or coalesce(youth, 0) + coalesce(adult, 0) + coalesce(supporter, 0) = 0))
    or (new_kind = 'team' and (new_team is null or coalesce(player, 0) = 0
      or youth is not null or adult is not null or supporter is not null or cap is not null or discount is not null)) then
    raise invalid_parameter_value using message = 'invalid_fee_round';
  end if;
  if new_team is not null and not exists (select 1 from core.teams team where team.id = new_team and team.club_id = target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if target_round_id is null then
    if expected_revision <> 0 then raise sqlstate 'PT409' using message = 'stale_revision'; end if;
    insert into core.club_fee_rounds (club_id, kind, team_id, title, due_on, amount_youth, amount_adult,
      amount_supporter, amount_player, family_cap, sibling_discount_percent, created_by)
    values (target_club_id, new_kind, new_team, new_title, new_due, youth, adult, supporter, player, cap, discount, actor_id)
    returning * into current_round;
  else
    perform pg_advisory_xact_lock(hashtextextended('club-fee-round:' || target_round_id::text, 0));
    select * into current_round from core.club_fee_rounds where id = target_round_id and club_id = target_club_id and state <> 'cancelled';
    if not found then raise insufficient_privilege using message = 'not_found'; end if;
    if current_round.revision <> expected_revision then raise sqlstate 'PT409' using message = 'stale_revision'; end if;
    if current_round.state <> 'draft' then raise invalid_parameter_value using message = 'fee_round_issued'; end if;
    update core.club_fee_rounds set kind = new_kind, team_id = new_team, title = new_title, due_on = new_due,
      amount_youth = youth, amount_adult = adult, amount_supporter = supporter, amount_player = player,
      family_cap = cap, sibling_discount_percent = discount, updated_at = now(), revision = revision + 1
    where id = target_round_id returning * into current_round;
  end if;
  result := jsonb_build_object('round_id', current_round.id, 'revision', current_round.revision);
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, 'club.fee_round.saved.v1', result);
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  values (target_club_id, actor_id, 'club.fee_round.saved.v1', 'club_fee_round', current_round.id, current_round.revision,
    internal.club_fee_round_json(current_round));
  return result;
end;
$$;

-- issue: create the fees with the amounts frozen. cancel: drop a draft.
create or replace function internal.decide_club_fee_round_for_actor(target_club_id uuid, target_round_id uuid,
  decision text, expected_revision bigint, idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); cached jsonb; current_round core.club_fee_rounds%rowtype; result jsonb;
  command text; created int := 0;
begin
  if not internal.actor_can_manage_club_fees(target_club_id) then
    raise insufficient_privilege using message = 'not_found';
  end if;
  if idempotency_key is null or expected_revision is null or decision is null or decision not in ('issue', 'cancel') then
    raise invalid_parameter_value using message = 'invalid_fee_round';
  end if;
  command := case decision when 'issue' then 'club.fee_round.issued.v1' else 'club.fee_round.cancelled.v1' end;
  select d.result into cached from internal.command_deduplication d where d.actor_profile_id = actor_id
    and d.command_type = command and d.idempotency_key = decide_club_fee_round_for_actor.idempotency_key;
  if cached is not null then return cached; end if;
  perform pg_advisory_xact_lock(hashtextextended('club-fee-round:' || target_round_id::text, 0));
  select * into current_round from core.club_fee_rounds where id = target_round_id and club_id = target_club_id and state <> 'cancelled';
  if not found then raise insufficient_privilege using message = 'not_found'; end if;
  if current_round.revision <> expected_revision then raise sqlstate 'PT409' using message = 'stale_revision'; end if;
  if current_round.state <> 'draft' then raise invalid_parameter_value using message = 'fee_round_issued'; end if;
  if decision = 'issue' then
    insert into core.club_fees (round_id, club_id, club_person_id, family_key, category, base_amount, discount_amount, amount, state)
    select current_round.id, target_club_id, line.person_id, line.family_key, line.category, line.base_amount,
      line.discount_amount, line.amount, case when line.amount = 0 then 'waived' else 'open' end
    from internal.club_fee_round_lines(current_round.id) line;
    get diagnostics created = row_count;
    if created = 0 then raise invalid_parameter_value using message = 'no_fees'; end if;
    update core.club_fee_rounds set state = 'issued', issued_at = now(), issued_by = actor_id, updated_at = now(),
      revision = revision + 1 where id = current_round.id returning * into current_round;
  else
    update core.club_fee_rounds set state = 'cancelled', updated_at = now(), revision = revision + 1
    where id = current_round.id returning * into current_round;
  end if;
  result := jsonb_build_object('round_id', current_round.id, 'state', current_round.state,
    'revision', current_round.revision, 'fee_count', created);
  insert into internal.command_deduplication (actor_profile_id, idempotency_key, command_type, result)
  values (actor_id, idempotency_key, command, result);
  insert into audit.command_events (club_id, actor_profile_id, command_type, aggregate_type, aggregate_id, aggregate_revision, metadata)
  values (target_club_id, actor_id, command, 'club_fee_round', current_round.id, current_round.revision,
    jsonb_build_object('fee_count', created));
  return result;
end;
$$;

create or replace function api.get_club_families(target_club_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_club_families_for_actor(target_club_id) $$;
create or replace function api.change_club_family(target_club_id uuid, change text, target_person_ids uuid[],
  idempotency_key uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.change_club_family_for_actor(target_club_id, change, target_person_ids, idempotency_key) $$;
create or replace function api.get_club_fee_rounds(target_club_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select internal.get_club_fee_rounds_for_actor(target_club_id) $$;
create or replace function api.get_club_fee_round(target_club_id uuid, target_round_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select internal.get_club_fee_round_for_actor(target_club_id, target_round_id) $$;
create or replace function api.save_club_fee_round(target_club_id uuid, target_round_id uuid, payload jsonb,
  expected_revision bigint, idempotency_key uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.save_club_fee_round_for_actor(target_club_id, target_round_id, payload, expected_revision, idempotency_key) $$;
create or replace function api.decide_club_fee_round(target_club_id uuid, target_round_id uuid, decision text,
  expected_revision bigint, idempotency_key uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select internal.decide_club_fee_round_for_actor(target_club_id, target_round_id, decision, expected_revision, idempotency_key) $$;

revoke all on function
  internal.actor_can_manage_club_fees(uuid), internal.club_family_keys(uuid), internal.club_effective_members(uuid),
  internal.club_fee_round_lines(uuid), internal.club_person_guardian_names(uuid, uuid), internal.club_family_members_of(uuid, uuid[]),
  internal.club_fee_round_json(core.club_fee_rounds),
  internal.get_club_families_for_actor(uuid), internal.change_club_family_for_actor(uuid, text, uuid[], uuid),
  internal.get_club_fee_rounds_for_actor(uuid), internal.get_club_fee_round_for_actor(uuid, uuid),
  internal.save_club_fee_round_for_actor(uuid, uuid, jsonb, bigint, uuid),
  internal.decide_club_fee_round_for_actor(uuid, uuid, text, bigint, uuid),
  api.get_club_families(uuid), api.change_club_family(uuid, text, uuid[], uuid),
  api.get_club_fee_rounds(uuid), api.get_club_fee_round(uuid, uuid),
  api.save_club_fee_round(uuid, uuid, jsonb, bigint, uuid), api.decide_club_fee_round(uuid, uuid, text, bigint, uuid)
from public, anon, authenticated;
grant execute on function
  internal.get_club_families_for_actor(uuid), internal.change_club_family_for_actor(uuid, text, uuid[], uuid),
  internal.get_club_fee_rounds_for_actor(uuid), internal.get_club_fee_round_for_actor(uuid, uuid),
  internal.save_club_fee_round_for_actor(uuid, uuid, jsonb, bigint, uuid),
  internal.decide_club_fee_round_for_actor(uuid, uuid, text, bigint, uuid),
  api.get_club_families(uuid), api.change_club_family(uuid, text, uuid[], uuid),
  api.get_club_fee_rounds(uuid), api.get_club_fee_round(uuid, uuid),
  api.save_club_fee_round(uuid, uuid, jsonb, bigint, uuid), api.decide_club_fee_round(uuid, uuid, text, bigint, uuid)
to authenticated;
notify pgrst, 'reload schema';
