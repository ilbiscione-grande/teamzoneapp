-- Manual kill switch for the approved audit project; does not change publication choices.
begin;
update internal.publication_runtime_state set enabled=false,
 gate_version='pub02-audit-web-disabled',revision=revision+1,changed_at=now()
 where singleton;
alter table internal.publication_runtime_state drop constraint if exists publication_runtime_state_enabled_check;
alter table internal.publication_runtime_state add constraint publication_runtime_state_enabled_check check(enabled=false);
commit;
