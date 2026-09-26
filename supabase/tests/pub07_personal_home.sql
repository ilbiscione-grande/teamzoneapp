-- Only isolated local fixtures; all writes rolled back.
begin;
insert into auth.users values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
insert into core.profiles select id from auth.users;
insert into core.teams values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Testlaget');
insert into public_api.club_projections(public_id,slug,name,source_revision,projected_at,visibility) values('10000000-0000-4000-8000-000000000001','testklubb','Testklubb',1,now(),'published');
insert into public_api.team_projections(public_id,club_public_id,club_slug,slug,name,source_revision,projected_at,visibility) values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','testklubb','testlag','Testlag',1,now(),'published');
insert into core.club_publication_settings values('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','testklubb','published');
insert into core.team_publication_settings values('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','testlag','published',gen_random_uuid());
insert into core.events values('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','completed','match','Testlag – Motståndare',now()-interval '1 hour',null);
insert into core.match_workspaces values('30000000-0000-4000-8000-000000000001','completed');
insert into core.match_projections values('30000000-0000-4000-8000-000000000001',1,0,2);
insert into public_api.content_projections(public_id,club_public_id,content_type,title,published_at,source_revision,projected_at,slug,club_channel)
values('40000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','news','Gemensam nyhet',now(),1,now(),'nyhet',true);
insert into public_api.content_team_channels values('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001');
do $$
declare r jsonb;cursor jsonb; club uuid:='10000000-0000-4000-8000-000000000001';team uuid:='20000000-0000-4000-8000-000000000001';event uuid:='30000000-0000-4000-8000-000000000001';
begin
 begin perform api.get_personal_public_home();raise exception 'Anonymous read accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
 perform api.set_public_channel_follow('club',club,true);perform api.set_public_channel_follow('team',team,true);perform api.set_public_channel_follow('team',team,true);
 r:=api.get_personal_public_home();
 if jsonb_array_length(r->'following')<>2 or jsonb_array_length(r->'items')<>1 then raise exception 'Following/feed duplicate: %',r;end if;
 -- Different authenticated account cannot see or delete A's subscriptions.
 perform set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
 r:=api.get_personal_public_home();if jsonb_array_length(r->'following')<>0 or jsonb_array_length(r->'items')<>0 then raise exception 'Account leak';end if;
 perform api.set_public_channel_follow('team',team,false);
 perform api.set_public_channel_follow('team',team,true); -- no club membership required
 begin perform api.configure_event_publication(event,'published',null,false,0,gen_random_uuid(),true);raise exception 'Unauthorized publisher';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
 -- Publication without result does not expose the private completed score.
 perform api.configure_event_publication(event,'published',null,false,0,gen_random_uuid());
 if exists(select 1 from public_api.match_result_projections) then raise exception 'Implicit score exposure';end if;
 r:=api.configure_event_publication(event,'published',null,false,1,gen_random_uuid(),true);
 if not(r->>'publish_result')::boolean then raise exception 'Missing result receipt';end if;
 r:=api.get_personal_public_home();
 if jsonb_array_length(r->'items')<>2 or (r#>>'{items,1,score_us}')::integer<>0 then raise exception 'Result absent or zero mishandled: %',r;end if;
 update core.match_projections set score_us=1,revision=2 where event_id=event;
 if exists(select 1 from public_api.match_result_projections) then raise exception 'Correction left stale result';end if;
 perform api.configure_event_publication(event,'published',null,false,2,gen_random_uuid(),true);
 update core.match_workspaces set state='live' where event_id=event;
 if exists(select 1 from public_api.match_result_projections) then raise exception 'Reopened match leaked score';end if;
 begin perform api.configure_event_publication(event,'published',null,false,3,gen_random_uuid(),true);raise exception 'Live score accepted';exception when check_violation then null;end;
 update core.match_workspaces set state='completed' where event_id=event;
 perform api.configure_event_publication(event,'published',null,false,3,gen_random_uuid(),true);
 perform api.configure_event_publication(event,'private',null,false,4,gen_random_uuid(),false);
 if exists(select 1 from public_api.match_result_projections) then raise exception 'Private event leaked result';end if;
 -- Invalid cursor must fail instead of bypassing paging with SQL NULL.
 begin perform api.get_personal_public_home(now(),null,'news');raise exception 'Partial cursor accepted';exception when invalid_parameter_value then null;end;
 -- Following club and team still yields one copy of each article; cursor never repeats a row.
 insert into public_api.content_projections(public_id,club_public_id,content_type,title,published_at,source_revision,projected_at,slug,club_channel)
 select gen_random_uuid(),club,'news','Nyhet '||n,now()-n*interval '1 minute',1,now(),'nyhet-'||n,true from generate_series(1,25) n;
 r:=api.get_personal_public_home();cursor:=r->'next_cursor';
 if jsonb_array_length(r->'items')<>20 or cursor='null'::jsonb then raise exception 'Page size';end if;
 r:=api.get_personal_public_home((cursor->>'before_at')::timestamptz,(cursor->>'before_id')::uuid,cursor->>'before_kind');
 if jsonb_array_length(r->'items')<>6 then raise exception 'Cursor duplicate or omission: %',r;end if;
 update public_api.club_projections set visibility='listed' where public_id=club;
 r:=api.get_personal_public_home();if jsonb_array_length(r->'following')<>0 or jsonb_array_length(r->'items')<>0 then raise exception 'Unpublished parent exposure';end if;
 begin perform api.set_public_channel_follow('team',team,true);raise exception 'Private channel follow accepted';exception when no_data_found then null;end;
 update public_api.club_projections set visibility='published' where public_id=club;
 perform api.set_public_channel_follow('team',team,false);
 r:=api.get_personal_public_home();if jsonb_array_length(r->'following')<>1 then raise exception 'Unfollow failed';end if;
 insert into core.public_channel_follows(user_id,kind,public_id)
 select auth.uid(),'club',gen_random_uuid() from generate_series(1,99);
 perform api.set_public_channel_follow('club',club,true); -- idempotent at the limit
 begin perform api.set_public_channel_follow('team',team,true);raise exception 'Follow limit bypassed';exception when program_limit_exceeded then null;end;
 delete from auth.users where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 if exists(select 1 from core.public_channel_follows where user_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then raise exception 'Account deletion retained subscriptions';end if;
 update internal.publication_runtime_state set enabled=false;
 r:=api.get_personal_public_home();if (r->>'available')::boolean or jsonb_array_length(r->'items')<>0 then raise exception 'Runtime gate bypass';end if;
 perform api.set_public_channel_follow('club',club,false); -- removal always possible
 if has_function_privilege('anon','api.get_personal_public_home(timestamptz,uuid,text)','execute') or has_table_privilege('authenticated','core.public_channel_follows','select') then raise exception 'Direct access granted';end if;
end;$$;
rollback;
