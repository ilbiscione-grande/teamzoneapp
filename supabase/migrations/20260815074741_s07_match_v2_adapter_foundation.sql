-- S07 greenfield adapter foundation. The v2 command contract remains the only
-- match write surface; S03 events and S04 callups are the source identities.

create table core.match_workspaces(
  event_id uuid primary key,
  club_id uuid not null,
  team_id uuid not null,
  state text not null default 'planning' check(state in ('planning','live','completed')),
  revision bigint not null default 0 check(revision>=0),
  roster_revision bigint not null default 0 check(roster_revision>=0),
  match_started_at timestamptz,
  match_paused_at timestamptz,
  paused_seconds integer not null default 0 check(paused_seconds>=0),
  completed_at timestamptz,
  unlocked_at timestamptz,
  updated_at timestamptz not null default now(),
  updated_by uuid references core.profiles(id),
  foreign key(event_id,club_id,team_id) references core.events(id,club_id,owning_team_id) on delete cascade,
  check((state='completed' and completed_at is not null) or state<>'completed')
);

create table audit.match_commands(
  command_id uuid primary key,
  event_id uuid not null references core.match_workspaces(event_id) on delete restrict,
  expected_revision bigint,
  command_type text not null,
  payload jsonb not null default '{}'::jsonb check(jsonb_typeof(payload)='object'),
  result jsonb not null default '{}'::jsonb check(jsonb_typeof(result)='object'),
  actor_profile_id uuid not null references core.profiles(id),
  created_at timestamptz not null default now()
);
create index match_commands_event_created_idx on audit.match_commands(event_id,created_at,command_id);
create index match_commands_actor_idx on audit.match_commands(actor_profile_id);

create table core.match_roster_revisions(
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.match_workspaces(event_id) on delete cascade,
  revision bigint not null check(revision>0),
  state text not null default 'frozen' check(state in ('frozen','superseded')),
  reason_code text not null check(reason_code in ('initial','late_callup','manual_correction')),
  source_squad_revision_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid not null references core.profiles(id),
  unique(event_id,revision)
);
create unique index match_roster_one_frozen_idx on core.match_roster_revisions(event_id) where state='frozen';

create table core.match_roster_members(
  roster_revision_id uuid not null references core.match_roster_revisions(id) on delete cascade,
  club_person_id uuid not null,
  club_id uuid not null,
  source_callup_id uuid,
  source_state text not null check(source_state in ('accepted','leader_added')),
  created_at timestamptz not null default now(),
  primary key(roster_revision_id,club_person_id),
  foreign key(club_person_id,club_id) references core.club_people(id,club_id),
  foreign key(source_callup_id,club_id) references core.callups(id,club_id)
);

create table core.match_plans(
  event_id uuid primary key references core.match_workspaces(event_id) on delete cascade,
  revision bigint not null default 0 check(revision>=0),
  formation text,
  starting_xi jsonb not null default '[]'::jsonb check(jsonb_typeof(starting_xi)='array'),
  substitution_checklist jsonb not null default '[]'::jsonb check(jsonb_typeof(substitution_checklist)='array'),
  set_pieces_notes text not null default '', tactics_notes text not null default '',
  match_kpis text not null default '', key_opponents_notes text not null default '',
  kpi_review text not null default '', board_background text not null default 'fullPitch',
  board_strokes jsonb not null default '[]'::jsonb check(jsonb_typeof(board_strokes)='array'),
  kpi_buttons jsonb not null default '[]'::jsonb check(jsonb_typeof(kpi_buttons)='array'),
  enabled_quick_actions jsonb not null default '[]'::jsonb check(jsonb_typeof(enabled_quick_actions)='array'),
  updated_at timestamptz not null default now(), updated_by uuid references core.profiles(id)
);

create table core.match_facts(
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.match_workspaces(event_id) on delete cascade,
  minute integer not null check(minute>=0),
  fact_type text not null check(fact_type in ('substitution','goal','card','injury','corner','free_kick','penalty','save','half_time','full_time','kpi','shot','score_adjustment')),
  side text check(side in ('us','opponent')),
  club_person_id uuid, secondary_club_person_id uuid, club_id uuid not null,
  detail jsonb not null default '{}'::jsonb check(jsonb_typeof(detail)='object'),
  source_command_id uuid not null references audit.match_commands(command_id) on delete restrict,
  state text not null default 'active' check(state in ('active','voided')),
  fact_revision bigint not null default 1 check(fact_revision>0),
  created_at timestamptz not null default now(), created_by uuid not null references core.profiles(id),
  updated_at timestamptz not null default now(), updated_by uuid not null references core.profiles(id),
  voided_at timestamptz, voided_by uuid references core.profiles(id), void_reason text,
  unique(event_id,source_command_id),
  foreign key(club_person_id,club_id) references core.club_people(id,club_id),
  foreign key(secondary_club_person_id,club_id) references core.club_people(id,club_id),
  check((state='voided' and voided_at is not null and voided_by is not null and nullif(btrim(void_reason),'') is not null) or state='active')
);
create index match_facts_active_timeline_idx on core.match_facts(event_id,minute,created_at,id) where state='active';

create table core.match_projections(
  event_id uuid primary key references core.match_workspaces(event_id) on delete cascade,
  revision bigint not null default 0 check(revision>=0),
  score_us integer not null default 0 check(score_us>=0),
  score_opponent integer not null default 0 check(score_opponent>=0),
  stats jsonb not null default '{}'::jsonb check(jsonb_typeof(stats)='object'),
  updated_at timestamptz not null default now()
);

alter table core.match_workspaces enable row level security;
alter table audit.match_commands enable row level security;
alter table core.match_roster_revisions enable row level security;
alter table core.match_roster_members enable row level security;
alter table core.match_plans enable row level security;
alter table core.match_facts enable row level security;
alter table core.match_projections enable row level security;

create policy match_workspaces_no_direct_read on core.match_workspaces for select to authenticated using(false);
create policy match_commands_no_direct_read on audit.match_commands for select to authenticated using(false);
create policy match_roster_revisions_no_direct_read on core.match_roster_revisions for select to authenticated using(false);
create policy match_roster_members_no_direct_read on core.match_roster_members for select to authenticated using(false);
create policy match_plans_no_direct_read on core.match_plans for select to authenticated using(false);
create policy match_facts_no_direct_read on core.match_facts for select to authenticated using(false);
create policy match_projections_no_direct_read on core.match_projections for select to authenticated using(false);

revoke insert,update,delete,truncate on core.match_workspaces,audit.match_commands,
 core.match_roster_revisions,core.match_roster_members,core.match_plans,
 core.match_facts,core.match_projections from anon,authenticated;

create function internal.reject_match_command_mutation()
returns trigger language plpgsql set search_path='' as $$
begin raise check_violation using message='match_commands_append_only'; end$$;
create trigger match_commands_append_only before update or delete on audit.match_commands
for each row execute function internal.reject_match_command_mutation();
revoke all on function internal.reject_match_command_mutation() from public,anon,authenticated;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260815074741_s07_match_v2_adapter_foundation','greenfield','TeamZone local v2 contract snapshot 2026-08-15');
