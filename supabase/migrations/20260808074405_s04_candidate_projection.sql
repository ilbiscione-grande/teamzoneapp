create function internal.list_squad_candidates_for_actor(target_event_id uuid)
returns table(person_id uuid,name text,eligibility_kind text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise insufficient_privilege using message='unauthenticated'; end if;
 if not internal.actor_can_manage_squad(target_event_id) then raise insufficient_privilege using message='not_found'; end if;
 return query select person.id,person.display_name,internal.person_eligibility_at_event(target_event_id,person.id)->>'kind'
 from core.club_people person join core.events event_row on event_row.id=target_event_id and event_row.club_id=person.club_id
 where person.status='active' and internal.person_eligibility_at_event(target_event_id,person.id) is not null order by person.display_name,person.id;
end; $$;
revoke all on function internal.list_squad_candidates_for_actor(uuid) from public,anon,authenticated;
grant execute on function internal.list_squad_candidates_for_actor(uuid) to authenticated;
create function api.list_squad_candidates(target_event_id uuid) returns table(person_id uuid,name text,eligibility_kind text)
language sql stable security invoker set search_path='' as $$select * from internal.list_squad_candidates_for_actor(target_event_id)$$;
revoke all on function api.list_squad_candidates(uuid) from public,anon;
grant execute on function api.list_squad_candidates(uuid) to authenticated;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808074405_s04_candidate_projection','greenfield',null);
notify pgrst,'reload schema';
