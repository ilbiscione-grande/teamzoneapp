-- A mistakenly booked event can be deleted outright as long as nobody has been
-- called up to it. Once a callup has been sent the event keeps its history and
-- must be cancelled and archived instead.
--
-- Previously only untouched drafts (revision 1, no squad) could be deleted.
-- The rule now allows draft, scheduled and cancelled one-off events owned by
-- the team when no callup was ever sent and no attendance, match workspace,
-- sponsor pledge or explicit public publication exists. Unsent squad drafts,
-- preparations, files and revisions are removed with the event by the
-- existing cascades; public team projections are cleared by the existing
-- delete triggers. Series occurrences are still archived, not deleted.

create or replace function internal.event_can_be_deleted_by_manager(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from core.events event_row where event_row.id=target_event_id
   and event_row.state in('draft','scheduled','cancelled') and event_row.recurrence_id is null
   and event_row.archived_at is null
   and internal.actor_can_manage_event_sharing(event_row.id)
   and not exists(select 1 from core.event_teams relation where relation.event_id=event_row.id and relation.relation='shared')
   and not exists(select 1 from core.callups callup where callup.event_id=event_row.id and callup.sent_at is not null)
   and not exists(select 1 from core.squad_revisions squad where squad.event_id=event_row.id and squad.state='sent')
   and not exists(select 1 from core.attendance_facts attendance where attendance.event_id=event_row.id)
   and not exists(select 1 from core.match_workspaces workspace where workspace.event_id=event_row.id)
   and not exists(select 1 from core.sponsor_pledges pledge where pledge.event_id=event_row.id)
   and not exists(select 1 from core.event_publication_settings publication
    where publication.event_id=event_row.id and publication.state='published')
 )
$$;

create or replace function internal.delete_event_draft_for_actor(target_event_id uuid,expected_revision bigint,
 idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor_id uuid:=auth.uid();event_row core.events%rowtype;existing jsonb;result jsonb;
begin
 if actor_id is null then raise insufficient_privilege using message='unauthenticated';end if;
 select internal.command_deduplication.result into existing from internal.command_deduplication
  where actor_profile_id=actor_id and command_type='event.event.delete_draft.v1'
   and internal.command_deduplication.idempotency_key=delete_event_draft_for_actor.idempotency_key;
 if existing is not null then return existing;end if;
 select * into event_row from core.events where id=target_event_id for update;
 if event_row.id is null or not internal.event_can_be_deleted_by_manager(event_row.id)
 then raise insufficient_privilege using message='not_found';end if;
 if event_row.revision<>expected_revision then raise serialization_failure using message='stale_revision';end if;
 perform pg_advisory_xact_lock(hashtextextended('event-lifecycle:'||event_row.id::text,0));
 result:=jsonb_build_object('event_id',event_row.id,'deleted',true);
 insert into audit.command_events(club_id,actor_profile_id,command_type,aggregate_type,aggregate_id,
  aggregate_revision,metadata) values(event_row.club_id,actor_id,'event.event.delete_draft.v1','event',
   event_row.id,event_row.revision,jsonb_build_object('state',event_row.state,'title',event_row.title,
   'starts_at',event_row.starts_at));
 insert into internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)
 values(actor_id,idempotency_key,'event.event.delete_draft.v1',result);
 -- The only event reference without a cascade that the rule still allows.
 delete from core.event_publication_settings where event_id=event_row.id;
 delete from core.events where id=event_row.id;
 return result;
end;$$;

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20261005090000_event_delete_without_sent_callups','greenfield',
 'Delete mistakenly booked events while no callup has been sent');
notify pgrst,'reload schema';
