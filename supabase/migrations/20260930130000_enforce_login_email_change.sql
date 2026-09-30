-- PROF-02: a login email can only change to an address support approved.
-- The account service keeps a pending change in auth.users.email_change and
-- moves it to auth.users.email when the confirmation link is used. Both
-- steps are refused unless the user has an approved request for exactly that
-- address; the final switch marks the request completed.

create or replace function internal.guard_login_email_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare wanted_pending text:=lower(nullif(btrim(coalesce(new.email_change,'')),''));
 wanted_email text:=lower(nullif(btrim(coalesce(new.email,'')),''));
begin
 -- Starting a change (or replacing a pending one).
 if wanted_pending is not null
  and wanted_pending is distinct from lower(nullif(btrim(coalesce(old.email_change,'')),''))
  and not exists(select 1 from core.login_email_change_requests request
   where request.profile_id=new.id and request.state='approved' and request.requested_email=wanted_pending)
 then
  raise exception 'email_change_requires_support' using errcode='42501';
 end if;
 -- The switch itself.
 if old.email is not null and wanted_email is distinct from lower(btrim(old.email)) then
  if wanted_email is null or not exists(select 1 from core.login_email_change_requests request
    where request.profile_id=new.id and request.state='approved' and request.requested_email=wanted_email)
  then
   raise exception 'email_change_requires_support' using errcode='42501';
  end if;
  update core.login_email_change_requests set state='completed'
  where profile_id=new.id and state='approved' and requested_email=wanted_email;
 end if;
 return new;
end$$;

revoke all on function internal.guard_login_email_change() from public,anon,authenticated;

drop trigger if exists guard_login_email_change on auth.users;
create trigger guard_login_email_change
before update of email,email_change on auth.users
for each row execute function internal.guard_login_email_change();

insert into internal.migration_provenance(migration_name,source_kind,source_reference)
values('20260930130000_enforce_login_email_change','greenfield',
 'PROF-02 login email changes only to support-approved addresses');
