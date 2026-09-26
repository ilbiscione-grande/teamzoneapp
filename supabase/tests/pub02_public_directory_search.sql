-- Run after the directory migration in an isolated test database.
-- Fixture changes and rate-limit buckets are rolled back.
begin;
insert into public_api.club_projections(public_id,slug,name,locality,source_revision,projected_at,official,visibility) values
 ('10000000-0000-0000-0000-000000000001','search-test-club','Sökprov IF','Örebro',1,now(),false,'published'),
 ('10000000-0000-0000-0000-000000000002','search-test-listed','Katalogprov IF','Vetlanda',1,now(),true,'listed'),
 ('10000000-0000-0000-0000-000000000003','search-test-hidden-field','Fälthemlighet IF',null,1,now(),false,'published');
insert into public_api.team_projections(public_id,club_public_id,club_slug,slug,name,age_class,source_revision,projected_at,visibility) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','search-test-club','juniorerna','Juniorerna','J18',1,now(),'published'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','search-test-club','hemligalaget','Hemligalaget','J20',1,now(),'listed'),
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','search-test-listed','doldaklubblaget','Doldaklubblaget','J18',1,now(),'published');
do $$
declare r jsonb; term text; ip text:=repeat('a',64); i integer;
begin
 foreach term in array array['SÖKPROV','öre','Sökprov Örebro'] loop
  r:=api.public_search_directory(term,ip,10);
  if jsonb_array_length(r->'items')<>2 then raise exception 'Expected club and team for %: %',term,r;end if;
 end loop;
 foreach term in array array['Junior','J18 Örebro','Junior Sökprov','Örebro Junior J18'] loop
  r:=api.public_search_directory(term,ip,10);
  if jsonb_array_length(r->'items')<>1 or r#>>'{items,0,kind}'<>'team'
   or r#>>'{items,0,club_slug}'<>'search-test-club' then raise exception 'Expected linked team for %: %',term,r;end if;
 end loop;
 foreach term in array array['Hemligalaget','Doldaklubblaget','Ejpubliceradort','%%%','Junior Vetlanda'] loop
  r:=api.public_search_directory(term,ip,10);
  if jsonb_array_length(r->'items')<>0 then raise exception 'Unexpected exposure for %: %',term,r;end if;
 end loop;
 r:=api.public_search_directory('Katalogprov',ip,10);
 if r#>>'{items,0,visibility}'<>'listed' or jsonb_array_length(r->'items')<>1 then raise exception 'Listed club contract: %',r;end if;
 r:=api.public_search_directory('Sökprov',ip,1);
 if jsonb_array_length(r->'items')<>1 or not(r->>'has_more')::boolean then raise exception 'Result limit: %',r;end if;
 r:=api.public_search_directory('Juniorerna',ip,10);
 if (r#>'{items,0}') ?| array['search_document','source_revision','projected_at','priority'] then raise exception 'Internal fields exposed';end if;
 begin perform api.public_search_directory('ab',ip,10);raise exception 'Short query accepted';exception when invalid_parameter_value then null;end;
 begin perform api.public_search_directory(repeat('x',81),ip,10);raise exception 'Long query accepted';exception when invalid_parameter_value then null;end;
 begin perform api.public_search_directory('Junior',ip,11);raise exception 'Large page accepted';exception when invalid_parameter_value then null;end;
 begin perform api.public_search_directory('Junior',ip,null);raise exception 'Null page accepted';exception when invalid_parameter_value then null;end;
 if has_function_privilege('anon','api.public_search_directory(text,text,integer)','execute')
  or has_function_privilege('authenticated','internal.public_search_directory(text,text,integer)','execute')
  or not has_function_privilege('service_role','api.public_search_directory(text,text,integer)','execute') then raise exception 'Wrong privileges';end if;
 for i in 1..20 loop perform api.public_search_directory('Junior',repeat('b',64),10);end loop;
 begin perform api.public_search_directory('Junior',repeat('b',64),10);raise exception 'Rate limit not enforced';exception when program_limit_exceeded then null;end;
 update public_api.club_projections set visibility='listed' where slug='search-test-club';
 r:=api.public_search_directory('Junior',ip,10);
 if jsonb_array_length(r->'items')<>0 then raise exception 'Unpublished parent leaked team';end if;
 delete from public_api.club_projections where slug='search-test-club';
 r:=api.public_search_directory('Junior',ip,10);
 if jsonb_array_length(r->'items')<>0 then raise exception 'Deleted parent leaked team';end if;
 raise notice 'Directory search assertions passed';
end;$$;
rollback;
