-- S10B confidential internal cash tracking and governance foundation.
-- No legal-bookkeeping claim, payment automation, fee run or settlement.

create table core.economy_accounts (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  team_id uuid,
  name text not null check (length(btrim(name)) between 1 and 120),
  currency text not null default 'SEK' check (currency = 'SEK'),
  state text not null default 'active' check (state in ('active','closed')),
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  foreign key (team_id,club_id) references core.teams(id,club_id),
  unique (id,club_id),
  unique nulls not distinct (club_id,team_id,name)
);

create table core.economy_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  account_id uuid not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency = 'SEK'),
  direction text not null check (direction in ('inflow','outflow')),
  category text not null check (category ~ '^[a-z][a-z0-9_]{1,47}$'),
  state text not null default 'pending' check (state in ('pending','posted','reversed','rejected')),
  risk_level text not null check (risk_level in ('regular','high')),
  reversal_of uuid references core.economy_ledger_entries(id),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  source_kind text not null check (source_kind in ('manual','fee','pledge','adjustment','opening_balance')),
  created_by uuid not null references core.profiles(id),
  created_at timestamptz not null default now(),
  posted_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  foreign key (account_id,club_id) references core.economy_accounts(id,club_id),
  check ((state='posted' and posted_at is not null) or (state<>'posted')),
  check ((reversal_of is null) = (source_kind <> 'adjustment')),
  check (reversal_of is null or reversal_of <> id)
);

create unique index economy_one_reversal_per_entry
  on core.economy_ledger_entries(reversal_of) where reversal_of is not null;
create index economy_ledger_account_created
  on core.economy_ledger_entries(account_id,created_at desc);

create table core.economy_entry_approvals (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  entry_id uuid not null references core.economy_ledger_entries(id),
  approver_profile_id uuid not null references core.profiles(id),
  decision text not null check (decision in ('approved','rejected')),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  decided_at timestamptz not null default now(),
  unique (entry_id,approver_profile_id)
);

create table core.fee_obligations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  account_id uuid not null,
  debtor_club_person_id uuid not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency = 'SEK'),
  due_at timestamptz not null,
  state text not null default 'draft' check (state in ('draft','issued','partially_paid','paid','waived','cancelled')),
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  foreign key (account_id,club_id) references core.economy_accounts(id,club_id),
  foreign key (debtor_club_person_id,club_id) references core.club_people(id,club_id)
);

create table core.sponsor_pledges (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  team_id uuid,
  account_id uuid not null,
  event_id uuid,
  amount_per_fact_minor bigint not null check (amount_per_fact_minor > 0),
  maximum_amount_minor bigint not null check (maximum_amount_minor >= amount_per_fact_minor),
  currency text not null check (currency = 'SEK'),
  fact_type text not null check (fact_type in ('goal_for','appearance','win')),
  terms_snapshot jsonb not null check (jsonb_typeof(terms_snapshot)='object'),
  state text not null default 'draft' check (state in ('draft','active','ended','cancelled')),
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  foreign key (team_id,club_id) references core.teams(id,club_id),
  foreign key (account_id,club_id) references core.economy_accounts(id,club_id),
  foreign key (event_id,club_id) references core.events(id,club_id)
);

create table core.board_mandates (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references core.clubs(id),
  assignment_id uuid not null references core.assignments(id),
  office text not null check (office in ('chair','treasurer','secretary','member','auditor')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  state text not null default 'active' check (state in ('active','ended','revoked')),
  created_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  check (ends_at > starts_at),
  unique (club_id,assignment_id,office,starts_at)
);

alter table core.economy_accounts enable row level security;
alter table core.economy_ledger_entries enable row level security;
alter table core.economy_entry_approvals enable row level security;
alter table core.fee_obligations enable row level security;
alter table core.sponsor_pledges enable row level security;
alter table core.board_mandates enable row level security;

create function internal.protect_posted_economy_entry()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.state in ('posted','reversed') then
    raise check_violation using message='immutable_ledger_entry';
  end if;
  return new;
end
$$;

create trigger protect_posted_economy_entry
before update or delete on core.economy_ledger_entries
for each row execute function internal.protect_posted_economy_entry();

revoke all on table core.economy_accounts,core.economy_ledger_entries,
  core.economy_entry_approvals,core.fee_obligations,core.sponsor_pledges,
  core.board_mandates from public,anon,authenticated;
revoke all on function internal.protect_posted_economy_entry() from public,anon,authenticated;

insert into internal.migration_provenance(migration_name,source_kind)
values('20260817154441_s10b_economy_board_foundation','greenfield');
