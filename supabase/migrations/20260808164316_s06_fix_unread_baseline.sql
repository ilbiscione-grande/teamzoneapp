do $$
declare definition text;
begin
 select pg_get_functiondef('internal.list_threads_for_actor(uuid[],timestamptz,integer)'::regprocedure) into definition;
 definition:=replace(definition,'greatest(thread.revision-coalesce(read_marker.through_revision,0),0)','greatest(thread.revision-coalesce(read_marker.through_revision,1),0)');
 if definition not like '%coalesce(read_marker.through_revision,1)%' then raise exception 'unread_baseline_patch_failed'; end if;
 execute definition;
end$$;
insert into internal.migration_provenance(migration_name,source_kind,source_reference) values('20260808164316_s06_fix_unread_baseline','greenfield',null);
