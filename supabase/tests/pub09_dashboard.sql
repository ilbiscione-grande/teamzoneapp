do $$
declare r jsonb;team uuid:='20000000-0000-4000-8000-000000000001';other_team uuid:='20000000-0000-4000-8000-000000000002';club uuid:='10000000-0000-4000-8000-000000000001';
begin
 begin perform api.get_personal_dashboard_content();raise exception 'Anonymous accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
 perform api.configure_event_publication('30000000-0000-4000-8000-000000000001','published',null,false,0,gen_random_uuid(),true);
 r:=api.get_personal_dashboard_content();
 if jsonb_array_length(r->'own_teams')<>1 or jsonb_array_length(r->'news')<>1 or jsonb_array_length(r->'results')<>1 or not(r#>>'{news,0,is_own}')::boolean then raise exception 'Own content absent without follows: %',r;end if;
 insert into core.teams values(other_team,club,'Andra laget');
 insert into core.team_publication_settings values(other_team,other_team,'andra','published',gen_random_uuid());
 insert into public_api.team_projections(public_id,club_public_id,club_slug,slug,name,source_revision,projected_at,visibility) values(other_team,club,'testklubb','andra','Andra laget',1,now(),'published');
 insert into public_api.content_projections(public_id,club_public_id,content_type,title,published_at,source_revision,projected_at,slug,club_channel) values('40000000-0000-4000-8000-000000000002',club,'news','Andra lagets nyhet',now(),1,now(),'andra-nyhet',false);
 insert into public_api.content_team_channels values('40000000-0000-4000-8000-000000000002',other_team);
 insert into public_api.event_projections(public_id,team_public_id,starts_at,event_type,title,source_revision,projected_at) select gen_random_uuid(),other_team,now()+interval '1 day',kind,kind,1,now() from unnest(array['match','training','meeting','activity'])kind;
 r:=api.get_personal_dashboard_content();if jsonb_array_length(r->'news')<>1 or jsonb_array_length(r->'events')<>0 then raise exception 'Other team included without follow';end if;
 perform api.set_public_channel_follow('team',other_team,true);
 r:=api.get_personal_dashboard_content();if jsonb_array_length(r->'news')<>2 or jsonb_array_length(r->'events')<>2 then raise exception 'Followed public data missing or private event types exposed: %',r;end if;
 perform api.set_public_channel_follow('team',team,true);
 r:=api.get_personal_dashboard_content();if jsonb_array_length(r->'news')<>2 then raise exception 'Own-follow duplicate';end if;
 perform set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
 r:=api.get_personal_dashboard_content();if jsonb_array_length(r->'own_teams')<>0 or jsonb_array_length(r->'news')<>0 or jsonb_array_length(r->'events')<>0 then raise exception 'Account data leak';end if;
 perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
 update public_api.club_projections set visibility='listed' where public_id=club;
 r:=api.get_personal_dashboard_content();if jsonb_array_length(r->'news')<>0 or jsonb_array_length(r->'events')<>0 or jsonb_array_length(r->'results')<>0 then raise exception 'Parent privacy leak';end if;
 update internal.publication_runtime_state set enabled=false;
 r:=api.get_personal_dashboard_content();if (r->>'available')::boolean then raise exception 'Runtime gate ignored';end if;
 if has_function_privilege('anon','api.get_personal_dashboard_content()','execute') then raise exception 'Anonymous grant';end if;
end;$$;
rollback;
