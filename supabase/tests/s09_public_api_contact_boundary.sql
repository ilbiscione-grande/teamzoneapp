begin;
set local role postgres;

do $$
declare result jsonb; i integer;
begin
 for i in 1..21 loop
  result:=internal.consume_public_rate_limit(repeat('a',64),'search',null);
 end loop;
 if (result->>'allowed')::boolean then raise exception 'search limit exceeded without denial'; end if;
 if (result->>'remaining')::integer<>0 then raise exception 'search remaining underflow'; end if;

 for i in 1..61 loop
  result:=internal.consume_public_rate_limit(repeat('b',64),'read',null);
 end loop;
 if (result->>'allowed')::boolean then raise exception 'read limit exceeded without denial'; end if;

 for i in 1..6 loop
  result:=internal.consume_public_rate_limit(
    repeat('c',64),'contact','89700000-0000-0000-0000-000000000001');
 end loop;
 if (result->>'allowed')::boolean then raise exception 'contact limit exceeded without denial'; end if;
end $$;

insert into auth.users(id,raw_user_meta_data)
values('89700000-0000-0000-0000-000000000001','{"display_name":"S09 Contact Test"}');
insert into core.clubs(id,name,slug)
values('89710000-0000-0000-0000-000000000001','S09 Contact Club','s09-contact-club');
insert into internal.public_contact_submissions(
  club_id,sender_name,sender_email,subject,message_body,captcha_assertion_hash,created_at,expires_at
) values(
  '89710000-0000-0000-0000-000000000001','Test Person','test@example.com','Test subject',
  'Test message',decode(repeat('d',64),'hex'),now()-interval '31 days',now()-interval '1 day'
);

set local role service_role;
select api.apply_public_contact_retention(10);
do $$ begin
 if api.public_search_clubs('abc',repeat('e',64),10)->>'available'<>'false' then
  raise exception 'search did not fail closed'; end if;
 if api.public_get_club('unknown',repeat('e',64))->>'available'<>'false' then
  raise exception 'club read did not fail closed'; end if;
 if api.public_submit_contact(
   '89700000-0000-0000-0000-000000000002','Name','mail@example.com','Subject','Message',
   repeat('e',64),true,repeat('f',64))->>'code'<>'unavailable' then
  raise exception 'contact did not fail closed'; end if;
end $$;

set local role postgres;
do $$ begin
 if exists(select 1 from internal.public_contact_submissions
   where state<>'erased' or sender_name<>'' or sender_email<>'' or subject<>'' or message_body<>'') then
  raise exception 'contact retention did not erase content'; end if;
 if has_schema_privilege('anon','public_api','usage') then raise exception 'anon schema usage opened'; end if;
 if has_function_privilege('anon','api.public_search_clubs(text,text,integer)','execute')
    or has_function_privilege('authenticated','api.public_search_clubs(text,text,integer)','execute')
    or has_function_privilege('anon','api.public_submit_contact(uuid,text,text,text,text,text,boolean,text)','execute') then
  raise exception 'public database RPC exposed directly'; end if;
 if not has_function_privilege('service_role','api.public_search_clubs(text,text,integer)','execute')
    or not has_function_privilege('service_role','api.public_submit_contact(uuid,text,text,text,text,text,boolean,text)','execute') then
  raise exception 'server role lacks public boundary'; end if;
 if (select enabled from internal.publication_runtime_state where singleton) then
  raise exception 'runtime unexpectedly enabled'; end if;
end $$;

rollback;
