-- Keep the public verification badge in sync without granting publication rights.
create function internal.reproject_club_on_public_state_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare next_revision bigint;next_action text;
begin
 if old.verification_status is not distinct from new.verification_status
  and old.status is not distinct from new.status then return new;end if;
 update core.club_publication_settings s set revision=s.revision+1,changed_at=now()
  where s.club_id=new.id and s.mode in('listed','published')
  returning revision into next_revision;
 if next_revision is null then return new;end if;
 next_action:=case when new.status='active' then 'rebuild' else 'remove' end;
 insert into internal.publication_projection_jobs(club_id,aggregate_type,aggregate_id,
  requested_revision,action,created_by)
 values(new.id,'club',new.id,next_revision,next_action,null);
 return new;
end;$$;
create trigger club_public_state_reprojection
after update of verification_status,status on core.clubs
for each row execute function internal.reproject_club_on_public_state_change();
revoke all on function internal.reproject_club_on_public_state_change() from public,anon,authenticated;
